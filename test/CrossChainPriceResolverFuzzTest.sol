// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/MockL2Inbox.sol";
import "../src/TestEventDecoding.sol";

/**
 * @title CrossChainPriceResolverFuzzTest
 * @notice Fuzz test harness for CrossChainPriceResolver
 * @dev Uses the forge-std library for testing
 */
contract CrossChainPriceResolverFuzzTest is Test {
    using stdStorage for StdStorage;
    
    CrossChainPriceResolver resolver;
    MockL2Inbox mockInbox;
    TestEventDecoding testDecoder;
    
    function setUp() public {
        mockInbox = new MockL2Inbox();
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
    function testFuzz_DecodeEventData(
        address source,
        uint64 chainId,  // Bounded to avoid overflow
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) public view {
        // Ensure chainId is not 0
        vm.assume(chainId > 0);
        // Ensure tick is within valid range
        vm.assume(tick >= -887272 && tick <= 887272);
        
        // Create mock event data
        bytes memory eventData = testDecoder.createMockEventData(
            source,
            chainId,
            poolId,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Decode the event data
        (
            address decodedSource,
            uint256 decodedChainId,
            bytes32 decodedPoolId,
            int24 decodedTick,
            uint160 decodedSqrtPriceX96,
            uint32 decodedTimestamp
        ) = resolver.decodeEventData(eventData);
        
        // Verify all fields match
        assertEq(decodedSource, source);
        assertEq(decodedChainId, chainId);
        assertEq(decodedPoolId, poolId);
        assertEq(decodedTick, tick);
        assertEq(decodedSqrtPriceX96, sqrtPriceX96);
        assertEq(decodedTimestamp, timestamp);
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
        
        // Update from first block
        resolver.updateFromRemote(id1, eventData);
        
        // Update from second (higher) block should succeed
        resolver.updateFromRemote(id2, eventData);
        
        // Try to update from an older block - this should revert
        id1.logIndex = 2; // Change log index to avoid duplicate event ID
        vm.expectRevert(abi.encodeWithSelector(
            CrossChainPriceResolver.EventFromOlderBlock.selector,
            lowerBlockNumber,
            higherBlockNumber
        ));
        resolver.updateFromRemote(id1, eventData);
    }
} 