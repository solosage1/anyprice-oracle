// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./CrossChainMessenger.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Interface for CrossL2Inbox (simplified for this implementation)
interface ICrossL2Inbox {
    // Identifier struct matches Optimism's standard structure for cross-chain event identification
    struct Identifier {
        uint256 chainId;    // Source chain ID
        address origin;     // Source contract address
        uint256 logIndex;   // Log index in the transaction
        uint256 blockNumber; // Block number
        uint256 timestamp;   // Block timestamp
    }
    
    // Validates a message from another chain
    function validateMessage(Identifier calldata _id, bytes32 _dataHash) external view returns (bool);
}

/**
 * @title CrossChainPriceResolver
 * @notice Resolver contract that validates and consumes oracle price data from other chains
 * @dev Uses Optimism's CrossL2Inbox for secure cross-chain event validation
 */
contract CrossChainPriceResolver is CrossChainMessenger, Pausable {
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
    
    /**
     * @notice Constructor
     * @param _crossL2Inbox Address of the CrossL2Inbox predeploy
     */
    constructor(address _crossL2Inbox) Ownable(msg.sender) {
        require(_crossL2Inbox != address(0), "Invalid CrossL2Inbox address");
        crossL2Inbox = ICrossL2Inbox(_crossL2Inbox == address(0) ? CROSS_L2_INBOX : _crossL2Inbox);
    }
    
    /**
     * @notice Registers a valid source oracle adapter
     * @param sourceChainId The chain ID of the source
     * @param sourceAdapter The adapter address on the source chain
     */
    function registerSource(uint256 sourceChainId, address sourceAdapter) external onlyOwner {
        require(sourceAdapter != address(0), "Invalid source address");
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
     * @notice Updates price data from a remote chain
     * @param _id The identifier for the cross-chain event
     * @param _data The event data
     * @dev Validates the cross-chain event using Optimism's CrossL2Inbox
     */
    function updateFromRemote(ICrossL2Inbox.Identifier calldata _id, bytes calldata _data) external whenNotPaused {
        // Verify the source is valid
        require(validSources[_id.chainId][_id.origin], "Invalid source");
        
        // Validate the message using CrossL2Inbox
        require(crossL2Inbox.validateMessage(_id, keccak256(_data)), "Message validation failed");
        
        // Decode the event data
        // Note: Event data format follows the OraclePriceUpdate event structure
        // The first 32 bytes are event signature, so we start decoding from [32:]
        (address source, uint256 sourceChainId, bytes32 poolId, int24 tick, uint160 sqrtPriceX96, uint32 timestamp) =
            abi.decode(_data[32:], (address, uint256, bytes32, int24, uint160, uint32));
        
        // Additional validations
        require(source == _id.origin, "Source mismatch");
        require(sourceChainId == _id.chainId, "Chain ID mismatch");
        
        // IMPROVEMENT 1: Block timestamp validation
        require(_id.timestamp <= block.timestamp, "Source block from future");
        
        // IMPROVEMENT 2: Timestamp validation (freshness check)
        require(
            block.timestamp <= uint256(timestamp) + freshnessThreshold,
            "Price data too old"
        );
        
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
        bool freshCheck = data.isValid && 
                          (block.timestamp <= uint256(data.timestamp) + freshnessThreshold);
        
        return (data.tick, data.sqrtPriceX96, data.timestamp, data.isValid, freshCheck);
    }
} 