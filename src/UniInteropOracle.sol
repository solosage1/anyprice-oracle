// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CrossChainMessenger.sol";

/**
 * @title UniInteropOracle
 * @dev Cross-chain oracle for Unichain interoperability with Optimism integration
 */
contract UniInteropOracle is Ownable, CrossChainMessenger {
    // Message status enum
    enum MessageStatus {
        NONE,
        SENT,
        RECEIVED,
        CONFIRMED,
        FAILED
    }
    
    // Complex message structure
    struct Message {
        bytes32 messageId;
        address sender;
        bytes payload;
        uint256 timestamp;
        MessageStatus status;
    }
    
    // Mapping of chain ID to messages
    mapping(uint256 => mapping(bytes32 => Message)) public chainMessages;
    
    // Keep track of all message IDs by chain ID
    mapping(uint256 => bytes32[]) public messageIdsByChain;
    
    // Optimism Goerli cross-domain messenger address
    address public constant OPTIMISM_CROSS_DOMAIN_MESSENGER_GOERLI = 0x5086d1eEF304eb5284A0f6720f79403b4e9bE294;
    
    // Optimism Mainnet cross-domain messenger address
    address public constant OPTIMISM_CROSS_DOMAIN_MESSENGER_MAINNET = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    
    // Events
    event MessageReceived(uint256 indexed sourceChainId, bytes32 indexed messageId, bytes payload);
    event MessageSent(uint256 indexed targetChainId, bytes32 indexed messageId, bytes payload);
    event MessageStatusUpdated(uint256 indexed chainId, bytes32 indexed messageId, MessageStatus status);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Generate a unique message ID
     */
    function generateMessageId(address sender, bytes memory payload, uint256 timestamp) 
        internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sender, payload, timestamp));
    }
    
    /**
     * @dev Record a message from another chain
     * @param sourceChainId The ID of the chain that sent the message
     * @param payload The message data
     */
    function receiveMessage(uint256 sourceChainId, bytes memory payload) external onlyOwner {
        bytes32 messageId = generateMessageId(msg.sender, payload, block.timestamp);
        
        // Store the complex message
        Message memory newMessage = Message({
            messageId: messageId,
            sender: msg.sender,
            payload: payload,
            timestamp: block.timestamp,
            status: MessageStatus.RECEIVED
        });
        
        chainMessages[sourceChainId][messageId] = newMessage;
        messageIdsByChain[sourceChainId].push(messageId);
        
        emit MessageReceived(sourceChainId, messageId, payload);
        emit MessageStatusUpdated(sourceChainId, messageId, MessageStatus.RECEIVED);
    }
    
    /**
     * @dev Send a message to another chain with Optimism bridge integration
     * @param targetChainId The ID of the chain to send to
     * @param payload The message data to send
     */
    function sendMessage(uint256 targetChainId, bytes memory payload) external onlyOwner {
        bytes32 messageId = generateMessageId(msg.sender, payload, block.timestamp);
        
        // Store the message in our local tracking
        Message memory newMessage = Message({
            messageId: messageId,
            sender: msg.sender,
            payload: payload,
            timestamp: block.timestamp,
            status: MessageStatus.SENT
        });
        
        chainMessages[targetChainId][messageId] = newMessage;
        messageIdsByChain[targetChainId].push(messageId);
        
        // Integration with Optimism's CrossDomainMessenger
        address crossDomainMessenger = getCrossDomainMessenger(targetChainId);
        
        if (crossDomainMessenger != address(0)) {
            // Prepare the call to the CrossDomainMessenger
            bytes memory callData = encodeCrossDomainCalldata(
                address(this),  // target contract on Optimism
                "receiveMessage(uint256,bytes)",
                abi.encode(block.chainid, payload),
                1000000         // gas limit
            );
            
            // In production, this would use the actual call to the messenger
            // We're not making the actual call here as it requires the correct interface
            // assembly {
            //     let success := call(gas(), crossDomainMessenger, 0, add(callData, 32), mload(callData), 0, 0)
            //     if iszero(success) {
            //         revert(0, 0)
            //     }
            // }
            
            // For now, we'll just emit the event for testing purposes
            emit MessageSent(targetChainId, messageId, payload);
            emit MessageStatusUpdated(targetChainId, messageId, MessageStatus.SENT);
        } else {
            // For other chains, we'd integrate with their specific bridges
            // This is a placeholder for future integrations
            emit MessageSent(targetChainId, messageId, payload);
            emit MessageStatusUpdated(targetChainId, messageId, MessageStatus.SENT);
        }
    }
    
    /**
     * @dev Update the status of a message
     * @param chainId The chain ID of the message
     * @param messageId The ID of the message to update
     * @param status The new status
     */
    function updateMessageStatus(uint256 chainId, bytes32 messageId, MessageStatus status) 
        external onlyOwner {
        require(chainMessages[chainId][messageId].messageId != bytes32(0), "Message does not exist");
        
        chainMessages[chainId][messageId].status = status;
        emit MessageStatusUpdated(chainId, messageId, status);
    }
    
    /**
     * @dev Get a specific message
     * @param chainId The chain ID to get a message from
     * @param messageId The ID of the message to get
     * @return The message
     */
    function getMessage(uint256 chainId, bytes32 messageId) 
        external view returns (Message memory) {
        return chainMessages[chainId][messageId];
    }
    
    /**
     * @dev Get all message IDs for a specific chain
     * @param chainId The chain ID to get message IDs for
     * @return Array of message IDs
     */
    function getMessageIds(uint256 chainId) external view returns (bytes32[] memory) {
        return messageIdsByChain[chainId];
    }
    
    /**
     * @dev Get the latest message from a specific chain
     * @param chainId The chain ID to get a message from
     * @return The latest message ID
     */
    function getLatestMessageId(uint256 chainId) external view returns (bytes32) {
        bytes32[] memory ids = messageIdsByChain[chainId];
        if (ids.length == 0) {
            return bytes32(0);
        }
        return ids[ids.length - 1];
    }
} 