# Cross-Chain Oracle Integration Guide

This document provides a comprehensive guide to integrating the TruncatedOracle system with Optimism's Superchain for cross-chain oracle availability.

## Architecture Overview

The cross-chain oracle system connects your existing TruncGeoOracleMulti implementation with Optimism's cross-chain messaging infrastructure, enabling secure and reliable oracle data sharing across multiple chains in the Superchain ecosystem.

![Architecture Diagram](https://via.placeholder.com/800x400?text=Cross-Chain+Oracle+Architecture)

### Key Components

1. **UniChainOracleAdapter**: Connects to your existing TruncGeoOracleMulti and publishes standardized events.
2. **CrossChainPriceResolver**: Validates and consumes oracle data from other chains using Optimism's CrossL2Inbox.
3. **UniChainOracleRegistry**: Tracks oracle adapters across different chains for discovery.
4. **TruncOracleIntegration**: Integrates with your existing TruncatedOracle system and manages cross-chain publishing.

## Event Standard

The system uses a standardized event format for cross-chain oracle updates:

```solidity
event OraclePriceUpdate(
    address indexed source,          // Indexed source contract (adapter)
    uint256 indexed sourceChainId,   // Indexed source chain ID
    bytes32 indexed poolId,          // Indexed pool identifier
    int24 tick,                      // Current tick value
    uint160 sqrtPriceX96,            // Square root price
    uint32 timestamp                 // Observation timestamp
);
```

This event format ensures:
- Efficient filtering via indexed fields
- Chain-specific identification
- Consistent data structure across chains

## Security Model

The system implements multiple security layers:

1. **Mutual Authentication**: Inherits the mutual authentication system from TruncGeoOracleMulti, ensuring only authorized contracts can publish oracle data.
2. **Cross-Chain Message Validation**: Uses Optimism's CrossL2Inbox to validate the authenticity of cross-chain events.
3. **Source Registry**: Maintains a registry of trusted oracle adapters to prevent unauthorized data sources.
4. **Timestamp Verification**: Prevents replay attacks by tracking and validating timestamps.

## Integration Guide

### Step 1: Deploy TruncOracleIntegration

The integration contract connects your existing TruncGeoOracleMulti with the cross-chain components:

```solidity
TruncOracleIntegration integration = new TruncOracleIntegration(
    truncGeoOracle,    // Your existing TruncGeoOracleMulti
    fullRangeHook,     // Your FullRange hook address
    address(0)         // Will create a new registry (or provide existing)
);
```

### Step 2: Register Pools

Register pools that should have their data published cross-chain:

```solidity
integration.registerPool(poolKey, true);  // Enable auto-publishing
```

### Step 3: Connect to FullRange Hook

Modify your FullRange contract to call the integration during callbacks:

```solidity
// In FullRange.sol, add:
ITruncOracleIntegration public oracleIntegration;

// In your swap or other relevant hooks:
if (address(oracleIntegration) != address(0)) {
    oracleIntegration.hookCallback(key);
}
```

### Step 4: Deploy CrossChainPriceResolver on Destination Chains

On each destination chain where you want to consume the oracle data:

```solidity
CrossChainPriceResolver resolver = new CrossChainPriceResolver(
    CROSS_L2_INBOX_ADDRESS  // Optimism's predeploy address
);
```

### Step 5: Register Source Adapters

Register the source chain's oracle adapter in the resolver:

```solidity
resolver.registerSource(
    SOURCE_CHAIN_ID,
    SOURCE_ADAPTER_ADDRESS
);
```

## Using Cross-Chain Oracle Data

### Receiving Updates

When a cross-chain event is detected:

1. The off-chain system (e.g., OP Supervisor) identifies the OraclePriceUpdate event.
2. A transaction is submitted to call updateFromRemote with the event identifier and data.
3. The resolver validates the event using CrossL2Inbox and updates its local state.

```solidity
// Simplified example of off-chain processing
const eventId = {
    chainId: event.sourceChainId,
    origin: event.source,
    logIndex: event.logIndex
};

await resolver.updateFromRemote(eventId, event.data);
```

### Reading Price Data

Applications can read the cross-chain price data from the resolver:

```solidity
(int24 tick, uint160 sqrtPriceX96, uint32 timestamp, bool isValid) = 
    resolver.getPrice(sourceChainId, poolId);
```

## Off-Chain Event Processing

The following JavaScript example shows how to monitor and process cross-chain oracle events:

```javascript
// Example using ethers.js
const ORACLE_ADAPTER_ABI = [/* ABI with OraclePriceUpdate event */];
const ORACLE_ADAPTER_ADDRESS = "0x...";

// Create contract instance
const oracleAdapter = new ethers.Contract(
    ORACLE_ADAPTER_ADDRESS,
    ORACLE_ADAPTER_ABI,
    provider
);

// Listen for oracle updates
oracleAdapter.on("OraclePriceUpdate", async (source, sourceChainId, poolId, tick, sqrtPrice, timestamp, event) => {
    console.log(`New price update for pool ${poolId} from chain ${sourceChainId}`);
    
    // Construct the event identifier
    const identifier = {
        chainId: sourceChainId,
        origin: source,
        logIndex: event.logIndex
    };
    
    // Get the event data
    const data = event.data;
    
    // Submit to the resolver on the destination chain
    const destinationChainProvider = new ethers.providers.JsonRpcProvider(DESTINATION_RPC_URL);
    const destinationChainSigner = new ethers.Wallet(PRIVATE_KEY, destinationChainProvider);
    const resolver = new ethers.Contract(RESOLVER_ADDRESS, RESOLVER_ABI, destinationChainSigner);
    
    await resolver.updateFromRemote(identifier, data);
});
```

## Optimism Superchain Deployment Addresses

| Chain           | Contract                | Address                                    |
|-----------------|-------------------------|-------------------------------------------|
| OP Mainnet      | CrossL2Inbox            | 0x95fC37A27a2f68e3A647CDc095F75e1bCF2A5eD8 |
| Base            | CrossL2Inbox            | 0x866E82a600A1414e583f7F13623F1aC5d58b0Afa |
| Zora            | CrossL2Inbox            | 0x51272Ce3Fe650691F20D9C2C934F953498d04574 |

*Note: Use these addresses when deploying your resolver on each destination chain.*

## Best Practices

1. **Monitor Gas Costs**: Cross-chain operations can be gas-intensive. Implement thresholds to ensure updates are economically viable.
2. **Implement Fallback Mechanisms**: In case of cross-chain message failures, have fallback methods to access oracle data.
3. **Validate Data Freshness**: Always check the timestamp of cross-chain oracle data to ensure it's sufficiently recent.
4. **Rate Limiting**: Implement rate limiting for oracle updates to prevent unnecessary costs and network congestion.
5. **Event Indexing**: For efficient event filtering, use indexed fields according to the most common query patterns.

## Troubleshooting

### Common Issues

1. **Message Validation Failures**
   - Check that the source adapter is correctly registered
   - Verify the event data hash matches what's registered in CrossL2Inbox
   
2. **Missing Oracle Data**
   - Ensure auto-publishing is enabled for the pool
   - Check that the oracle adapter is emitting events correctly
   - Verify the off-chain monitoring system is functioning

3. **Inconsistent Price Data**
   - Compare timestamp values to identify potential delays
   - Check the tick movement capping parameters to ensure they're appropriate

## Future Enhancements

1. **Multi-Source Aggregation**: Incorporate multiple oracle sources for enhanced reliability
2. **Dynamic Fee Optimization**: Adjust update frequency based on gas costs and price volatility
3. **Governance Integration**: Add parameter tuning through on-chain governance mechanisms
4. **Enhanced Monitoring**: Develop specialized tools for tracking cross-chain oracle performance

## Appendix: Identifier Structure

The Identifier struct used by CrossL2Inbox follows Optimism's standard format:

```solidity
struct Identifier {
    uint256 chainId;    // Source chain ID
    address origin;     // Source contract address
    uint256 logIndex;   // Log index in the transaction
}
```

This structure uniquely identifies a cross-chain event and is used for validation.