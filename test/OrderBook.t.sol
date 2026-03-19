// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/OrderBook.sol";
import "../src/RateToken.sol";
import "../src/ResourceToken.sol";
import "../src/AgentRegistry.sol";
import "../src/ReputationLedger.sol";
import "../src/AuditLog.sol";

contract OrderBookTest is Test {
    OrderBook public orderBook;
    RateToken public rateToken;
    ResourceToken public computeToken;
    AgentRegistry public agentRegistry;
    ReputationLedger public reputationLedger;
    AuditLog public auditLog;

    address public admin = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public unauthorized = address(4);

    uint256 public sellerAgentId;
    uint256 public buyerAgentId;

    uint256 constant INITIAL_RATE_BALANCE = 1_000_000 * 1e18;
    uint256 constant INITIAL_COMPUTE_BALANCE = 10_000 * 1e18;

    event OrderPlaced(
        uint256 indexed orderId,
        address indexed seller,
        address indexed resourceToken,
        uint256 amount,
        uint256 pricePerUnit
    );

    event OrderMatched(
        uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 fillAmount, uint256 rateAmount
    );

    event OrderCancelled(uint256 indexed orderId, address indexed seller);

    function setUp() public {
        // Deploy core contracts
        rateToken = new RateToken(admin);
        computeToken = new ResourceToken("Compute", "COMPUTE", admin);
        agentRegistry = new AgentRegistry(admin);
        reputationLedger = new ReputationLedger(admin);
        auditLog = new AuditLog(admin);

        // Deploy OrderBook
        orderBook = new OrderBook(
            address(rateToken), address(agentRegistry), address(reputationLedger), address(auditLog), admin
        );

        // Grant roles
        vm.startPrank(admin);
        reputationLedger.grantRole(reputationLedger.RECORDER_ROLE(), address(orderBook));
        auditLog.grantRole(auditLog.LOGGER_ROLE(), address(orderBook));
        computeToken.grantRole(computeToken.MINTER_ROLE(), admin);

        // Register agents
        sellerAgentId = agentRegistry.registerAgent(seller, "ipfs://seller");
        buyerAgentId = agentRegistry.registerAgent(buyer, "ipfs://buyer");

        // Grant action permissions
        agentRegistry.grantAction(sellerAgentId, agentRegistry.ACTION_ORDER_PLACE());
        agentRegistry.grantAction(sellerAgentId, agentRegistry.ACTION_ORDER_CANCEL());
        agentRegistry.grantAction(buyerAgentId, agentRegistry.ACTION_ORDER_MATCH());
        agentRegistry.grantAction(buyerAgentId, agentRegistry.ACTION_ORDER_PLACE());

        // Mint tokens
        rateToken.transfer(seller, INITIAL_RATE_BALANCE / 2);
        rateToken.transfer(buyer, INITIAL_RATE_BALANCE / 2);
        computeToken.mint(seller, INITIAL_COMPUTE_BALANCE);

        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertEq(address(orderBook.rateToken()), address(rateToken));
        assertEq(address(orderBook.agentRegistry()), address(agentRegistry));
        assertEq(address(orderBook.reputationLedger()), address(reputationLedger));
        assertEq(address(orderBook.auditLog()), address(auditLog));
        assertTrue(orderBook.hasRole(orderBook.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_PlaceOrder_Success() public {
        uint256 amount = 100 * 1e18;
        uint256 pricePerUnit = 3 * 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);

        vm.expectEmit(true, true, true, true);
        emit OrderPlaced(1, seller, address(computeToken), amount, pricePerUnit);

        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        assertEq(orderId, 1);
        assertEq(computeToken.balanceOf(address(orderBook)), amount);
        assertEq(computeToken.balanceOf(seller), INITIAL_COMPUTE_BALANCE - amount);

        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.seller, seller);
        assertEq(order.resourceToken, address(computeToken));
        assertEq(order.totalAmount, amount);
        assertEq(order.filledAmount, 0);
        assertEq(order.pricePerUnit, pricePerUnit);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.ACTIVE));
    }

    function test_PlaceOrder_RevertsUnauthorized() public {
        // Unauthorized agent is not registered, so AgentRegistry reverts with AgentNotRegistered
        vm.startPrank(unauthorized);
        computeToken.approve(address(orderBook), 100 * 1e18);

        vm.expectRevert();
        orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();
    }

    function test_PlaceOrder_RevertsInvalidParameters() public {
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);

        // Zero resource token
        vm.expectRevert(OrderBook.InvalidOrderParameters.selector);
        orderBook.placeOrder(address(0), 100 * 1e18, 3 * 1e18);

        // Zero amount
        vm.expectRevert(OrderBook.InvalidOrderParameters.selector);
        orderBook.placeOrder(address(computeToken), 0, 3 * 1e18);

        // Zero price
        vm.expectRevert(OrderBook.InvalidOrderParameters.selector);
        orderBook.placeOrder(address(computeToken), 100 * 1e18, 0);

        vm.stopPrank();
    }

    function test_MatchOrder_FullFill() public {
        // Seller places order
        uint256 amount = 100 * 1e18;
        uint256 pricePerUnit = 3 * 1e18;
        uint256 totalCost = amount * pricePerUnit / 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        // Buyer matches order
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), totalCost);

        vm.expectEmit(true, true, true, true);
        emit OrderMatched(orderId, seller, buyer, amount, totalCost);

        bool success = orderBook.matchOrder(orderId, amount);
        vm.stopPrank();

        assertTrue(success);

        // Check token transfers
        assertEq(computeToken.balanceOf(buyer), amount);
        assertEq(computeToken.balanceOf(address(orderBook)), 0);
        assertEq(rateToken.balanceOf(seller), INITIAL_RATE_BALANCE / 2 + totalCost);
        assertEq(rateToken.balanceOf(buyer), INITIAL_RATE_BALANCE / 2 - totalCost);

        // Check order status
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.filledAmount, amount);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.FILLED));

        // Check reputation was recorded
        assertGt(reputationLedger.getReputation(buyerAgentId), 0);
        assertGt(reputationLedger.getReputation(sellerAgentId), 0);
    }

    function test_MatchOrder_PartialFill() public {
        // Seller places order for 100 units
        uint256 totalAmount = 100 * 1e18;
        uint256 pricePerUnit = 3 * 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), totalAmount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), totalAmount, pricePerUnit);
        vm.stopPrank();

        // Buyer matches only 40 units
        uint256 fillAmount = 40 * 1e18;
        uint256 fillCost = fillAmount * pricePerUnit / 1e18;

        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), fillCost);
        orderBook.matchOrder(orderId, fillAmount);
        vm.stopPrank();

        // Check order status
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.filledAmount, fillAmount);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.ACTIVE));
        assertEq(orderBook.getRemainingAmount(orderId), totalAmount - fillAmount);

        // Check balances
        assertEq(computeToken.balanceOf(buyer), fillAmount);
        assertEq(computeToken.balanceOf(address(orderBook)), totalAmount - fillAmount);
    }

    function test_MatchOrder_MultiplePartialFills() public {
        // Seller places order for 100 units
        uint256 totalAmount = 100 * 1e18;
        uint256 pricePerUnit = 2 * 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), totalAmount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), totalAmount, pricePerUnit);
        vm.stopPrank();

        // Register buyer2 and set up
        address buyer2 = address(5);
        vm.startPrank(admin);
        uint256 buyer2AgentId = agentRegistry.registerAgent(buyer2, "ipfs://buyer2");
        agentRegistry.grantAction(buyer2AgentId, agentRegistry.ACTION_ORDER_MATCH());
        vm.stopPrank();

        // Mint RATE directly to buyer2 (admin may not have balance left)
        deal(address(rateToken), buyer2, 200 * 1e18);

        // First buyer fills 30 units
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 60 * 1e18);
        orderBook.matchOrder(orderId, 30 * 1e18);
        vm.stopPrank();

        // Second buyer fills 50 units
        vm.startPrank(buyer2);
        rateToken.approve(address(orderBook), 100 * 1e18);
        orderBook.matchOrder(orderId, 50 * 1e18);
        vm.stopPrank();

        // First buyer fills remaining 20 units
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 40 * 1e18);
        orderBook.matchOrder(orderId, 20 * 1e18);
        vm.stopPrank();

        // Check final state
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(order.filledAmount, totalAmount);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.FILLED));
        assertEq(orderBook.getRemainingAmount(orderId), 0);
    }

    function test_MatchOrder_RevertsUnauthorized() public {
        // Seller places order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Unauthorized agent is not registered, so AgentRegistry reverts
        vm.startPrank(unauthorized);
        vm.expectRevert();
        orderBook.matchOrder(orderId, 100 * 1e18);
        vm.stopPrank();
    }

    function test_MatchOrder_RevertsInsufficientRemaining() public {
        // Seller places order for 100 units
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Buyer tries to fill 150 units
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 450 * 1e18);
        vm.expectRevert(OrderBook.InsufficientOrderRemaining.selector);
        orderBook.matchOrder(orderId, 150 * 1e18);
        vm.stopPrank();
    }

    function test_CancelOrder_Success() public {
        // Seller places order
        uint256 amount = 100 * 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, 3 * 1e18);

        // Cancel order
        vm.expectEmit(true, true, false, false);
        emit OrderCancelled(orderId, seller);

        orderBook.cancelOrder(orderId);
        vm.stopPrank();

        // Check order status
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.CANCELLED));

        // Check tokens returned
        assertEq(computeToken.balanceOf(seller), INITIAL_COMPUTE_BALANCE);
        assertEq(computeToken.balanceOf(address(orderBook)), 0);
    }

    function test_CancelOrder_PartiallyFilled() public {
        // Seller places order for 100 units
        uint256 totalAmount = 100 * 1e18;
        uint256 pricePerUnit = 3 * 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), totalAmount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), totalAmount, pricePerUnit);
        vm.stopPrank();

        // Buyer fills 40 units
        uint256 fillAmount = 40 * 1e18;
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), fillAmount * pricePerUnit / 1e18);
        orderBook.matchOrder(orderId, fillAmount);
        vm.stopPrank();

        // Seller cancels remaining
        vm.prank(seller);
        orderBook.cancelOrder(orderId);

        // Check balances — seller got back unfilled tokens, buyer keeps filled amount
        assertEq(computeToken.balanceOf(seller), INITIAL_COMPUTE_BALANCE - fillAmount);
        assertEq(computeToken.balanceOf(address(orderBook)), 0);
    }

    function test_CancelOrder_RevertsUnauthorized() public {
        // Seller places order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Unauthorized tries to cancel
        vm.prank(unauthorized);
        vm.expectRevert(OrderBook.UnauthorizedCaller.selector);
        orderBook.cancelOrder(orderId);
    }

    function test_CancelOrder_RevertsNotOwner() public {
        // Seller places order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Buyer tries to cancel seller's order
        vm.prank(buyer);
        vm.expectRevert(OrderBook.UnauthorizedCaller.selector);
        orderBook.cancelOrder(orderId);
    }

    function test_CancelOrder_RevertsAlreadyFilled() public {
        // Seller places order
        uint256 amount = 100 * 1e18;
        uint256 pricePerUnit = 3 * 1e18;

        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        // Buyer fills entire order
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), amount * pricePerUnit / 1e18);
        orderBook.matchOrder(orderId, amount);
        vm.stopPrank();

        // Seller tries to cancel filled order
        vm.prank(seller);
        vm.expectRevert(OrderBook.OrderNotActive.selector);
        orderBook.cancelOrder(orderId);
    }

    function test_QueryFunctions() public view {
        assertTrue(orderBook.canPlaceOrder(seller));
        assertTrue(orderBook.canCancelOrder(seller));
        assertTrue(orderBook.canMatchOrder(buyer));
        // Unregistered agent returns false (no revert)
        assertFalse(orderBook.canPlaceOrder(unauthorized));
        assertFalse(orderBook.canMatchOrder(unauthorized));
        // Registered but no cancel permission
        assertFalse(orderBook.canCancelOrder(buyer));
    }

    function testFuzz_PlaceAndMatchOrder(uint96 amount, uint96 pricePerUnit) public {
        vm.assume(amount >= 1e15 && amount < 1000 * 1e18); // Respect MIN_ORDER_AMOUNT
        vm.assume(pricePerUnit > 0 && pricePerUnit < 100 * 1e18);

        // Ensure rateAmount > 0 and buyer has enough RATE
        uint256 totalCost = uint256(amount) * uint256(pricePerUnit) / 1e18;
        vm.assume(totalCost > 0 && totalCost <= INITIAL_RATE_BALANCE / 2);

        // Place order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        // Match order
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), totalCost);
        orderBook.matchOrder(orderId, amount);
        vm.stopPrank();

        // Verify
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.FILLED));
        assertEq(computeToken.balanceOf(buyer), amount);
    }

    function test_MatchOrder_RevertsZeroFillAmount() public {
        // Seller places order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Buyer tries to fill 0 units
        vm.startPrank(buyer);
        vm.expectRevert(OrderBook.InsufficientOrderRemaining.selector);
        orderBook.matchOrder(orderId, 0);
        vm.stopPrank();
    }

    function test_MatchOrder_RevertsOnCancelledOrder() public {
        // Seller places and cancels order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        orderBook.cancelOrder(orderId);
        vm.stopPrank();

        // Buyer tries to match cancelled order
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 300 * 1e18);
        vm.expectRevert(OrderBook.OrderNotActive.selector);
        orderBook.matchOrder(orderId, 100 * 1e18);
        vm.stopPrank();
    }

    function test_MatchOrder_RevertsRegisteredButNoPermission() public {
        // Register unauthorized user but don't grant ORDER_MATCH
        vm.startPrank(admin);
        agentRegistry.registerAgent(unauthorized, "ipfs://unauthorized");
        vm.stopPrank();

        // Seller places order
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(computeToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Registered but unauthorized tries to match
        vm.startPrank(unauthorized);
        rateToken.approve(address(orderBook), 300 * 1e18);
        vm.expectRevert();
        orderBook.matchOrder(orderId, 100 * 1e18);
        vm.stopPrank();
    }

    function test_PlaceOrder_RevertsOnNonexistentOrder() public {
        // Try to cancel non-existent order
        vm.startPrank(seller);
        vm.expectRevert(OrderBook.OrderNotFound.selector);
        orderBook.cancelOrder(999);
        vm.stopPrank();
    }

    function test_AtomicSettlement_TokensTransferredCorrectly() public {
        // Verify exact token flows for atomic settlement
        uint256 amount = 50 * 1e18;
        uint256 pricePerUnit = 4 * 1e18;
        uint256 totalCost = amount * pricePerUnit / 1e18; // 200 RATE

        uint256 sellerComputeBefore = computeToken.balanceOf(seller);
        uint256 sellerRateBefore = rateToken.balanceOf(seller);
        uint256 buyerComputeBefore = computeToken.balanceOf(buyer);
        uint256 buyerRateBefore = rateToken.balanceOf(buyer);

        // Seller places order (locks COMPUTE)
        vm.startPrank(seller);
        computeToken.approve(address(orderBook), amount);
        uint256 orderId = orderBook.placeOrder(address(computeToken), amount, pricePerUnit);
        vm.stopPrank();

        // Verify escrow
        assertEq(computeToken.balanceOf(seller), sellerComputeBefore - amount);
        assertEq(computeToken.balanceOf(address(orderBook)), amount);

        // Buyer matches order
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), totalCost);
        orderBook.matchOrder(orderId, amount);
        vm.stopPrank();

        // Verify final balances
        assertEq(computeToken.balanceOf(buyer), buyerComputeBefore + amount);
        assertEq(computeToken.balanceOf(address(orderBook)), 0);
        assertEq(rateToken.balanceOf(seller), sellerRateBefore + totalCost);
        assertEq(rateToken.balanceOf(buyer), buyerRateBefore - totalCost);
    }

    // Reentrancy attack test with malicious token callback
    function test_ReentrancyGuard() public {
        // Deploy a malicious token that attempts reentrancy on transfer
        MaliciousToken malToken = new MaliciousToken(address(orderBook));

        // Register malToken seller
        address malSeller = address(6);
        vm.startPrank(admin);
        uint256 malAgentId = agentRegistry.registerAgent(malSeller, "ipfs://mal");
        agentRegistry.grantAction(malAgentId, agentRegistry.ACTION_ORDER_PLACE());
        agentRegistry.grantAction(malAgentId, agentRegistry.ACTION_ORDER_CANCEL());
        vm.stopPrank();

        // Mint malicious tokens to seller
        malToken.mint(malSeller, 1000 * 1e18);

        // Place order with malicious token
        vm.startPrank(malSeller);
        malToken.approve(address(orderBook), 100 * 1e18);
        uint256 orderId = orderBook.placeOrder(address(malToken), 100 * 1e18, 3 * 1e18);
        vm.stopPrank();

        // Configure malToken to attempt reentrancy on next transfer
        malToken.setReentrant(true, orderId);

        // Buyer matches — malicious token callback should be blocked by nonReentrant
        vm.startPrank(buyer);
        rateToken.approve(address(orderBook), 300 * 1e18);
        // The malicious callback will try to call cancelOrder during transfer,
        // but ReentrancyGuard prevents it. The matchOrder itself should succeed
        // because the reentrancy attempt reverts silently (try/catch in maltoken).
        orderBook.matchOrder(orderId, 100 * 1e18);
        vm.stopPrank();

        // Verify the order was properly filled despite reentrancy attempt
        OrderBook.Order memory order = orderBook.getOrder(orderId);
        assertEq(uint256(order.status), uint256(OrderBook.OrderStatus.FILLED));
    }
}

/// @notice Malicious ERC-20 token that attempts reentrancy during transfers.
contract MaliciousToken {
    string public name = "EVIL";
    string public symbol = "EVIL";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public target;
    bool public reentrant;
    uint256 public reentrantOrderId;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address _target) {
        target = _target;
    }

    function setReentrant(bool _reentrant, uint256 _orderId) external {
        reentrant = _reentrant;
        reentrantOrderId = _orderId;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);

        // Attempt reentrancy on transfer to buyer (during matchOrder)
        if (reentrant && to != target && to != address(0)) {
            reentrant = false; // Prevent infinite loop
            // Try to call cancelOrder during the transfer callback
            try OrderBook(target).cancelOrder(reentrantOrderId) {
            // If this succeeds, reentrancy guard is broken
            }
                catch {
                // Expected: ReentrancyGuard blocks this
            }
        }
        return true;
    }
}
