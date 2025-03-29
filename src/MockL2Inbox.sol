// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICrossL2Inbox.sol";

/**
 * @title MockL2Inbox
 * @notice Mock implementation of Optimism's CrossL2Inbox for local testing
 * @dev Simulates the behavior of the CrossL2Inbox predeploy used in Optimism
 */
contract MockL2Inbox is Ownable, ICrossL2Inbox {
    // Maps message identifier and data hash to validity
    mapping(bytes32 => mapping(bytes32 => bool)) public validMessages;
    
    // Override validation for testing
    bool public validationOverride;
    bool public useValidationOverride;
    
    // Custom errors
    error InvalidIdentifier();
    error MessageNotRegistered(bytes32 idHash, bytes32 dataHash);
    error MessageFromFuture();
    error SameChainMessages();
    
    // Events
    event MessageRegistered(
        uint256 indexed chainId,
        address indexed origin,
        uint256 logIndex,
        uint256 blockNumber,
        uint256 timestamp,
        bytes32 dataHash
    );
    
    event MessageUnregistered(
        uint256 indexed chainId,
        address indexed origin,
        uint256 logIndex,
        bytes32 dataHash
    );
    
    event DebugValidation(uint256 idTimestamp, uint256 blockTimestamp, bool isFromFuture, bool isSameChain);
    
    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Validates a message from another chain
     * @param _id The message identifier
     * @param _dataHash Hash of the message data
     * @return Whether the message is valid
     */
    function validateMessage(Identifier calldata _id, bytes32 _dataHash) external view override returns (bool) {
        // If using validation override, return the override value
        if (useValidationOverride) {
            return validationOverride;
        }
        
        // Verify the identifier has valid components
        if (_id.chainId == 0 || _id.origin == address(0)) {
            revert InvalidIdentifier();
        }
        
        // Debug info
        bool isFromFuture = _id.timestamp > block.timestamp;
        
        // Add these checks to better match Optimism CrossL2Inbox behavior
        // Check in a safer way to avoid potential overflows
        if (isFromFuture) revert MessageFromFuture();
        
        bytes32 idHash = _getIdentifierHash(_id);
        if (!validMessages[idHash][_dataHash]) {
            revert MessageNotRegistered(idHash, _dataHash);
        }
        
        return true;
    }
    
    /**
     * @notice Sets a validation override for testing purposes
     * @param _isValid The validation result to return
     */
    function setValidation(bool _isValid) external {
        validationOverride = _isValid;
        useValidationOverride = true;
    }
    
    /**
     * @notice Clears the validation override
     */
    function clearValidationOverride() external {
        useValidationOverride = false;
    }
    
    /**
     * @notice Registers a message as valid (for testing purposes)
     * @param _id The message identifier
     * @param _dataHash Hash of the message data
     */
    function registerMessage(Identifier calldata _id, bytes32 _dataHash) external onlyOwner {
        // Verify the identifier has valid components
        if (_id.chainId == 0 || _id.origin == address(0)) {
            revert InvalidIdentifier();
        }
        
        bytes32 idHash = _getIdentifierHash(_id);
        validMessages[idHash][_dataHash] = true;
        
        emit MessageRegistered(
            _id.chainId, 
            _id.origin, 
            _id.logIndex, 
            _id.blockNumber,
            _id.timestamp,
            _dataHash
        );
    }
    
    /**
     * @notice Unregisters a message (for testing purposes)
     * @param _id The message identifier
     * @param _dataHash Hash of the message data
     */
    function unregisterMessage(Identifier calldata _id, bytes32 _dataHash) external onlyOwner {
        bytes32 idHash = _getIdentifierHash(_id);
        validMessages[idHash][_dataHash] = false;
        
        emit MessageUnregistered(
            _id.chainId, 
            _id.origin, 
            _id.logIndex, 
            _dataHash
        );
    }
    
    /**
     * @notice Gets a hash for an identifier
     * @param _id The identifier
     * @return The hash
     */
    function _getIdentifierHash(Identifier calldata _id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            _id.chainId, 
            _id.origin, 
            _id.logIndex,
            _id.blockNumber,
            _id.timestamp
        ));
    }
    
    /**
     * @notice Utility function to get the identifier hash (for testing)
     * @param _id The identifier
     * @return The identifier hash
     */
    function getIdentifierHash(Identifier calldata _id) external pure returns (bytes32) {
        return _getIdentifierHash(_id);
    }
}