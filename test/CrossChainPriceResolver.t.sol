// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/MockL2Inbox.sol";
import "../src/TestEventDecoding.sol";

contract CrossChainPriceResolverTest is Test {
    CrossChainPriceResolver public resolver;
    MockL2Inbox public mockInbox;
    TestEventDecoding public testDecoder;
    
    address public constant SOURCE_ADAPTER = address(0x1);
    uint256 public constant SOURCE_CHAIN_ID = 10;
    bytes32 public constant POOL_ID = bytes32(uint256(1));
    
    function setUp() public {
        mockInbox = new MockL2Inbox();
        resolver = new CrossChainPriceResolver(address(mockInbox));
        testDecoder = new TestEventDecoding();
    }
    
    function testRegisterSource() public {
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        assertTrue(resolver.validSources(SOURCE_CHAIN_ID, SOURCE_ADAPTER), "Source should be registered");
    }
    
    function testNonOwnerCannotRegisterSource() public {
        vm.prank(address(0x2));
        vm.expectRevert();
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
    }
    
    function testRemoveSource() public {
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        resolver.removeSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        assertFalse(resolver.validSources(SOURCE_CHAIN_ID, SOURCE_ADAPTER), "Source should be removed");
    }
    
    function testSetFreshnessThreshold() public {
        uint256 newThreshold = 3600 * 2; // 2 hours
        resolver.setFreshnessThreshold(newThreshold);
        assertEq(resolver.freshnessThreshold(), newThreshold, "Freshness threshold should be updated");
    }
    
    function testSetChainTimeBuffer() public {
        uint256 buffer = 300; // 5 minutes
        resolver.setChainTimeBuffer(SOURCE_CHAIN_ID, buffer);
        assertEq(resolver.chainTimeBuffers(SOURCE_CHAIN_ID), buffer, "Chain time buffer should be updated");
    }
    
    function testPauseAndUnpause() public {
        resolver.pause();
        assertTrue(resolver.paused(), "Resolver should be paused");
        
        resolver.unpause();
        assertFalse(resolver.paused(), "Resolver should be unpaused");
    }
    
    function testUpdateFromRemote() public {
        // Register the source
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        
        // Set the block timestamp to a reasonable value for testing
        uint256 mockTimestamp = 1000000;
        vm.warp(mockTimestamp);
        
        // Create event data with safe values
        int24 tick = 1000;
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        uint32 timestamp = uint32(mockTimestamp - 60); // Use a timestamp from 1 minute ago
        
        bytes memory eventData = testDecoder.createMockEventData(
            SOURCE_ADAPTER,
            SOURCE_CHAIN_ID,
            POOL_ID,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Record current values for debugging (should now be set to mockTimestamp)
        uint256 currentBlockTime = block.timestamp;
        uint256 currentBlockNumber = block.number;
        
        // Create identifier with safe values
        ICrossL2Inbox.Identifier memory id = ICrossL2Inbox.Identifier({
            chainId: SOURCE_CHAIN_ID,
            origin: SOURCE_ADAPTER,
            logIndex: 0,
            blockNumber: currentBlockNumber > 10 ? currentBlockNumber - 10 : 1, // Safe past block
            timestamp: uint32(mockTimestamp - 120) // Earlier than the event timestamp
        });
        
        // Override validation for testing
        mockInbox.setValidation(true);
        
        // Split event data into topics and data
        (bytes32[] memory topics, bytes memory data) = _splitEventData(eventData);
        
        // Update price from remote chain
        resolver.updateFromRemote(id, topics, data);
        
        // Verify the price was updated
        (int24 storedTick, uint160 storedSqrt, uint32 storedTimestamp, bool isValid, bool isFresh) = 
            resolver.getPrice(SOURCE_CHAIN_ID, POOL_ID);
            
        assertEq(storedTick, tick, "Tick should match");
        assertEq(storedSqrt, sqrtPriceX96, "SqrtPrice should match");
        assertEq(storedTimestamp, timestamp, "Timestamp should match");
        assertTrue(isValid, "Price should be valid");
        assertTrue(isFresh, "Price should be fresh");
    }
    
    function testRejectNonValidatedSource() public {
        // Set the block timestamp to a reasonable value for testing
        uint256 mockTimestamp = 1000000;
        vm.warp(mockTimestamp);
        
        // Source is not registered
        
        // Create event data with parameters that won't cause overflow
        int24 tick = 1000;
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        uint32 timestamp = uint32(mockTimestamp - 60); // Use a timestamp from 1 minute ago
        
        // Use the test decoder which works correctly
        bytes memory eventData = testDecoder.createMockEventData(
            SOURCE_ADAPTER,
            SOURCE_CHAIN_ID,
            POOL_ID,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Record current values for debugging (should now be set to mockTimestamp)
        uint256 currentBlockTime = block.timestamp;
        uint256 currentBlockNumber = block.number;
        
        // Create identifier with safe values
        ICrossL2Inbox.Identifier memory id = ICrossL2Inbox.Identifier({
            chainId: SOURCE_CHAIN_ID,
            origin: SOURCE_ADAPTER,
            logIndex: 0,
            blockNumber: currentBlockNumber > 10 ? currentBlockNumber - 10 : 1, // Safe past block
            timestamp: uint32(mockTimestamp - 120) // Earlier than the event timestamp
        });
        
        // Override validation for testing
        mockInbox.setValidation(false);
        
        // Split event data into topics and data
        (bytes32[] memory topics, bytes memory data) = _splitEventData(eventData);
        
        // Attempt to update from remote with invalid message
        vm.expectRevert();
        resolver.updateFromRemote(id, topics, data);
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