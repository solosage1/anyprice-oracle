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
    
    // Enhanced replay protection with last processed block number tracking
    mapping(uint256 => mapping(address => uint256)) public lastProcessedBlockNumber;
    
    // Track abnormal timestamps
    mapping(uint256 => mapping(bytes32 => bool)) public hasAbnormalTimestamp;
    
    // Finality constants
    uint256 public constant FINALITY_BLOCKS = 50; // Number of blocks for finality
    
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
    event AbnormalTimestamp(uint256 chainId, bytes32 poolId, uint32 dataTimestamp, uint256 blockTimestamp);
    event DebugTimestampCheck(uint256 idTimestamp, uint256 blockTimestamp, uint32 dataTimestamp, uint256 effectiveThreshold);
    
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
    error EventFromOlderBlock(uint256 eventBlockNumber, uint256 lastProcessedBlockNumber);
    error EventNotYetFinal(uint256 eventBlockNumber, uint256 currentBlockNumber, uint256 finalityBlocks);
    error FutureTimestamp();
    
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
     * @dev EVM log structure:
     * - First 32 bytes: Event signature (keccak256 of event signature string)
     * - Next 32*N bytes: Indexed parameters (topics), each padded to 32 bytes
     * - Remaining bytes: ABI-encoded non-indexed parameters
     */

    /**
     * @notice Extracts an address from a raw EVM topic
     * @param topicData Raw topic bytes (32 bytes)
     * @return The extracted address (20 bytes)
     */
    function _extractAddressFromTopic(bytes calldata topicData) internal pure returns (address) {
        // An address is 20 bytes, but topics are 32 bytes, so we extract the last 20 bytes
        // by first converting to uint256, then to uint160, then to address
        return address(uint160(uint256(bytes32(topicData))));
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
        // Extract indexed params from topics (each topic is 32 bytes)
        // First topic [0:32] is the event signature
        source = _extractAddressFromTopic(_data[32:64]); // Second topic: indexed address
        sourceChainId = uint256(bytes32(_data[64:96])); // Third topic: indexed uint256
        poolId = bytes32(_data[96:128]);                // Fourth topic: indexed bytes32
        
        // Decode non-indexed params from data section
        // Data section starts after all topics (4 topics * 32 bytes = 128 bytes)
        (tick, sqrtPriceX96, timestamp) = 
            abi.decode(_data[128:], (int24, uint160, uint32));
        
        return (source, sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
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
        
        // Add stronger replay protection with block number tracking
        if (_id.blockNumber <= lastProcessedBlockNumber[_id.chainId][_id.origin]) {
            revert EventFromOlderBlock(_id.blockNumber, lastProcessedBlockNumber[_id.chainId][_id.origin]);
        }
        
        // Only process events that are at least FINALITY_BLOCKS old (prevent reorg attacks)
        // Skip this check for same-chain events or if the finality check would overflow
        if (_id.chainId != block.chainid && block.number >= FINALITY_BLOCKS) {
            uint256 finalityThreshold = block.number - FINALITY_BLOCKS;
            if (_id.blockNumber > finalityThreshold) {
                revert EventNotYetFinal(_id.blockNumber, block.number, FINALITY_BLOCKS);
            }
        }
        
        // Update last processed block number
        lastProcessedBlockNumber[_id.chainId][_id.origin] = _id.blockNumber;
        
        // Check if event has already been processed
        if (processedEvents[eventId]) revert EventAlreadyProcessed(eventId);
        
        // Mark event as processed to prevent replay attacks
        processedEvents[eventId] = true;
        
        // Validate the message using CrossL2Inbox
        if (!crossL2Inbox.validateMessage(_id, keccak256(_data))) revert MessageValidationFailed();
        
        // Decode the event data using our improved helper function
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
        
        // Validate source block timestamp - use safer comparison
        bool isSourceFromFuture = _id.timestamp > block.timestamp;
        if (isSourceFromFuture) revert SourceBlockFromFuture(_id.timestamp, block.timestamp);
        
        // Determine effective freshness threshold with chain-specific buffer
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[_id.chainId];
        
        // Emit debug info
        emit DebugTimestampCheck(_id.timestamp, block.timestamp, timestamp, effectiveThreshold);
        
        // Timestamp validation (freshness check) - avoid underflow with safer comparison
        bool isDataOld = timestamp < block.timestamp && 
                        (block.timestamp - timestamp) > effectiveThreshold;
        if (isDataOld) {
            revert PriceDataTooOld(timestamp, effectiveThreshold, block.timestamp);
        }
        
        // Check for abnormal timestamp (future timestamp)
        bool isFutureTimestamp = timestamp > block.timestamp;
        if (isFutureTimestamp) {
            // Reject future timestamps outright to maintain data integrity
            revert FutureTimestamp();
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
     * @notice Helper function for decoding event data - for external use and testing
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
     * @notice Gets the price data for a specific pool from a source chain
     * @param chainId The source chain ID
     * @param poolId The pool identifier
     * @return tick The current tick
     * @return sqrtPriceX96 The square root price
     * @return timestamp The timestamp of the observation
     * @return isValid Whether the data is valid
     * @return isFresh Whether the data is fresh
     */
    function getPrice(uint256 chainId, bytes32 poolId) external view returns (
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp,
        bool isValid,
        bool isFresh
    ) {
        PriceData memory data = prices[chainId][poolId];
        
        // If data is invalid, return early with default values
        if (!data.isValid) {
            return (0, 0, 0, false, false);
        }
        
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[chainId];
        
        // Three-stage freshness check with timestamp safety
        bool freshCheck;
        if (data.timestamp == 0) {
            // Uninitialized timestamp
            freshCheck = false;
        } else if (data.timestamp >= block.timestamp || hasAbnormalTimestamp[chainId][poolId]) {
            // Current time is before or equal to data timestamp
            // OR this pool has been detected to have abnormal timestamps
            // Consider as fresh to prevent DOS
            freshCheck = true;
        } else {
            // Normal case: timestamp is in the past
            // Avoid underflow by ensuring data.timestamp is less than block.timestamp
            freshCheck = (block.timestamp - data.timestamp) <= effectiveThreshold;
        }
        
        return (data.tick, data.sqrtPriceX96, data.timestamp, true, freshCheck);
    }
    
    /**
     * @notice Checks if a pool has abnormal timestamps
     * @param chainId The source chain ID
     * @param poolId The pool identifier
     * @return Whether the pool has abnormal timestamps
     */
    function checkAbnormalTimestamp(uint256 chainId, bytes32 poolId) external view returns (bool) {
        return hasAbnormalTimestamp[chainId][poolId];
    }
}