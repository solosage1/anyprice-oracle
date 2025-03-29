// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TruncGeoOracleMulti} from "./TruncGeoOracleMulti.sol";

/**
 * @title UniChainOracleAdapter
 * @notice Adapter for publishing oracle data from TruncGeoOracleMulti to the Superchain
 * @dev Emits standardized events that can be picked up by OP Supervisor and validated across chains
 */
contract UniChainOracleAdapter {
    // The truncated oracle being adapted
    TruncGeoOracleMulti public immutable truncGeoOracle;
    
    // Chain ID of the current chain (set during construction)
    uint256 public immutable sourceChainId;
    
    // Tracks the last published timestamp for each pool to prevent duplicate events
    mapping(bytes32 => uint32) public lastPublishedTimestamp;
    
    // Standardized event format for cross-chain oracle updates
    // Indexed fields enable efficient filtering by cross-chain systems
    event OraclePriceUpdate(
        address indexed source,          // Indexed source contract (this adapter)
        uint256 indexed sourceChainId,   // Indexed source chain ID
        bytes32 indexed poolId,          // Indexed pool identifier
        int24 tick,                      // Current tick value
        uint160 sqrtPriceX96,            // Square root price
        uint32 timestamp                 // Observation timestamp
    );
    
    /**
     * @notice Constructor
     * @param _truncGeoOracle The oracle to adapt for cross-chain use
     */
    constructor(TruncGeoOracleMulti _truncGeoOracle) {
        truncGeoOracle = _truncGeoOracle;
        sourceChainId = block.chainid;
    }
    
    /**
     * @notice Publishes oracle data for a specific pool to be consumed across chains
     * @param key The pool key
     * @dev Emits an OraclePriceUpdate event if new data is available
     */
    function publishPoolData(PoolKey calldata key) external {
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        
        // Get latest observation from the oracle
        (uint32 timestamp, int24 tick, int48 tickCumulative, uint144 secondsPerLiquidityCumulativeX128) = 
            truncGeoOracle.getLastObservation(pid);
        
        // Only publish if we have fresh data
        if (timestamp > lastPublishedTimestamp[poolIdBytes]) {
            // Get sqrtPriceX96 from the tick
            uint160 sqrtPriceX96 = _tickToSqrtPriceX96(tick);
            
            // Update the last published timestamp
            lastPublishedTimestamp[poolIdBytes] = timestamp;
            
            // Emit the standardized cross-chain event
            emit OraclePriceUpdate(
                address(this),
                sourceChainId,
                poolIdBytes,
                tick,
                sqrtPriceX96,
                timestamp
            );
        }
    }
    
    /**
     * @notice View function to get the latest price data for a pool
     * @param key The pool key
     * @return timestamp The timestamp of the observation
     * @return tick The tick value
     * @return sqrtPriceX96 The square root price
     */
    function getLatestPoolData(PoolKey calldata key) external view returns (
        uint32 timestamp,
        int24 tick,
        uint160 sqrtPriceX96
    ) {
        PoolId pid = key.toId();
        
        // Get latest observation from the oracle
        (timestamp, tick, , ) = truncGeoOracle.getLastObservation(pid);
        
        // Convert tick to sqrtPriceX96
        sqrtPriceX96 = _tickToSqrtPriceX96(tick);
    }
    
    /**
     * @notice Converts a tick value to the corresponding sqrtPriceX96
     * @param tick The tick value
     * @return sqrtPriceX96 The square root price value
     * @dev Uses the TickMath library from Uniswap V4
     */
    function _tickToSqrtPriceX96(int24 tick) internal pure returns (uint160) {
        // For simplicity, we'll recreate the tick to price calculation
        // In production, you'd use the full TickMath.getSqrtRatioAtTick implementation
        
        // Simplified version for demo
        int24 clampedTick = tick < -887272 ? -887272 : (tick > 887272 ? 887272 : tick);
        
        // Base value for tick 0
        uint160 baseValue = 79228162514264337593543950336;
        
        if (clampedTick < 0) {
            return uint160(baseValue >> (-clampedTick / 2));
        } else {
            return uint160(baseValue << (clampedTick / 2));
        }
    }
} 