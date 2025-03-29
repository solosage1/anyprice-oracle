// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./CrossChainMessenger.sol";
import "./interfaces/ICrossL2Inbox.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CrossChainPriceResolver
 * @notice Resolver contract that validates and consumes oracle price data from other chains
 * @dev Uses Optimism's CrossL2Inbox for secure cross-chain event validation
 */
contract CrossChainPriceResolver is CrossChainMessenger, Pausable, ReentrancyGuard {
    // Price data structure
    struct PriceData {
        int24 tick;                 // Tick value
        uint160 sqrtPriceX96;       // Square root price
        uint32 timestamp;           // Observation timestamp
        bool isValid;               // Whether the data is valid/initialized
    }
    
    // Reference to CrossL2Inbox contract (Optimism predeploy)
    ICrossL2Inbox public immutable crossL2Inbox;
    
    // Price storage: chainId => poolId => PriceData
    mapping(uint256 => mapping(bytes32 => PriceData)) public prices;
    
    // Validated source adapters: chainId => adapter address => isValid
    mapping(uint256 => mapping(address => bool)) public validSources;
    
    // Timestamp threshold for freshness validation (default: 1 hour)
    uint256 public freshnessThreshold = 1 hours;
    
    // Chain-specific time buffers to account for differences in block times
    mapping(uint256 => uint256) public chainTimeBuffers;
    
    // Event replay protection: hash(chainId, origin, logIndex, blockNumber) => processed
    mapping(bytes32 => bool) public processedEvents;
    
    // Events
    event PriceUpdated(
        uint256 indexed sourceChainId,
        bytes32 indexed poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    );
    event FreshnessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event SourceRegistered(uint256 indexed sourceChainId, address indexed sourceAdapter);
    event SourceRemoved(uint256 indexed sourceChainId, address indexed sourceAdapter);
    event ChainTimeBufferUpdated(uint256 indexed chainId, uint256 oldBuffer, uint256 newBuffer);
    
    // Errors
    error InvalidCrossL2InboxAddress();
    error InvalidSourceAddress();
    error SourceNotRegistered(uint256 chainId, address source);
    error MessageValidationFailed();
    error EventAlreadyProcessed(bytes32 eventId);
    error SourceMismatch(address expected, address received);
    error ChainIdMismatch(uint256 expected, uint256 received);
    error SourceBlockFromFuture(uint256 sourceTimestamp, uint256 currentTimestamp);
    error PriceDataTooOld(uint32 dataTimestamp, uint256 threshold, uint256 currentTimestamp);
    
    /**
     * @notice Constructor
     * @param _crossL2Inbox Address of the CrossL2Inbox predeploy
     */
    constructor(address _crossL2Inbox) Ownable(msg.sender) {
        if (_crossL2Inbox == address(0)) revert InvalidCrossL2InboxAddress();
        crossL2Inbox = ICrossL2Inbox(_crossL2Inbox == address(0) ? CROSS_L2_INBOX : _crossL2Inbox);
    }
    
    /**
     * @notice Registers a valid source oracle adapter
     * @param sourceChainId The chain ID of the source
     * @param sourceAdapter The adapter address on the source chain
     */
    function registerSource(uint256 sourceChainId, address sourceAdapter) external onlyOwner {
        if (sourceAdapter == address(0)) revert InvalidSourceAddress();
        validSources[sourceChainId][sourceAdapter] = true;
        emit SourceRegistered(sourceChainId, sourceAdapter);
    }
    
    /**
     * @notice Removes a source oracle adapter
     * @param sourceChainId The chain ID of the source
     * @param sourceAdapter The adapter address on the source chain
     */
    function removeSource(uint256 sourceChainId, address sourceAdapter) external onlyOwner {
        validSources[sourceChainId][sourceAdapter] = false;
        emit SourceRemoved(sourceChainId, sourceAdapter);
    }
    
    /**
     * @notice Sets the freshness threshold for timestamp validation
     * @param newThreshold The new threshold in seconds
     */
    function setFreshnessThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = freshnessThreshold;
        freshnessThreshold = newThreshold;
        emit FreshnessThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /**
     * @notice Sets the time buffer for a specific chain
     * @param chainId The chain ID to set the buffer for
     * @param buffer The time buffer in seconds
     */
    function setChainTimeBuffer(uint256 chainId, uint256 buffer) external onlyOwner {
        uint256 oldBuffer = chainTimeBuffers[chainId];
        chainTimeBuffers[chainId] = buffer;
        emit ChainTimeBufferUpdated(chainId, oldBuffer, buffer);
    }
    
    /**
     * @notice Pauses the resolver (circuit breaker)
     * @dev When paused, price updates are rejected
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpauses the resolver
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Creates a unique event ID for replay protection
     * @param _id The cross-chain event identifier
     * @return The unique event ID
     */
    function _createEventId(ICrossL2Inbox.Identifier calldata _id) internal pure returns (bytes32) {
        return keccak256(abi.encode(_id.chainId, _id.origin, _id.logIndex, _id.blockNumber));
    }
    
    /**
     * @notice Updates price data from a remote chain
     * @param _id The identifier for the cross-chain event
     * @param _data The event data
     * @dev Validates the cross-chain event using Optimism's CrossL2Inbox
     */
    function updateFromRemote(ICrossL2Inbox.Identifier calldata _id, bytes calldata _data) external whenNotPaused nonReentrant {
        // Verify the source is valid
        if (!validSources[_id.chainId][_id.origin]) revert SourceNotRegistered(_id.chainId, _id.origin);
        
        // Create unique event ID for replay protection
        bytes32 eventId = _createEventId(_id);
        
        // Check if event has already been processed
        if (processedEvents[eventId]) revert EventAlreadyProcessed(eventId);
        
        // Mark event as processed to prevent replay attacks
        processedEvents[eventId] = true;
        
        // Validate the message using CrossL2Inbox
        if (!crossL2Inbox.validateMessage(_id, keccak256(_data))) revert MessageValidationFailed();
        
        // Extract event signature and topics
        bytes32 eventSig;
        assembly {
            eventSig := calldataload(add(_data.offset, 32))
        }
        
        // Decode the event data internally instead of using an external call
        (
            address source,
            uint256 sourceChainId,
            bytes32 poolId,
            int24 tick,
            uint160 sqrtPriceX96,
            uint32 timestamp
        ) = _decodeEventData(_data);
        
        // Additional validations
        if (source != _id.origin) revert SourceMismatch(_id.origin, source);
        if (sourceChainId != _id.chainId) revert ChainIdMismatch(_id.chainId, sourceChainId);
        
        // Validate source block timestamp
        if (_id.timestamp > block.timestamp) revert SourceBlockFromFuture(_id.timestamp, block.timestamp);
        
        // Determine effective freshness threshold with chain-specific buffer
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[_id.chainId];
        
        // Timestamp validation (freshness check)
        if (block.timestamp > uint256(timestamp) + effectiveThreshold) {
            revert PriceDataTooOld(timestamp, effectiveThreshold, block.timestamp);
        }
        
        // Check if we already have fresher data
        if (prices[_id.chainId][poolId].isValid && prices[_id.chainId][poolId].timestamp >= timestamp) {
            return; // Silently ignore older updates
        }
        
        // Store the price data
        prices[_id.chainId][poolId] = PriceData(tick, sqrtPriceX96, timestamp, true);
        
        // Emit event for off-chain tracking
        emit PriceUpdated(sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
    }
    
    /**
     * @notice Internal helper function for decoding event data
     * @param _data The event data to decode
     * @return source The source address that sent the event
     * @return sourceChainId The chain ID where the event originated
     * @return poolId The unique identifier for the pool
     * @return tick The tick value from the price update
     * @return sqrtPriceX96 The square root price value in X96 format
     * @return timestamp The timestamp when the price was observed
     */
    function _decodeEventData(bytes calldata _data) internal pure returns (
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) {
        // Skip the initial 32 bytes (event signature) plus 32 bytes for each indexed parameter (3 in this case)
        (source, sourceChainId, poolId, tick, sqrtPriceX96, timestamp) = 
            abi.decode(_data[128:], (address, uint256, bytes32, int24, uint160, uint32));
        return (source, sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
    }
    
    /**
     * @notice Helper function for decoding event data - deprecated, use internal function instead
     * @dev This function is kept for backward compatibility but shouldn't be used in production
     * @param _data The event data to decode
     * @return source The source address that sent the event
     * @return sourceChainId The chain ID where the event originated
     * @return poolId The unique identifier for the pool
     * @return tick The tick value from the price update
     * @return sqrtPriceX96 The square root price value in X96 format
     * @return timestamp The timestamp when the price was observed
     */
    function decodeEventData(bytes calldata _data) external pure returns (
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) {
        return _decodeEventData(_data);
    }
    
    /**
     * @notice Gets the latest price data for a pool
     * @param chainId The chain ID where the pool exists
     * @param poolId The pool identifier
     * @return tick The tick value
     * @return sqrtPriceX96 The square root price
     * @return timestamp The observation timestamp
     * @return isValid Whether the data is valid
     * @return isFresh Whether the data meets the freshness requirement
     */
    function getPrice(uint256 chainId, bytes32 poolId) external view returns (
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp,
        bool isValid,
        bool isFresh
    ) {
        PriceData memory data = prices[chainId][poolId];
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[chainId];
        bool freshCheck = data.isValid && 
                          (block.timestamp <= uint256(data.timestamp) + effectiveThreshold);
        
        return (data.tick, data.sqrtPriceX96, data.timestamp, data.isValid, freshCheck);
    }
}