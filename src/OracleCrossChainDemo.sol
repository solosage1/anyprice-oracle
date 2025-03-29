// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/UniChainOracleAdapter.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/UniChainOracleRegistry.sol";
import "../src/TruncOracleIntegration.sol";
import "../src/MockL2Inbox.sol";
import "../src/TruncGeoOracleMulti.sol";

/**
 * @title OracleCrossChainDemoScript
 * @notice Demo script for the cross-chain oracle system
 * @dev Demonstrates the full flow of data from source chain to destination chain
 */
contract OracleCrossChainDemoScript is Script {
    // Mock addresses for testing
    address constant MOCK_POOL_MANAGER = address(0x100);
    address constant MOCK_FULL_RANGE_HOOK = address(0x200);
    
    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Create mocks
        MockL2Inbox mockCrossL2Inbox = new MockL2Inbox();
        
        // Step 2: Deploy the oracle system on the source chain (Chain A)
        console.log("=== Deploying Source Chain Components (Chain A) ===");
        
        // Deploy TruncGeoOracleMulti (would use your actual deployment in practice)
        TruncGeoOracleMulti truncOracle = new TruncGeoOracleMulti(
            IPoolManager(MOCK_POOL_MANAGER),
            MOCK_FULL_RANGE_HOOK
        );
        console.log("TruncGeoOracleMulti deployed at:", address(truncOracle));
        
        // Deploy Oracle Integration (main integration point with your existing system)
        TruncOracleIntegration integration = new TruncOracleIntegration(
            truncOracle,
            MOCK_FULL_RANGE_HOOK,
            address(0) // Will create a new registry
        );
        console.log("TruncOracleIntegration deployed at:", address(integration));
        console.log("UniChainOracleAdapter deployed at:", address(integration.oracleAdapter()));
        console.log("UniChainOracleRegistry deployed at:", address(integration.oracleRegistry()));
        
        // Step 3: Deploy the resolver on the destination chain (Chain B)
        console.log("=== Deploying Destination Chain Components (Chain B) ===");
        
        CrossChainPriceResolver resolver = new CrossChainPriceResolver(
            address(mockCrossL2Inbox)
        );
        console.log("CrossChainPriceResolver deployed at:", address(resolver));
        
        // Step 4: Register the source oracle adapter in the resolver
        address sourceAdapter = address(integration.oracleAdapter());
        uint256 sourceChainId = block.chainid; // In real deployment, this would be different
        resolver.registerSource(sourceChainId, sourceAdapter);
        console.log("Source adapter registered in resolver");
        
        // Step 5: Simulate a cross-chain oracle update
        
        // Create a mock pool ID for demonstration
        bytes32 mockPoolId = keccak256(abi.encodePacked("WETH-USDC"));
        
        // Create a mock pool key
        PoolKey memory mockPoolKey;
        // In a real implementation, this would be populated with actual pool data
        
        // Register the pool for auto-publishing
        integration.registerPool(mockPoolKey, true);
        console.log("Pool registered for auto-publishing");
        
        // Simulate publishing oracle data for the pool
        integration.publishPoolData(mockPoolKey);
        console.log("Oracle data published on source chain");
        
        // Step 6: Simulate cross-chain event validation
        // In reality, this would happen through OP Supervisor and CrossDomainMessenger
        
        // Create a mock event identifier
        CrossChainPriceResolver.ICrossL2Inbox.Identifier memory identifier = 
            CrossChainPriceResolver.ICrossL2Inbox.Identifier({
                chainId: sourceChainId,
                origin: sourceAdapter,
                logIndex: 0, // Would be the actual log index in practice
                blockNumber: block.number,
                timestamp: block.timestamp
            });
        
        // Create mock event data (would be the actual event data in practice)
        // Format must match OraclePriceUpdate event structure
        bytes memory eventData = abi.encode(
            bytes32(0), // Event signature (placeholder)
            sourceAdapter,
            sourceChainId,
            mockPoolId,
            int24(1000), // Sample tick value
            uint160(79228162514264337593543950336), // Sample sqrtPriceX96 value
            uint32(block.timestamp)
        );
        
        // Register the message in the mock CrossL2Inbox
        mockCrossL2Inbox.registerMessage(identifier, keccak256(eventData));
        console.log("Message registered in mock CrossL2Inbox");
        
        // Update price from remote chain in the resolver
        resolver.updateFromRemote(identifier, eventData);
        console.log("Price updated in destination chain resolver");
        
        // Step 7: Verify the cross-chain data
        (int24 tick, uint160 sqrtPriceX96, uint32 timestamp, bool isValid, bool isFresh) = 
            resolver.getPrice(sourceChainId, mockPoolId);
        
        console.log("=== Cross-Chain Price Verification ===");
        console.log("Tick:", uint256(uint24(tick)));
        console.log("SqrtPriceX96:", sqrtPriceX96);
        console.log("Timestamp:", timestamp);
        console.log("Is Valid:", isValid);
        console.log("Is Fresh:", isFresh);
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
