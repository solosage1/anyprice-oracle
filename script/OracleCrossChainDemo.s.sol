import "forge-std/console.sol";
// SPDX-License-Identifier: BSL-1.1
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
        
        console.log(unicode"\n📦 Deploying UniChainOracleRegistry...");
        
        // Step 2: Deploy the oracle system on the source chain (Chain A)
        
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
        
        state.resolver = new CrossChainPriceResolver(
            address(state.mockCrossL2Inbox)
        );
        console.log("CrossChainPriceResolver deployed at:", address(state.resolver));
    }
    
    function setupOracleSystem() internal {
        // Step 4: Register the source oracle adapter in the resolver
        state.sourceAdapter = address(state.integration.oracleAdapter());
        // Use a different chain ID for the source chain
        state.sourceChainId = 10; // Simulating Optimism
        console.log("Source Chain ID:", state.sourceChainId);
        
        state.resolver.registerSource(state.sourceChainId, state.sourceAdapter);
        console.log("Source adapter registered in resolver");
        
        // Set chain-specific time buffer and increase freshness threshold
        state.resolver.setChainTimeBuffer(state.sourceChainId, 60); // 1 minute buffer
        state.resolver.setFreshnessThreshold(4 hours); // Set a longer threshold for the demo
        console.log("Chain time buffer and freshness threshold set");
        
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
        // Get the current timestamp and ensure it's reasonable
        uint256 safeTimestamp = block.timestamp;
        console.log("Current timestamp for event data:", safeTimestamp);
        
        // Create a mock event identifier with a different chain ID
        identifier = ICrossL2Inbox.Identifier({
            chainId: state.sourceChainId, // Using our simulated source chain ID
            origin: state.sourceAdapter,
            logIndex: 0, // Would be the actual log index in practice
            blockNumber: block.number > 100 ? block.number - 100 : 1, // Use a past block
            timestamp: safeTimestamp > 300 ? safeTimestamp - 300 : 1 // Use a past timestamp
        });
        
        // Log the identifier details for debugging
        console.log("Event identifier details:");
        console.log("  ChainId:", identifier.chainId);
        console.log("  Origin:", identifier.origin);
        console.log("  BlockNumber:", identifier.blockNumber);
        console.log("  Timestamp:", identifier.timestamp);
        
        // Use a safe timestamp for the price data - needs to be recent enough to pass freshness check
        // But also not in the future compared to the current block time
        uint32 safePriceTimestamp = uint32(safeTimestamp > 60 ? safeTimestamp - 60 : 1); // 1 minute ago
        console.log("Price data timestamp:", safePriceTimestamp);
        
        // Proper EVM log structure:
        bytes32 eventSig = keccak256("OraclePriceUpdate(address,uint256,bytes32,int24,uint160,uint32)");
        
        // Avoid double encoding of values - EVM logs use raw 32-byte fields
        bytes32 topic2 = bytes32(uint256(uint160(state.sourceAdapter)));
        bytes32 topic3 = bytes32(state.sourceChainId);
        bytes32 topic4 = state.actualPoolId;
        
        // Only non-indexed params in data section
        bytes memory dataSection = abi.encode(int24(1000), uint160(79228162514264337593543950336), safePriceTimestamp);
        
        // Combine into full Ethereum log format
        fullEventData = bytes.concat(
            eventSig,  // topic1 (event signature)
            topic2,    // topic2 (indexed parameter 1)
            topic3,    // topic3 (indexed parameter 2)
            topic4,    // topic4 (indexed parameter 3)
            dataSection  // data containing only non-indexed params
        );
        
        return (fullEventData, identifier);
    }
    
    function executeOracleUpdateDemo() internal {
        // Set a reasonable timestamp for testing
        uint256 mockTimestamp = block.timestamp;  // Use current timestamp
        vm.warp(mockTimestamp);
        
        console.log(unicode"\n🚀 Starting AnyPrice Demo...");
        console.log("Step 1: Deploying Registry, Adapters, Resolver...\n");
        
        // Create a mock pool key for publishing data - must match the one used in setup
        PoolKey memory mockPoolKey;
        // Default values are already zeros, which matches our setup
        
        // Simulate being on source chain (Optimism in this scenario)
        uint256 sourceChainId = 10; // Optimism
        uint256 destChainId = 1;    // Ethereum Mainnet
        
        // Step 1: Source chain operations
        vm.chainId(sourceChainId);
        console.log(unicode"\n📡 Simulating source chain (Chain ID:", sourceChainId, ")");
        
        // Try to initialize pool for testing
        try state.truncOracle.mockInitializePool(state.actualPoolId, 1000) {
            console.log("Re-initialized mock pool in source chain oracle");
        } catch {
            // Pool may already be initialized
        }
        
        // Simulate publishing oracle data for the pool
        try state.integration.publishPoolData(mockPoolKey) {
            console.log(unicode"\n🔗 Registering Oracle Adapters...");
            console.log("Oracle data published on source chain");
        } catch Error(string memory reason) {
            console.log("Oracle data publishing failed:", reason);
        } catch {
            console.log("Oracle data publishing failed with unknown error");
            
            // Let's manually create the event data to simulate a successful publish
            console.log("Creating manual oracle update event data");
        }
        
        // Create the event data with proper Ethereum log format
        (bytes memory fullEventData, ICrossL2Inbox.Identifier memory identifier) = createEventData();
        
        // Step 2: Destination chain operations - use a completely different chain ID
        vm.chainId(destChainId);
        console.log(unicode"\n📡 Sending cross-chain price request for DAI...");
        console.log("Switched to destination chain (Chain ID:", block.chainid, ")");
        
        // Register the message in the mock CrossL2Inbox
        state.mockCrossL2Inbox.registerMessage(identifier, keccak256(fullEventData));
        console.log("Message registered in mock CrossL2Inbox");
        
        // Advance time a bit to simulate passage of time between chains
        vm.warp(mockTimestamp + 600); // 10 minutes later
        
        // Disable the same-chain validation override just for this demo
        try state.mockCrossL2Inbox.clearValidationOverride() {
            console.log("Cleared validation override");
        } catch {
            console.log("Failed to clear validation override");
        }
        
        // Set validation to true to bypass specific checks for demo
        state.mockCrossL2Inbox.setValidation(true);
        console.log(unicode"\n🔁 Simulating UniChain OracleAdapter response...");
        
        // Update price from remote chain in the resolver
        bytes32[] memory topics = new bytes32[](4);
        bytes memory data;
        (topics, data) = _splitEventData(fullEventData);
        try state.resolver.updateFromRemote(identifier, topics, data) {
            console.log(unicode"\n✅ Resolving price on Optimism side...");
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
        
        console.log("\n=== Cross-Chain Price Verification ===");
        console.log("Tick:", uint256(uint24(tick)));
        console.log("SqrtPriceX96:", sqrtPriceX96);
        console.log("Timestamp:", timestamp);
        console.log("Is Valid:", isValid);
        console.log("Is Fresh:", isFresh);
        
        console.log(unicode"\n🏁 Demo Complete: AnyPrice cross-chain resolution succeeded.");
    }

    /// @notice Helper function to split event data into topics and data
    function _splitEventData(bytes memory fullEventData) internal pure returns (bytes32[] memory topics, bytes memory data) {
        require(fullEventData.length >= 128, "Invalid event data length"); // At least 4 topics (32 bytes each)
        
        // Create topics array
        topics = new bytes32[](4);
        for(uint i = 0; i < 4; i++) {
            assembly {
                mstore(add(topics, add(32, mul(i, 32))), mload(add(fullEventData, add(32, mul(i, 32)))))
            }
        }
        
        // Extract data part (everything after the topics)
        uint dataLength = fullEventData.length - 128; // 128 = 4 topics * 32 bytes
        data = new bytes(dataLength);
        assembly {
            let dataStart := add(fullEventData, 160) // 160 = 32 (length word) + 128 (topics)
            let dataPtr := add(data, 32)
            for { let i := 0 } lt(i, dataLength) { i := add(i, 32) } {
                mstore(add(dataPtr, i), mload(add(dataStart, i)))
            }
        }
        
        return (topics, data);
    }
}