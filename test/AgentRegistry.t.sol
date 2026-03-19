// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    address public admin = makeAddr("admin");
    address public agentAlpha = makeAddr("agentAlpha");
    address public agentBeta = makeAddr("agentBeta");
    address public nobody = makeAddr("nobody");

    function setUp() public {
        registry = new AgentRegistry(admin);
    }

    // -------------------------------------------------------------------------
    // Deployment
    // -------------------------------------------------------------------------

    function test_Deployment_CorrectNameAndSymbol() public view {
        assertEq(registry.name(), "MANDATE Agent");
        assertEq(registry.symbol(), "MAGENT");
    }

    function test_Deployment_AdminHasRoles() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.REGISTRAR_ROLE(), admin));
        assertTrue(registry.hasRole(registry.OPERATOR_ROLE(), admin));
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert("AgentRegistry: zero admin");
        new AgentRegistry(address(0));
    }

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    function test_RegisterAgent_Success() public {
        vm.prank(admin);
        uint256 agentId = registry.registerAgent(agentAlpha, "ipfs://alpha");

        assertEq(agentId, 1);
        assertEq(registry.agentIdOf(agentAlpha), 1);
        assertEq(registry.ownerOf(1), agentAlpha);
        assertEq(registry.tokenURI(1), "ipfs://alpha");
        assertTrue(registry.isRegistered(agentAlpha));
    }

    function test_RegisterAgent_SequentialIds() public {
        vm.startPrank(admin);
        uint256 id1 = registry.registerAgent(agentAlpha, "ipfs://alpha");
        uint256 id2 = registry.registerAgent(agentBeta, "ipfs://beta");
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_RevertWhen_RegisterDuplicate() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");

        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentAlreadyRegistered.selector, agentAlpha));
        registry.registerAgent(agentAlpha, "ipfs://alpha-v2");
        vm.stopPrank();
    }

    function test_RevertWhen_RegisterByNonRegistrar() public {
        vm.prank(nobody);
        vm.expectRevert();
        registry.registerAgent(agentAlpha, "ipfs://alpha");
    }

    function test_RevertWhen_RegisterZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("AgentRegistry: zero agent");
        registry.registerAgent(address(0), "ipfs://zero");
    }

    // -------------------------------------------------------------------------
    // Allowlist management
    // -------------------------------------------------------------------------

    function test_UpdateAllowlist_FullBitmap() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");

        uint256 bitmap = (1 << registry.ACTION_ORDER_PLACE()) | (1 << registry.ACTION_ORDER_CANCEL());
        registry.updateAllowlist(1, bitmap);
        vm.stopPrank();

        assertEq(registry.allowlistOf(1), bitmap);
    }

    function test_GrantAction_SingleBit() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");
        registry.grantAction(1, registry.ACTION_ORDER_PLACE());
        vm.stopPrank();

        assertTrue(registry.isActionPermitted(agentAlpha, registry.ACTION_ORDER_PLACE()));
        assertFalse(registry.isActionPermitted(agentAlpha, registry.ACTION_ORDER_CANCEL()));
    }

    function test_RevokeAction_SingleBit() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");

        uint256 bitmap = (1 << registry.ACTION_ORDER_PLACE()) | (1 << registry.ACTION_ORDER_CANCEL());
        registry.updateAllowlist(1, bitmap);
        registry.revokeAction(1, registry.ACTION_ORDER_CANCEL());
        vm.stopPrank();

        assertTrue(registry.isActionPermitted(agentAlpha, registry.ACTION_ORDER_PLACE()));
        assertFalse(registry.isActionPermitted(agentAlpha, registry.ACTION_ORDER_CANCEL()));
    }

    // -------------------------------------------------------------------------
    // validateAction — THE GATE
    // -------------------------------------------------------------------------

    function test_ValidateAction_PermittedAction() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");
        registry.grantAction(1, registry.ACTION_ORDER_PLACE());
        vm.stopPrank();

        bool result = registry.validateAction(agentAlpha, registry.ACTION_ORDER_PLACE());
        assertTrue(result);
    }

    function test_RevertWhen_ValidateAction_UnregisteredAgent() public {
        uint8 actionPlace = registry.ACTION_ORDER_PLACE();
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, nobody));
        registry.validateAction(nobody, actionPlace);
    }

    /// @dev KEY ADVERSARIAL TEST: Agent attempts action NOT on allowlist → reverts.
    ///      This is the core security property — deterministic enforcement that
    ///      no prompt injection can bypass.
    function test_RevertWhen_ValidateAction_UnpermittedAction() public {
        uint8 actionPlace = registry.ACTION_ORDER_PLACE();
        uint8 actionCancel = registry.ACTION_ORDER_CANCEL();

        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");
        // Only grant ORDER_PLACE, NOT ORDER_CANCEL
        registry.grantAction(1, actionPlace);
        vm.stopPrank();

        // ORDER_PLACE should pass
        registry.validateAction(agentAlpha, actionPlace);

        // ORDER_CANCEL should revert — this is the key security demo
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.ActionNotPermitted.selector, agentAlpha, actionCancel));
        registry.validateAction(agentAlpha, actionCancel);
    }

    function test_RevertWhen_ValidateAction_NoActionsGranted() public {
        uint8 actionPlace = registry.ACTION_ORDER_PLACE();

        vm.prank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");
        // No actions granted — agent is registered but cannot do anything

        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.ActionNotPermitted.selector, agentAlpha, actionPlace));
        registry.validateAction(agentAlpha, actionPlace);
    }

    // -------------------------------------------------------------------------
    // isActionPermitted (non-reverting check)
    // -------------------------------------------------------------------------

    function test_IsActionPermitted_FalseForUnregistered() public view {
        assertFalse(registry.isActionPermitted(nobody, registry.ACTION_ORDER_PLACE()));
    }

    function test_IsActionPermitted_FalseForNotGranted() public {
        vm.prank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");

        assertFalse(registry.isActionPermitted(agentAlpha, registry.ACTION_ORDER_PLACE()));
    }

    // -------------------------------------------------------------------------
    // URI management
    // -------------------------------------------------------------------------

    function test_UpdateAgentURI() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");
        registry.updateAgentURI(1, "ipfs://alpha-v2");
        vm.stopPrank();

        assertEq(registry.tokenURI(1), "ipfs://alpha-v2");
    }

    // -------------------------------------------------------------------------
    // ERC-721 compliance
    // -------------------------------------------------------------------------

    function test_ERC721_BalanceOf() public {
        vm.startPrank(admin);
        registry.registerAgent(agentAlpha, "ipfs://alpha");
        registry.registerAgent(agentBeta, "ipfs://beta");
        vm.stopPrank();

        assertEq(registry.balanceOf(agentAlpha), 1);
        assertEq(registry.balanceOf(agentBeta), 1);
    }

    function test_ERC721_SupportsInterface() public view {
        // ERC-721 interface ID
        assertTrue(registry.supportsInterface(0x80ac58cd));
        // ERC-165 interface ID
        assertTrue(registry.supportsInterface(0x01ffc9a7));
        // AccessControl interface ID
        assertTrue(registry.supportsInterface(type(IAccessControl).interfaceId));
    }
}

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
