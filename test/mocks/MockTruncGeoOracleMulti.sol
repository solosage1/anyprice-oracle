// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

// Mock for TruncGeoOracleMulti (adjust based on actual interface if needed)
contract MockTruncGeoOracleMulti {
    // using PoolIdLibrary for PoolId; // Remove this - unwrap doesn't exist in this version's library

    mapping(bytes32 => Observation) public observations;
    mapping(bytes32 => bool) public poolExists;

    struct Observation {
        uint32 timestamp;
        int24 tick;
        int48 tickCumulative;
        uint144 secondsPerLiquidityCumulativeX128;
    }

    function setObservation(PoolId poolId, uint32 ts, int24 t, int48 tc, uint144 slc) public {
        // Use the built-in unwrap for User Defined Value Types
        observations[PoolId.unwrap(poolId)] = Observation(ts, t, tc, slc);
    }
    
    function setPoolExists(PoolId poolId, bool exists) public {
        // Use the built-in unwrap for User Defined Value Types
        poolExists[PoolId.unwrap(poolId)] = exists;
    }

    function getLastObservation(PoolId poolId) 
        external 
        view 
        returns (uint32 timestamp, int24 tick, int48 tickCumulative, uint144 secondsPerLiquidityCumulativeX128)
    {
        // Use the built-in unwrap for User Defined Value Types
        bytes32 pidBytes = PoolId.unwrap(poolId);
        if (!poolExists[pidBytes]) {
            revert("Mock: Pool not enabled");
        }
        Observation memory obs = observations[pidBytes];
        return (obs.timestamp, obs.tick, obs.tickCumulative, obs.secondsPerLiquidityCumulativeX128);
    }
} 