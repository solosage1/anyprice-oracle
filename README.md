# UniChain Interoperability Oracle

Cross-chain oracle system for distributing price data from Uniswap v4 oracles to multiple EVM chains, using Optimism's CrossL2Inbox for secure cross-chain communication.

## Overview

This project implements a secure cross-chain oracle system that can distribute price data from Uniswap v4 pools across multiple EVM chains.

The oracle system leverages Optimism's CrossDomainMessenger and CrossL2Inbox pattern to provide secure, verifiable cross-chain oracle data.

## Architecture

The solution follows a standardized approach using the CrossL2Inbox pattern:

1. **Source Chain**: 
   - TruncGeoOracleMulti observes Uniswap v4 pools and creates reliable price oracles
   - UniChainOracleAdapter emits standardized events for cross-chain consumption

2. **Cross-Chain Bridge**:
   - Optimism's Cross-Chain Messaging infrastructure delivers events to destination chains
   - CrossL2Inbox provides secure verification of cross-chain events

3. **Destination Chain**:
   - CrossChainPriceResolver verifies and consumes oracle data from source chains
   - Applications on the destination chain can query the resolver for verified price data

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed design documentation.

## Key Components

### Core Contracts

- **TruncGeoOracleMulti**: Truncated geometric mean oracle for Uniswap v4
- **TruncOracleIntegration**: Integration contract connecting TruncGeoOracle to the cross-chain system
- **UniChainOracleAdapter**: Adapter that formats and publishes oracle data in a cross-chain compatible format
- **CrossChainPriceResolver**: Resolver contract that consumes and validates cross-chain oracle data

### Supporting Contracts

- **MockL2Inbox**: Mock implementation of Optimism's CrossL2Inbox for testing
- **UniChainOracleRegistry**: Registry that tracks oracle adapters across multiple chains

## Security Features

- **Replay Protection**: Events are tracked by unique IDs to prevent replay attacks
- **Freshness Validation**: Oracle data includes timestamps and is validated for staleness
- **Cross-Chain Verification**: Oracle data is verified through Optimism's secure CrossL2Inbox
- **Source Authentication**: Only registered and validated source oracles are accepted
- **Mutual Authentication**: Bidirectional authentication between components
- **Reentrancy Protection**: Key functions are protected against reentrancy attacks

## Frequently Asked Questions

For detailed information about how the system works, deployment instructions, and technical details, see our [FAQ](./FAQ.md).

## Getting Started

See [InstallationGuide.md](./InstallationGuide.md) for detailed setup instructions.

### Quick Start

1. Clone the repository
2. Install dependencies: `forge install`
3. Run tests: `forge test`
4. Deploy: `forge script script/OracleCrossChainDemo.s.sol --fork-url $RPC_URL --broadcast`

## Demo Script

The project includes a demo script (`script/OracleCrossChainDemo.s.sol`) that demonstrates the full cross-chain oracle flow:

1. Deploy oracle components on both source and destination chains
2. Register the source oracle in the destination resolver
3. Simulate a cross-chain oracle update with price data
4. Verify the cross-chain data in the resolver

### Running the Demo

To run the demo locally:

1. Start a local Ethereum node with Anvil:
   ```bash
   anvil --chain-id 1337
   ```

2. In a new terminal, run the demo script:
   ```bash
   forge script script/OracleCrossChainDemo.s.sol --fork-url http://127.0.0.1:8545 -vv
   ```

3. To broadcast transactions to the local node:
   ```bash
   forge script script/OracleCrossChainDemo.s.sol --fork-url http://127.0.0.1:8545 --broadcast
   ```

## Oracle Monitor

The project includes a JavaScript monitor (`Oracle-Monitor.js`) that demonstrates how to monitor oracle events and relay them across chains:

1. Install dependencies:
   ```bash
   npm install
   ```

2. Configure environment variables in `.env`:
   ```
   SOURCE_RPC_URL=http://127.0.0.1:8545
   DEST_RPC_URL=http://127.0.0.1:8545
   PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   ORACLE_ADAPTER_ADDRESS=0x75537828f2ce51be7289709686A69CbFDbB714F1
   RESOLVER_ADDRESS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
   ```

3. Start the monitor:
   ```bash
   node Oracle-Monitor.js
   ```

The monitor will listen for oracle events on the source chain and forward them to the destination chain.

## License

This project is licensed under the Business Source License 1.1 (BUSL-1.1).

- The license restricts production use until the Change Date (June 15, 2027).
- After the Change Date, the license converts to MIT.
- For additional use grants or more information, see the [LICENSE](./LICENSE) file.
