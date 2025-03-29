// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CrossChainPriceResolver.sol";

/**
 * @title MockL2Inbox
 * @notice Mock implementation of Optimism's CrossL2Inbox for local testing
 * @dev Simulates the behavior of the CrossL2Inbox predeploy used in Optimism
 */
contract MockL2Inbox is Ownable, ICrossL2Inbox {
    // Maps message identifier and data hash to validity
    mapping(bytes32 => mapping(bytes32 => bool)) public validMessages;
    
    // Events
    event MessageRegistered(
        uint256 indexed chainId,
        address indexed origin,
        uint256 logIndex,
        bytes32 dataHash
    );
    
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
    function validateMessage(ICrossL2Inbox.Identifier calldata _id, bytes32 _dataHash) external view override returns (bool) {
        bytes32 idHash = _getIdentifierHash(_id);
        return validMessages[idHash][_dataHash];
    }
    
    /**
     * @notice Registers a message as valid (for testing purposes)
     * @param _id The message identifier
     * @param _dataHash Hash of the message data
     */
    function registerMessage(ICrossL2Inbox.Identifier calldata _id, bytes32 _dataHash) external onlyOwner {
        bytes32 idHash = _getIdentifierHash(_id);
        validMessages[idHash][_dataHash] = true;
        
        emit MessageRegistered(_id.chainId, _id.origin, _id.logIndex, _dataHash);
    }
    
    /**
     * @notice Unregisters a message (for testing purposes)
     * @param _id The message identifier
     * @param _dataHash Hash of the message data
     */
    function unregisterMessage(ICrossL2Inbox.Identifier calldata _id, bytes32 _dataHash) external onlyOwner {
        bytes32 idHash = _getIdentifierHash(_id);
        validMessages[idHash][_dataHash] = false;
    }
    
    /**
     * @notice Gets a hash for an identifier
     * @param _id The identifier
     * @return The hash
     */
    function _getIdentifierHash(ICrossL2Inbox.Identifier calldata _id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            _id.chainId, 
            _id.origin, 
            _id.logIndex,
            _id.blockNumber,
            _id.timestamp
        ));
    }
}