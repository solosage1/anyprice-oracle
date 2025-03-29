// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/UniInteropOracle.sol";

contract UniInteropOracleTest is Test {
    UniInteropOracle public oracle;
    address owner = address(1);
    address user = address(2);
    
    function setUp() public {
        vm.prank(owner);
        oracle = new UniInteropOracle();
    }
    
    function testReceiveMessage() public {
        // Setup test variables
        uint256 sourceChainId = 10; // Optimism chain ID
        bytes memory payload = abi.encode("Test message");
        
        // Only owner can receive messages
        vm.prank(owner);
        oracle.receiveMessage(sourceChainId, payload);
        
        // Get the latest message ID
        bytes32 messageId = oracle.getLatestMessageId(sourceChainId);
        
        // Check if message was stored correctly
        UniInteropOracle.Message memory message = oracle.getMessage(sourceChainId, messageId);
        assertEq(uint256(message.status), uint256(UniInteropOracle.MessageStatus.RECEIVED));
        assertEq(keccak256(message.payload), keccak256(payload));
    }
    
    function testNonOwnerCannotReceiveMessage() public {
        // Setup test variables
        uint256 sourceChainId = 10; // Optimism chain ID
        bytes memory payload = abi.encode("Test message");
        
        // Non-owner should not be able to receive messages
        vm.prank(user);
        vm.expectRevert();
        oracle.receiveMessage(sourceChainId, payload);
    }
    
    function testSendMessage() public {
        // Setup test variables
        uint256 targetChainId = 10; // Optimism chain ID
        bytes memory payload = abi.encode("Test outbound message");
        
        // Send message as owner
        vm.prank(owner);
        oracle.sendMessage(targetChainId, payload);
        
        // Get the latest message ID
        bytes32 messageId = oracle.getLatestMessageId(targetChainId);
        
        // Check if message was stored correctly
        UniInteropOracle.Message memory message = oracle.getMessage(targetChainId, messageId);
        assertEq(uint256(message.status), uint256(UniInteropOracle.MessageStatus.SENT));
        assertEq(keccak256(message.payload), keccak256(payload));
    }
    
    function testNonOwnerCannotSendMessage() public {
        // Setup test variables
        uint256 targetChainId = 10; // Optimism chain ID
        bytes memory payload = abi.encode("Test outbound message");
        
        // Non-owner should not be able to send messages
        vm.prank(user);
        vm.expectRevert();
        oracle.sendMessage(targetChainId, payload);
    }
    
    function testUpdateMessageStatus() public {
        // Setup test variables
        uint256 chainId = 10; // Optimism chain ID
        bytes memory payload = abi.encode("Test message for status update");
        
        // Create a message
        vm.prank(owner);
        oracle.receiveMessage(chainId, payload);
        bytes32 messageId = oracle.getLatestMessageId(chainId);
        
        // Update status to CONFIRMED
        vm.prank(owner);
        oracle.updateMessageStatus(chainId, messageId, UniInteropOracle.MessageStatus.CONFIRMED);
        
        // Check if status was updated correctly
        UniInteropOracle.Message memory message = oracle.getMessage(chainId, messageId);
        assertEq(uint256(message.status), uint256(UniInteropOracle.MessageStatus.CONFIRMED));
    }
    
    function testNonOwnerCannotUpdateMessageStatus() public {
        // Setup test variables
        uint256 chainId = 10; // Optimism chain ID
        bytes memory payload = abi.encode("Test message for status update");
        
        // Create a message
        vm.prank(owner);
        oracle.receiveMessage(chainId, payload);
        bytes32 messageId = oracle.getLatestMessageId(chainId);
        
        // Non-owner should not be able to update message status
        vm.prank(user);
        vm.expectRevert();
        oracle.updateMessageStatus(chainId, messageId, UniInteropOracle.MessageStatus.CONFIRMED);
    }
    
    function testGetMessageIds() public {
        // Setup test variables
        uint256 chainId = 10; // Optimism chain ID
        
        // Create multiple messages
        vm.startPrank(owner);
        oracle.receiveMessage(chainId, abi.encode("Message 1"));
        oracle.receiveMessage(chainId, abi.encode("Message 2"));
        oracle.receiveMessage(chainId, abi.encode("Message 3"));
        vm.stopPrank();
        
        // Get message IDs
        bytes32[] memory messageIds = oracle.getMessageIds(chainId);
        
        // Check if we have the correct number of messages
        assertEq(messageIds.length, 3);
    }
} 