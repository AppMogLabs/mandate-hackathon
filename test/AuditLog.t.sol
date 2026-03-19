// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/AuditLog.sol";

contract AuditLogTest is Test {
    AuditLog public auditLog;

    address public admin = address(1);
    address public logger = address(2);
    address public unauthorized = address(3);

    event ActionLogged(uint256 indexed agentId, bytes32 indexed action, bytes metadata, uint256 timestamp);

    function setUp() public {
        auditLog = new AuditLog(admin);

        // Grant LOGGER_ROLE to logger
        vm.startPrank(admin);
        auditLog.grantRole(auditLog.LOGGER_ROLE(), logger);
        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertTrue(auditLog.hasRole(auditLog.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_ConstructorRevertsOnZeroAdmin() public {
        vm.expectRevert("AuditLog: zero admin");
        new AuditLog(address(0));
    }

    function test_LogAction_Success() public {
        uint256 agentId = 1;
        bytes32 action = auditLog.ORDER_PLACED();
        bytes memory metadata = abi.encode(100, 200);

        vm.expectEmit(true, true, false, true);
        emit ActionLogged(agentId, action, metadata, block.timestamp);

        vm.prank(logger);
        auditLog.logAction(agentId, action, metadata);
    }

    function test_LogAction_RevertsUnauthorized() public {
        uint256 agentId = 1;
        bytes32 action = auditLog.ORDER_PLACED();
        bytes memory metadata = abi.encode(100, 200);

        vm.prank(unauthorized);
        vm.expectRevert();
        auditLog.logAction(agentId, action, metadata);
    }

    function test_GetActionTypes() public view {
        (
            bytes32 orderPlaced,
            bytes32 orderMatched,
            bytes32 orderCancelled,
            bytes32 agentRegistered,
            bytes32 allowlistUpdated,
            bytes32 feedbackPosted
        ) = auditLog.getActionTypes();

        assertEq(orderPlaced, keccak256("ORDER_PLACED"));
        assertEq(orderMatched, keccak256("ORDER_MATCHED"));
        assertEq(orderCancelled, keccak256("ORDER_CANCELLED"));
        assertEq(agentRegistered, keccak256("AGENT_REGISTERED"));
        assertEq(allowlistUpdated, keccak256("ALLOWLIST_UPDATED"));
        assertEq(feedbackPosted, keccak256("FEEDBACK_POSTED"));
    }

    function testFuzz_LogAction(uint256 agentId, bytes32 action) public {
        bytes memory metadata = abi.encode(agentId, action);

        vm.expectEmit(true, true, false, true);
        emit ActionLogged(agentId, action, metadata, block.timestamp);

        vm.prank(logger);
        auditLog.logAction(agentId, action, metadata);
    }

    function test_MultipleLoggers() public {
        address logger2 = address(4);

        vm.startPrank(admin);
        auditLog.grantRole(auditLog.LOGGER_ROLE(), logger2);
        vm.stopPrank();

        uint256 agentId = 1;
        bytes32 action = auditLog.ORDER_PLACED();
        bytes memory metadata = abi.encode(100);

        // First logger
        vm.prank(logger);
        auditLog.logAction(agentId, action, metadata);

        // Second logger
        vm.prank(logger2);
        auditLog.logAction(agentId, action, metadata);
    }
}
