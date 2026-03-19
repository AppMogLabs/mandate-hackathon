// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/ReputationLedger.sol";

contract ReputationLedgerTest is Test {
    ReputationLedger public ledger;
    
    address public admin = address(1);
    address public recorder = address(2);
    address public unauthorized = address(3);
    
    event ReputationUpdated(uint256 indexed agentId, uint256 newScore, uint256 delta);
    
    function setUp() public {
        ledger = new ReputationLedger(admin);
        
        // Grant RECORDER_ROLE to recorder
        vm.startPrank(admin);
        ledger.grantRole(ledger.RECORDER_ROLE(), recorder);
        vm.stopPrank();
    }
    
    function test_Constructor() public view {
        assertTrue(ledger.hasRole(ledger.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(ledger.totalReputation(), 0);
    }
    
    function test_ConstructorRevertsOnZeroAdmin() public {
        vm.expectRevert("ReputationLedger: zero admin");
        new ReputationLedger(address(0));
    }
    
    function test_RecordTransaction_Success() public {
        uint256 buyerId = 1;
        uint256 sellerId = 2;
        uint256 amount = 10_000; // Should give 10 reputation points each
        
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(buyerId, 10, 10);
        
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(sellerId, 10, 10);
        
        vm.prank(recorder);
        ledger.recordTransaction(buyerId, sellerId, amount);
        
        assertEq(ledger.getReputation(buyerId), 10);
        assertEq(ledger.getReputation(sellerId), 10);
        assertEq(ledger.totalReputation(), 20);
    }
    
    function test_RecordTransaction_SmallAmount() public {
        uint256 buyerId = 1;
        uint256 sellerId = 2;
        uint256 amount = 500; // Less than 1000, should give 0 reputation
        
        vm.prank(recorder);
        ledger.recordTransaction(buyerId, sellerId, amount);
        
        assertEq(ledger.getReputation(buyerId), 0);
        assertEq(ledger.getReputation(sellerId), 0);
        assertEq(ledger.totalReputation(), 0);
    }
    
    function test_RecordTransaction_AccumulatesScores() public {
        uint256 buyerId = 1;
        uint256 sellerId = 2;
        
        vm.startPrank(recorder);
        
        // First transaction
        ledger.recordTransaction(buyerId, sellerId, 5_000); // +5 each
        assertEq(ledger.getReputation(buyerId), 5);
        assertEq(ledger.getReputation(sellerId), 5);
        
        // Second transaction
        ledger.recordTransaction(buyerId, sellerId, 3_000); // +3 each
        assertEq(ledger.getReputation(buyerId), 8);
        assertEq(ledger.getReputation(sellerId), 8);
        
        // Third transaction
        ledger.recordTransaction(buyerId, sellerId, 2_000); // +2 each
        assertEq(ledger.getReputation(buyerId), 10);
        assertEq(ledger.getReputation(sellerId), 10);
        
        vm.stopPrank();
        
        assertEq(ledger.totalReputation(), 20);
    }
    
    function test_RecordTransaction_RevertsUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        ledger.recordTransaction(1, 2, 10_000);
    }
    
    function test_GetReputationBatch() public {
        // Record some transactions
        vm.startPrank(recorder);
        ledger.recordTransaction(1, 2, 10_000); // +10 each
        ledger.recordTransaction(3, 4, 5_000);  // +5 each
        ledger.recordTransaction(1, 3, 3_000);  // +3 each
        vm.stopPrank();
        
        // Query batch
        uint256[] memory agentIds = new uint256[](4);
        agentIds[0] = 1;
        agentIds[1] = 2;
        agentIds[2] = 3;
        agentIds[3] = 4;
        
        uint256[] memory scores = ledger.getReputationBatch(agentIds);
        
        assertEq(scores[0], 13); // Agent 1: 10 + 3
        assertEq(scores[1], 10); // Agent 2: 10
        assertEq(scores[2], 8);  // Agent 3: 5 + 3
        assertEq(scores[3], 5);  // Agent 4: 5
    }
    
    function testFuzz_RecordTransaction(uint256 buyerId, uint256 sellerId, uint256 amount) public {
        vm.assume(buyerId != 0 && sellerId != 0);
        vm.assume(buyerId != sellerId); // Must be different agents
        vm.assume(amount < type(uint128).max); // Prevent overflow on multiplication
        
        uint256 expectedGain = amount / 1000;
        
        vm.prank(recorder);
        ledger.recordTransaction(buyerId, sellerId, amount);
        
        assertEq(ledger.getReputation(buyerId), expectedGain);
        assertEq(ledger.getReputation(sellerId), expectedGain);
        assertEq(ledger.totalReputation(), expectedGain * 2);
    }
    
    function test_MultipleRecorders() public {
        address recorder2 = address(4);
        
        vm.startPrank(admin);
        ledger.grantRole(ledger.RECORDER_ROLE(), recorder2);
        vm.stopPrank();
        
        // First recorder
        vm.prank(recorder);
        ledger.recordTransaction(1, 2, 10_000);
        
        // Second recorder
        vm.prank(recorder2);
        ledger.recordTransaction(1, 2, 5_000);
        
        assertEq(ledger.getReputation(1), 15);
        assertEq(ledger.getReputation(2), 15);
    }
}
