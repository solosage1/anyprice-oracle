// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @title Math utilities for oracle calculations
/// @dev Specialized math functions for Uniswap v4 oracle integration
library MathUtils {
    /// @notice Calculates the absolute difference between two int24 values
    /// @param a First tick value
    /// @param b Second tick value
    /// @return absolute difference as a uint24
    function absDiff(int24 a, int24 b) internal pure returns (uint24) {
        return a >= b ? uint24(a - b) : uint24(b - a);
    }
    
    /// @notice Clamps a tick value to the valid Uniswap v4 tick range
    /// @param tick The input tick value
    /// @return The clamped tick
    function clampTick(int24 tick) internal pure returns (int24) {
        if (tick < TickMath.MIN_TICK) {
            return TickMath.MIN_TICK;
        } else if (tick > TickMath.MAX_TICK) {
            return TickMath.MAX_TICK;
        }
        return tick;
    }
    
    /// @notice Calculates the absolute value of an int256
    /// @param x The input value
    /// @return The absolute value as a uint256
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
    
    /// @notice Returns the minimum of two uint256 values
    /// @param a First value
    /// @param b Second value
    /// @return The minimum value
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /// @notice Returns the maximum of two uint256 values
    /// @param a First value
    /// @param b Second value
    /// @return The maximum value
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
} 