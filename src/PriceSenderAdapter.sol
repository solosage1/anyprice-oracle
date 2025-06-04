//SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TruncGeoOracleMulti} from "./TruncGeoOracleMulti.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Predeploys} from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import {IL2ToL2CrossDomainMessenger} from "@eth-optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PriceSenderAdapter
 * @notice Adapter for sending oracle data from TruncGeoOracleMulti to other chains in the Superchain
 * @dev Uses L2ToL2CrossDomainMessenger for direct cross-chain communication. Access controlled.
 */
contract PriceSenderAdapter is AccessControl {
    // Role for accounts authorized to trigger routine price updates
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    // The L2-to-L2 messenger for cross-chain communication
    IL2ToL2CrossDomainMessenger public immutable messenger;

    // The truncated oracle being adapted
    TruncGeoOracleMulti public immutable truncGeoOracle;
    
    // Target chain and contract information
    uint256 public immutable targetChainId;
    address public immutable targetResolverAddress;
    
    // Tracks the last published timestamp for each pool to prevent duplicate updates
    mapping(bytes32 => uint32) public lastPublishedTimestamp;
    
    // Custom errors
    error PoolNotEnabledInOracle(bytes32 poolId);
    error OracleDataUnchanged(bytes32 poolId, uint32 lastTimestamp);
    error FutureTimestamp();
    error ZeroAddressNotAllowed();
    
    /**
     * @notice Constructor
     * @param _truncGeoOracle The oracle to adapt for cross-chain use
     * @param _targetChainId The chain ID where the resolver is deployed
     * @param _targetResolverAddress The address of the resolver on the target chain
     * @param _messenger The address of the L2ToL2CrossDomainMessenger to use
     */
    constructor(
        TruncGeoOracleMulti _truncGeoOracle,
        uint256 _targetChainId,
        address _targetResolverAddress,
        IL2ToL2CrossDomainMessenger _messenger
    ) {
        if (address(_truncGeoOracle) == address(0) || _targetResolverAddress == address(0) || address(_messenger) == address(0)) 
            revert ZeroAddressNotAllowed();
        truncGeoOracle = _truncGeoOracle;
        targetChainId = _targetChainId;
        targetResolverAddress = _targetResolverAddress;
        messenger = _messenger;

        // Grant admin and keeper roles to the deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KEEPER_ROLE, msg.sender);
    }
    
    /**
     * @notice Publishes oracle data for a specific pool to the target chain
     * @param key The pool key
     * @dev Sends a cross-chain message via L2ToL2CrossDomainMessenger if new data is available.
     *      Requires KEEPER_ROLE.
     * @return success Boolean indicating if the message was sent
     */
    function publishPoolData(PoolKey calldata key) external onlyRole(KEEPER_ROLE) returns (bool success) {
        PoolId pid = PoolIdLibrary.toId(key);
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        
        // Get latest observation from the oracle (Remove try/catch)
        (uint32 timestamp, int24 tick, , ) = truncGeoOracle.getLastObservation(pid);

        // Only publish if we have fresh data
        if (timestamp <= lastPublishedTimestamp[poolIdBytes]) {
            revert OracleDataUnchanged(poolIdBytes, lastPublishedTimestamp[poolIdBytes]);
        }
        
        // Clamp tick before calculating sqrtPriceX96
        int24 clampedTick = tick;
        if (clampedTick < TickMath.MIN_TICK) {
            clampedTick = TickMath.MIN_TICK;
        } else if (clampedTick > TickMath.MAX_TICK) {
            clampedTick = TickMath.MAX_TICK;
        }
        
        // Get sqrtPriceX96 from the tick
        uint160 sqrtPriceX96 = _tickToSqrtPriceX96(clampedTick);
        
        // Update the last published timestamp
        lastPublishedTimestamp[poolIdBytes] = timestamp;
        
        // Encode the price update call for the target contract
        bytes memory message = abi.encodeCall(
            IPriceReceiverResolver.receivePriceUpdate,
            (poolIdBytes, clampedTick, sqrtPriceX96, timestamp)
        );
        
        // Send the cross-chain message
        messenger.sendMessage(
            targetChainId,
            targetResolverAddress,
            message
        );
        // Return true on successful execution
        return true;
    }
    
    /**
     * @notice Publishes price data directly to the target chain
     * @param poolId The pool identifier
     * @param tick The current tick
     * @param sqrtPriceX96 The square root price
     * @param timestamp The observation timestamp
     * @dev Allows an admin to push arbitrary price data. Use with caution (e.g., for emergencies or seeding).
     *      Requires DEFAULT_ADMIN_ROLE.
     *      This bypasses the direct oracle fetch, allowing manual price injection.
     * @return success Boolean indicating if the message was sent
     */
    function publishPriceData(
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool success) {
        // Timestamp validation
        if (timestamp > block.timestamp) revert FutureTimestamp();
        
        // Rate limiting
        if (timestamp <= lastPublishedTimestamp[poolId]) {
            revert OracleDataUnchanged(poolId, lastPublishedTimestamp[poolId]);
        }
        
        // Update timestamp tracking
        lastPublishedTimestamp[poolId] = timestamp;
        
        // Encode the price update call for the target contract
        bytes memory message = abi.encodeCall(
            IPriceReceiverResolver.receivePriceUpdate,
            (poolId, tick, sqrtPriceX96, timestamp)
        );
        
        // Send the cross-chain message
        messenger.sendMessage(
            targetChainId,
            targetResolverAddress,
            message
        );
        // Return true on successful execution
        return true;
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
        int24 originalTick;

        // Get latest observation from the oracle
        (timestamp, originalTick, , ) = truncGeoOracle.getLastObservation(pid);

        // Clamp tick before calculating sqrtPriceX96
        int24 clampedTick = originalTick;
        if (clampedTick < TickMath.MIN_TICK) {
            clampedTick = TickMath.MIN_TICK;
        } else if (clampedTick > TickMath.MAX_TICK) {
            clampedTick = TickMath.MAX_TICK;
        }

        // Convert clamped tick to sqrtPriceX96
        sqrtPriceX96 = _tickToSqrtPriceX96(clampedTick);

        // Return the clamped tick for consistency with sqrtPriceX96 calculation
        tick = clampedTick;
    }
    
    /**
     * @notice Converts a tick value to the corresponding sqrtPriceX96
     * @param tick The tick value
     * @return sqrtPriceX96 The square root price value
     * @dev Uses the TickMath library from Uniswap V4
     */
    function _tickToSqrtPriceX96(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }
}

/**
 * @title IPriceReceiverResolver
 * @notice Interface for the price receiver contract on the target chain
 */
interface IPriceReceiverResolver {
    function receivePriceUpdate(
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) external;
} 