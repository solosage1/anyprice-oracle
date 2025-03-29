# Unichain Interop Oracle

A cross-chain interoperability oracle system for blockchain communication.

## Overview

The Unichain Interop Oracle facilitates secure and reliable cross-chain messaging between different blockchain networks, with a focus on Optimism integration. The oracle provides:

- Integration with Optimism's bridge (CrossDomainMessenger)
- Complex message structures with message status tracking
- Monitoring system for cross-chain message status
- Testnet deployment support (Goerli, Optimism Goerli)

## Tech Stack

- **Foundry**: Development toolkit for Ethereum
- **Solidity**: Smart contract programming language
- **Optimism**: Layer 2 scaling solution
- **Optimism CrossDomainMessenger**: Bridge for L1-L2 communication

## Project Structure

- `src/`: Smart contract source files
- `test/`: Test files
- `script/`: Deployment and monitoring scripts
- `lib/`: Dependencies

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

1. Clone the repository:
```shell
git clone https://github.com/your-username/unichain-interop-oracle.git
cd unichain-interop-oracle
```

2. Install dependencies:
```shell
forge install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

## Deployment

### Setting Up Environment Variables

Create an `.env` file with the necessary variables:

```shell
# Private key for deployment
PRIVATE_KEY=your_private_key

# For monitoring (optional)
ORACLE_ADDRESS=deployed_oracle_address
CHAIN_ID=10  # Default is Optimism
```

### Deploy to Testnets

#### Goerli Testnet

```shell
forge script script/Deploy.s.sol:DeployToGoerli --rpc-url goerli --broadcast --verify
```

#### Optimism Goerli Testnet

```shell
forge script script/Deploy.s.sol:DeployToOptimismGoerli --rpc-url opgoerli --broadcast --verify
```

## Message Monitoring

The project includes a monitoring system to track the status of cross-chain messages:

### Monitor Messages

```shell
# Set the ORACLE_ADDRESS environment variable first
forge script script/Monitor.s.sol:MonitorScript --rpc-url opgoerli
```

### Update Message Status

```shell
# Required environment variables: ORACLE_ADDRESS, CHAIN_ID, MESSAGE_ID, STATUS_CODE
# STATUS_CODE: 0=NONE, 1=SENT, 2=RECEIVED, 3=CONFIRMED, 4=FAILED
forge script script/Monitor.s.sol:UpdateMessageStatus --rpc-url opgoerli --broadcast
```

## Bridge Integration

The oracle integrates with Optimism's CrossDomainMessenger for cross-chain communication. The implementation:

1. Supports sending messages from L1 to L2 and vice versa
2. Tracks message status through the entire lifecycle
3. Uses a unique messageId to correlate messages across chains

## Message Structure

Messages use a structured format instead of simple bytes32 values:

```solidity
struct Message {
    bytes32 messageId;   // Unique identifier
    address sender;      // Address that sent the message
    bytes payload;       // Arbitrary message data
    uint256 timestamp;   // When the message was sent/received
    MessageStatus status; // Current status of the message
}
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
