# UniChain Interoperability Oracle Architecture

This document outlines the core architecture and design decisions for the UniChain Interoperability Oracle system.

## Core Architecture

The system uses Optimism's CrossL2Inbox pattern for secure cross-chain message passing:

```
[Source Chain]                         [Destination Chain]
+----------------+                     +------------------+
| TruncGeoOracle |                     |                  |
+----------------+                     |                  |
        |                              |                  |
        v                              |                  |
+----------------+                     |                  |
| OracleAdapter  |-- event emitted --> | CrossL2Inbox    |
+----------------+                     +------------------+
                                                |
                                                v
                                       +------------------+
                                       | PriceResolver    |
                                       +------------------+
```

## Key Components

### 1. Interfaces

- `ICrossL2Inbox`: Standardized interface for Optimism's CrossL2Inbox contract, providing secure cross-chain event verification.

### 2. Source Chain Components

- `TruncGeoOracleMulti`: Core oracle that produces price data from Uniswap v4 pools.
- `TruncOracleIntegration`: Integration contract that connects TruncGeoOracle to the cross-chain system.
- `UniChainOracleAdapter`: Adapter that formats and emits the oracle data in a cross-chain compatible format.
- `UniChainOracleRegistry`: Registry that maintains information about available oracle adapters.

### 3. Destination Chain Components

- `CrossChainPriceResolver`: Consumes and validates oracle data from other chains, using the CrossL2Inbox for secure message verification.

### 4. Testing Components

- `MockL2Inbox`: Mock implementation of CrossL2Inbox for development and testing.

## Security Measures

1. **Strict Event Validation**: All cross-chain events are validated using Optimism's L2 inbox.
2. **Replay Protection**: Events are tracked by a unique ID to prevent replay attacks.
3. **Freshness Checks**: Oracle data is validated for timeliness to prevent stale data usage.
4. **Mutual Authentication**: Bidirectional authentication ensures only authorized components can interact.
5. **Reentrancy Protection**: Critical functions use nonReentrant modifiers to prevent reentrancy attacks.

## Message Flow

1. Price data is collected by the TruncGeoOracle on the source chain
2. The OracleAdapter emits standardized events containing the price data
3. Optimism's cross-chain infrastructure delivers these events to the destination chain
4. The CrossL2Inbox on the destination chain can verify the authenticity of the events
5. The PriceResolver validates and stores the price data for consumption by other contracts 