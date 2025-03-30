// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
// import {StdCheats} from "forge-std/StdCheats.sol"; // Remove this import
import {Predeploys} from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // Import Ownable for the error
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol"; // Import Pausable for the error

import {PriceReceiverResolver} from "../src/PriceReceiverResolver.sol";
import {MockL2ToL2CrossDomainMessenger} from "./mocks/MockL2ToL2CrossDomainMessenger.sol"; // Using the mock from the previous test

contract PriceReceiverResolverTest is Test { // Remove StdCheats from here
    PriceReceiverResolver resolver;
    MockL2ToL2CrossDomainMessenger mockMessenger;

    address owner = address(0x1);
    address nonOwner = address(0x2);
    address sourceAdapter = address(0xcafe);
    uint256 sourceChainId = 901; // Example Chain A ID
    address messengerAddress = Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER;

    bytes32 poolId = keccak256("pool1");
    int24 tick = 1000;
    uint160 sqrtPriceX96 = 79228162514264337593543950336; // TickMath.getSqrtPriceAtTick(1000);
    uint32 timestamp;

    function setUp() public {
        // --- Deploy Mock Messenger ---
        // Replace internal messenger with our mock at the predeploy address
        vm.etch(messengerAddress, address(new MockL2ToL2CrossDomainMessenger()).code);
        mockMessenger = MockL2ToL2CrossDomainMessenger(payable(messengerAddress));

        // --- Deploy Resolver ---
        vm.prank(owner);
        resolver = new PriceReceiverResolver();

        // --- Initial State ---
        vm.prank(owner);
        resolver.registerSource(sourceChainId, sourceAdapter); 

        timestamp = uint32(block.timestamp);
    }

    // --- Test Constructor ---

    function test_constructor_setsOwner() public {
        assertEq(resolver.owner(), owner);
        assertEq(address(resolver.messenger()), messengerAddress);
    }

    // --- Test Source Management ---

    function test_registerSource() public {
        address newSourceAdapter = address(0xdead);
        uint256 newSourceChainId = 903;
        assertFalse(resolver.validSources(newSourceChainId, newSourceAdapter));

        vm.expectEmit(true, true, false, true);
        emit PriceReceiverResolver.SourceRegistered(newSourceChainId, newSourceAdapter);
        vm.prank(owner);
        resolver.registerSource(newSourceChainId, newSourceAdapter);

        assertTrue(resolver.validSources(newSourceChainId, newSourceAdapter));
    }

    function test_registerSource_reverts_notOwner() public {
        // Expect the custom error OwnableUnauthorizedAccount
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        vm.prank(nonOwner);
        resolver.registerSource(903, address(0xdead));
    }

    function test_registerSource_reverts_zeroAddress() public {
        vm.expectRevert(PriceReceiverResolver.InvalidSourceAddress.selector);
        vm.prank(owner);
        resolver.registerSource(903, address(0));
    }

    function test_removeSource() public {
        assertTrue(resolver.validSources(sourceChainId, sourceAdapter));

        vm.expectEmit(true, true, false, true);
        emit PriceReceiverResolver.SourceRemoved(sourceChainId, sourceAdapter);
        vm.prank(owner);
        resolver.removeSource(sourceChainId, sourceAdapter);

        assertFalse(resolver.validSources(sourceChainId, sourceAdapter));
    }

    function test_removeSource_reverts_notOwner() public {
        // Expect the custom error OwnableUnauthorizedAccount
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        vm.prank(nonOwner);
        resolver.removeSource(sourceChainId, sourceAdapter);
    }

    // --- Test Configuration ---
    
    function test_setFreshnessThreshold() public {
        uint256 oldThreshold = resolver.freshnessThreshold();
        uint256 newThreshold = oldThreshold + 100;

        vm.expectEmit(false, false, false, true); // No indexed params
        emit PriceReceiverResolver.FreshnessThresholdUpdated(oldThreshold, newThreshold);
        vm.prank(owner);
        resolver.setFreshnessThreshold(newThreshold);

        assertEq(resolver.freshnessThreshold(), newThreshold);
    }

     function test_setChainTimeBuffer() public {
        uint256 oldBuffer = resolver.chainTimeBuffers(sourceChainId);
        uint256 newBuffer = oldBuffer + 50;

        vm.expectEmit(true, false, false, true);
        emit PriceReceiverResolver.ChainTimeBufferUpdated(sourceChainId, oldBuffer, newBuffer);
        vm.prank(owner);
        resolver.setChainTimeBuffer(sourceChainId, newBuffer);

        assertEq(resolver.chainTimeBuffers(sourceChainId), newBuffer);
    }

    // --- Test Pausable ---

    function test_pause_unpause() public {
        assertFalse(resolver.paused());
        vm.prank(owner);
        resolver.pause();
        assertTrue(resolver.paused());
        vm.prank(owner);
        resolver.unpause();
        assertFalse(resolver.paused());
    }

    // --- Test receivePriceUpdate ---

    function test_receivePriceUpdate_success() public {
        // Arrange: Mock the messenger context
        vm.mockCall(
            address(mockMessenger),
            abi.encodeWithSelector(MockL2ToL2CrossDomainMessenger.crossDomainMessageContext.selector),
            abi.encode(sourceAdapter, sourceChainId) // Return values: sender, chainId
        );

        // Arrange: Expect events
        vm.expectEmit(true, true, false, true);
        emit PriceReceiverResolver.PriceUpdated(sourceChainId, poolId, tick, sqrtPriceX96, timestamp);
        vm.expectEmit(true, true, true, true);
        emit PriceReceiverResolver.CrossDomainPriceUpdate(sourceAdapter, sourceChainId, poolId, tick, sqrtPriceX96, timestamp);

        // Act: Call from the messenger address
        vm.prank(messengerAddress);
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, timestamp);

        // Assert: State updated
        PriceReceiverResolver.PriceData memory data = resolver.getPrice(sourceChainId, poolId);
        assertTrue(data.isValid);
        assertEq(data.tick, tick);
        assertEq(data.sqrtPriceX96, sqrtPriceX96);
        assertEq(data.timestamp, timestamp);
    }

    function test_receivePriceUpdate_reverts_notFromMessenger() public {
        // Act & Assert: Call from an address *other* than the messenger
        vm.expectRevert(PriceReceiverResolver.NotFromMessenger.selector);
        vm.prank(nonOwner); // Any address except messengerAddress
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, timestamp);
    }

    function test_receivePriceUpdate_reverts_sourceNotRegistered() public {
        // Arrange: Mock the messenger context with an *unregistered* source
        address unregisteredSource = address(0xbad);
        uint256 unregisteredChainId = 999;
        vm.mockCall(
            address(mockMessenger),
            abi.encodeWithSelector(MockL2ToL2CrossDomainMessenger.crossDomainMessageContext.selector),
            abi.encode(unregisteredSource, unregisteredChainId)
        );

        // Act & Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceReceiverResolver.SourceNotRegistered.selector,
                unregisteredChainId,
                unregisteredSource
            )
        );
        vm.prank(messengerAddress);
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, timestamp);
    }

    function test_receivePriceUpdate_reverts_futureTimestamp() public {
         // Arrange: Mock the messenger context
        vm.mockCall(
            address(mockMessenger),
            abi.encodeWithSelector(MockL2ToL2CrossDomainMessenger.crossDomainMessageContext.selector),
            abi.encode(sourceAdapter, sourceChainId) 
        );
        
        // Arrange: Timestamp slightly in the future
        uint32 futureTimestamp = uint32(block.timestamp + 1);

        // Act & Assert
        vm.expectRevert(PriceReceiverResolver.FutureTimestamp.selector);
        vm.prank(messengerAddress);
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, futureTimestamp);
    }

    function test_receivePriceUpdate_reverts_priceTooOld() public {
        // Arrange: Mock the messenger context
        vm.mockCall(
            address(mockMessenger),
            abi.encodeWithSelector(MockL2ToL2CrossDomainMessenger.crossDomainMessageContext.selector),
            abi.encode(sourceAdapter, sourceChainId) 
        );

        // Arrange: Warp time forward past freshness threshold
        uint256 threshold = resolver.freshnessThreshold() + resolver.chainTimeBuffers(sourceChainId);
        vm.warp(block.timestamp + threshold + 1);
        uint32 oldTimestamp = timestamp; // Timestamp from setUp

        // Act & Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceReceiverResolver.PriceDataTooOld.selector,
                oldTimestamp,
                threshold,
                block.timestamp
            )
        );
        vm.prank(messengerAddress);
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, oldTimestamp);
    }

    function test_receivePriceUpdate_reverts_whenPaused() public {
        // Arrange: Pause the contract
        vm.prank(owner);
        resolver.pause();

         // Arrange: Mock the messenger context
        vm.mockCall(
            address(mockMessenger),
            abi.encodeWithSelector(MockL2ToL2CrossDomainMessenger.crossDomainMessageContext.selector),
            abi.encode(sourceAdapter, sourceChainId) 
        );

        // Act & Assert: Expect the actual error observed
        // If EnforcedPause is standard Pausable error, use Pausable.EnforcedPause.selector
        // If it's custom, this might need adjustment
        vm.expectRevert(Pausable.EnforcedPause.selector);
        // vm.expectRevert(); // Fallback: Expect generic revert if selector is wrong
        vm.prank(messengerAddress);
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, timestamp);
    }

    // TODO: Add test for reentrancy guard if applicable (depends on interactions)

    // --- Test getPrice ---
    
    function test_getPrice_returnsData() public {
        // Arrange: Set some data first via receivePriceUpdate
        vm.mockCall(
            address(mockMessenger),
            abi.encodeWithSelector(MockL2ToL2CrossDomainMessenger.crossDomainMessageContext.selector),
            abi.encode(sourceAdapter, sourceChainId) 
        );
        vm.prank(messengerAddress);
        resolver.receivePriceUpdate(poolId, tick, sqrtPriceX96, timestamp);

        // Act
        PriceReceiverResolver.PriceData memory data = resolver.getPrice(sourceChainId, poolId);

        // Assert
        assertTrue(data.isValid);
        assertEq(data.tick, tick);
        assertEq(data.sqrtPriceX96, sqrtPriceX96);
        assertEq(data.timestamp, timestamp);
    }

    function test_getPrice_returnsDefault_when_noData() public {
         // Act
        PriceReceiverResolver.PriceData memory data = resolver.getPrice(999, keccak256("otherPool"));

        // Assert
        assertFalse(data.isValid);
        assertEq(data.tick, 0);
        assertEq(data.sqrtPriceX96, 0);
        assertEq(data.timestamp, 0);
    }
} 