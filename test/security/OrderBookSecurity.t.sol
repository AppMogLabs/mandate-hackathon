// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OrderBook} from "../../src/OrderBook.sol";
import {RateToken} from "../../src/RateToken.sol";
import {ResourceToken} from "../../src/ResourceToken.sol";
import {AgentRegistry} from "../../src/AgentRegistry.sol";
import {ReputationLedger} from "../../src/ReputationLedger.sol";
import {AuditLog} from "../../src/AuditLog.sol";

/// @title OrderBook Security Tests — Adversarial edge cases
/// @notice Tests for dust/rounding exploits, self-matching, DoS, and economic attacks.
contract OrderBookSecurityTest is Test {
    OrderBook public orderBook;
    RateToken public rateToken;
    ResourceToken public computeToken;
    AgentRegistry public agentRegistry;
    ReputationLedger public reputationLedger;
    AuditLog public auditLog;

    address public admin = address(1);
    address public seller = address(2);
    address public buyer = address(3);

    uint256 public sellerAgentId;
    uint256 public buyerAgentId;

    uint256 constant INITIAL_RATE = 1_000_000 * 1e18;
    uint256 constant INITIAL_COMPUTE = 10_000 * 1e18;

    function setUp() public {
        rateToken = new RateToken(admin);
        computeToken = new ResourceToken("Compute", "COMPUTE", admin);
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

        vm.startPrank(admin);
        reputationLedger.grantRole(reputationLedger.RECORDER_ROLE(), address(orderBook));
        auditLog.grantRole(auditLog.LOGGER_ROLE(), address(orderBook));

        sellerAgentId = agentRegistry.registerAgent(seller, "ipfs://seller");
        buyerAgentId = agentRegistry.registerAgent(buyer, "ipfs://buyer");

        agentRegistry.grantAction(sellerAgentId, agentRegistry.ACTION_ORDER_PLACE());
        agentRegistry.grantAction(sellerAgentId, agentRegistry.ACTION_ORDER_CANCEL());
        agentRegistry.grantAction(sellerAgentId, agentRegistry.ACTION_ORDER_MATCH());
        agentRegistry.grantAction(buyerAgentId, agentRegistry.ACTION_ORDER_PLACE());
        agentRegistry.grantAction(buyerAgentId, agentRegistry.ACTION_ORDER_CANCEL());
        agentRegistry.grantAction(buyerAgentId, agentRegistry.ACTION_ORDER_MATCH());

        rateToken.transfer(seller, INITIAL_RATE / 2);
        rateToken.transfer(buyer, INITIAL_RATE / 2);
        computeToken.mint(seller, INITIAL_COMPUTE);
        computeToken.mint(buyer, INITIAL_COMPUTE);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // HIGH: Zero rateAmount via integer truncation — free token extraction
    // -------------------------------------------------------------------------

    /// @notice FIXED: fillAmount * pricePerUnit < 1e18 now reverts with InvalidOrderParameters
    ///         because rateAmount == 0 is blocked.
    function test_ZeroRateAmount_NowReverts() public {
        // Seller places order: 1000 tokens at 0.1 RATE per unit (1e17)
        uint256 amount = 1000 * 1e18;
        uint256 pricePerUnit = 1e17; // 0.1 RATE

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        // Buyer tries to fill 1 wei — rateAmount = 1 * 1e17 / 1e18 = 0 → reverts
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 1);
        vm.expectRevert(OrderBook.InvalidOrderParameters.selector);
        orderBook.matchOrder(orderId, 1); // fill 1 wei → reverts
        vm.stopPrank();
    }

    /// @notice FIXED: Repeated dust fills are now blocked by rateAmount > 0 check.
    function test_RepeatedDustFills_NowReverts() public {
        uint256 amount = 1e18; // Minimum order size (above MIN_ORDER_AMOUNT)
        uint256 pricePerUnit = 1e17; // 0.1 RATE per unit

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        // Buyer tries to fill 1 wei — rateAmount = 0 → reverts
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 1e18);
        vm.expectRevert(OrderBook.InvalidOrderParameters.selector);
        orderBook.matchOrder(orderId, 1);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // MEDIUM: Self-matching — reputation gaming
    // -------------------------------------------------------------------------

    /// @notice FIXED: Self-matching now reverts with UnauthorizedCaller.
    function test_SelfMatch_NowReverts() public {
        // Seller places order
        uint256 amount = 1000 * 1e18;
        uint256 pricePerUnit = 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);

        // Seller tries to match own order — blocked by self-match check
        rateToken.approve(address(orderBook), 1000 * 1e18);
        vm.expectRevert(OrderBook.UnauthorizedCaller.selector);
        orderBook.matchOrder(orderId, amount);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // LOW: No minimum order size — dust order DoS
    // -------------------------------------------------------------------------

    /// @notice FIXED: Dust orders below MIN_ORDER_AMOUNT now revert.
    function test_DustOrder_NowReverts() public {
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 1000);

        // Place 1-wei order — below MIN_ORDER_AMOUNT → reverts
        vm.expectRevert(OrderBook.InvalidOrderParameters.selector);
        orderBook.placeOrder(address(computeToken), 1, 1);
        vm.stopPrank();
    }

    /// @notice Orders at MIN_ORDER_AMOUNT succeed.
    function test_MinOrderAmount_Succeeds() public {
        uint256 minAmount = orderBook.MIN_ORDER_AMOUNT();

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), minAmount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), minAmount, 1e18);
        vm.stopPrank();

        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.totalAmount, minAmount);
    }

    // -------------------------------------------------------------------------
    // EDGE CASE: Place order without sufficient approval
    // -------------------------------------------------------------------------

    /// @notice Placing an order without token approval reverts.
    function test_PlaceOrder_RevertsWithoutApproval() public {
        vm.prank(seller);
        vm.expectRevert();
        orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
    }

    // -------------------------------------------------------------------------
    // EDGE CASE: Match order with insufficient RATE balance
    // -------------------------------------------------------------------------

    /// @notice Matching without sufficient RATE balance reverts.
    function test_MatchOrder_RevertsInsufficientRateBalance() public {
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Create a new agent with no RATE
        address poorBuyer = address(99);
        vm.startPrank(admin);
        uint256 poorId = agentRegistry.registerAgent(poorBuyer, "ipfs://poor");
        agentRegistry.grantAction(poorId, agentRegistry.ACTION_ORDER_MATCH());
        vm.stopPrank();

        vm.startPrank(poorBuyer);
        rateToken.approve(address(orderBook), type(uint256).max);
        vm.expectRevert();
        orderBook.matchOrder(orderId, 100 * 1e18);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // EDGE CASE: Cancel already-cancelled order
    // -------------------------------------------------------------------------

    /// @notice Cancelling an already-cancelled order reverts.
    function test_CancelOrder_RevertsCancelledTwice() public {
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        orderBook.cancelOrder(orderId);

        vm.expectRevert(OrderBook.OrderNotActive.selector);
        orderBook.cancelOrder(orderId);
        vm.stopPrank();
    }
}
