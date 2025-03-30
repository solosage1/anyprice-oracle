//SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Predeploys} from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import {IL2ToL2CrossDomainMessenger} from "@eth-optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

/**
 * @title PriceReceiverResolver
 * @notice Resolver contract that validates and consumes oracle price data from other chains
 * @dev Uses L2ToL2CrossDomainMessenger for secure cross-chain message validation
 */
contract PriceReceiverResolver is Pausable, ReentrancyGuard, Ownable {
    // The L2-to-L2 messenger for cross-chain communication
    IL2ToL2CrossDomainMessenger public immutable messenger =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    // Price data structure
    struct PriceData {
        int24 tick;                // Tick value
        uint160 sqrtPriceX96;      // Square root price
        uint32 timestamp;          // Observation timestamp
        bool isValid;              // Whether the data is valid/initialized
    }
    
    // Price storage: chainId => poolId => PriceData
    mapping(uint256 => mapping(bytes32 => PriceData)) public prices;
    
    // Validated source adapters: chainId => adapter address => isValid
    mapping(uint256 => mapping(address => bool)) public validSources;
    
    // Timestamp threshold for freshness validation (default: 1 hour)
    uint256 public freshnessThreshold = 1 hours;
    
    // Chain-specific time buffers to account for differences in block times
    mapping(uint256 => uint256) public chainTimeBuffers;
    
    // Events
    event PriceUpdated(
        uint256 indexed sourceChainId,
        bytes32 indexed poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    );
    event CrossDomainPriceUpdate(
        address indexed sender,     // Original sender on the source chain
        uint256 indexed chainId,    // Source chain ID
        bytes32 indexed poolId,     // Pool identifier
        int24 tick,                 // Price tick
        uint160 sqrtPriceX96,      // Square root price
        uint32 timestamp           // Observation timestamp
    );
    event FreshnessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event SourceRegistered(uint256 indexed sourceChainId, address indexed sourceAdapter);
    event SourceRemoved(uint256 indexed sourceChainId, address indexed sourceAdapter);
    event ChainTimeBufferUpdated(uint256 indexed chainId, uint256 oldBuffer, uint256 newBuffer);
    
    // Errors
    error InvalidSourceAddress();
    error SourceNotRegistered(uint256 chainId, address source);
    error PriceDataTooOld(uint32 dataTimestamp, uint256 threshold, uint256 currentTimestamp);
    error FutureTimestamp();
    error NotFromMessenger();
    
    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}
    
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
     * @notice Receives and processes a price update from a source chain
     * @param poolId The pool identifier
     * @param tick The tick value
     * @param sqrtPriceX96 The square root price
     * @param timestamp The observation timestamp
     */
    function receivePriceUpdate(
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) external whenNotPaused nonReentrant {
        // Verify the call is from the L2ToL2CrossDomainMessenger
        if (msg.sender != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) {
            revert NotFromMessenger();
        }

        // Get the original sender and chain ID
        (address sourceSender, uint256 sourceChainId) = messenger.crossDomainMessageContext();

        // Validate the source
        if (!validSources[sourceChainId][sourceSender]) {
            revert SourceNotRegistered(sourceChainId, sourceSender);
        }

        // Timestamp validation
        if (timestamp > block.timestamp) {
            revert FutureTimestamp();
        }

        // Freshness check with chain-specific buffer
        uint256 effectiveThreshold = freshnessThreshold + chainTimeBuffers[sourceChainId];
        if (block.timestamp - timestamp > effectiveThreshold) {
            revert PriceDataTooOld(timestamp, effectiveThreshold, block.timestamp);
        }

        // Store the price data
        prices[sourceChainId][poolId] = PriceData({
            tick: tick,
            sqrtPriceX96: sqrtPriceX96,
            timestamp: timestamp,
            isValid: true
        });

        // Emit events
        emit PriceUpdated(sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
        emit CrossDomainPriceUpdate(
            sourceSender,
            sourceChainId,
            poolId,
            tick,
            sqrtPriceX96,
            timestamp
        );
    }

    /**
     * @notice Gets the latest price data for a pool from a specific chain
     * @param sourceChainId The chain ID to get the price from
     * @param poolId The pool identifier
     * @return The price data structure
     */
    function getPrice(uint256 sourceChainId, bytes32 poolId) external view returns (PriceData memory) {
        return prices[sourceChainId][poolId];
    }
} 