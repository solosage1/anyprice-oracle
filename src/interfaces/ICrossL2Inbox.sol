// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

/**
 * @title ICrossL2Inbox
 * @notice Standard interface for Optimism's CrossL2Inbox contract
 * @dev This interface is compatible with Optimism's cross-chain messaging system
 */
interface ICrossL2Inbox {
    /**
     * @notice Standardized Identifier struct for cross-chain event identification
     * @dev Follows Optimism's cross-chain event identification pattern
     */
    struct Identifier {
        uint256 chainId;     // Source chain ID
        address origin;      // Source contract address
        uint256 logIndex;    // Log index in the transaction
        uint256 blockNumber; // Block number
        uint256 timestamp;   // Block timestamp
    }
    
    /**
     * @notice Validates a message from another chain
     * @param _id The identifier for the cross-chain event
     * @param _dataHash Hash of the event data
     * @return Whether the message is valid
     */
    function validateMessage(Identifier calldata _id, bytes32 _dataHash) external view returns (bool);
} 