// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./CrossChainPriceResolver.sol";

/**
 * @title TestEventDecoding
 * @notice Test contract for verifying event decoding functionality
 * @dev Used for testing the cross-chain event decoding in various scenarios
 */
contract TestEventDecoding {
    /**
     * @notice Tests event decoding with provided event data
     * @param eventData Raw event data to decode
     * @return source Extracted source address
     * @return sourceChainId Extracted source chain ID
     * @return poolId Extracted pool ID
     * @return tick Extracted tick value
     * @return sqrtPriceX96 Extracted sqrt price
     * @return timestamp Extracted timestamp
     * @return success Whether decoding succeeded
     */
    function testEventDecoding(bytes calldata eventData) external pure returns (
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp,
        bool success
    ) {
        // Validate minimum event data length
        if (eventData.length < 128) {
            return (address(0), 0, bytes32(0), 0, 0, 0, false);
        }
        
        try CrossChainPriceResolver(address(0)).decodeEventData(eventData) returns (
            address _source,
            uint256 _sourceChainId,
            bytes32 _poolId,
            int24 _tick,
            uint160 _sqrtPriceX96,
            uint32 _timestamp
        ) {
            return (_source, _sourceChainId, _poolId, _tick, _sqrtPriceX96, _timestamp, true);
        } catch {
            return (address(0), 0, bytes32(0), 0, 0, 0, false);
        }
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