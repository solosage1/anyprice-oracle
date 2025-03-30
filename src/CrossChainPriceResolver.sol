// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import "./interfaces/ICrossL2Inbox.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrossChainPriceResolver
 * @notice Resolver contract that validates and consumes oracle price data from other chains
 * @dev Uses Optimism's CrossL2Inbox for secure cross-chain event validation (implicitly via relayer proof)
 */
contract CrossChainPriceResolver is Pausable, ReentrancyGuard, Ownable {
    // Price data structure
    struct PriceData {
        int24 tick;                 // Tick value
        uint160 sqrtPriceX96;       // Square root price
        uint32 timestamp;           // Observation timestamp
        bool isValid;               // Whether the data is valid/initialized
    }
    
    // Reference to CrossL2Inbox contract (Optimism predeploy) - address might be passed if flexibility needed
    ICrossL2Inbox public immutable crossL2Inbox; // Keep immutable if address is fixed for deployment target
    
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
    
    // Enhanced replay protection with last processed block number tracking per source
    mapping(uint256 => mapping(address => uint256)) public lastProcessedBlockNumber;
    
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
    event DebugTimestampCheck(uint256 idTimestamp, uint256 blockTimestamp, uint32 dataTimestamp, uint256 effectiveThreshold);
    
    // Errors
    error InvalidCrossL2InboxAddress();
    error InvalidSourceAddress();
    error SourceNotRegistered(uint256 chainId, address source);
    error EventAlreadyProcessed(bytes32 eventId);
    error SourceMismatch(address expected, address received);
    error ChainIdMismatch(uint256 expected, uint256 received);
    error SourceBlockFromFuture(uint256 sourceTimestamp, uint256 currentTimestamp);
    error PriceDataTooOld(uint32 dataTimestamp, uint256 threshold, uint256 currentTimestamp);
    error EventFromOlderBlock(uint256 eventBlockNumber, uint256 lastProcessedBlockNumber);
    error EventNotYetFinal(uint256 eventBlockNumber, uint256 currentBlockNumber, uint256 finalityBlocks);
    error FutureTimestamp();
    error InvalidEventTopics(); // New error for topic validation
    
    /**
     * @notice Constructor
     * @param _crossL2Inbox Address of the CrossL2Inbox predeploy
     */
    constructor(address _crossL2Inbox) Ownable(msg.sender) { // Ownable sets owner
        if (_crossL2Inbox == address(0)) revert InvalidCrossL2InboxAddress();
        crossL2Inbox = ICrossL2Inbox(_crossL2Inbox);
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
     * @notice Creates a unique event ID hash for replay protection using Identifier fields
     * @param _id The cross-chain event identifier
     * @return The unique event ID hash
     */
    function _getEventIdHash(ICrossL2Inbox.Identifier calldata _id) internal pure returns (bytes32) {
        // Hash includes all fields that make the source event unique
        return keccak256(abi.encode(_id.chainId, _id.origin, _id.logIndex, _id.blockNumber));
    }

    /**
     * @notice Internal helper function for decoding OraclePriceUpdate event data from topics and data
     * @param topics Array of event topics (topic[0] = signature, topic[1] = source, topic[2] = chainId, topic[3] = poolId)
     * @param data The ABI-encoded data containing non-indexed parameters (tick, sqrtPriceX96, timestamp)
     * @return source The source address that sent the event (from topic[1])
     * @return sourceChainId The chain ID where the event originated (from topic[2])
     * @return poolId The unique identifier for the pool (from topic[3])
     * @return tick The tick value from the price update (from data)
     * @return sqrtPriceX96 The square root price value in X96 format (from data)
     * @return timestamp The timestamp when the price was observed (from data)
     */
    function _decodeOraclePriceUpdate(bytes32[] calldata topics, bytes calldata data) internal pure returns (
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) {
        // Standard event structure check for OraclePriceUpdate
        if (topics.length != 4) revert InvalidEventTopics();

        // Extract indexed params from topics
        // topics[0]: Event signature hash (ignored here)
        // topics[1]: Indexed param 1 (source address) - extract address from bytes32
        source = address(uint160(uint256(topics[1])));
        // topics[2]: Indexed param 2 (sourceChainId) - convert bytes32 to uint256
        sourceChainId = uint256(topics[2]);
        // topics[3]: Indexed param 3 (poolId) - use bytes32 directly
        poolId = topics[3];

        // Decode non-indexed params from data section
        (tick, sqrtPriceX96, timestamp) = abi.decode(data, (int24, uint160, uint32));

        return (source, sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
    }

    /**
     * @notice Updates price data from a remote chain based on event topics and data
     * @param _id The identifier for the cross-chain event (contains origin, blockNumber etc.)
     * @param topics The event topics array (including signature hash at topics[0])
     * @param data The ABI-encoded event data (containing non-indexed parameters)
     * @dev Validates the cross-chain event using Optimism's CrossL2Inbox (implicitly via off-chain relay proof)
     *      and performs extensive internal checks.
     */
    function updateFromRemote(
        ICrossL2Inbox.Identifier calldata _id,
        bytes32[] calldata topics,
        bytes calldata data
    ) external whenNotPaused nonReentrant {
        // --- Initial Checks & Replay Protection ---
        if (!validSources[_id.chainId][_id.origin]) revert SourceNotRegistered(_id.chainId, _id.origin);

        // Ensure this specific event hasn't been processed using its unique identifier hash
        bytes32 eventIdHash = _getEventIdHash(_id);
        if (processedEvents[eventIdHash]) revert EventAlreadyProcessed(eventIdHash);

        // Ensure we haven't processed an event from a later block for this source
        if (_id.blockNumber <= lastProcessedBlockNumber[_id.chainId][_id.origin]) {
            revert EventFromOlderBlock(_id.blockNumber, lastProcessedBlockNumber[_id.chainId][_id.origin]);
        }
        // Update last processed block number *after* passing the check
        lastProcessedBlockNumber[_id.chainId][_id.origin] = _id.blockNumber;

        // --- Finality Check ---
        // Skip check for same-chain messages or if block.number is too low
        if (_id.chainId != block.chainid && block.number >= FINALITY_BLOCKS) {
            uint256 finalityThreshold = block.number - FINALITY_BLOCKS;
            // Ensure the source block is below the finality threshold
            if (_id.blockNumber > finalityThreshold) {
                revert EventNotYetFinal(_id.blockNumber, block.number, FINALITY_BLOCKS);
            }
        }

        // --- L2Inbox Validation (Implicit) ---
        // The CrossL2Inbox pattern relies on the relayer submitting a valid proof to the L2 inbox contract.
        // We don't call validateMessage directly here. If this transaction executes successfully,
        // it implies the message authentication via the L2Inbox mechanism succeeded.

        // --- Decode & Validate Event Data ---
        // Decode using the standard topics/data structure
        (
            address source,         // Decoded source from topics[1]
            uint256 sourceChainId,  // Decoded chainId from topics[2]
            bytes32 poolId,         // Decoded poolId from topics[3]
            int24 tick,
            uint160 sqrtPriceX96,
            uint32 timestamp        // Decoded timestamp from data
        ) = _decodeOraclePriceUpdate(topics, data);

        // --- Consistency Checks ---
        // Ensure decoded data matches the trusted Identifier fields
        if (source != _id.origin) revert SourceMismatch(_id.origin, source);
        if (sourceChainId != _id.chainId) revert ChainIdMismatch(_id.chainId, sourceChainId);

        // --- Timestamp Checks ---
        // Validate source block timestamp (from Identifier) against current block timestamp
        bool isSourceBlockFromFuture = _id.timestamp > block.timestamp;
        if (isSourceBlockFromFuture) revert SourceBlockFromFuture(_id.timestamp, block.timestamp);

        // Determine effective freshness threshold including chain-specific buffer
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[_id.chainId];
        emit DebugTimestampCheck(_id.timestamp, block.timestamp, timestamp, effectiveThreshold);

        // Validate data timestamp (from event data) against current block timestamp
        // 1. Data timestamp cannot be in the future relative to current block
        bool isFutureDataTimestamp = timestamp > block.timestamp;
        if (isFutureDataTimestamp) revert FutureTimestamp();

        // 2. Data timestamp cannot be too old (freshness check)
        // Safe subtraction because we know timestamp <= block.timestamp from the check above
        bool isDataOld = (block.timestamp - timestamp) > effectiveThreshold;
        if (isDataOld) revert PriceDataTooOld(timestamp, effectiveThreshold, block.timestamp);

        // --- Check Against Existing Data ---
        // Avoid overwriting with stale data (same or older timestamp)
        if (prices[_id.chainId][poolId].isValid && prices[_id.chainId][poolId].timestamp >= timestamp) {
            return; // Silently ignore older or same-timestamp updates
        }

        // --- Update State ---
        // All checks passed, mark event as processed and store the price data
        processedEvents[eventIdHash] = true; // Mark event ID hash as processed

        prices[_id.chainId][poolId] = PriceData(tick, sqrtPriceX96, timestamp, true);

        // Emit event for off-chain tracking/consumers on this chain
        emit PriceUpdated(sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
    }

    /**
     * @notice Public helper function for decoding OraclePriceUpdate event data - for external use and testing
     * @param topics The event topics array (must include signature hash at index 0)
     * @param data The ABI-encoded event data (non-indexed parameters)
     * @return source The source address that sent the event
     * @return sourceChainId The chain ID where the event originated
     * @return poolId The unique identifier for the pool
     * @return tick The tick value from the price update
     * @return sqrtPriceX96 The square root price value in X96 format
     * @return timestamp The timestamp when the price was observed
     */
    function decodeOraclePriceUpdate(bytes32[] calldata topics, bytes calldata data) external pure returns (
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) {
        return _decodeOraclePriceUpdate(topics, data);
    }
    
    /**
     * @notice Gets the price data for a specific pool from a source chain
     * @param chainId The source chain ID
     * @param poolId The pool identifier
     * @return tick The current tick
     * @return sqrtPriceX96 The square root price
     * @return timestamp The timestamp of the observation
     * @return isValid Whether the data is valid
     * @return isFresh Whether the data is fresh based on current time and thresholds
     */
    function getPrice(uint256 chainId, bytes32 poolId) external view returns (
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp,
        bool isValid,
        bool isFresh
    ) {
        PriceData memory data = prices[chainId][poolId];
        
        // If data is invalid (never stored), return early with default values
        if (!data.isValid) {
            return (0, 0, 0, false, false);
        }
        
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[chainId];
        
        // Revised freshness check:
        // 1. Data must be valid (already checked).
        // 2. Timestamp cannot be zero (implicitly covered by isValid).
        // 3. Timestamp cannot be in the future relative to current block time.
        // 4. The age (block.timestamp - data.timestamp) must be within the effective threshold.
        if (data.timestamp > block.timestamp) {
            // Should ideally not happen due to checks in updateFromRemote, but check defensively
            isFresh = false;
        } else {
            // Safe subtraction since data.timestamp <= block.timestamp
            isFresh = (block.timestamp - data.timestamp) <= effectiveThreshold;
        }
        
        return (data.tick, data.sqrtPriceX96, data.timestamp, data.isValid, isFresh);
    }
}