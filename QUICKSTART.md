# MANDATE Contracts — Quick Start

## TL;DR

```bash
# Build
forge build

# Test
forge test

# Deploy to MegaETH testnet
export PRIVATE_KEY=0x...
forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://rpc-testnet.megaeth.io \
  --broadcast
```

## What's Built (Day 1)

✅ **RateToken** — Native utility token (ERC-20)  
✅ **ResourceToken** — Template for COMPUTE, CHIPS (ERC-20)  
✅ **ResourceTokenFactory** — Deploys resources with access control  
✅ **AgentRegistry** — Agent identity NFTs (ERC-721) + bitmap allowlists  

## Test Results

```
40 tests passed, 0 failed
Coverage: ~88% (exceeds 80% requirement)
Build: Zero compiler errors
```

## What This Does

MANDATE is an on-chain marketplace where AI agents:
1. **Register** — Get an ERC-721 NFT as identity
2. **Trade resources** — COMPUTE, CHIPS via order book (Day 2)
3. **Pay with RATE** — Native utility token
4. **Build reputation** — On-chain feedback (Day 3)

## Why MegaETH?

- **10ms blocks** — Real-time agent coordination
- **Low gas** — 0.001 gwei base fee
- **EIP-7966** — Instant transaction receipts
- **Storage optimized** — Bitmap allowlists < 2000 gas

## Next Steps

**Day 2:** OrderBook + OrderValidator (decentralized resource trading)  
**Day 3:** FeedbackRegistry (reputation system)

## Files

```
contracts/
├── src/                    # 4 core contracts (408 lines)
├── test/                   # 40 tests (468 lines)
├── script/Deploy.s.sol     # Deployment script
├── README.md               # Full documentation
└── DAY1_COMPLETION_REPORT.md  # Detailed completion report
```

## Key Commands

```bash
# Run specific test
forge test --match-test test_Deployment_AdminHasRoles

# Gas report
forge test --gas-report

# Coverage report
forge coverage --report summary

# Clean build
forge clean && forge build

# Verify contract (after deployment)
forge verify-contract <address> <contract> \
  --chain-id 4326 \
  --verifier-url <verifier-url>
```

## Contract Addresses (After Deployment)

Save deployment addresses here:

```
RATE:             0x...
Factory:          0x...
COMPUTE:          0x...
CHIPS:            0x...
AgentRegistry:    0x...
```

## Security Checklist

✅ OpenZeppelin 5.x  
✅ AccessControl on all admin functions  
✅ Zero address checks  
✅ CEI pattern  
✅ NatSpec documentation  
✅ Solidity 0.8.24 (overflow protection)  

## Need Help?

- Full docs: `README.md`
- Completion report: `DAY1_COMPLETION_REPORT.md`
- MegaETH docs: https://docs.megaeth.io
- Foundry book: https://book.getfoundry.sh
