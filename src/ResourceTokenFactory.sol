// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ResourceToken} from "./ResourceToken.sol";

/// @title ResourceTokenFactory — deploys resource ERC-20 tokens
/// @notice Factory pattern for deploying individual resource tokens (COMPUTE, CHIPS, etc.).
/// @dev Each resource gets its own ERC-20 contract for per-resource access control and failure isolation.
///      Uses CREATE (not Clones/EIP-1167) because each ResourceToken needs unique name/symbol
///      set at construction time, and the contract is small enough that full deployment is acceptable.
contract ResourceTokenFactory is AccessControl {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /// @notice Maps resource symbol => deployed token address.
    mapping(string => address) public tokensBySymbol;

    /// @notice All deployed resource token addresses.
    address[] public deployedTokens;

    event ResourceDeployed(address indexed token, string name, string symbol);
    event MintAuthorityUpdated(address indexed token, address indexed authority, bool authorised);

    /// @param admin Address that receives DEFAULT_ADMIN_ROLE and DEPLOYER_ROLE.
    constructor(address admin) {
        if (admin == address(0)) revert("ResourceTokenFactory: zero admin");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DEPLOYER_ROLE, admin);
    }

    /// @notice Deploy a new resource ERC-20 token.
    /// @param name Token name (e.g. "COMPUTE").
    /// @param symbol Token symbol (e.g. "COMPUTE").
    /// @return token Address of the newly deployed ResourceToken.
    function deployResource(string calldata name, string calldata symbol)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address token)
    {
        if (tokensBySymbol[symbol] != address(0)) {
            revert("ResourceTokenFactory: already deployed");
        }

        ResourceToken rt = new ResourceToken(name, symbol, address(this));
        token = address(rt);

        tokensBySymbol[symbol] = token;
        deployedTokens.push(token);

        emit ResourceDeployed(token, name, symbol);
    }

    /// @notice Grant or revoke MINTER_ROLE on a resource token.
    /// @param token Address of the ResourceToken.
    /// @param authority Address to grant/revoke minting authority.
    /// @param authorised True to grant, false to revoke.
    function setMintAuthority(address token, address authority, bool authorised) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 minterRole = ResourceToken(token).MINTER_ROLE();
        if (authorised) {
            ResourceToken(token).grantRole(minterRole, authority);
        } else {
            ResourceToken(token).revokeRole(minterRole, authority);
        }

        emit MintAuthorityUpdated(token, authority, authorised);
    }

    /// @notice Look up a deployed resource token by symbol.
    /// @param symbol The token symbol (e.g. "COMPUTE").
    /// @return The token address, or address(0) if not deployed.
    function getTokenAddress(string calldata symbol) external view returns (address) {
        return tokensBySymbol[symbol];
    }

    /// @notice Number of deployed resource tokens.
    function deployedTokenCount() external view returns (uint256) {
        return deployedTokens.length;
    }
}
