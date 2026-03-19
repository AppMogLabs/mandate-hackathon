// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title AgentRegistry — ERC-8004 Identity Registry for MANDATE agents
/// @notice Each agent receives an ERC-721 NFT as its on-chain identity. The action allowlist
///         bitmap defines permitted transaction types. validateAction() gates every write path.
/// @dev Conforms to ERC-8004 v1 Identity Registry pattern. Bitmap-based allowlist provides
///      deterministic enforcement — no LLM prompt injection can bypass a missing allowlist bit.
contract AgentRegistry is ERC721, AccessControl, EIP712 {
    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // Action type constants (bitmap positions)
    // -------------------------------------------------------------------------
    uint8 public constant ACTION_TRANSFER = 0;
    uint8 public constant ACTION_ORDER_PLACE = 1;
    uint8 public constant ACTION_ORDER_CANCEL = 2;
    uint8 public constant ACTION_ORDER_MATCH = 3;
    uint8 public constant ACTION_FEEDBACK_POST = 4;
    uint8 public constant ACTION_RESOURCE_MINT = 5;
    uint8 public constant ACTION_RESOURCE_BURN = 6;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    uint256 private _nextAgentId = 1;

    /// @notice Maps agent wallet address => agentId (NFT token ID). 0 = not registered.
    mapping(address => uint256) public agentIdOf;

    /// @notice Maps agentId => action allowlist bitmap.
    mapping(uint256 => uint256) public allowlistOf;

    /// @notice Maps agentId => agent URI (off-chain registration file).
    mapping(uint256 => string) public agentURI;

    // -------------------------------------------------------------------------
    // EIP-712 typed data for guard signatures
    // -------------------------------------------------------------------------
    bytes32 public constant GUARD_ACTION_TYPEHASH = keccak256(
        "GuardAction(address agent,uint8 actionType,address target,bytes32 dataHash,uint256 nonce,uint256 deadline)"
    );

    /// @notice Per-agent nonce for guard signatures, preventing replay.
    mapping(address => uint256) public guardNonces;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event AgentRegistered(uint256 indexed agentId, address indexed agentAddress, string agentURI);
    event AllowlistUpdated(uint256 indexed agentId, uint256 newBitmap);
    event AgentURIUpdated(uint256 indexed agentId, string newURI);
    event ActionValidated(uint256 indexed agentId, uint8 actionType, bool allowed);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error AgentAlreadyRegistered(address agent);
    error AgentNotRegistered(address agent);
    error ActionNotPermitted(address agent, uint8 actionType);
    error InvalidGuardSignature();
    error GuardSignatureExpired();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param admin Address that receives DEFAULT_ADMIN_ROLE, REGISTRAR_ROLE, and OPERATOR_ROLE.
    constructor(address admin)
        ERC721("MANDATE Agent", "MAGENT")
        EIP712("MANDATE AgentRegistry", "1")
    {
        if (admin == address(0)) revert("AgentRegistry: zero admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    /// @notice Register a new agent. Mints an ERC-721 NFT as the agent's identity.
    /// @param agentAddress The wallet address of the agent being registered.
    /// @param uri Off-chain registration file URI (ERC-8004 agentURI).
    /// @return agentId The minted NFT token ID.
    function registerAgent(
        address agentAddress,
        string calldata uri
    ) external onlyRole(REGISTRAR_ROLE) returns (uint256 agentId) {
        if (agentIdOf[agentAddress] != 0) revert AgentAlreadyRegistered(agentAddress);
        if (agentAddress == address(0)) revert("AgentRegistry: zero agent");

        agentId = _nextAgentId++;

        _safeMint(agentAddress, agentId);
        agentIdOf[agentAddress] = agentId;
        agentURI[agentId] = uri;

        emit AgentRegistered(agentId, agentAddress, uri);
    }

    // -------------------------------------------------------------------------
    // Allowlist management
    // -------------------------------------------------------------------------

    /// @notice Set the full action allowlist bitmap for an agent.
    /// @param agentId The agent's NFT token ID.
    /// @param actionBitmap Bitmap where bit N = 1 means action N is permitted.
    function updateAllowlist(
        uint256 agentId,
        uint256 actionBitmap
    ) external onlyRole(OPERATOR_ROLE) {
        _requireOwned(agentId);
        allowlistOf[agentId] = actionBitmap;

        emit AllowlistUpdated(agentId, actionBitmap);
    }

    /// @notice Grant a single action type on an agent's allowlist.
    /// @param agentId The agent's NFT token ID.
    /// @param actionType The action bit position to enable.
    function grantAction(uint256 agentId, uint8 actionType) external onlyRole(OPERATOR_ROLE) {
        _requireOwned(agentId);
        allowlistOf[agentId] |= (uint256(1) << actionType);

        emit AllowlistUpdated(agentId, allowlistOf[agentId]);
    }

    /// @notice Revoke a single action type from an agent's allowlist.
    /// @param agentId The agent's NFT token ID.
    /// @param actionType The action bit position to disable.
    function revokeAction(uint256 agentId, uint8 actionType) external onlyRole(OPERATOR_ROLE) {
        _requireOwned(agentId);
        allowlistOf[agentId] &= ~(uint256(1) << actionType);

        emit AllowlistUpdated(agentId, allowlistOf[agentId]);
    }

    // -------------------------------------------------------------------------
    // Validation — THE GATE
    // -------------------------------------------------------------------------

    /// @notice Check whether an agent is permitted to perform an action.
    /// @dev This MUST be called at the start of every write path in every contract.
    /// @param agent The agent's wallet address.
    /// @param actionType The action type (bit position).
    /// @return True if the agent is registered and the action is on its allowlist.
    function validateAction(address agent, uint8 actionType) external view returns (bool) {
        uint256 agentId = agentIdOf[agent];
        if (agentId == 0) revert AgentNotRegistered(agent);
        if ((allowlistOf[agentId] & (uint256(1) << actionType)) == 0) {
            revert ActionNotPermitted(agent, actionType);
        }
        return true;
    }

    /// @notice Check registration status without reverting.
    /// @param agent The agent's wallet address.
    /// @return True if the agent is registered.
    function isRegistered(address agent) external view returns (bool) {
        return agentIdOf[agent] != 0;
    }

    /// @notice Check if an action is permitted without reverting.
    /// @param agent The agent's wallet address.
    /// @param actionType The action type (bit position).
    /// @return True if registered and action is permitted.
    function isActionPermitted(address agent, uint8 actionType) external view returns (bool) {
        uint256 agentId = agentIdOf[agent];
        if (agentId == 0) return false;
        return (allowlistOf[agentId] & (uint256(1) << actionType)) != 0;
    }

    // -------------------------------------------------------------------------
    // Guard-signed execution (EIP-712)
    // -------------------------------------------------------------------------

    /// @notice Verify a guard agent's EIP-712 signature for a specific action.
    /// @dev Internal until Phase 2 guard agent infrastructure is ready.
    ///      Will be exposed via an external wrapper with GUARD_ROLE validation.
    /// @param agent The agent performing the action.
    /// @param actionType The action type.
    /// @param target The target contract address.
    /// @param dataHash Hash of the action calldata.
    /// @param deadline Timestamp after which the signature expires.
    /// @param guardSig The guard agent's signature.
    /// @return signer The recovered signer address.
    function verifyGuardSignature(
        address agent,
        uint8 actionType,
        address target,
        bytes32 dataHash,
        uint256 deadline,
        bytes memory guardSig
    ) internal returns (address signer) {
        if (block.timestamp > deadline) revert GuardSignatureExpired();

        bytes32 structHash = keccak256(abi.encode(
            GUARD_ACTION_TYPEHASH,
            agent,
            actionType,
            target,
            dataHash,
            guardNonces[agent]++,
            deadline
        ));

        bytes32 digest = _hashTypedDataV4(structHash);
        signer = ECDSA.recover(digest, guardSig);

        if (signer == address(0)) revert InvalidGuardSignature();
    }

    // -------------------------------------------------------------------------
    // URI management
    // -------------------------------------------------------------------------

    /// @notice Update the agent's off-chain registration URI.
    /// @param agentId The agent's NFT token ID.
    /// @param newURI New agent URI.
    function updateAgentURI(uint256 agentId, string calldata newURI) external onlyRole(OPERATOR_ROLE) {
        _requireOwned(agentId);
        agentURI[agentId] = newURI;

        emit AgentURIUpdated(agentId, newURI);
    }

    /// @notice ERC-721 tokenURI resolves to the agent's registration URI.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return agentURI[tokenId];
    }

    // -------------------------------------------------------------------------
    // Overrides required by Solidity
    // -------------------------------------------------------------------------

    /// @dev Agent NFTs are soulbound (non-transferable) in Sprint 0.
    ///      Transferable agent identities require careful design around reputation
    ///      and allowlist semantics — deferred to a later sprint.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        // Allow minting (from == address(0)), block all transfers
        if (from != address(0) && to != address(0)) {
            revert("AgentRegistry: soulbound token");
        }
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
