# Security Fixes Required

## Priority 1 (Critical — Must fix before testnet)

- [x] **H-01: Add `require(rateAmount > 0)` in `OrderBook.matchOrder()`** — `src/OrderBook.sol:270`
  - Integer truncation allows zero-cost token extraction when `fillAmount * pricePerUnit < 1e18`
  - Fixed: `if (rateAmount == 0) revert InvalidOrderParameters();`

## Priority 2 (High — Should fix before testnet)

- [x] **M-02: Add `Pausable` to OrderBook** — `src/OrderBook.sol`
  - No emergency stop mechanism existed
  - Fixed: Inherited `Pausable`, added `whenNotPaused` to `placeOrder` and `matchOrder`, added `pause()`/`unpause()` with `OPERATOR_ROLE`. `cancelOrder` remains callable when paused.

- [x] **M-03: Make agent NFTs soulbound** — `src/AgentRegistry.sol`
  - NFT transfer left stale identity mapping; old owner retained permissions
  - Fixed: Override `_update()` to revert on transfers (soulbound). Minting still works. Transferable identities deferred to later sprint with proper reputation/allowlist transfer semantics.

- [x] **L-01: Block self-matching in OrderBook** — `src/OrderBook.sol:259` (promoted from P3 per operator feedback)
  - Seller could match own order, inflating reputation
  - Fixed: `if (msg.sender == order.seller) revert UnauthorizedCaller();`

- [x] **L-03: Validate non-zero agentIds in ReputationLedger** — `src/ReputationLedger.sol:62` (promoted from P3 per operator feedback)
  - Zero agentId (unregistered) could receive reputation
  - Fixed: `require(buyerAgentId != 0 && sellerAgentId != 0, "ReputationLedger: zero agentId");`

- [x] **L-02: Add minimum order size** — `src/OrderBook.sol:68`
  - 1-wei orders created storage bloat
  - Fixed: `MIN_ORDER_AMOUNT = 1e15` constant (`PHASE_3_PLACEHOLDER`). Complementary defence to H-01.

## Priority 3 (Medium — Fix before mainnet)

- [x] **M-01: Make `verifyGuardSignature()` internal** — `src/AgentRegistry.sol:204`
  - No role check on caller; no validation that recovered signer is a guard
  - Fixed: Changed from `external` to `internal`. Will be re-exposed via external wrapper with GUARD_ROLE validation in Phase 2.

## Priority 4 (Low/Gas — Tracked for post-hackathon)

- [ ] **L-04: Document admin renounce risk** — All contracts
  - `DEFAULT_ADMIN_ROLE` can be renounced, bricking role management
  - Plan: Address via TimelockController + multisig governance in Phase 2 spec

- [ ] **G-01/G-02/G-03: Gas optimizations** — Various
  - Assembly keccak256, immutable naming, batch query bounds
  - Cosmetic/minor; defer to Phase 2

## Demo Script Bugs (Not Security)

- [x] **Demo.s.sol Step 3** — Agent Beta now granted `ACTION_ORDER_MATCH` (needed for Step 5 `matchOrder()`)
- [x] **Demo.s.sol Step 1** — Deployer now granted `MINTER_ROLE` on COMPUTE and CHIPS via `factory.setMintAuthority()` (needed for Step 4 minting)
