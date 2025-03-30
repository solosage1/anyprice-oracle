// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TruncGeoOracleMulti} from "./TruncGeoOracleMulti.sol";
import {UniChainOracleAdapter} from "./UniChainOracleAdapter.sol";
import {UniChainOracleRegistry} from "./UniChainOracleRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TruncOracleIntegration
 * @notice Integration contract connecting TruncGeoOracleMulti to the cross-chain oracle system
 * @dev Manages the oracle adapter and handles pool data publishing with proper authentication
 */
contract TruncOracleIntegration is Ownable, ReentrancyGuard {
    // Custom errors
    error Unauthorized(address caller);
    error PoolNotRegistered(bytes32 poolId);
    error OracleUpdateFailed(bytes32 poolId, string reason);
    error AuthenticationMismatch(address expectedHook, address providedHook);
    error ZeroAddressNotAllowed(string paramName);
    
    // Gas-optimized packed struct for pool state
    struct PoolState {
        bool autoPublish;
        uint16 consecutiveFailures;
        uint32 lastSuccessTimestamp;
        uint32 lastUpdateTimestamp;
        bool hasActiveAlert;
    }
    
    // The truncated oracle being integrated
    TruncGeoOracleMulti public immutable truncGeoOracle;
    
    // The oracle adapter for cross-chain publishing
    UniChainOracleAdapter public immutable oracleAdapter;
    
    // The FullRange hook address
    address public immutable fullRangeHook;
    
    // The oracle registry
    UniChainOracleRegistry public oracleRegistry;
    
    // Packed pool states with comprehensive tracking
    mapping(bytes32 => PoolState) public poolStates;
    
    // Authentication mapping for mutual authentication
    mapping(address => bool) public authorizedCallers;
    
    // Constants
    uint256 public constant MAX_FAILURES_BEFORE_ALERT = 3;
    
    // Events
    event PoolRegistered(bytes32 indexed poolId, bool autoPublish);
    event PoolDataPublished(bytes32 indexed poolId);
    event CallerAuthorized(address indexed caller);
    event CallerDeauthorized(address indexed caller);
    event OracleUpdateAlert(bytes32 indexed poolId, string reason, uint256 failures);
    event AlertCleared(bytes32 indexed poolId);
    
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
        
        // Verify the truncGeoOracle accepts this integration as authorized
        if (_truncGeoOracle.fullRangeHook() != _fullRangeHook) {
            revert AuthenticationMismatch(_truncGeoOracle.fullRangeHook(), _fullRangeHook);
        }
        
        // Additional validation for zero addresses
        if (_truncGeoOracle == TruncGeoOracleMulti(address(0))) revert ZeroAddressNotAllowed("truncGeoOracle");
        if (_fullRangeHook == address(0)) revert ZeroAddressNotAllowed("fullRangeHook");
        
        // Add the hook to authorized callers
        authorizedCallers[_fullRangeHook] = true;
        emit CallerAuthorized(_fullRangeHook);
        
        // Deploy the adapter that will publish oracle data to the cross-chain system
        oracleAdapter = new UniChainOracleAdapter(_truncGeoOracle);
        
        // Add the adapter to authorized callers
        authorizedCallers[address(oracleAdapter)] = true;
        emit CallerAuthorized(address(oracleAdapter));
        
        // Connect to existing registry or deploy a new one
        if (_registryAddress != address(0)) {
            oracleRegistry = UniChainOracleRegistry(_registryAddress);
        } else {
            // Deploy a new registry
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
            
            // Transfer ownership of the registry to the contract owner
            oracleRegistry.transferOwnership(owner());
        }
    }
    
    /**
     * @notice Authorizes a caller for mutual authentication
     * @param caller The address to authorize
     */
    function authorizeCaller(address caller) external onlyOwner {
        if (caller == address(0)) revert ZeroAddressNotAllowed("caller");
        authorizedCallers[caller] = true;
        emit CallerAuthorized(caller);
    }
    
    /**
     * @notice Removes authorization from a caller
     * @param caller The address to deauthorize
     */
    function deauthorizeCaller(address caller) external onlyOwner {
        // Don't deauthorize critical components
        if (caller == fullRangeHook || caller == address(oracleAdapter)) {
            revert ZeroAddressNotAllowed("Cannot deauthorize critical components");
        }
        authorizedCallers[caller] = false;
        emit CallerDeauthorized(caller);
    }
    
    /**
     * @notice Registers a pool for auto-publishing
     * @param key The pool key
     * @param autoPublish Whether to auto-publish this pool's data
     */
    function registerPool(PoolKey calldata key, bool autoPublish) external onlyOwner {
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        
        // Initialize or update the pool state
        PoolState storage state = poolStates[poolIdBytes];
        state.autoPublish = autoPublish;
        
        emit PoolRegistered(poolIdBytes, autoPublish);
    }
    
    /**
     * @notice Publishes oracle data for a specific pool
     * @param key The pool key
     * @dev Can be called manually or through the hook callback system
     */
    function publishPoolData(PoolKey calldata key) external nonReentrant {
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        PoolState storage state = poolStates[poolIdBytes];
        
        // Authentication check
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert Unauthorized(msg.sender);
        }
        
        try oracleAdapter.publishPoolData(key) {
            emit PoolDataPublished(poolIdBytes);
            
            // Update state efficiently
            state.consecutiveFailures = 0;
            state.lastSuccessTimestamp = uint32(block.timestamp);
            state.lastUpdateTimestamp = uint32(block.timestamp);
            
            // Clear alert flag if it was set
            if (state.hasActiveAlert) {
                state.hasActiveAlert = false;
                emit AlertCleared(poolIdBytes);
            }
        } catch Error(string memory reason) {
            state.consecutiveFailures++;
            state.lastUpdateTimestamp = uint32(block.timestamp);
            
            // Only emit alert once until it's cleared
            if (state.consecutiveFailures >= MAX_FAILURES_BEFORE_ALERT && !state.hasActiveAlert) {
                state.hasActiveAlert = true;
                emit OracleUpdateAlert(poolIdBytes, reason, state.consecutiveFailures);
            }
            
            revert OracleUpdateFailed(poolIdBytes, reason);
        } catch (bytes memory) {
            state.consecutiveFailures++;
            state.lastUpdateTimestamp = uint32(block.timestamp);
            
            // Only emit alert once until it's cleared
            if (state.consecutiveFailures >= MAX_FAILURES_BEFORE_ALERT && !state.hasActiveAlert) {
                state.hasActiveAlert = true;
                emit OracleUpdateAlert(poolIdBytes, "unknown error", state.consecutiveFailures);
            }
            
            revert OracleUpdateFailed(poolIdBytes, "unknown error");
        }
    }
    
    /**
     * @notice Hook callback function for auto-publishing
     * @param key The pool key
     * @dev Called by the FullRange hook during its callbacks
     */
    function hookCallback(PoolKey calldata key) external nonReentrant {
        // Only authorized callers can call this, with special focus on the FullRange hook
        if (msg.sender != fullRangeHook && !authorizedCallers[msg.sender]) {
            revert Unauthorized(msg.sender);
        }
        
        PoolId pid = key.toId();
        bytes32 poolIdBytes = PoolId.unwrap(pid);
        PoolState storage state = poolStates[poolIdBytes];
        
        // Check if auto-publishing is enabled for this pool
        if (!state.autoPublish) {
            return; // Silently return instead of reverting to prevent hook failures
        }
        
        // Check if the oracle should be updated
        if (truncGeoOracle.shouldUpdateOracle(pid)) {
            try oracleAdapter.publishPoolData(key) {
                emit PoolDataPublished(poolIdBytes);
                
                // Update state efficiently
                state.consecutiveFailures = 0;
                state.lastSuccessTimestamp = uint32(block.timestamp);
                state.lastUpdateTimestamp = uint32(block.timestamp);
                
                // Clear alert flag if it was set
                if (state.hasActiveAlert) {
                    state.hasActiveAlert = false;
                    emit AlertCleared(poolIdBytes);
                }
            } catch Error(string memory reason) {
                state.consecutiveFailures++;
                state.lastUpdateTimestamp = uint32(block.timestamp);
                
                // Only emit alert once until it's cleared
                if (state.consecutiveFailures >= MAX_FAILURES_BEFORE_ALERT && !state.hasActiveAlert) {
                    state.hasActiveAlert = true;
                    emit OracleUpdateAlert(poolIdBytes, reason, state.consecutiveFailures);
                }
            } catch (bytes memory) {
                state.consecutiveFailures++;
                state.lastUpdateTimestamp = uint32(block.timestamp);
                
                // Only emit alert once until it's cleared
                if (state.consecutiveFailures >= MAX_FAILURES_BEFORE_ALERT && !state.hasActiveAlert) {
                    state.hasActiveAlert = true;
                    emit OracleUpdateAlert(poolIdBytes, "unknown error", state.consecutiveFailures);
                }
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