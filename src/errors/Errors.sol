// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Errors {
    error InvalidInput();
    error Unauthorized();
    error InvalidConfiguration();
    error PoolNotRegistered();
    error InvalidPoolKey();
    error ZeroAddress();
    error AccessNotAuthorized(address caller);
    error OracleOperationFailed(string operation, string reason);
    error OnlyDynamicFeePoolAllowed();
} 