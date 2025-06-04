// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Mock for L2ToL2CrossDomainMessenger (based on IL2ToL2CrossDomainMessenger)
// Add other functions from the interface if needed by tests
contract MockL2ToL2CrossDomainMessenger {
    // Event mirroring the actual sendMessage call for testing with vm.expectCall
    event MockSendMessageCalled(uint256 targetChainId, address target, bytes message);

    // Variables to store context for vm.mockCall override
    address public mockSender;
    uint256 public mockChainId;

    // State variables to record last sendMessage call args
    uint256 public lastTargetChainId;
    address public lastTarget;
    bytes public lastMessage;
    uint256 public sendMessageCallCount;

    // Function to be mocked in tests using vm.expectCall
    function sendMessage(uint256 _targetChainId, address _target, bytes memory _message) public {
        emit MockSendMessageCalled(_targetChainId, _target, _message);
        // Record args
        lastTargetChainId = _targetChainId;
        lastTarget = _target;
        lastMessage = _message;
        sendMessageCallCount++;
        // No actual sending logic needed in mock
    }

    // Function to be mocked in PriceReceiverResolver tests using vm.mockCall
    // The actual return values will be determined by the vm.mockCall setup in the test
    function crossDomainMessageContext() external view returns (address sender, uint256 chainId) {
        // Return the stored mock values. These are set via vm.mockCall in the test.
        return (mockSender, mockChainId);
    }

    // Allow tests to configure the return values for crossDomainMessageContext if needed directly
    // Although vm.mockCall is generally preferred for this.
    function setMockContext(address _sender, uint256 _chainId) public {
        mockSender = _sender;
        mockChainId = _chainId;
    }

    // --- Other potentially required functions from IL2ToL2CrossDomainMessenger ---
    // Add implementations (likely just emitting events or returning defaults) 
    // if your contracts interact with these parts of the messenger.

    function messageNonce() external view returns (uint256) {
        // Return a default or mockable value if needed
        return 0; 
    }

    function successfulMessages(bytes32) external view returns (bool) {
        // Return default/mockable
        return false; 
    }

    function receivedMessages(bytes32) external view returns (bool) {
        // Return default/mockable
        return false;
    }

    // Add relayMessage if needed for advanced testing scenarios
    // function relayMessage(bytes32 _messageId, bytes calldata _payload) external payable {}
} 