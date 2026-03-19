// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../../src/AgentRegistry.sol";

/// @title AgentRegistry Security Tests — Adversarial edge cases
/// @notice Tests for allowlist bypass, guard signature abuse, nonce manipulation, and role escalation.
contract AgentRegistrySecurityTest is Test {
    AgentRegistry public registry;
    address public admin = makeAddr("admin");
    address public agent = makeAddr("agent");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        registry = new AgentRegistry(admin);
    }

    // -------------------------------------------------------------------------
    // CRITICAL: Agent with allowlist 0x0 attempts action → must revert
    // -------------------------------------------------------------------------

    /// @notice Agent registered but allowlist is 0 — every action must revert.
    function test_ZeroAllowlist_AllActionsRevert() public {
        vm.prank(admin);
        registry.registerAgent(agent, "ipfs://agent");

        // Allowlist is 0 by default — all actions should revert
        for (uint8 i = 0; i <= 6; i++) {
            vm.expectRevert(abi.encodeWithSelector(AgentRegistry.ActionNotPermitted.selector, agent, i));
            registry.validateAction(agent, i);
        }
    }

    // -------------------------------------------------------------------------
    // Agent attempts to modify own allowlist → must revert (no OPERATOR_ROLE)
    // -------------------------------------------------------------------------

    /// @notice Agent cannot set its own allowlist — only OPERATOR_ROLE can.
    function test_AgentCannotModifyOwnAllowlist() public {
        vm.prank(admin);
        uint256 agentId = registry.registerAgent(agent, "ipfs://agent");

        // Agent tries to set its own allowlist — lacks OPERATOR_ROLE
        vm.prank(agent);
        vm.expectRevert();
        registry.updateAllowlist(agentId, type(uint256).max);
    }

    /// @notice Agent cannot grant itself actions.
    function test_AgentCannotGrantSelfActions() public {
        vm.prank(admin);
        uint256 agentId = registry.registerAgent(agent, "ipfs://agent");

        vm.prank(agent);
        vm.expectRevert();
        registry.grantAction(agentId, 0);
    }

    // -------------------------------------------------------------------------
    // Operator sets allowlist for non-existent agent → must revert
    // -------------------------------------------------------------------------

    /// @notice Setting allowlist for non-existent agentId reverts.
    function test_UpdateAllowlist_NonexistentAgent() public {
        vm.prank(admin);
        vm.expectRevert(); // _requireOwned will revert
        registry.updateAllowlist(999, type(uint256).max);
    }

    /// @notice Granting action for non-existent agentId reverts.
    function test_GrantAction_NonexistentAgent() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.grantAction(999, 0);
    }

    /// @notice Revoking action for non-existent agentId reverts.
    function test_RevokeAction_NonexistentAgent() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.revokeAction(999, 0);
    }

    // -------------------------------------------------------------------------
    // FIXED: verifyGuardSignature is now internal — not callable externally
    // -------------------------------------------------------------------------

    /// @notice verifyGuardSignature is internal — cannot be called externally.
    ///         This is verified at compile time (no test needed for function access).
    ///         The nonce manipulation and access control concerns are resolved.

    // -------------------------------------------------------------------------
    // ERC-721 transfer does not clear allowlist (design concern)
    // -------------------------------------------------------------------------

    /// @notice FIXED: Agent NFTs are now soulbound — transfers revert.
    function test_NFTTransfer_Soulbound_Reverts() public {
        vm.startPrank(admin);
        uint256 agentId = registry.registerAgent(agent, "ipfs://agent");
        registry.grantAction(agentId, registry.ACTION_ORDER_PLACE());
        vm.stopPrank();

        // Agent tries to transfer NFT — blocked by soulbound check
        vm.prank(agent);
        vm.expectRevert("AgentRegistry: soulbound token");
        registry.transferFrom(agent, attacker, agentId);

        // Agent still owns the NFT and retains permissions
        assertEq(registry.ownerOf(agentId), agent);
        assertTrue(registry.isActionPermitted(agent, registry.ACTION_ORDER_PLACE()));
    }

    // -------------------------------------------------------------------------
    // Bitmap edge: action type 255 (highest bit)
    // -------------------------------------------------------------------------

    /// @notice Action type 255 (highest bit in uint256) works correctly.
    function test_AllowlistBitmapHighBit() public {
        vm.startPrank(admin);
        uint256 agentId = registry.registerAgent(agent, "ipfs://agent");
        registry.grantAction(agentId, 255);
        vm.stopPrank();

        assertTrue(registry.isActionPermitted(agent, 255));
        assertFalse(registry.isActionPermitted(agent, 254));
    }

    // -------------------------------------------------------------------------
    // Full max bitmap — all actions permitted
    // -------------------------------------------------------------------------

    /// @notice Setting allowlist to type(uint256).max permits all 256 action types.
    function test_AllowlistMaxBitmap() public {
        vm.startPrank(admin);
        uint256 agentId = registry.registerAgent(agent, "ipfs://agent");
        registry.updateAllowlist(agentId, type(uint256).max);
        vm.stopPrank();

        for (uint8 i = 0; i < 7; i++) {
            assertTrue(registry.isActionPermitted(agent, i));
        }
        assertTrue(registry.isActionPermitted(agent, 255));
    }

    // -------------------------------------------------------------------------
    // DEFAULT_ADMIN_ROLE renounce risk
    // -------------------------------------------------------------------------

    /// @notice Admin can renounce DEFAULT_ADMIN_ROLE, losing ability to manage roles.
    ///         OZ v5 renounceRole requires msg.sender == account.
    function test_AdminRenounce_CannotGrantNewRoles() public {
        bytes32 adminRole = registry.DEFAULT_ADMIN_ROLE();
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(admin);
        registry.renounceRole(adminRole, admin);

        // Admin no longer has DEFAULT_ADMIN_ROLE
        assertFalse(registry.hasRole(adminRole, admin));

        // Admin still has REGISTRAR and OPERATOR (those weren't renounced),
        // but cannot grant DEFAULT_ADMIN_ROLE to anyone else
        vm.expectRevert();
        registry.grantRole(adminRole, newAdmin);
        vm.stopPrank();
    }
}
