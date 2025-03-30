// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/ICrossL2Inbox.sol";

contract MockCrossL2Inbox is ICrossL2Inbox {
    bool private _validationResult = true;

    function setValidation(bool result) external {
        _validationResult = result;
    }

    function validateMessage(
        Identifier calldata _id,
        bytes32 _messageHash
    ) external view returns (bool) {
        return _validationResult;
    }
} 