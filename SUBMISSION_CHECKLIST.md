# MANDATE Hackathon Submission Checklist

**Submission Deadline**: March 22, 2026  
**Hackathon**: The Synthesis (Agents that Pay, Trust, Cooperate)  
**Chain**: MegaETH (Chain ID 4326)

## Pre-Submission Verification

### ✅ Code Quality
- [ ] All contracts deployed to testnet
- [ ] Demo script runs end-to-end without errors
- [ ] All tests passing (80/80)
- [ ] No compiler warnings (`forge build --force`)
- [ ] No security vulnerabilities in scope
- [ ] All PHASE_3_PLACEHOLDER tags present on economic parameters

### ✅ Documentation
- [ ] README.md complete with all 7 required sections:
  - [ ] What MANDATE is (1 paragraph)
  - [ ] What this submission demonstrates (Synthesis themes)
  - [ ] Architecture overview (7 contracts)
  - [ ] How to run (deployment + demo instructions)
  - [ ] MegaETH context (3-4 sentences)
  - [ ] ERC-8004 context (3-4 sentences)
  - [ ] What comes next (Sprint 0 of 6-sprint Phase 2)
- [ ] Deployment addresses in README (filled after testnet deployment)
- [ ] Link to full handoff doc in repo
- [ ] All reference documents accessible

### ✅ Deployment
- [ ] All 7 contracts deployed to MegaETH testnet
- [ ] Deployment addresses saved to `deployments/testnet-addresses.json`
- [ ] Test RATE distributed to agent addresses
- [ ] Roles granted (MINTER_ROLE, RECORDER_ROLE, LOGGER_ROLE)
- [ ] Contracts verified on block explorer (if applicable)

### ✅ Demo Script
- [ ] `script/Demo.s.sol` executes all 8 steps without errors
- [ ] Step 1: Setup (deploy contracts, mint RATE)
- [ ] Step 2: Registration (both agents registered with ERC-721 IDs)
- [ ] Step 3: Allowlisting (Alpha: ORDER_PLACE + ORDER_CANCEL, Beta: ORDER_PLACE only)
- [ ] Step 4: Resource minting (COMPUTE to Alpha, CHIPS to Beta)
- [ ] Step 5: Trading (order placed, matched, settled atomically)
- [ ] Step 6: Reputation (feedback posted, score updated)
- [ ] Step 7: Audit verification (action history queried)
- [ ] Step 8: Security demonstration (unpermitted action reverts)
- [ ] Console output is human-readable and tells a clear story
- [ ] Demo demonstrates deterministic enforcement (allowlist bitmap security)

### ✅ Security
- [ ] Repository clean (no `.env` with real private keys)
- [ ] No hardcoded private keys in any file
- [ ] SafeERC20 used on all token transfers
- [ ] ReentrancyGuard on functions that transfer tokens
- [ ] CEI pattern enforced everywhere
- [ ] AgentRegistry.validateAction() gates all write paths
- [ ] No block.number for time logic (block.timestamp used)

### ✅ Naming Conventions
- [ ] All RATE token references use disambiguating prefix (`rateToken`, `rateTokenAmount`, etc.)
- [ ] No ambiguous variable names like `rate`, `tokenBalance`
- [ ] Consistent naming across all contracts

## Deployment Commands

### Build & Test
```bash
cd contracts
forge build
forge test -vv
```

### Deploy to Testnet
```bash
# Set environment variables
export PRIVATE_KEY=0x...
export RPC_URL=https://megaeth-testnet-rpc-url

# Deploy all contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

# Copy output JSON to deployments/testnet-addresses.json
```

### Run Demo Script
```bash
# Execute 8-step demo narrative
forge script script/Demo.s.sol:Demo \
  --rpc-url $RPC_URL \
  --broadcast
```

### Verify Contracts (if supported)
```bash
# Verify each contract on block explorer
forge verify-contract <CONTRACT_ADDRESS> src/RateToken.sol:RateToken \
  --chain-id 4326 \
  --compiler-version 0.8.24
```

## Final Checks Before Submission

### Code Repository
- [ ] All files committed to git
- [ ] `.gitignore` excludes `.env`, `cache/`, `out/`, `broadcast/`
- [ ] Clean commit history (no "WIP" commits in submission branch)
- [ ] Repository public or accessible to judges

### Submission Materials
- [ ] README.md tells the complete story
- [ ] Demo script output demonstrates all key features
- [ ] Testnet deployment is live and verifiable
- [ ] All reference documents included in repo

### Narrative Quality
- [ ] Submission clearly explains the "why" (not just "what")
- [ ] Allowlist bitmap security innovation is highlighted
- [ ] MegaETH choice is justified (10ms blocks, sub-cent gas)
- [ ] ERC-8004 portable identity is explained
- [ ] Judges can understand what MANDATE is in 60 seconds

## Success Criteria

A judge (human or AI) should be able to:

1. ✅ Read README and understand what MANDATE is
2. ✅ See deployed contracts on block explorer
3. ✅ Run demo script and watch agents register, trade, build reputation
4. ✅ Understand allowlist bitmap is deterministic enforcement (not LLM suggestion)
5. ✅ See this is a vertical slice of real architecture, not a weekend hack
6. ✅ Recognize alignment with Synthesis themes (Agents that Pay, Trust, Cooperate)

## Post-Submission

- [ ] Submission link recorded
- [ ] Confirmation email received
- [ ] Testnet deployment remains live through judging period
- [ ] Team available for questions during review

---

**Sprint 0 Status**: Days 1-3 complete (7 contracts, 80 tests, full demo)  
**Phase 2 Roadmap**: 26 contracts across 6 sprints  
**Repository**: [Link to repo]  
**Demo Video**: [Link if applicable]
