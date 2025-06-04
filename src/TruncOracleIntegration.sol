// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TruncGeoOracleMulti} from "./TruncGeoOracleMulti.sol";
import {PriceSenderAdapter} from "./PriceSenderAdapter.sol";
import {IL2ToL2CrossDomainMessenger} from "@eth-optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import {Predeploys} from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TruncOracleIntegration
 * @notice Integration contract connecting TruncGeoOracleMulti to the cross-chain oracle system
 * @dev Manages the PriceSenderAdapter and handles pool data publishing with proper authentication
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
    PriceSenderAdapter public immutable priceSenderAdapter;
    
    // The FullRange hook address
    address public immutable fullRangeHook;
    
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
     * @param _targetChainId The chain ID where the resolver is deployed
     * @param _targetResolverAddress The address of the resolver on the target chain
     * @param _messengerAddress The address of the L2-L2 messenger (use address(0) for default predeploy)
     */
    constructor(
        TruncGeoOracleMulti _truncGeoOracle,
        address _fullRangeHook,
        uint256 _targetChainId,
        address _targetResolverAddress,
        address _messengerAddress
    ) Ownable(msg.sender) {
        truncGeoOracle = _truncGeoOracle;
        fullRangeHook = _fullRangeHook;
        
        // Verify the truncGeoOracle accepts this integration as authorized
        if (_truncGeoOracle.fullRangeHook() != _fullRangeHook) {
            revert AuthenticationMismatch(_truncGeoOracle.fullRangeHook(), _fullRangeHook);
        }
        
        // Additional validation for zero addresses
        if (address(_truncGeoOracle) == address(0)) revert ZeroAddressNotAllowed("truncGeoOracle");
        if (_fullRangeHook == address(0)) revert ZeroAddressNotAllowed("fullRangeHook");
        if (_targetResolverAddress == address(0)) revert ZeroAddressNotAllowed("targetResolverAddress");
        
        // Add the hook to authorized callers
        authorizedCallers[_fullRangeHook] = true;
        emit CallerAuthorized(_fullRangeHook);
        
        // Determine messenger address
        IL2ToL2CrossDomainMessenger messenger = (_messengerAddress == address(0)) 
            ? IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER)
            : IL2ToL2CrossDomainMessenger(_messengerAddress);
        
        // Deploy the sender adapter 
        priceSenderAdapter = new PriceSenderAdapter(
            _truncGeoOracle,
            _targetChainId,
            _targetResolverAddress,
            messenger
        );
        
        // Add the adapter to authorized callers
        authorizedCallers[address(priceSenderAdapter)] = true;
        emit CallerAuthorized(address(priceSenderAdapter));
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
        if (caller == fullRangeHook || caller == address(priceSenderAdapter)) {
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
        
        // Call the new adapter directly, allowing reverts to propagate
        priceSenderAdapter.publishPoolData(key);
        emit PoolDataPublished(poolIdBytes);
        
        // Update state efficiently (only reached if adapter call succeeds)
        state.consecutiveFailures = 0;
        state.lastSuccessTimestamp = uint32(block.timestamp);
        state.lastUpdateTimestamp = uint32(block.timestamp);
        
        // Clear alert flag if it was set
        if (state.hasActiveAlert) {
            state.hasActiveAlert = false;
            emit AlertCleared(poolIdBytes);
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
            // Call the new adapter directly - Reverts will propagate and fail the hook callback
            priceSenderAdapter.publishPoolData(key);
            emit PoolDataPublished(poolIdBytes);
            
            // Update state efficiently (only reached if adapter call succeeds)
            state.consecutiveFailures = 0;
            state.lastSuccessTimestamp = uint32(block.timestamp);
            state.lastUpdateTimestamp = uint32(block.timestamp);
            
            // Clear alert flag if it was set
            if (state.hasActiveAlert) {
                state.hasActiveAlert = false;
                emit AlertCleared(poolIdBytes);
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
        return priceSenderAdapter.getLatestPoolData(key);
    }
}