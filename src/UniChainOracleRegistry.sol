// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UniChainOracleRegistry
 * @notice Registry for tracking oracle adapters across the Superchain
 * @dev Serves as a directory for discovering oracle adapters on different chains
 */
contract UniChainOracleRegistry is Ownable {
    // Oracle adapter information
    struct OracleAdapter {
        address adapterAddress;  // Address of the adapter contract
        uint256 chainId;         // Chain ID where the adapter is deployed
        string name;             // Human-readable name
        string description;      // Brief description
        bool isActive;           // Whether the adapter is active
    }
    
    // Tracks oracle adapters by chain ID and then by a unique identifier
    mapping(uint256 => mapping(bytes32 => OracleAdapter)) public oracleAdapters;
    
    // List of all adapter IDs by chain ID
    mapping(uint256 => bytes32[]) public adapterIdsByChain;
    
    // Events
    event OracleAdapterRegistered(
        bytes32 indexed adapterId,
        uint256 indexed chainId,
        address adapterAddress,
        string name
    );
    
    event OracleAdapterUpdated(
        bytes32 indexed adapterId,
        uint256 indexed chainId,
        address adapterAddress,
        bool isActive
    );
    
    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Registers a new oracle adapter
     * @param adapterId A unique identifier for the adapter
     * @param chainId Chain ID where the adapter is deployed
     * @param adapterAddress Address of the adapter contract
     * @param name Human-readable name
     * @param description Brief description
     */
    function registerAdapter(
        bytes32 adapterId,
        uint256 chainId,
        address adapterAddress,
        string calldata name,
        string calldata description
    ) external onlyOwner {
        require(oracleAdapters[chainId][adapterId].adapterAddress == address(0), "Adapter ID already exists");
        
        OracleAdapter memory adapter = OracleAdapter({
            adapterAddress: adapterAddress,
            chainId: chainId,
            name: name,
            description: description,
            isActive: true
        });
        
        oracleAdapters[chainId][adapterId] = adapter;
        adapterIdsByChain[chainId].push(adapterId);
        
        emit OracleAdapterRegistered(adapterId, chainId, adapterAddress, name);
    }
    
    /**
     * @notice Updates an existing oracle adapter's status
     * @param adapterId The adapter's unique identifier
     * @param chainId Chain ID where the adapter is deployed
     * @param isActive Whether the adapter is active
     */
    function updateAdapter(
        bytes32 adapterId,
        uint256 chainId,
        bool isActive
    ) external onlyOwner {
        require(oracleAdapters[chainId][adapterId].adapterAddress != address(0), "Adapter does not exist");
        
        OracleAdapter storage adapter = oracleAdapters[chainId][adapterId];
        
        adapter.isActive = isActive;
        
        emit OracleAdapterUpdated(adapterId, chainId, adapter.adapterAddress, isActive);
    }
    
    /**
     * @notice Gets information about an oracle adapter
     * @param chainId Chain ID where the adapter is deployed
     * @param adapterId The adapter's unique identifier
     * @return adapterAddress Address of the adapter contract
     * @return name Human-readable name
     * @return description Brief description
     * @return isActive Whether the adapter is active
     */
    function getAdapter(uint256 chainId, bytes32 adapterId) external view returns (
        address adapterAddress,
        string memory name,
        string memory description,
        bool isActive
    ) {
        OracleAdapter memory adapter = oracleAdapters[chainId][adapterId];
        return (adapter.adapterAddress, adapter.name, adapter.description, adapter.isActive);
    }
    
    /**
     * @notice Gets all adapter IDs for a specific chain
     * @param chainId Chain ID to query
     * @return List of adapter IDs
     */
    function getAdapterIds(uint256 chainId) external view returns (bytes32[] memory) {
        return adapterIdsByChain[chainId];
    }
    
    /**
     * @notice Generates a unique adapter ID from an address
     * @param adapterAddress The adapter address
     * @return The generated ID
     * @dev Utility function for creating consistent IDs
     */
    function generateAdapterId(address adapterAddress) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(adapterAddress));
    }
}