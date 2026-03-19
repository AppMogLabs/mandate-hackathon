// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AuditLog — Immutable event log for MANDATE actions
/// @notice Append-only log of all critical agent actions. Event-only design (no state storage)
///         for gas efficiency. Only authorized contracts can write.
/// @dev Uses OpenZeppelin AccessControl with LOGGER_ROLE. Will be granted to OrderBook,
///      AgentRegistry, and other core contracts during deployment.
contract AuditLog is AccessControl {
    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------
    bytes32 public constant LOGGER_ROLE = keccak256("LOGGER_ROLE");

    // -------------------------------------------------------------------------
    // Action type constants
    // -------------------------------------------------------------------------
    bytes32 public constant ORDER_PLACED = keccak256("ORDER_PLACED");
    bytes32 public constant ORDER_MATCHED = keccak256("ORDER_MATCHED");
    bytes32 public constant ORDER_CANCELLED = keccak256("ORDER_CANCELLED");
    bytes32 public constant AGENT_REGISTERED = keccak256("AGENT_REGISTERED");
    bytes32 public constant ALLOWLIST_UPDATED = keccak256("ALLOWLIST_UPDATED");
    bytes32 public constant FEEDBACK_POSTED = keccak256("FEEDBACK_POSTED");

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted for every logged action.
    /// @param agentId The agent performing the action (NFT token ID from AgentRegistry).
    /// @param action Keccak256 hash of the action type (e.g., ORDER_PLACED).
    /// @param metadata ABI-encoded additional data (contract-specific).
    /// @param timestamp Block timestamp when action was logged.
    event ActionLogged(uint256 indexed agentId, bytes32 indexed action, bytes metadata, uint256 timestamp);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param admin Address that receives DEFAULT_ADMIN_ROLE (can grant LOGGER_ROLE).
    constructor(address admin) {
        require(admin != address(0), "AuditLog: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Logging
    // -------------------------------------------------------------------------

    /// @notice Log an action to the immutable audit trail.
    /// @param agentId The agent ID (from AgentRegistry).
    /// @param action Action type (use predefined constants or custom keccak256 hashes).
    /// @param metadata ABI-encoded context (order details, feedback scores, etc.).
    function logAction(uint256 agentId, bytes32 action, bytes calldata metadata) external onlyRole(LOGGER_ROLE) {
        emit ActionLogged(agentId, action, metadata, block.timestamp);
    }

    // -------------------------------------------------------------------------
    // Query Helpers (Off-chain indexing)
    // -------------------------------------------------------------------------

    /// @notice Returns action type constants for off-chain queries.
    /// @dev These are helper views for indexers — the actual log is event-only.
    function getActionTypes()
        external
        pure
        returns (
            bytes32 orderPlaced,
            bytes32 orderMatched,
            bytes32 orderCancelled,
            bytes32 agentRegistered,
            bytes32 allowlistUpdated,
            bytes32 feedbackPosted
        )
    {
        return (ORDER_PLACED, ORDER_MATCHED, ORDER_CANCELLED, AGENT_REGISTERED, ALLOWLIST_UPDATED, FEEDBACK_POSTED);
    }
}
