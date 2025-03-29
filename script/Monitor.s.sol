// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/UniInteropOracle.sol";

contract MonitorScript is Script {
    function run() external view {
        // Load oracle address from environment or use a default
        address oracleAddress = vm.envOr("ORACLE_ADDRESS", address(0));
        require(oracleAddress != address(0), "Oracle address must be provided");
        
        // Load chain ID to monitor from environment or use a default (Optimism)
        uint256 chainId = vm.envOr("CHAIN_ID", uint256(10));
        
        // Create an instance of the oracle contract
        UniInteropOracle oracle = UniInteropOracle(oracleAddress);
        
        // Get all message IDs for the specified chain
        bytes32[] memory messageIds = oracle.getMessageIds(chainId);
        
        // Check if any messages exist
        if (messageIds.length == 0) {
            console.log("No messages found for chain ID:", chainId);
            return;
        }
        
        // Display monitoring information
        console.log("===== Message Status Monitor =====");
        console.log("Oracle address:", oracleAddress);
        console.log("Chain ID:", chainId);
        console.log("Total messages:", messageIds.length);
        console.log("==============================");
        
        // Display status for each message
        for (uint i = 0; i < messageIds.length; i++) {
            // Get message details
            UniInteropOracle.Message memory message = oracle.getMessage(chainId, messageIds[i]);
            
            // Convert status to a readable string
            string memory statusString;
            if (uint(message.status) == uint(UniInteropOracle.MessageStatus.NONE)) {
                statusString = "NONE";
            } else if (uint(message.status) == uint(UniInteropOracle.MessageStatus.SENT)) {
                statusString = "SENT";
            } else if (uint(message.status) == uint(UniInteropOracle.MessageStatus.RECEIVED)) {
                statusString = "RECEIVED";
            } else if (uint(message.status) == uint(UniInteropOracle.MessageStatus.CONFIRMED)) {
                statusString = "CONFIRMED";
            } else if (uint(message.status) == uint(UniInteropOracle.MessageStatus.FAILED)) {
                statusString = "FAILED";
            }
            
            // Display message information
            console.log("Message ID:", uint256(messageIds[i]));
            console.log("  Status:", statusString);
            console.log("  Sender:", message.sender);
            console.log("  Timestamp:", message.timestamp);
            console.log("------------------------------");
        }
    }
}

contract UpdateMessageStatus is Script {
    function run() external {
        // Load required environment variables
        address oracleAddress = vm.envOr("ORACLE_ADDRESS", address(0));
        require(oracleAddress != address(0), "Oracle address must be provided");
        
        uint256 chainId = vm.envOr("CHAIN_ID", uint256(0));
        require(chainId != 0, "Chain ID must be provided");
        
        string memory messageIdStr = vm.envOr("MESSAGE_ID", string(""));
        require(bytes(messageIdStr).length > 0, "Message ID must be provided");
        bytes32 messageId = bytes32(abi.encodePacked(messageIdStr));
        
        uint256 statusCode = vm.envOr("STATUS_CODE", uint256(0));
        require(statusCode <= 4, "Invalid status code (0-4)");
        
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Update message status
        UniInteropOracle oracle = UniInteropOracle(oracleAddress);
        oracle.updateMessageStatus(chainId, messageId, UniInteropOracle.MessageStatus(statusCode));
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        console.log("Message status updated");
        console.log("Chain ID:", chainId);
        console.log("Message ID:", uint256(messageId));
        console.log("New Status:", statusCode);
    }
} 