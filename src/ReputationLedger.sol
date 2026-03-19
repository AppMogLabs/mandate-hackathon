// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ReputationLedger — On-chain trust scores for MANDATE agents
/// @notice Tracks reputation scores for agents. Score increases with successful transactions.
///         Conforms to ERC-8004 Reputation Registry pattern.
/// @dev Uses OpenZeppelin AccessControl with RECORDER_ROLE (granted to OrderBook).
///      Score accumulates linearly — future versions can add decay or weighted formulas.
contract ReputationLedger is AccessControl {
    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Maps agentId => cumulative reputation score.
    mapping(uint256 => uint256) public reputationOf;

    /// @notice Total reputation distributed across all agents.
    uint256 public totalReputation;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when an agent's reputation score is updated.
    /// @param agentId The agent whose score changed.
    /// @param newScore The updated cumulative score.
    /// @param delta The amount added to the score.
    event ReputationUpdated(uint256 indexed agentId, uint256 newScore, uint256 delta);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param admin Address that receives DEFAULT_ADMIN_ROLE (can grant RECORDER_ROLE).
    constructor(address admin) {
        require(admin != address(0), "ReputationLedger: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Recording
    // -------------------------------------------------------------------------

    /// @notice Record a successful transaction between two agents.
    /// @dev Only callable by contracts with RECORDER_ROLE (e.g., OrderBook).
    ///      Both buyer and seller receive reputation based on transaction amount.
    /// @param buyerAgentId The agent ID of the buyer.
    /// @param sellerAgentId The agent ID of the seller.
    /// @param amount The transaction amount (used to weight reputation gain).
    function recordTransaction(uint256 buyerAgentId, uint256 sellerAgentId, uint256 amount)
        external
        onlyRole(RECORDER_ROLE)
    {
        require(buyerAgentId != 0 && sellerAgentId != 0, "ReputationLedger: zero agentId");

        // Simple linear scoring: 1 reputation point per 1000 RATE transacted
        // Adjust divisor for desired score granularity
        uint256 reputationGain = amount / 1000;

        if (reputationGain > 0) {
            // Credit buyer
            reputationOf[buyerAgentId] += reputationGain;
            totalReputation += reputationGain;
            emit ReputationUpdated(buyerAgentId, reputationOf[buyerAgentId], reputationGain);

            // Credit seller
            reputationOf[sellerAgentId] += reputationGain;
            totalReputation += reputationGain;
            emit ReputationUpdated(sellerAgentId, reputationOf[sellerAgentId], reputationGain);
        }
    }

    // -------------------------------------------------------------------------
    // Query
    // -------------------------------------------------------------------------

    /// @notice Get the reputation score of an agent.
    /// @param agentId The agent to query.
    /// @return score The cumulative reputation score.
    function getReputation(uint256 agentId) external view returns (uint256 score) {
        return reputationOf[agentId];
    }

    /// @notice Get reputation data for multiple agents (batch query).
    /// @param agentIds Array of agent IDs to query.
    /// @return scores Array of reputation scores in same order.
    function getReputationBatch(uint256[] calldata agentIds) external view returns (uint256[] memory scores) {
        scores = new uint256[](agentIds.length);
        for (uint256 i = 0; i < agentIds.length; i++) {
            scores[i] = reputationOf[agentIds[i]];
        }
    }
}
