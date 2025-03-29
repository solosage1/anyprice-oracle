// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/CrossChainPriceResolver.sol";
import "../src/MockL2Inbox.sol";

contract CrossChainPriceResolverTest is Test {
    CrossChainPriceResolver public resolver;
    MockL2Inbox public mockInbox;
    
    address public constant SOURCE_ADAPTER = address(0x1);
    uint256 public constant SOURCE_CHAIN_ID = 10;
    bytes32 public constant POOL_ID = bytes32(uint256(1));
    
    function setUp() public {
        mockInbox = new MockL2Inbox();
        resolver = new CrossChainPriceResolver(address(mockInbox));
    }
    
    function testRegisterSource() public {
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        assertTrue(resolver.validSources(SOURCE_CHAIN_ID, SOURCE_ADAPTER), "Source should be registered");
    }
    
    function testNonOwnerCannotRegisterSource() public {
        vm.prank(address(0x2));
        vm.expectRevert();
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
    }
    
    function testRemoveSource() public {
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        resolver.removeSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        assertFalse(resolver.validSources(SOURCE_CHAIN_ID, SOURCE_ADAPTER), "Source should be removed");
    }
    
    function testSetFreshnessThreshold() public {
        uint256 newThreshold = 3600 * 2; // 2 hours
        resolver.setFreshnessThreshold(newThreshold);
        assertEq(resolver.freshnessThreshold(), newThreshold, "Freshness threshold should be updated");
    }
    
    function testSetChainTimeBuffer() public {
        uint256 buffer = 300; // 5 minutes
        resolver.setChainTimeBuffer(SOURCE_CHAIN_ID, buffer);
        assertEq(resolver.chainTimeBuffers(SOURCE_CHAIN_ID), buffer, "Chain time buffer should be updated");
    }
    
    function testPauseAndUnpause() public {
        resolver.pause();
        assertTrue(resolver.paused(), "Resolver should be paused");
        
        resolver.unpause();
        assertFalse(resolver.paused(), "Resolver should be unpaused");
    }
    
    function testUpdateFromRemote() public {
        // Register the source
        resolver.registerSource(SOURCE_CHAIN_ID, SOURCE_ADAPTER);
        
        // Create event data
        int24 tick = 1000;
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        uint32 timestamp = uint32(block.timestamp);
        
        bytes memory eventData = createEventData(
            SOURCE_ADAPTER,
            SOURCE_CHAIN_ID,
            POOL_ID,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Create identifier
        ICrossL2Inbox.Identifier memory id = ICrossL2Inbox.Identifier({
            chainId: SOURCE_CHAIN_ID,
            origin: SOURCE_ADAPTER,
            logIndex: 0,
            blockNumber: block.number,
            timestamp: block.timestamp
        });
        
        // Register message in mock inbox
        mockInbox.registerMessage(id, keccak256(eventData));
        
        // Update from remote
        resolver.updateFromRemote(id, eventData);
        
        // Verify the price was updated
        (int24 storedTick, uint160 storedSqrt, uint32 storedTimestamp, bool isValid, bool isFresh) = 
            resolver.getPrice(SOURCE_CHAIN_ID, POOL_ID);
            
        assertEq(storedTick, tick, "Tick should match");
        assertEq(storedSqrt, sqrtPriceX96, "SqrtPrice should match");
        assertEq(storedTimestamp, timestamp, "Timestamp should match");
        assertTrue(isValid, "Price should be valid");
        assertTrue(isFresh, "Price should be fresh");
    }
    
    function testRejectNonValidatedSource() public {
        // Source is not registered
        
        // Create event data
        int24 tick = 1000;
        uint160 sqrtPriceX96 = 79228162514264337593543950336;
        uint32 timestamp = uint32(block.timestamp);
        
        bytes memory eventData = createEventData(
            SOURCE_ADAPTER,
            SOURCE_CHAIN_ID,
            POOL_ID,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Create identifier
        ICrossL2Inbox.Identifier memory id = ICrossL2Inbox.Identifier({
            chainId: SOURCE_CHAIN_ID,
            origin: SOURCE_ADAPTER,
            logIndex: 0,
            blockNumber: block.number,
            timestamp: block.timestamp
        });
        
        // Register message in mock inbox
        mockInbox.registerMessage(id, keccak256(eventData));
        
        // Expect revert due to unregistered source
        vm.expectRevert();
        resolver.updateFromRemote(id, eventData);
    }
    
    // Helper to create event data in the format expected by the resolver
    function createEventData(
        address source,
        uint256 sourceChainId,
        bytes32 poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        // Create event signature (topic0)
        bytes32 eventSig = keccak256("OraclePriceUpdate(address,uint256,bytes32,int24,uint160,uint32)");
        
        // Create the indexed parameters (topics 1-3)
        bytes32 topic1 = bytes32(uint256(uint160(source))); // address padded to bytes32
        bytes32 topic2 = bytes32(sourceChainId);
        bytes32 topic3 = poolId;
        
        // Create the data portion (all parameters for decoding)
        bytes memory data = abi.encode(
            source,
            sourceChainId,
            poolId,
            tick,
            sqrtPriceX96,
            timestamp
        );
        
        // Combine into full Ethereum log format
        return abi.encodePacked(
            eventSig,  // topic0 (event signature)
            topic1,    // topic1 (indexed parameter 1)
            topic2,    // topic2 (indexed parameter 2)
            topic3,    // topic3 (indexed parameter 3)
            data       // data containing ALL parameters
        );
    }
} 