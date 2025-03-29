// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TruncGeoOracleMulti} from "./TruncGeoOracleMulti.sol";
import {UniChainOracleAdapter} from "./UniChainOracleAdapter.sol";
import {UniChainOracleRegistry} from "./UniChainOracleRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TruncOracleIntegration
 * @notice Integration contract connecting TruncGeoOracleMulti to the cross-chain oracle system
 * @dev Manages the oracle adapter and handles pool data publishing
 */
contract TruncOracleIntegration is Ownable {
    // The truncated oracle being integrated
    TruncGeoOracleMulti public immutable truncGeoOracle;
    
    // The oracle adapter for cross-chain publishing
    UniChainOracleAdapter public immutable oracleAdapter;
    
    // The FullRange hook address
    address public immutable fullRangeHook;
    
    // The oracle registry
    UniChainOracleRegistry public oracleRegistry;
    
    // Registered pools with auto-publishing enabled
    mapping(bytes32 => bool) public autoPublishPools;
    
    // Events
    event PoolRegistered(bytes32 indexed poolId, bool autoPublish);
    event PoolDataPublished(bytes32 indexed poolId);
    
    /**
     * @notice Constructor
     * @param _truncGeoOracle The truncated oracle
     * @param _fullRangeHook The FullRange hook address
     * @param _registryAddress The oracle registry address (optional)
     */
    constructor(
        TruncGeoOracleMulti _truncGeoOracle,
        address _fullRangeHook,
        address _registryAddress
    ) Ownable(msg.sender) {
        truncGeoOracle = _truncGeoOracle;
        fullRangeHook = _fullRangeHook;
        
        // Deploy the adapter that will publish oracle data to the cross-chain system
        oracleAdapter = new UniChainOracleAdapter(_truncGeoOracle);
        
        // Connect to existing registry or deploy a new one
        if (_registryAddress != address(0)) {
            oracleRegistry = UniChainOracleRegistry(_registryAddress);
        } else {
            oracleRegistry = new UniChainOracleRegistry();
            // Register our adapter in the new registry
            bytes32 adapterId = oracleRegistry.generateAdapterId(address(oracleAdapter));
            oracleRegistry.registerAdapter(
                adapterId,
                block.chainid,
                address(oracleAdapter),
                "TruncGeoOracle Adapter",
                "Cross-chain adapter for truncated geometric mean oracle"
            );
        }
    }
    
    /**
     * @notice Registers a pool for auto-publishing
     * @param key The pool key
     * @param autoPublish Whether to auto-publish this pool's data
     */
    function registerPool(PoolKey calldata key, bool autoPublish) external onlyOwner {
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        
        autoPublishPools[poolIdBytes] = autoPublish;
        
        emit PoolRegistered(poolIdBytes, autoPublish);
    }
    
    /**
     * @notice Publishes oracle data for a specific pool
     * @param key The pool key
     * @dev Can be called manually or through the hook callback system
     */
    function publishPoolData(PoolKey calldata key) external {
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        
        // Only the owner or the FullRange hook can call this
        require(
            msg.sender == owner() || msg.sender == fullRangeHook,
            "Unauthorized: not owner or hook"
        );
        
        // Publish the data through the adapter
        oracleAdapter.publishPoolData(key);
        
        emit PoolDataPublished(poolIdBytes);
    }
    
    /**
     * @notice Hook callback function for auto-publishing
     * @param key The pool key
     * @dev Called by the FullRange hook during its callbacks
     */
    function hookCallback(PoolKey calldata key) external {
        // Only the FullRange hook can call this
        require(msg.sender == fullRangeHook, "Unauthorized: not hook");
        
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        
        // Check if auto-publishing is enabled for this pool
        if (autoPublishPools[poolIdBytes]) {
            // Check if the oracle should be updated
            if (truncGeoOracle.shouldUpdateOracle(pid)) {
                // Publish the data through the adapter
                oracleAdapter.publishPoolData(key);
                emit PoolDataPublished(poolIdBytes);
            }
        }
    }
    
    /**
     * @notice Gets the latest published data for a pool
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
        return oracleAdapter.getLatestPoolData(key);
    }
}