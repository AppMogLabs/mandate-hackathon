# MANDATE Day 2 — OrderBook + Reputation System

Build OrderBook, ReputationLedger, AuditLog for The Synthesis hackathon (deadline: March 22, 2026).

## Context Documents (Read First)
1. `/Users/user01/.openclaw/workspace/projects/active/MANDATE/CLAUDE_HANDOFF.md` — Full project context
2. `/Users/user01/.openclaw/workspace/projects/active/MANDATE/Hackathon/MANDATE_Phase2_SmartContracts_v03.md` — Technical spec
3. `/Users/user01/.openclaw/workspace/projects/active/MANDATE/contracts/DAY1_COMPLETION_REPORT.md` — Day 1 deliverables

## Skills Available (Already Cloned)
- `.megaeth-skill/` — MegaETH development patterns, optimization guides
- OpenZeppelin 5.x docs: https://docs.openzeppelin.com/contracts/5.x
- ethskills.com security patterns: https://ethskills.com/security

## Day 1 Foundation (Already Built)
✅ **RateToken** (src/RateToken.sol) — ERC-20 utility token with burn, permit, AccessControl (1M initial supply)
✅ **ResourceToken** (src/ResourceToken.sol) — ERC-20 template for COMPUTE/CHIPS (MINTER_ROLE gated)
✅ **ResourceTokenFactory** (src/ResourceTokenFactory.sol) — Factory deployer with AccessControl + event tracking
✅ **AgentRegistry** (src/AgentRegistry.sol) — ERC-721 identity NFTs + bitmap allowlists (8 action types) + `validateAction()` gate

## Your Mission: Build 3 New Contracts

### 1. OrderBook (src/OrderBook.sol) — ~250 lines

**Purpose:** Peer-to-peer marketplace for resource tokens (COMPUTE, CHIPS) priced in RATE tokens.

**Architecture:**
- Sellers place orders (lock RATE tokens as collateral)
- Buyers match orders (atomic settlement)
- All actions gated by `AgentRegistry.validateAction()`
- Integrates with ReputationLedger + AuditLog

**Key Functions:**

#### `placeOrder(address resourceToken, uint256 amount, uint256 pricePerUnit) → uint256 orderId`
**Logic:**
1. Validate: `AgentRegistry.validateAction(msg.sender, ORDER_PLACE)` (action type = 1)
2. Calculate total cost: `totalCost = amount * pricePerUnit`
3. Transfer RATE tokens from seller to OrderBook: `rateToken.transferFrom(msg.sender, address(this), totalCost)` (use SafeERC20)
4. Create order: `Order({seller: msg.sender, resourceToken, totalAmount: amount, filledAmount: 0, pricePerUnit, status: ACTIVE, timestamp: block.timestamp})`
5. Store: `orders[nextOrderId] = order`
6. Increment: `nextOrderId++`
7. Emit: `OrderPlaced(orderId, msg.sender, resourceToken, amount, pricePerUnit)`
8. Call: `auditLog.logAction(agentIdOf(msg.sender), "ORDER_PLACED", abi.encode(orderId))`

**Security:**
- ReentrancyGuard
- CEI pattern (update state before external calls)
- SafeERC20 for transfers

#### `cancelOrder(uint256 orderId)`
**Logic:**
1. Validate: order exists, caller is seller, status is ACTIVE
2. Validate: `AgentRegistry.validateAction(msg.sender, ORDER_CANCEL)` (action type = 2)
3. Calculate refund: `refundAmount = (order.totalAmount - order.filledAmount) * order.pricePerUnit`
4. Update state: `order.status = CANCELLED`
5. Transfer: Return locked RATE tokens to seller
6. Emit: `OrderCancelled(orderId)`
7. Call: `auditLog.logAction(agentIdOf(msg.sender), "ORDER_CANCELLED", abi.encode(orderId))`

#### `matchOrder(uint256 orderId, uint256 fillAmount) → bool`
**Logic:**
1. Validate: order exists, status is ACTIVE, fillAmount > 0, fillAmount <= remaining amount
2. Validate: `AgentRegistry.validateAction(msg.sender, ORDER_MATCH)` (action type = 3)
3. Calculate payment: `rateAmount = fillAmount * order.pricePerUnit`
4. Update state: `order.filledAmount += fillAmount`
5. If fully filled: `order.status = FILLED`
6. Transfer resource tokens: `order.resourceToken.transferFrom(msg.sender, order.seller, fillAmount)` (SafeERC20)
7. Transfer RATE tokens: `rateToken.transfer(msg.sender, rateAmount)` (from locked collateral)
8. Emit: `OrderMatched(orderId, order.seller, msg.sender, fillAmount, rateAmount)`
9. Call: `reputationLedger.recordTransaction(agentIdOf(msg.sender), agentIdOf(order.seller), fillAmount)`
10. Call: `auditLog.logAction(agentIdOf(msg.sender), "ORDER_MATCHED", abi.encode(orderId, fillAmount))`

**Helper Function:**
- `agentIdOf(address owner) → uint256` — Reverse lookup via `AgentRegistry.tokenOfOwnerByIndex(owner, 0)` (assumes 1 NFT per owner)

**Storage:**
```solidity
struct Order {
    address seller;
    address resourceToken;
    uint256 totalAmount;
    uint256 filledAmount;
    uint256 pricePerUnit;
    OrderStatus status;
    uint256 timestamp;
}

enum OrderStatus { ACTIVE, FILLED, CANCELLED }

mapping(uint256 => Order) public orders;
uint256 public nextOrderId = 1;
```

**Constructor:**
```solidity
constructor(
    address _rateToken,
    address _agentRegistry,
    address _reputationLedger,
    address _auditLog
)
```

**Imports:**
- OpenZeppelin 5.x: `AccessControl`, `ReentrancyGuard`
- OpenZeppelin 5.x: `SafeERC20`, `IERC20`

---

### 2. ReputationLedger (src/ReputationLedger.sol) — ~120 lines

**Purpose:** Track on-chain reputation scores for agents based on completed transactions.

**Key Functions:**

#### `recordTransaction(uint256 buyerAgentId, uint256 sellerAgentId, uint256 amount)`
**Logic:**
1. Validate: `onlyRole(RECORDER_ROLE)` (granted to OrderBook)
2. Increment: `reputationScores[buyerAgentId] += amount`
3. Increment: `reputationScores[sellerAgentId] += amount`
4. Emit: `ReputationUpdated(buyerAgentId, reputationScores[buyerAgentId])`
5. Emit: `ReputationUpdated(sellerAgentId, reputationScores[sellerAgentId])`

#### `getReputation(uint256 agentId) → uint256`
**Logic:**
- View function: Return `reputationScores[agentId]`

**Storage:**
```solidity
mapping(uint256 => uint256) public reputationScores;
bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");
```

**Constructor:**
```solidity
constructor(address defaultAdmin) {
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
}
```

**Imports:**
- OpenZeppelin 5.x: `AccessControl`

---

### 3. AuditLog (src/AuditLog.sol) — ~60 lines

**Purpose:** Immutable event log for all critical actions (no state storage, events only).

**Key Functions:**

#### `logAction(uint256 agentId, bytes32 action, bytes calldata metadata)`
**Logic:**
1. Validate: `onlyRole(LOGGER_ROLE)`
2. Emit: `ActionLogged(agentId, action, metadata, block.timestamp)`

**Storage:**
```solidity
bytes32 public constant LOGGER_ROLE = keccak256("LOGGER_ROLE");
```

**Constructor:**
```solidity
constructor(address defaultAdmin) {
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
}
```

**Actions to Log:**
- `ORDER_PLACED`, `ORDER_MATCHED`, `ORDER_CANCELLED` (from OrderBook)
- `AGENT_REGISTERED`, `ALLOWLIST_UPDATED` (from AgentRegistry — wire in Day 3)
- `FEEDBACK_POSTED` (Day 3)

**Imports:**
- OpenZeppelin 5.x: `AccessControl`

---

## Non-Negotiable Requirements

### Code Quality
- Solidity 0.8.24+
- OpenZeppelin 5.x imports ONLY (no 4.x)
- Use `SafeERC20` for ALL token transfers
- `ReentrancyGuard` on all state-changing functions
- CEI pattern (Checks-Effects-Interactions)
- Use `block.timestamp` (NOT `block.number`)
- NatSpec comments on ALL external functions
- Zero compiler warnings

### Security Patterns
- AgentRegistry.validateAction() on ALL write paths (OrderBook only)
- AccessControl roles for cross-contract calls (ReputationLedger, AuditLog)
- No floating point math (use integer arithmetic)
- No unchecked transfers (always SafeERC20)

### Testing Requirements
Write comprehensive tests in `test/`:

**test/OrderBook.t.sol:**
- ✅ Place order with valid permissions
- ✅ Place order fails without permissions
- ✅ Cancel order by owner
- ✅ Cancel order fails for non-owner
- ✅ Match order (full fill)
- ✅ Match order (partial fill)
- ✅ Match order fails without permissions
- ✅ Atomic settlement verification (tokens transferred correctly)
- ✅ ReentrancyGuard attack test (simulate malicious callback)
- ✅ Edge cases: zero amounts, invalid token addresses

**test/ReputationLedger.t.sol:**
- ✅ Record transaction (authorized caller)
- ✅ Record transaction fails (unauthorized caller)
- ✅ Reputation score accumulation (multiple transactions)
- ✅ Get reputation (view function)

**test/AuditLog.t.sol:**
- ✅ Log action (authorized caller)
- ✅ Log action fails (unauthorized caller)
- ✅ Event emission verification

**Integration Tests:**
- ✅ End-to-end flow: register agent → place order → match order → verify reputation + audit log
- ✅ Use RateToken + COMPUTE resource from Day 1

**Coverage Target:**
- 100% branch coverage on order matching logic
- 80%+ overall line coverage

**Run:**
```bash
forge test
forge coverage --report summary
```

---

## Deployment Script Updates

Update `script/Deploy.s.sol` to include Day 2 contracts:

```solidity
// ... Day 1 deployments (RATE, ResourceTokenFactory, COMPUTE, CHIPS, AgentRegistry)

// Day 2 deployments
ReputationLedger reputationLedger = new ReputationLedger(msg.sender);
console.log("ReputationLedger deployed:", address(reputationLedger));

AuditLog auditLog = new AuditLog(msg.sender);
console.log("AuditLog deployed:", address(auditLog));

OrderBook orderBook = new OrderBook(
    address(rateToken),
    address(agentRegistry),
    address(reputationLedger),
    address(auditLog)
);
console.log("OrderBook deployed:", address(orderBook));

// Grant roles
reputationLedger.grantRole(reputationLedger.RECORDER_ROLE(), address(orderBook));
auditLog.grantRole(auditLog.LOGGER_ROLE(), address(orderBook));
auditLog.grantRole(auditLog.LOGGER_ROLE(), address(agentRegistry)); // For Day 3

console.log("Roles granted");
```

---

## Documentation Updates

### Update `README.md`
Add Day 2 contracts to architecture section:

```markdown
## Architecture (7 Contracts)

**Economic Layer:**
- RateToken — ERC-20 utility token (1M supply)
- ResourceToken — ERC-20 template for COMPUTE/CHIPS
- ResourceTokenFactory — Minimal proxy deployer

**Identity & Access:**
- AgentRegistry — ERC-721 NFTs + bitmap allowlists (8 action types)

**Marketplace (Day 2):**
- OrderBook — P2P resource trading with atomic settlement
- ReputationLedger — On-chain reputation scores
- AuditLog — Immutable event log for critical actions
```

Add usage example:

```markdown
## OrderBook Usage

```solidity
// 1. Register agent
uint256 agentId = agentRegistry.register();

// 2. Grant ORDER_PLACE permission
agentRegistry.grantAction(agentId, 1); // ORDER_PLACE

// 3. Approve RATE tokens
rateToken.approve(address(orderBook), 1000 ether);

// 4. Place order
uint256 orderId = orderBook.placeOrder(
    address(computeToken), // resource
    100 ether,             // amount
    10 ether               // price per unit (10 RATE per COMPUTE)
);

// 5. Match order (as buyer)
computeToken.approve(address(orderBook), 50 ether);
orderBook.matchOrder(orderId, 50 ether); // Partial fill
```
```

### Create `DAY2_COMPLETION_REPORT.md`
Template:

```markdown
# MANDATE Day 2 — Completion Report

## Deliverables

### Contracts Implemented (X lines in `src/`)
1. ✅ OrderBook.sol — P2P marketplace with atomic settlement
2. ✅ ReputationLedger.sol — On-chain reputation tracking
3. ✅ AuditLog.sol — Immutable event log

### Test Suite (X lines in `test/`)
- ✅ OrderBook.t.sol — X tests (place/cancel/match/security)
- ✅ ReputationLedger.t.sol — X tests (record/authorize/accumulate)
- ✅ AuditLog.t.sol — X tests (log/authorize/events)
- ✅ Integration.t.sol — End-to-end flow tests

### Verification
```bash
forge build  # ✅ Zero errors, zero warnings
forge test   # ✅ X/X passing
forge coverage --report summary  # ✅ X% lines, X% branches
```

### Test Results
[Paste forge test output]

### Coverage Report
[Paste forge coverage output]

### Files Created/Modified
**Created:**
- src/OrderBook.sol
- src/ReputationLedger.sol
- src/AuditLog.sol
- test/OrderBook.t.sol
- test/ReputationLedger.t.sol
- test/AuditLog.t.sol
- test/Integration.t.sol (if applicable)

**Modified:**
- script/Deploy.s.sol (added Day 2 deployments)
- README.md (added Day 2 architecture + usage)

### Integration Test Results
[Describe end-to-end flow verification]

### Deployment Readiness
- ✅ All contracts compile
- ✅ All tests pass
- ✅ Coverage exceeds 80%
- ✅ Deployment script updated

### Blockers
[List any issues or deviations from spec]

### Next Steps
Day 3: Wire AuditLog to AgentRegistry, add FeedbackRegistry (if time permits)
```

---

## Verification Checklist

Before reporting completion:

1. ✅ `forge build` — Zero errors, zero warnings
2. ✅ `forge test` — 100% passing
3. ✅ `forge coverage` — 80%+ overall, 100% on order matching
4. ✅ All NatSpec comments present
5. ✅ SafeERC20 used on all transfers
6. ✅ ReentrancyGuard on OrderBook state-changing functions
7. ✅ AgentRegistry.validateAction() on all write paths
8. ✅ CEI pattern verified
9. ✅ Deployment script runs without errors
10. ✅ README.md updated with Day 2 content

---

## Work Directory
`/Users/user01/.openclaw/workspace/projects/active/MANDATE/contracts`

All contracts go in `src/`, all tests in `test/`, deployment script in `script/Deploy.s.sol`.

---

## Final Notes

**Critical Security Pattern:**
Every OrderBook write function MUST call `AgentRegistry.validateAction()` first. This is the gate that enforces bitmap allowlists.

**MegaETH Optimizations:**
- Bitmap allowlists (<2000 gas)
- View functions for pre-transaction checks
- Event-heavy design for off-chain indexing

**Reference Material:**
- `.megaeth-skill/` for MegaETH-specific patterns
- OpenZeppelin 5.x docs for API reference
- ethskills.com for security patterns

**Timeline Context:**
- Day 1: ✅ RateToken, ResourceToken, ResourceTokenFactory, AgentRegistry
- Day 2: ⏳ OrderBook, ReputationLedger, AuditLog (YOU ARE HERE)
- Day 3: Integration tests, demo script, README polish
- Day 4: Deployment to testnet, submission to Devfolio

Build with production-grade quality. This is a hackathon submission, but the code must be audit-ready.
