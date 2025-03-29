// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/MockL2Inbox.sol";

contract DeployScript is Script {
    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockL2Inbox for testing
        MockL2Inbox mockInbox = new MockL2Inbox();
        console.log("MockL2Inbox deployed at:", address(mockInbox));

        // Deploy CrossChainPriceResolver
        CrossChainPriceResolver resolver = new CrossChainPriceResolver(address(mockInbox));
        console.log("CrossChainPriceResolver deployed at:", address(resolver));

        vm.stopBroadcast();
    }
}

contract DeployToGoerli is Script {
    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockL2Inbox for testing on Goerli
        MockL2Inbox mockInbox = new MockL2Inbox();
        console.log("MockL2Inbox deployed to Goerli at:", address(mockInbox));

        // Deploy CrossChainPriceResolver to Goerli
        CrossChainPriceResolver resolver = new CrossChainPriceResolver(address(mockInbox));
        console.log("CrossChainPriceResolver deployed to Goerli at:", address(resolver));

        vm.stopBroadcast();
    }
}

contract DeployToOptimismGoerli is Script {
    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // On Optimism, use the actual CrossL2Inbox address
        address crossL2Inbox = 0x4200000000000000000000000000000000000022;
        
        // Deploy CrossChainPriceResolver to Optimism Goerli
        CrossChainPriceResolver resolver = new CrossChainPriceResolver(crossL2Inbox);
        console.log("CrossChainPriceResolver deployed to Optimism Goerli at:", address(resolver));

        vm.stopBroadcast();
    }
} 