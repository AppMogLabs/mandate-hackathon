# MANDATE

An AI-native strategy game on MegaETH where human owners write strategic mandates and autonomous AI agents execute them entirely on-chain.

## What MANDATE Is

MANDATE is a multiplayer strategy game built for the age of AI agents. Human players ("Commanders") set high-level strategic objectives ("mandates") for their AI agents, who then autonomously execute trades, build alliances, and compete for resources—all on-chain. The game's core innovation is **deterministic enforcement via allowlist bitmaps**: human owners control what actions their AI agents can perform through cryptographic permissions, not LLM prompts. No prompt injection can bypass a missing bit. This creates a trustless environment where AI agents operate within provably bounded authority, enabling true on-chain coordination, competition, and reputation building.

## What This Submission Demonstrates

This hackathon submission implements Sprint 0 (Days 1-3) of MANDATE's Phase 2 smart contract architecture. It demonstrates core themes from The Synthesis hackathon:

### Agents that Pay
- **RateToken**: Native currency for all economic activity
- **OrderBook**: Agents place/match limit orders, settling trades atomically
- **Resource tokens** (COMPUTE, CHIPS): Agents acquire resources through trade

### Agents that Trust
- **ReputationLedger**: On-chain reputation scores from post-trade feedback
- **ERC-8004 identity**: Each agent has a portable ERC-721 NFT identity
- **AuditLog**: Immutable action history for transparency

### Agents that Cooperate
- **AgentRegistry**: Allowlist bitmap defines permitted actions per agent
- **Deterministic enforcement**: validateAction() gates every write path
- **Guard signatures** (EIP-712): Optional multi-agent approval workflows

The allowlist bitmap is the **security innovation**: it's a cryptographic gate, not an LLM suggestion. If an agent's allowlist doesn't include ORDER_MATCH, the transaction reverts—period. This enables safe, autonomous agent coordination at scale.

## Architecture Overview

### Core Contracts (7)

1. **RateToken** (ERC-20)  
   Native currency. All trades settle against RATE. Mintable by owner (Phase 3 will add staking/rewards).

2. **ResourceTokenFactory**  
   Deploys ResourceToken instances (COMPUTE, CHIPS, etc.). Owner-controlled minting.

3. **AgentRegistry** (ERC-721 + ERC-8004)  
   Each agent receives an NFT identity. Allowlist bitmap defines permitted actions (ORDER_PLACE, ORDER_CANCEL, ORDER_MATCH, etc.). `validateAction()` is called by every contract before state changes.

4. **OrderBook**  
   Decentralized limit order book. Agents place sell orders (resource for RATE), buyers match them. Atomic settlement via SafeERC20. Integrates with ReputationLedger and AuditLog.

5. **ReputationLedger**  
   Tracks reputation scores (feedback-based) and transaction counts. OrderBook auto-records trades. Agents can post feedback on counterparties.

6. **AuditLog**  
   Immutable log of all agent actions (ORDER_PLACED, ORDER_MATCHED, etc.). Indexed by agentId. Provides full historical transparency.

7. **ResourceToken** (ERC-20)  
   Template for game resources (COMPUTE, CHIPS). Owner-controlled minting. Agents trade these via OrderBook.

### Data Flow

```
Human Owner
    ↓ (sets mandate)
AgentRegistry ← allowlist bitmap (ORDER_PLACE, ORDER_CANCEL, etc.)
    ↓ (validateAction gate)
OrderBook → placeOrder / matchOrder
    ↓ (atomic settlement)
RATE ↔ ResourceToken (transfer via SafeERC20)
    ↓ (record outcome)
ReputationLedger (trust score)
AuditLog (immutable history)
```

Every state-changing function in every contract calls `agentRegistry.validateAction(msg.sender, ACTION_TYPE)` before proceeding. If the bit isn't set, the transaction reverts.

## How to Run

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- MegaETH testnet RPC URL (Chain ID 4326)
- Private key with testnet ETH

### 1. Install Dependencies
```bash
cd contracts
forge install
```

### 2. Set Environment Variables
```bash
export PRIVATE_KEY=0x...
export RPC_URL=https://megaeth-testnet-rpc-url  # Replace with actual URL
```

### 3. Run Tests
```bash
forge test -vv
```

All 80 tests should pass (unit + integration coverage).

### 4. Deploy to Testnet
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
```

This deploys all 7 contracts, sets up roles, and mints initial RATE/resource tokens.

### 5. Run Demo Script
```bash
forge script script/Demo.s.sol:Demo --rpc-url $RPC_URL --broadcast
```

This executes an 8-step narrative:
1. Deploy all contracts
2. Register two agents (Alpha, Beta)
3. Set allowlists (Alpha: ORDER_PLACE + ORDER_CANCEL, Beta: ORDER_PLACE only)
4. Mint resources (COMPUTE to Alpha, CHIPS to Beta)
5. Trade execution (Alpha sells 100 COMPUTE at 3 RATE each, Beta buys)
6. Reputation update (Beta posts feedback on Alpha)
7. Audit verification (query Alpha's action history)
8. **Security demonstration**: Alpha tries ORDER_MATCH (not on allowlist) → reverts

The demo output tells the story. Watch for the final step—that's the key moment showing deterministic enforcement.

## MegaETH Context

MANDATE is built on MegaETH, an ultra-low-latency Layer 2 optimized for real-time applications. Key properties:

- **10ms block times**: Near-instant finality for AI agent actions
- **Sub-cent gas fees**: ~0.001 gwei base fee enables high-frequency micro-transactions
- **100K+ TPS capacity**: Scales to thousands of concurrent agents
- **512KB contract limit**: Enforces modular design (why we split OrderBook/ReputationLedger/AuditLog)

MegaETH's speed enables **real-time strategy gameplay**. In a traditional 12-second block time chain, an AI agent placing 10 trades/minute would flood the mempool. On MegaETH, that's trivial. The demo script's atomic settlement (Steps 5-6) happens in milliseconds, not minutes.

## ERC-8004 Context

MANDATE implements **ERC-8004 (Portable Agent Identity)**, an emerging standard for AI agent interoperability. Key features:

- **ERC-721 NFT per agent**: The agentId is a transferable NFT. If a human transfers it, the new owner controls the agent's allowlist.
- **Structured reputation**: ReputationLedger uses agentId as the key, so reputation is portable across games/protocols.
- **Ecosystem composability**: Any contract can query `agentRegistry.validateAction(agent, actionType)` to enforce permissions.

ERC-8004 solves the **"agent identity fragmentation"** problem. Without it, each protocol would implement its own agent registry, and reputation/permissions wouldn't transfer. With ERC-8004, an agent's identity (and reputation) is portable. If MANDATE's OrderBook wanted to integrate with a future "Agent Lending Protocol," both would use the same agentId → instant trust interoperability.

This is critical for AI agent economies. Just as ERC-20 enabled token composability, ERC-8004 enables agent composability.

## What Comes Next

This submission covers **Sprint 0 (Days 1-3)** of MANDATE's Phase 2. The full architecture includes 26 contracts across 6 sprints:

- **Sprint 1**: Escrow, resource conversion, territory mechanics
- **Sprint 2**: Alliance contracts, shared treasuries
- **Sprint 3**: Governance (voting, mandates-as-code)
- **Sprint 4**: Advanced security (guard agents, multi-sig)
- **Sprint 5**: Economic loops (staking, rewards, deflation)

Full architecture: [Hackathon/MANDATE_Phase2_SmartContracts_v03.md](../Hackathon/MANDATE_Phase2_SmartContracts_v03.md)

The goal: a **provably fair, AI-native strategy game** where human creativity (mandate design) meets AI execution (autonomous trading/coordination), all running on-chain with cryptographic enforcement.

## Testnet Deployment Addresses

> **Note**: Update this section after deploying to MegaETH testnet.

| Contract | Address | Explorer Link |
|----------|---------|---------------|
RateToken:           0x8B44630C791471d96a2125ed24258f9b5BD2F1b6
ResourceTokenFactory: 0xfD208Ef99e81a87365E69525ba18196982250E50
COMPUTE:             0x3ca3494a52E5014989949D927a1e9432947E21Bc
CHIPS:               0x2e63796511f6B03372eD7741217d41b7Dd2D96A0
AgentRegistry:       0xf5BaA5C5F06870114db94f0cA23E6895CB570c05
ReputationLedger:    0xD00f7faC56EFbC88dC8faDaA223ffe363b23e739
AuditLog:            0xbA097645B23A8b1046d9d0a55D1151E00FfAB396
OrderBook:           0x33C62A87c0359605671F1722d54aE36A30d9De70

## Reference Documentation

- **Full Handoff Doc**: [MANDATE_Sprint0_Argos_Handoff.md](../Hackathon/MANDATE_Sprint0_Argos_Handoff.md)
- **Phase 2 Architecture**: [MANDATE_Phase2_SmartContracts_v03.md](../Hackathon/MANDATE_Phase2_SmartContracts_v03.md)
- **Game Design**: [MANDATE_GDD_v03.docx](../Hackathon/MANDATE_GDD_v03.docx)
- **Phase 3/4 Annex**: [MANDATE_SmartContract_Annex_v03.md](../Hackathon/MANDATE_SmartContract_Annex_v03.md)

## License

MIT

---

**Built for The Synthesis Hackathon (March 2026)**  
**Theme**: Agents that Pay, Trust, and Cooperate  
**Chain**: MegaETH (Chain ID 4326)
