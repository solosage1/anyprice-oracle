# 📡 AnyPrice — Unified Cross-Chain Oracle Access

**⚡ Fetch real-time asset prices from any chain, using a single call. Modular. Composable. No lock-in.**

## 🚀 What It Does

AnyPrice is a cross-chain oracle framework that lets your dApp on Optimism (or any L2) fetch price data from remote chains like UniChain as if it were local.

### Use Case

You're on Optimism. The asset you want to price only has liquidity on UniChain.

**Normally? You'd need to:**
* Bridge data manually
* Set up custom relayers
* Handle async flows
* Deal with mismatched oracle formats

**With AnyPrice, you just call:**

```solidity
CrossChainPriceResolver.resolvePrice("TOKEN", uniChainId);
```

✅ You get a fresh, validated price  
✅ Backed by registered oracle adapters  
✅ Delivered cross-chain via L2-native messaging

## 🧱 How It Works

### 🛰 1. Oracle Adapter System

Each chain (e.g., UniChain) hosts its own OracleRegistry, which maps token symbols to custom OracleAdapters.

Adapters implement a unified interface to fetch raw prices from native oracles.

### 🔁 2. Cross-Chain Messaging

Using the CrossChainMessenger (based on Optimism's ICrossDomainMessenger), price requests are routed to the target chain, processed, and responded to.

### 🧠 3. Local Price Resolution

CrossChainPriceResolver acts as the main interface. It abstracts away messaging, validation, and normalization. For the dApp, it looks like a single unified price feed.

## 📦 Architecture Overview

```
+--------------------------+
|  Your dApp (Optimism)    |
|    ↳ resolvePrice()      |
+-----------+--------------+
            |
            v
+--------------------------+
| CrossChainPriceResolver  |
+-----------+--------------+
            |
            v
+--------------------------+
| CrossChainMessenger      |
| ↳ Sends req to UniChain  |
+-----------+--------------+
            |
            v
+--------------------------+
| UniChainOracleRegistry   |
| ↳ Adapter fetches price  |
+--------------------------+
```

## 🎬 Demo Video

Watch a demonstration of AnyPrice in action:

[Watch the AnyPrice Demo on Loom](https://www.loom.com/share/f3150995f4524a42838ce76505df4978?sid=e7088649-1748-458d-ad80-2eba9c9da8e1)

## 🛠 Contracts Breakdown

| Contract | Purpose |
|----------|---------|
| CrossChainPriceResolver | Main interface to fetch price |
| CrossChainMessenger | Manages cross-chain messaging |
| UniChainOracleRegistry | Maps symbols to adapters |
| UniChainOracleAdapter | Fetches price from local oracle |
| ICrossL2Inbox | Interface for message send |
| IOptimismBridgeAdapter | Abstract bridge transport |
| TruncOracleIntegration | Example integration |
| OracleCrossChainDemo.s.sol | End-to-end test + deployment |

## 🧪 Demo Walkthrough

### Prerequisites
* Foundry installed
* Local forks or testnets for Optimism + UniChain
* Set up .env with RPC URLs + private key

### 1. Deploy Everything

```bash
forge script script/OracleCrossChainDemo.s.sol \
  --broadcast --verify --rpc-url $OPTIMISM_RPC
```

This:
* Deploys the registry, adapters, resolver, and messenger
* Registers symbols
* Mocks oracle prices on UniChain

### 2. Trigger Cross-Chain Price Fetch

```solidity
price = resolver.resolvePrice("ETH", uniChainId);
```

Behind the scenes:
* Request is sent to UniChain
* Adapter pulls price from native oracle
* Response is sent back and cached locally

### 3. Consume in Your App

```solidity
uint price = CrossChainPriceResolver.resolvePrice("DAI", uniChainId);
doSomething(price);
```

## 🧠 Why This Matters

| Feature | AnyPrice | Chainlink CCIP | Custom Relayers |
|---------|----------|----------------|-----------------|
| Modular Oracle Adapters | ✅ | ❌ | ❌ |
| Works Across Any L2 | ✅ | ❓ | ✅ |
| Native Oracle Format Support | ✅ | ❌ | ❓ |
| Dev UX: Single Function Call | ✅ | ❌ | ❌ |

## 💡 Extending It
* Add adapters for Chainlink, Pyth, custom oracles
* Plug into any app that uses price feeds (DEX, lending, liquidation bots)
* Swap messaging layer with CCIP, Hyperlane, LayerZero if needed

## 🏁 Final Thoughts

AnyPrice makes cross-chain price feeds composable, modular, and dev-friendly.

* No more waiting for someone to deploy Chainlink on your favorite L2.
* No more brittle relayer scripts.
* Just plug in and price.

## 🔒 Security Overview

The AnyPrice Oracle system incorporates several security measures to ensure reliable and tamper-resistant cross-chain price data:

### Cross-Chain Message Security

- **Optimism CrossL2Inbox Validation**: Uses Optimism's native cross-chain message verification to validate all cross-chain events.
- **Chain ID Validation**: Ensures messages originate from the expected source chain.
- **Source Address Validation**: Verifies messages come from registered and authorized oracles.

### Data Integrity Protections

- **Replay Attack Prevention**: Implements multiple levels of replay protection:
  - Unique event ID tracking using `keccak256(chainId, origin, logIndex, blockNumber)`
  - Block number monotonicity enforcement
  - Transaction-specific validation
- **Finality Requirements**: Enforces minimum block confirmations before accepting cross-chain data to prevent reorganization attacks.
- **Stale Data Prevention**: Rejects price data that exceeds configurable freshness thresholds.
- **Timestamp Validation**: Checks for future timestamps and anomalous timestamp patterns.

### Access Controls

- **Source Registry**: Only accepts price updates from explicitly registered oracle adapters.
- **Admin Functions**: Owner-only functions for managing sources, thresholds, and other sensitive parameters.
- **Circuit Breaker**: Includes a pausable mechanism to halt price updates during emergencies.

### Implementation Safeguards

- **Reentrancy Protection**: Uses OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks.
- **Strict Data Validation**: Enforces extensive validation on all cross-chain messages.
- **Chain-Specific Time Buffers**: Accounts for differences in block times across chains.
- **Timeliness Checks**: Ensures that prices are current and representative.

### Security Best Practices

- **Immutable Core Components**: Critical components like chain IDs and oracle references are immutable.
- **Defensive Programming**: Uses custom error types and robust error handling.
- **Comprehensive Event Emission**: Extensive event logging for off-chain monitoring and forensics.
- **Incremental Updates**: Smart freshness checks that only accept newer data than what's already stored.

### Known Limitations

- **Cross-Chain Messaging Dependency**: Relies on the security of the underlying cross-chain messaging protocol.
- **Oracle Data Quality**: Depends on the accuracy of the source oracle implementations.
- **Block Timestamp Reliance**: Some security features depend on block timestamps, which can be slightly manipulated by validators.

For security disclosures or concerns, please contact the project maintainer directly.

## 👨‍💻 Author

Built for the Unichain x Optimism Hackathon  
By Bryan Gross — [@bryangross on X](https://twitter.com/bryangross)
