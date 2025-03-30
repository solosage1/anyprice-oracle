// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Predeploys} from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import {IL2ToL2CrossDomainMessenger} from "@eth-optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import {PriceReceiverResolver} from "../src/PriceReceiverResolver.sol";
import {PriceSenderAdapter} from "../src/PriceSenderAdapter.sol";
import {TruncGeoOracleMulti} from "../src/TruncGeoOracleMulti.sol"; // Assuming this needs to exist on Chain A

/**
 * @title DeployL2L2Script
 * @notice Deploys the PriceReceiverResolver to Chain B and PriceSenderAdapter to Chain A
 * @dev Requires environment variables:
 *      PRIVATE_KEY: Deployer private key
 *      RPC_URL_A: RPC URL for Chain A
 *      RPC_URL_B: RPC URL for Chain B
 *      CHAIN_ID_B: Chain ID for Chain B (passed to Sender on Chain A)
 *      TRUNC_ORACLE_MULTI_ADDRESS_A: Address of the deployed TruncGeoOracleMulti on Chain A
 */
contract DeployL2L2Script is Script {

    function run() external returns (address resolverAddr, address adapterAddr) {
        // --- Config --- 
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory rpcUrlA = vm.envString("RPC_URL_A");
        string memory rpcUrlB = vm.envString("RPC_URL_B");
        uint256 chainIdB = vm.envUint("CHAIN_ID_B");
        address truncOracleAddressA = vm.envAddress("TRUNC_ORACLE_MULTI_ADDRESS_A");

        // Use the actual L2ToL2CrossDomainMessenger predeploy address
        IL2ToL2CrossDomainMessenger messenger = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // --- Deploy Resolver to Chain B --- 
        console.log("Deploying PriceReceiverResolver to Chain B (%s)...", rpcUrlB);
        uint256 forkB = vm.createSelectFork(rpcUrlB); // Create & select fork for Chain B
        
        vm.startBroadcast(deployerPrivateKey);
        PriceReceiverResolver resolver = new PriceReceiverResolver();
        vm.stopBroadcast();
        
        resolverAddr = address(resolver);
        console.log("PriceReceiverResolver deployed to Chain B at:", resolverAddr);

        // --- Deploy Sender Adapter to Chain A ---
        console.log("Deploying PriceSenderAdapter to Chain A (%s)...", rpcUrlA);
        uint256 forkA = vm.createSelectFork(rpcUrlA); // Create & select fork for Chain A
        
        vm.startBroadcast(deployerPrivateKey);
        // Ensure TruncGeoOracleMulti exists at the specified address on Chain A
        if (truncOracleAddressA.code.length == 0) {
             revert("TruncGeoOracleMulti not found at specified address on Chain A");
        }
        PriceSenderAdapter adapter = new PriceSenderAdapter(
            TruncGeoOracleMulti(truncOracleAddressA),
            chainIdB,
            resolverAddr,
            messenger // Use actual messenger address
        );
        vm.stopBroadcast();

        adapterAddr = address(adapter);
        console.log("PriceSenderAdapter deployed to Chain A at:", adapterAddr);

        // Select initial fork again if needed for further scripting
        // vm.selectFork(forkA); // Or forkB
    }
} 