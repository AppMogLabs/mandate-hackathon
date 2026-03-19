// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/OrderBook.sol";
import "../src/RateToken.sol";
import "../src/ResourceToken.sol";
import "../src/ResourceTokenFactory.sol";
import "../src/AgentRegistry.sol";
import "../src/ReputationLedger.sol";
import "../src/AuditLog.sol";

/// @title Integration Test — End-to-end flow for MANDATE ecosystem
/// @notice Tests the full lifecycle: register agents → deploy resources → place/match orders → verify reputation/audit
contract IntegrationTest is Test {
    OrderBook public orderBook;
    RateToken public rateToken;
    ResourceToken public computeToken;
    ResourceTokenFactory public factory;
    AgentRegistry public agentRegistry;
    ReputationLedger public reputationLedger;
    AuditLog public auditLog;
    
    address public admin = address(100);
    address public agent1 = address(101);
    address public agent2 = address(102);
    
    uint256 public agent1Id;
    uint256 public agent2Id;
    
    function setUp() public {
        // Deploy all contracts
        rateToken = new RateToken(admin);
        factory = new ResourceTokenFactory(admin);
        agentRegistry = new AgentRegistry(admin);
        reputationLedger = new ReputationLedger(admin);
        auditLog = new AuditLog(admin);
        
        orderBook = new OrderBook(
            address(rateToken),
            address(agentRegistry),
            address(reputationLedger),
            address(auditLog),
            admin
        );
        
        // Setup roles
        vm.startPrank(admin);
        reputationLedger.grantRole(reputationLedger.RECORDER_ROLE(), address(orderBook));
        auditLog.grantRole(auditLog.LOGGER_ROLE(), address(orderBook));
        auditLog.grantRole(auditLog.LOGGER_ROLE(), address(agentRegistry));
        
        // Register agents
        agent1Id = agentRegistry.registerAgent(agent1, "ipfs://agent1");
        agent2Id = agentRegistry.registerAgent(agent2, "ipfs://agent2");
        
        // Grant all permissions to both agents
        agentRegistry.grantAction(agent1Id, agentRegistry.ACTION_ORDER_PLACE());
        agentRegistry.grantAction(agent1Id, agentRegistry.ACTION_ORDER_CANCEL());
        agentRegistry.grantAction(agent1Id, agentRegistry.ACTION_ORDER_MATCH());
        agentRegistry.grantAction(agent2Id, agentRegistry.ACTION_ORDER_PLACE());
        agentRegistry.grantAction(agent2Id, agentRegistry.ACTION_ORDER_CANCEL());
        agentRegistry.grantAction(agent2Id, agentRegistry.ACTION_ORDER_MATCH());
        
        // Deploy COMPUTE resource token
        address computeAddr = factory.deployResource("Compute", "COMPUTE");
        computeToken = ResourceToken(computeAddr);
        
        // Grant minting authority to admin
        factory.setMintAuthority(computeAddr, admin, true);
        
        // Mint tokens
        rateToken.transfer(agent1, 10_000 * 1e18);
        rateToken.transfer(agent2, 10_000 * 1e18);
        computeToken.mint(agent1, 1_000 * 1e18);
        computeToken.mint(agent2, 1_000 * 1e18);
        
        vm.stopPrank();
    }
    
    function test_EndToEndFlow() public {
        // Agent1 places an order to sell 100 COMPUTE at 5 RATE per unit
        uint256 sellAmount = 100 * 1e18;
        uint256 pricePerUnit = 5 * 1e18;
        
        vm.startPrank(agent1);
        computeToken.approve(address(orderBook), sellAmount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), sellAmount, pricePerUnit);
        vm.stopPrank();
        
        assertEq(orderId, 1);
        assertEq(computeToken.balanceOf(address(orderBook)), sellAmount);
        
        // Agent2 matches the entire order
        uint256 totalCost = (sellAmount * pricePerUnit) / 1e18; // 500 RATE
        
        vm.startPrank(agent2);
        rateToken.approve(address(orderBook), totalCost);
        bool success = orderBook.matchOrder(orderId, sellAmount);
        vm.stopPrank();
        
        assertTrue(success);
        
        // Verify token transfers
        assertEq(computeToken.balanceOf(agent2), 1_100 * 1e18); // Initial 1000 + 100 bought
        assertEq(computeToken.balanceOf(agent1), 900 * 1e18);   // Initial 1000 - 100 sold
        assertEq(rateToken.balanceOf(agent1), 10_500 * 1e18);   // Initial 10000 + 500 received
        assertEq(rateToken.balanceOf(agent2), 9_500 * 1e18);    // Initial 10000 - 500 paid
        
        // Verify order status
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.FILLED));
        assertEq(order.filledAmount, sellAmount);
        
        // Verify reputation was recorded (500 RATE / 1000 = 0.5 * 1e18 reputation in wei)
        uint256 rep1 = reputationLedger.getReputation(agent1Id);
        uint256 rep2 = reputationLedger.getReputation(agent2Id);
        // 500 RATE (5e20 wei) / 1000 = 5e17 reputation each
        assertEq(rep1, 5e17);
        assertEq(rep2, 5e17);
    }
    
    function test_PartialFillFlow() public {
        // Agent1 places order for 300 COMPUTE at 10 RATE per unit
        uint256 totalAmount = 300 * 1e18;
        uint256 pricePerUnit = 10 * 1e18;
        
        vm.startPrank(agent1);
        computeToken.approve(address(orderBook), totalAmount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), totalAmount, pricePerUnit);
        vm.stopPrank();
        
        // Agent2 fills 100 units
        uint256 firstFill = 100 * 1e18;
        uint256 firstCost = (firstFill * pricePerUnit) / 1e18; // 1000 RATE
        
        vm.startPrank(agent2);
        rateToken.approve(address(orderBook), firstCost);
        orderBook.matchOrder(orderId, firstFill);
        vm.stopPrank();
        
        // Check order is still active
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.ACTIVE));
        assertEq(order.filledAmount, firstFill);
        assertEq(orderBook.getRemainingAmount(orderId), 200 * 1e18);
        
        // Check balances after first fill
        assertEq(computeToken.balanceOf(agent2), 1_100 * 1e18);
        assertEq(rateToken.balanceOf(agent1), 11_000 * 1e18);
        
        // Check reputation (1000 RATE / 1000 = 1 * 1e18 reputation points each in wei)
        assertEq(reputationLedger.getReputation(agent1Id), 1 * 1e18);
        assertEq(reputationLedger.getReputation(agent2Id), 1 * 1e18);
        
        // Agent1 cancels remaining order
        vm.prank(agent1);
        orderBook.cancelOrder(orderId);
        
        // Check order is cancelled and tokens returned
        order = orderBook.getOrder(orderId);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.CANCELLED));
        assertEq(computeToken.balanceOf(agent1), 900 * 1e18); // Got back 200 of the 300 locked
    }
}
