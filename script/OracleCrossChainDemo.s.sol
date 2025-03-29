// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/UniChainOracleAdapter.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/UniChainOracleRegistry.sol";
import "../src/TruncOracleIntegration.sol";
import "../src/MockL2Inbox.sol";
import "../src/TruncGeoOracleMulti.sol";
import "../src/interfaces/ICrossL2Inbox.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

/**
 * @title OracleCrossChainDemoScript
 * @notice Demo script for the cross-chain oracle system
 * @dev Demonstrates the full flow of data from source chain to destination chain
 */
contract OracleCrossChainDemoScript is Script {
    // Mock addresses for testing
    address constant MOCK_POOL_MANAGER = address(0x100);
    address constant MOCK_FULL_RANGE_HOOK = address(0x200);
    
    using PoolIdLibrary for PoolKey;
    
    // Store deployment state to avoid stack too deep error
    struct DeploymentState {
        MockL2Inbox mockCrossL2Inbox;
        TruncGeoOracleMulti truncOracle;
        TruncOracleIntegration integration;
        CrossChainPriceResolver resolver;
        address sourceAdapter;
        uint256 sourceChainId;
        bytes32 actualPoolId;
    }
    
    DeploymentState state;
    
    function run() external {
        // Load private key from environment or use default test key
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy all contracts
        deployContracts();
        
        // Set up the oracle system
        setupOracleSystem();
        
        // Execute cross-chain oracle update demo
        executeOracleUpdateDemo();
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
    
    function deployContracts() internal {
        // Step 1: Create mocks
        state.mockCrossL2Inbox = new MockL2Inbox();
        
        // Step 2: Deploy the oracle system on the source chain (Chain A)
        console.log("=== Deploying Source Chain Components (Chain A) ===");
        
        // Deploy TruncGeoOracleMulti (would use your actual deployment in practice)
        state.truncOracle = new TruncGeoOracleMulti(
            IPoolManager(MOCK_POOL_MANAGER),
            MOCK_FULL_RANGE_HOOK
        );
        console.log("TruncGeoOracleMulti deployed at:", address(state.truncOracle));
        
        // Deploy Oracle Integration (main integration point with your existing system)
        state.integration = new TruncOracleIntegration(
            state.truncOracle,
            MOCK_FULL_RANGE_HOOK,
            address(0) // Will create a new registry
        );
        console.log("TruncOracleIntegration deployed at:", address(state.integration));
        console.log("UniChainOracleAdapter deployed at:", address(state.integration.oracleAdapter()));
        console.log("UniChainOracleRegistry deployed at:", address(state.integration.oracleRegistry()));
        
        // Step 3: Deploy the resolver on the destination chain (Chain B)
        console.log("=== Deploying Destination Chain Components (Chain B) ===");
        
        state.resolver = new CrossChainPriceResolver(
            address(state.mockCrossL2Inbox)
        );
        console.log("CrossChainPriceResolver deployed at:", address(state.resolver));
    }
    
    function setupOracleSystem() internal {
        // Step 4: Register the source oracle adapter in the resolver
        state.sourceAdapter = address(state.integration.oracleAdapter());
        state.sourceChainId = block.chainid; // In real deployment, this would be different
        state.resolver.registerSource(state.sourceChainId, state.sourceAdapter);
        console.log("Source adapter registered in resolver");
        
        // Step 5: Set up the pool for cross-chain updates
        
        // Create a mock pool key
        PoolKey memory mockPoolKey;
        // In a real implementation, this would be populated with actual pool data
        
        // Register the pool for auto-publishing
        state.integration.registerPool(mockPoolKey, true);
        console.log("Pool registered for auto-publishing");
        
        // Get the actual pool ID from the mock pool key
        state.actualPoolId = PoolId.unwrap(mockPoolKey.toId());
        console.log("Using pool ID for initialization");
        
        // Initialize the mock pool in the oracle for demo purposes
        state.truncOracle.mockInitializePool(state.actualPoolId, 1000); // Initial tick of 1000
        console.log("Mock pool initialized in oracle");
    }
    
    function createEventData() internal view returns (bytes memory fullEventData, ICrossL2Inbox.Identifier memory identifier) {
        // Create a mock event identifier
        identifier = ICrossL2Inbox.Identifier({
            chainId: state.sourceChainId,
            origin: state.sourceAdapter,
            logIndex: 0, // Would be the actual log index in practice
            blockNumber: block.number,
            timestamp: block.timestamp
        });
        
        // Use current timestamp for the data (important to pass the freshness check)
        uint32 currentTimestamp = uint32(block.timestamp);
        
        // Event signature (topic1) - keccak256 hash of the event signature
        // This should be calculated from the exact event signature as defined in the emitting contract
        bytes32 eventSig = keccak256("OraclePriceUpdate(address,uint256,bytes32,int24,uint160,uint32)");
        
        // Create the three indexed parameters (topics 2-4)
        bytes32 topic2 = bytes32(uint256(uint160(state.sourceAdapter))); // address padded to bytes32
        bytes32 topic3 = bytes32(state.sourceChainId);
        bytes32 topic4 = state.actualPoolId;
        
        // Create properly ABI encoded data for the non-indexed parameters
        // CrossChainPriceResolver.decodeEventData skips 128 bytes (32 for eventSig + 3*32 for indexed topics)
        // But it still expects to decode ALL parameters including the indexed ones
        bytes memory eventData = abi.encode(
            state.sourceAdapter,  // address source
            state.sourceChainId,  // uint256 sourceChainId
            state.actualPoolId,   // bytes32 poolId
            int24(1000),          // int24 tick
            uint160(79228162514264337593543950336), // sqrtPriceX96 (demo value)
            currentTimestamp      // uint32 timestamp (using current block timestamp)
        );
        
        // Combine into full Ethereum log format - the EVM stores:
        // - Event signature (32 bytes)
        // - Indexed topics (each 32 bytes)
        // - Actual data 
        fullEventData = abi.encodePacked(
            eventSig,  // topic1 (event signature)
            topic2,    // topic2 (indexed parameter 1)
            topic3,    // topic3 (indexed parameter 2)
            topic4,    // topic4 (indexed parameter 3)
            eventData  // data containing ALL parameters for decoding
        );
        
        return (fullEventData, identifier);
    }
    
    function executeOracleUpdateDemo() internal {
        // Create a mock pool key for publishing data - must match the one used in setup
        PoolKey memory mockPoolKey;
        // Default values are already zeros, which matches our setup
        
        // Simulate publishing oracle data for the pool
        try state.integration.publishPoolData(mockPoolKey) {
            console.log("Oracle data published on source chain");
        } catch Error(string memory reason) {
            console.log("Oracle data publishing failed:", reason);
        } catch {
            console.log("Oracle data publishing failed with unknown error");
        }
        
        // Step 6: Simulate cross-chain event validation
        
        // Create the event data with proper Ethereum log format
        (bytes memory fullEventData, ICrossL2Inbox.Identifier memory identifier) = createEventData();
        
        // Register the message in the mock CrossL2Inbox
        state.mockCrossL2Inbox.registerMessage(identifier, keccak256(fullEventData));
        console.log("Message registered in mock CrossL2Inbox");
        
        // Update price from remote chain in the resolver
        try state.resolver.updateFromRemote(identifier, fullEventData) {
            console.log("Price updated in destination chain resolver");
        } catch Error(string memory reason) {
            console.log("Price update failed:", reason);
        } catch {
            console.log("Price update failed with unknown error");
            try state.mockCrossL2Inbox.validateMessage(identifier, keccak256(fullEventData)) returns (bool valid) {
                console.log("Message validation in L2Inbox:", valid ? "succeeded" : "failed");
            } catch Error(string memory reason) {
                console.log("Message validation check failed:", reason);
            }
        }
        
        // Step 7: Verify the cross-chain data
        (int24 tick, uint160 sqrtPriceX96, uint32 timestamp, bool isValid, bool isFresh) = 
            state.resolver.getPrice(state.sourceChainId, state.actualPoolId);
        
        console.log("=== Cross-Chain Price Verification ===");
        console.log("Tick:", uint256(uint24(tick)));
        console.log("SqrtPriceX96:", sqrtPriceX96);
        console.log("Timestamp:", timestamp);
        console.log("Is Valid:", isValid);
        console.log("Is Fresh:", isFresh);
    }
}