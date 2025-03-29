// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainMessenger
 * @dev Base contract for cross-chain messaging functionality
 * @notice Provides core messaging functionality that can be used by both general and specialized oracle components
 */
abstract contract CrossChainMessenger is Ownable {
    // Message status enum
    enum MessageStatus {
        NONE,
        SENT,
        RECEIVED,
        CONFIRMED,
        FAILED
    }
    
    // Base message structure
    struct Message {
        bytes32 messageId;
        address sender;
        bytes payload;
        uint256 timestamp;
        MessageStatus status;
    }
    
    // Common Optimism messenger addresses
    address public constant OPTIMISM_CROSS_DOMAIN_MESSENGER_GOERLI = 0x5086d1eEF304eb5284A0f6720f79403b4e9bE294;
    address public constant OPTIMISM_CROSS_DOMAIN_MESSENGER_MAINNET = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address public constant CROSS_L2_INBOX = 0x4200000000000000000000000000000000000022;
    
    // Events
    event MessageReceived(uint256 indexed sourceChainId, bytes32 indexed messageId, bytes payload);
    event MessageSent(uint256 indexed targetChainId, bytes32 indexed messageId, bytes payload);
    event MessageStatusUpdated(uint256 indexed chainId, bytes32 indexed messageId, MessageStatus status);
    
    /**
     * @dev Generate a unique message ID
     * @param sender Address of the sender
     * @param payload The message payload
     * @param timestamp The current timestamp
     * @return The generated message ID
     */
    function generateMessageId(address sender, bytes memory payload, uint256 timestamp) 
        internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sender, payload, timestamp));
    }
    
    /**
     * @dev Get the appropriate cross-domain messenger for a given chain ID
     * @param chainId The target chain ID
     * @return The messenger address
     */
    function getCrossDomainMessenger(uint256 chainId) internal pure returns (address) {
        if (chainId == 10) {
            return OPTIMISM_CROSS_DOMAIN_MESSENGER_MAINNET;
        } else if (chainId == 420) {
            return OPTIMISM_CROSS_DOMAIN_MESSENGER_GOERLI;
        } else {
            return address(0); // Unknown chain
        }
    }
    
    /**
     * @dev Prepare calldata for a cross-domain message
     * @param targetContract Address of contract on target chain
     * @param functionSignature The function to call
     * @param payload The parameters to pass
     * @param gasLimit Gas limit for the cross-chain call
     * @return The encoded calldata
     */
    function encodeCrossDomainCalldata(
        address targetContract,
        string memory functionSignature,
        bytes memory payload,
        uint32 gasLimit
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSignature(
            "sendMessage(address,bytes,uint32)",
            targetContract,
            payload,
            gasLimit
        );
    }
} 