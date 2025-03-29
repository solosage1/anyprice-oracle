// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/CrossChainPriceResolver.sol";

contract MonitorScript is Script {
    function run() external view {
        // Get the resolver address from environment
        address resolverAddress = vm.envAddress("RESOLVER_ADDRESS");
        
        // Get the chain ID from environment (default to Optimism mainnet)
        uint256 chainId = vm.envOr("CHAIN_ID", uint256(10));
        
        CrossChainPriceResolver resolver = CrossChainPriceResolver(resolverAddress);
        
        console.log("CrossChainPriceResolver Address:", resolverAddress);
        console.log("Chain ID:", chainId);
        
        // Monitor registered sources
        address[] memory validSources = getRegisteredSources(resolver, chainId);
        console.log("==== Registered Oracle Sources ====");
        for (uint i = 0; i < validSources.length; i++) {
            console.log("Source:", validSources[i]);
        }
        
        // Show freshness parameters
        uint256 freshnessThreshold = resolver.freshnessThreshold();
        uint256 chainTimeBuffer = resolver.chainTimeBuffers(chainId);
        console.log("==== Freshness Parameters ====");
        console.log("Base Freshness Threshold:", freshnessThreshold, "seconds");
        console.log("Chain Time Buffer:", chainTimeBuffer, "seconds");
        console.log("Effective Threshold:", freshnessThreshold + chainTimeBuffer, "seconds");
        
        // Future: implement pool price monitoring
        // To be used when specific pool IDs are available
    }
    
    // Helper function to get registered sources
    function getRegisteredSources(CrossChainPriceResolver resolver, uint256 chainId) 
        internal view returns (address[] memory) {
        // This is a simplification since we don't have a direct way to query all sources
        // In a real implementation, we would need to track sources via events or other means
        
        // Placeholder implementation
        address[] memory sources = new address[](0);
        return sources;
    }
}

contract UpdateSourceScript is Script {
    function run() external {
        // Get necessary parameters from environment
        address resolverAddress = vm.envAddress("RESOLVER_ADDRESS");
        uint256 sourceChainId = vm.envUint("SOURCE_CHAIN_ID");
        address sourceAdapter = vm.envAddress("SOURCE_ADAPTER");
        bool shouldRegister = vm.envBool("SHOULD_REGISTER");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        CrossChainPriceResolver resolver = CrossChainPriceResolver(resolverAddress);
        
        if (shouldRegister) {
            resolver.registerSource(sourceChainId, sourceAdapter);
            console.log("Registered source:", sourceAdapter);
            console.log("For chain ID:", sourceChainId);
        } else {
            resolver.removeSource(sourceChainId, sourceAdapter);
            console.log("Removed source:", sourceAdapter);
            console.log("For chain ID:", sourceChainId);
        }
        
        vm.stopBroadcast();
    }
} 