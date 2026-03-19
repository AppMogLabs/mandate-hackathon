// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IAgentRegistry {
    function validateAction(address agent, uint8 actionType) external view returns (bool);
    function isActionPermitted(address agent, uint8 actionType) external view returns (bool);
    function agentIdOf(address agent) external view returns (uint256);
}

interface IReputationLedger {
    function recordTransaction(uint256 buyerAgentId, uint256 sellerAgentId, uint256 amount) external;
}

interface IAuditLog {
    function logAction(uint256 agentId, bytes32 action, bytes calldata metadata) external;
}

/// @title OrderBook — Decentralized limit order book for MANDATE resources
/// @notice Agents place/cancel/match orders for resource tokens. All trades settled against RATE.
///         Integrates with AgentRegistry for permission checks, ReputationLedger for trust scores,
///         and AuditLog for immutable action history.
/// @dev Uses OpenZeppelin SafeERC20, ReentrancyGuard, and AccessControl. CEI pattern enforced.
contract OrderBook is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------------
    // Order status enum
    // -------------------------------------------------------------------------
    enum OrderStatus {
        ACTIVE,
        FILLED,
        CANCELLED
    }

    // -------------------------------------------------------------------------
    // Order struct
    // -------------------------------------------------------------------------
    struct Order {
        uint256 orderId;
        address seller; // Agent placing the order (selling resource)
        address resourceToken; // Resource being sold
        uint256 totalAmount; // Total resource amount
        uint256 filledAmount; // Amount already filled
        uint256 pricePerUnit; // Price in RATE per unit of resource
        OrderStatus status;
        uint64 timestamp; // Uses block.timestamp per EthSkills L2 guidance
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IERC20 public immutable rateToken;
    IAgentRegistry public immutable agentRegistry;
    IReputationLedger public immutable reputationLedger;
    IAuditLog public immutable auditLog;

    /// @notice Minimum order amount to prevent dust attacks.
    uint256 public constant MIN_ORDER_AMOUNT = 1e15; // PHASE_3_PLACEHOLDER

    /// @notice Auto-incrementing order ID counter.
    uint256 private _nextOrderId = 1;

    /// @notice Maps orderId => Order struct.
    mapping(uint256 => Order) public orders;

    /// @notice Action type constants (must match AgentRegistry).
    uint8 public constant ACTION_ORDER_PLACE = 1;
    uint8 public constant ACTION_ORDER_CANCEL = 2;
    uint8 public constant ACTION_ORDER_MATCH = 3;

    /// @notice Action hashes for AuditLog.
    bytes32 public constant ORDER_PLACED = keccak256("ORDER_PLACED");
    bytes32 public constant ORDER_MATCHED = keccak256("ORDER_MATCHED");
    bytes32 public constant ORDER_CANCELLED = keccak256("ORDER_CANCELLED");

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new order is placed.
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed seller,
        address indexed resourceToken,
        uint256 amount,
        uint256 pricePerUnit
    );

    /// @notice Emitted when an order is matched (fully or partially).
    event OrderMatched(
        uint256 indexed orderId, address indexed seller, address indexed buyer, uint256 fillAmount, uint256 rateAmount
    );

    /// @notice Emitted when an order is cancelled.
    event OrderCancelled(uint256 indexed orderId, address indexed seller);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error ActionNotPermitted(address agent, uint8 actionType);
    error InvalidOrderParameters();
    error OrderNotFound();
    error OrderNotActive();
    error UnauthorizedCaller();
    error InsufficientOrderRemaining();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _rateToken Address of the RATE token (ERC-20).
    /// @param _agentRegistry Address of the AgentRegistry contract.
    /// @param _reputationLedger Address of the ReputationLedger contract.
    /// @param _auditLog Address of the AuditLog contract.
    /// @param admin Address that receives DEFAULT_ADMIN_ROLE and OPERATOR_ROLE.
    constructor(
        address _rateToken,
        address _agentRegistry,
        address _reputationLedger,
        address _auditLog,
        address admin
    ) {
        require(_rateToken != address(0), "OrderBook: zero rateToken");
        require(_agentRegistry != address(0), "OrderBook: zero agentRegistry");
        require(_reputationLedger != address(0), "OrderBook: zero reputationLedger");
        require(_auditLog != address(0), "OrderBook: zero auditLog");
        require(admin != address(0), "OrderBook: zero admin");

        rateToken = IERC20(_rateToken);
        agentRegistry = IAgentRegistry(_agentRegistry);
        reputationLedger = IReputationLedger(_reputationLedger);
        auditLog = IAuditLog(_auditLog);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Emergency controls
    // -------------------------------------------------------------------------

    /// @notice Pause order placement and matching. Cancel remains available.
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    /// @notice Resume normal operations.
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Order Placement
    // -------------------------------------------------------------------------

    /// @notice Place a limit order to sell a resource for RATE.
    /// @dev Validates agent permission via AgentRegistry.validateAction(). Locks resource tokens
    ///      in escrow via SafeERC20.safeTransferFrom(). Emits OrderPlaced event and logs to AuditLog.
    /// @param resourceToken Address of the resource token being sold.
    /// @param amount Total amount of resource to sell.
    /// @param pricePerUnit Price in RATE per unit of resource.
    /// @return orderId The ID of the newly created order.
    function placeOrder(address resourceToken, uint256 amount, uint256 pricePerUnit)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 orderId)
    {
        // Validation: AgentRegistry permission check (reverts if not permitted)
        agentRegistry.validateAction(msg.sender, ACTION_ORDER_PLACE);

        // Validation: parameters
        if (resourceToken == address(0) || amount < MIN_ORDER_AMOUNT || pricePerUnit == 0) {
            revert InvalidOrderParameters();
        }

        // Effects: create order
        orderId = _nextOrderId++;
        orders[orderId] = Order({
            orderId: orderId,
            seller: msg.sender,
            resourceToken: resourceToken,
            totalAmount: amount,
            filledAmount: 0,
            pricePerUnit: pricePerUnit,
            status: OrderStatus.ACTIVE,
            timestamp: uint64(block.timestamp)
        });

        // Interactions: lock resource tokens in escrow
        IERC20(resourceToken).safeTransferFrom(msg.sender, address(this), amount);

        // Events
        emit OrderPlaced(orderId, msg.sender, resourceToken, amount, pricePerUnit);

        // Audit log
        uint256 sellerAgentId = agentRegistry.agentIdOf(msg.sender);
        bytes memory metadata = abi.encode(orderId, resourceToken, amount, pricePerUnit);
        auditLog.logAction(sellerAgentId, ORDER_PLACED, metadata);

        return orderId;
    }

    // -------------------------------------------------------------------------
    // Order Cancellation
    // -------------------------------------------------------------------------

    /// @notice Cancel an active order and return escrowed tokens to the seller.
    /// @dev Validates caller owns the order and has cancel permission. Returns unfilled resource
    ///      tokens via SafeERC20.safeTransfer(). Emits OrderCancelled and logs to AuditLog.
    /// @param orderId The ID of the order to cancel.
    function cancelOrder(uint256 orderId) external nonReentrant {
        // Checks: order exists and is active
        Order storage order = orders[orderId];
        if (order.seller == address(0)) revert OrderNotFound();
        if (order.status != OrderStatus.ACTIVE) revert OrderNotActive();
        if (order.seller != msg.sender) revert UnauthorizedCaller();

        // Checks: AgentRegistry permission (reverts if not permitted)
        agentRegistry.validateAction(msg.sender, ACTION_ORDER_CANCEL);

        // Effects: mark order as cancelled
        order.status = OrderStatus.CANCELLED;

        // Interactions: return unfilled resource tokens to seller
        uint256 remainingAmount = order.totalAmount - order.filledAmount;
        if (remainingAmount > 0) {
            IERC20(order.resourceToken).safeTransfer(order.seller, remainingAmount);
        }

        // Events
        emit OrderCancelled(orderId, msg.sender);

        // Audit log
        uint256 sellerAgentId = agentRegistry.agentIdOf(msg.sender);
        bytes memory metadata = abi.encode(orderId, remainingAmount);
        auditLog.logAction(sellerAgentId, ORDER_CANCELLED, metadata);
    }

    // -------------------------------------------------------------------------
    // Order Matching
    // -------------------------------------------------------------------------

    /// @notice Match an existing order by buying resources with RATE.
    /// @dev Validates buyer permission, locks RATE in escrow, transfers resource to buyer,
    ///      transfers RATE to seller, records reputation, and logs to audit. Supports partial fills.
    /// @param orderId The ID of the order to match.
    /// @param fillAmount Amount of resource to buy (must be ≤ remaining amount).
    /// @return success True if the match succeeded.
    function matchOrder(uint256 orderId, uint256 fillAmount)
        external
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        // Checks: order exists and is active
        Order storage order = orders[orderId];
        if (order.seller == address(0)) revert OrderNotFound();
        if (order.status != OrderStatus.ACTIVE) revert OrderNotActive();

        // Checks: fillAmount is valid
        uint256 remainingAmount = order.totalAmount - order.filledAmount;
        if (fillAmount == 0 || fillAmount > remainingAmount) {
            revert InsufficientOrderRemaining();
        }

        // Checks: no self-matching (prevents reputation gaming)
        if (msg.sender == order.seller) revert UnauthorizedCaller();

        // Checks: AgentRegistry permission (reverts if not permitted)
        agentRegistry.validateAction(msg.sender, ACTION_ORDER_MATCH);

        // Calculate RATE amount to transfer
        // Both fillAmount and pricePerUnit are in 1e18 units, so divide by 1e18
        uint256 rateAmount = (fillAmount * order.pricePerUnit) / 1e18;
        if (rateAmount == 0) revert InvalidOrderParameters();

        // Effects: update filled amount
        order.filledAmount += fillAmount;

        // Effects: mark as FILLED if fully matched
        if (order.filledAmount == order.totalAmount) {
            order.status = OrderStatus.FILLED;
        }

        // Interactions: transfer RATE from buyer to seller
        rateToken.safeTransferFrom(msg.sender, order.seller, rateAmount);

        // Interactions: transfer resource from escrow to buyer
        IERC20(order.resourceToken).safeTransfer(msg.sender, fillAmount);

        // Events
        emit OrderMatched(orderId, order.seller, msg.sender, fillAmount, rateAmount);

        // Reputation: record transaction
        uint256 buyerAgentId = agentRegistry.agentIdOf(msg.sender);
        uint256 sellerAgentId = agentRegistry.agentIdOf(order.seller);
        reputationLedger.recordTransaction(buyerAgentId, sellerAgentId, rateAmount);

        // Audit log
        bytes memory metadata = abi.encode(orderId, fillAmount, rateAmount, buyerAgentId, sellerAgentId);
        auditLog.logAction(buyerAgentId, ORDER_MATCHED, metadata);

        return true;
    }

    // -------------------------------------------------------------------------
    // Query Functions
    // -------------------------------------------------------------------------

    /// @notice Get order details.
    /// @param orderId The ID of the order to query.
    /// @return order The full Order struct.
    function getOrder(uint256 orderId) external view returns (Order memory order) {
        return orders[orderId];
    }

    /// @notice Get remaining amount available to fill for an order.
    /// @param orderId The ID of the order to query.
    /// @return remaining The unfilled amount.
    function getRemainingAmount(uint256 orderId) external view returns (uint256 remaining) {
        Order storage order = orders[orderId];
        if (order.status != OrderStatus.ACTIVE) return 0;
        return order.totalAmount - order.filledAmount;
    }

    /// @notice Check if an agent is permitted to place an order.
    /// @param agent The agent address to check.
    /// @return permitted True if the agent can place orders.
    function canPlaceOrder(address agent) external view returns (bool permitted) {
        return agentRegistry.isActionPermitted(agent, ACTION_ORDER_PLACE);
    }

    /// @notice Check if an agent is permitted to cancel an order.
    /// @param agent The agent address to check.
    /// @return permitted True if the agent can cancel orders.
    function canCancelOrder(address agent) external view returns (bool permitted) {
        return agentRegistry.isActionPermitted(agent, ACTION_ORDER_CANCEL);
    }

    /// @notice Check if an agent is permitted to match an order.
    /// @param agent The agent address to check.
    /// @return permitted True if the agent can match orders.
    function canMatchOrder(address agent) external view returns (bool permitted) {
        return agentRegistry.isActionPermitted(agent, ACTION_ORDER_MATCH);
    }
}
