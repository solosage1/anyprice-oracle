# Source Directory Organization

This directory contains the smart contracts for the UniChain Interoperability Oracle system. The code has been reorganized to follow a more consistent pattern and eliminate duplication.

## Directory Structure

- `interfaces/`: Contains standardized interface definitions
- `libraries/`: Contains shared utility libraries
- `errors/`: Contains error definitions

## Key Files

- `CrossChainPriceResolver.sol`: Resolver that validates and consumes cross-chain oracle data
- `TruncGeoOracleMulti.sol`: Core oracle implementation based on geometric mean
- `TruncOracleIntegration.sol`: Integration between the oracle and cross-chain system
- `UniChainOracleAdapter.sol`: Adapter that formats and publishes oracle data
- `MockL2Inbox.sol`: Mock implementation of Optimism's CrossL2Inbox for testing
- `CrossChainMessenger.sol`: Base contract with cross-chain messaging functionality
- `UniChainOracleRegistry.sol`: Registry for oracle adapters

## Removed Files

The following files have been removed to avoid duplication and inconsistencies:

- `UniInteropOracle.sol`: Removed in favor of the more robust CrossL2Inbox pattern
- `OracleCrossChainDemo.sol`: Demo code moved to `script/OracleCrossChainDemo.s.sol`

## Architecture Notes

This codebase standardizes on Optimism's CrossL2Inbox pattern for cross-chain message passing. This approach has several benefits:

1. Leverages Optimism's established cross-chain verification infrastructure
2. Provides a secure way to validate cross-chain events
3. Compatible with Optimism's existing bridge systems

For details on the overall architecture, see the `ARCHITECTURE.md` file in the root directory. 