// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/UniInteropOracle.sol";

contract DeployScript is Script {
    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the oracle contract
        UniInteropOracle oracle = new UniInteropOracle();
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        // Log the deployed contract address
        console.log("UniInteropOracle deployed at:", address(oracle));
        console.log("Chain ID:", block.chainid);
    }
}

contract DeployToGoerli is Script {
    function run() external {
        // This script is specifically for deploying to Ethereum Goerli (chain ID 5)
        require(block.chainid == 5, "This script is intended to be run on Goerli");
        
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the oracle contract
        UniInteropOracle oracle = new UniInteropOracle();
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        // Log the deployed contract address
        console.log("UniInteropOracle deployed to Goerli at:", address(oracle));
    }
}

contract DeployToOptimismGoerli is Script {
    function run() external {
        // This script is specifically for deploying to Optimism Goerli (chain ID 420)
        require(block.chainid == 420, "This script is intended to be run on Optimism Goerli");
        
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the oracle contract
        UniInteropOracle oracle = new UniInteropOracle();
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        // Log the deployed contract address
        console.log("UniInteropOracle deployed to Optimism Goerli at:", address(oracle));
    }
} 