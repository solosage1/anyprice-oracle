// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IOptimismBridgeAdapter
 * @notice Interface for adapters that publish price data in a cross-chain compatible format
 * @dev Compatible with Optimism's cross-chain messaging system
 */
interface IOptimismBridgeAdapter {
    /**
     * @notice Standardized event for cross-chain oracle updates
     * @dev Should be emitted exactly as defined to ensure proper cross-chain detection
     */
    event OraclePriceUpdate(
        address indexed source,          // This contract's address
        uint256 indexed sourceChainId,   // This chain's ID
        bytes32 indexed poolId,          // Pool identifier
        int24 tick,                      // Price tick
        uint160 sqrtPriceX96,            // Square root price
        uint32 timestamp                 // Observation timestamp
    );
    
    /**
     * @notice Publishes price data in a cross-chain compatible format
     * @param poolId The pool identifier
     * @param tick The current tick
     * @param sqrtPriceX96 The square root price
     * @param timestamp The observation timestamp
     * @return success Whether the publication was successful
     */
    function publishPriceData(
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) external returns (bool success);
} 