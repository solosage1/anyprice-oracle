// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/TestEventDecoding.sol";
import "../src/mocks/MockCrossL2Inbox.sol";

/**
 * @title CrossChainPriceResolverFuzzTest
 * @notice Fuzz test harness for CrossChainPriceResolver
 * @dev Uses the forge-std library for testing
 */
contract CrossChainPriceResolverFuzzTest is Test {
    CrossChainPriceResolver resolver;
    TestEventDecoding testDecoder;
    MockCrossL2Inbox mockInbox;
    
    function setUp() public {
        mockInbox = new MockCrossL2Inbox();
        resolver = new CrossChainPriceResolver(address(mockInbox));
        testDecoder = new TestEventDecoding();
    }
    
    /**
     * @notice Fuzz test for event data decoding
     * @param source Random source address
     * @param chainId Random chain ID (bounded to avoid overflow)
     * @param poolId Random pool ID
     * @param tick Random tick value (bounded to valid tick range)
     * @param sqrtPriceX96 Random sqrt price
     * @param timestamp Random timestamp
     */
    function testFuzzEventDecoding(
        address source,
        uint256 chainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) public {
        // Bound tick to realistic values
        vm.assume(tick >= -887272 && tick <= 887272);
        
        // Create event data
        bytes memory eventData = testDecoder.createMockEventData(
            source,
            chainId,
            poolId,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Decode and verify
        (
            address decodedSource,
            uint256 decodedSourceChainId,
            bytes32 decodedPoolId,
            int24 decodedTick,
            uint160 decodedSqrtPriceX96,
            uint32 decodedTimestamp,
            bool success
        ) = testDecoder.tryDecodeEventData(eventData);
        
        // Verify decoding succeeded
        assertTrue(success, "Event decoding failed");
        
        // Verify all fields match
        assertEq(decodedSource, source, "Source mismatch");
        assertEq(decodedSourceChainId, chainId, "Chain ID mismatch");
        assertEq(decodedPoolId, poolId, "Pool ID mismatch");
        assertEq(decodedTick, tick, "Tick mismatch");
        assertEq(decodedSqrtPriceX96, sqrtPriceX96, "SqrtPrice mismatch");
        assertEq(decodedTimestamp, timestamp, "Timestamp mismatch");
    }
    
    /**
     * @notice Fuzz test for replay protection
     * @param chainId Random chain ID
     * @param origin Random origin address
     * @param blockNumber1 First block number
     * @param blockNumber2 Second block number
     */
    function testFuzz_ReplayProtection(
        uint8 chainId,  // Use smaller uint to avoid chain ID overflow
        address origin,
        uint16 blockNumber1,  // Use smaller uint to avoid overflow
        uint16 blockNumber2   // Use smaller uint to avoid overflow
    ) public {
        // Assume valid parameters
        vm.assume(chainId > 0);
        vm.assume(origin != address(0));
        vm.assume(blockNumber1 > 0);
        vm.assume(blockNumber2 > 0);
        vm.assume(blockNumber1 != blockNumber2);
        
        // Use smaller block numbers to avoid overflow
        uint16 lowerBlockNumber = blockNumber1 < blockNumber2 ? blockNumber1 : blockNumber2;
        uint16 higherBlockNumber = blockNumber1 > blockNumber2 ? blockNumber1 : blockNumber2;
        
        // Get current chain ID (use the fuzzed chainId but ensure it's not the current block.chainid)
        uint256 chainIdToUse = chainId;
        if (chainIdToUse == block.chainid) {
            // If we match the current chain ID, use a different one to avoid SameChainMessages error
            chainIdToUse = chainIdToUse == 1 ? 2 : 1;
        }
        
        // Set the block timestamp to a reasonable value for testing
        uint256 mockTimestamp = 1000000;
        vm.warp(mockTimestamp);
        
        // Get safe timestamps that won't overflow when casting to uint32
        uint32 safeTimestamp1 = uint32(mockTimestamp - 100);
        uint32 safeTimestamp2 = uint32(mockTimestamp - 50);
        
        // Create two identifiers with different block numbers
        ICrossL2Inbox.Identifier memory id1 = ICrossL2Inbox.Identifier({
            chainId: chainIdToUse,
            origin: origin,
            logIndex: 0,
            blockNumber: lowerBlockNumber,
            timestamp: safeTimestamp1
        });
        
        ICrossL2Inbox.Identifier memory id2 = ICrossL2Inbox.Identifier({
            chainId: chainIdToUse,
            origin: origin,
            logIndex: 1,  // Different log index
            blockNumber: higherBlockNumber,
            timestamp: safeTimestamp2
        });
        
        // Register the source
        vm.startPrank(resolver.owner());
        resolver.registerSource(chainIdToUse, origin);
        vm.stopPrank();
        
        // Create mock event data with safe timestamp
        bytes memory eventData = testDecoder.createMockEventData(
            origin,
            chainIdToUse,
            bytes32(uint256(1)),
            1000, // Random tick
            1000000, // Random sqrtPriceX96
            safeTimestamp1 // Use the same safe timestamp
        );
        
        // Mock the inbox validation to return true
        mockInbox.setValidation(true);
        
        // Split event data into topics and data
        (bytes32[] memory topics, bytes memory data) = _splitEventData(eventData);
        
        // Update from first block
        resolver.updateFromRemote(id1, topics, data);
        
        // Update from second (higher) block should succeed
        resolver.updateFromRemote(id2, topics, data);
        
        // Try to update from an older block - this should revert
        id1.logIndex = 2; // Change log index to avoid duplicate event ID
        vm.expectRevert(abi.encodeWithSelector(
            CrossChainPriceResolver.EventFromOlderBlock.selector,
            lowerBlockNumber,
            higherBlockNumber
        ));
        resolver.updateFromRemote(id1, topics, data);
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