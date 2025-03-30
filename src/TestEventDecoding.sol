// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import "./CrossChainPriceResolver.sol";
import "./interfaces/ICrossL2Inbox.sol";

/**
 * @title TestEventDecoding
 * @notice Test contract for verifying event decoding functionality
 * @dev Used for testing the cross-chain event decoding in various scenarios
 */
contract TestEventDecoding {
    /**
     * @notice Attempts to decode event data and returns the result with a success flag
     * @param eventData The event data to decode
     * @return source Source address
     * @return sourceChainId Source chain ID
     * @return poolId Pool identifier
     * @return tick Tick value
     * @return sqrtPriceX96 Square root price
     * @return timestamp Observation timestamp
     * @return success Whether decoding succeeded
     */
    function tryDecodeEventData(bytes memory eventData) external pure returns (
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp,
        bool success
    ) {
        if (eventData.length < 128) {
            return (address(0), 0, bytes32(0), 0, 0, 0, false);
        }
        
        // Split event data into topics and data
        bytes32[] memory topics = new bytes32[](4);
        bytes memory data;
        for(uint i = 0; i < 4; i++) {
            assembly {
                mstore(add(topics, add(32, mul(i, 32))), mload(add(eventData, add(32, mul(i, 32)))))
            }
        }
        
        uint dataLength = eventData.length - 128;
        data = new bytes(dataLength);
        assembly {
            let dataStart := add(eventData, 160)
            let dataPtr := add(data, 32)
            for { let i := 0 } lt(i, dataLength) { i := add(i, 32) } {
                mstore(add(dataPtr, i), mload(add(dataStart, i)))
            }
        }
        
        // Extract indexed params from topics
        // topics[0]: Event signature hash (ignored here)
        // topics[1]: Indexed param 1 (source address) - extract address from bytes32
        source = address(uint160(uint256(topics[1])));
        // topics[2]: Indexed param 2 (sourceChainId) - convert bytes32 to uint256
        sourceChainId = uint256(topics[2]);
        // topics[3]: Indexed param 3 (poolId) - use bytes32 directly
        poolId = topics[3];

        // Decode non-indexed params from data section
        (tick, sqrtPriceX96, timestamp) = abi.decode(data, (int24, uint160, uint32));
        
        return (source, sourceChainId, poolId, tick, sqrtPriceX96, timestamp, true);
    }
    
    /**
     * @notice Creates mock event data for testing
     * @param source Source address
     * @param sourceChainId Source chain ID
     * @param poolId Pool identifier
     * @param tick Tick value
     * @param sqrtPriceX96 Square root price
     * @param timestamp Observation timestamp
     * @return Mock event data bytes
     */
    function createMockEventData(
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) external pure returns (bytes memory) {
        bytes32 eventSig = keccak256("OraclePriceUpdate(address,uint256,bytes32,int24,uint160,uint32)");
        
        // Encode non-indexed params for data section
        bytes memory dataPart = abi.encode(tick, sqrtPriceX96, timestamp);
        
        // Combine into full event format
        return bytes.concat(
            eventSig,                            // topic0 (event signature)
            bytes32(uint256(uint160(source))),   // topic1 (indexed source address)
            bytes32(sourceChainId),              // topic2 (indexed source chain ID)
            poolId,                              // topic3 (indexed pool ID)
            dataPart                             // non-indexed parameters
        );
    }
} 