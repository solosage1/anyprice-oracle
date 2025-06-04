// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockTruncGeoOracleMulti} from "test/mocks/MockTruncGeoOracleMulti.sol";

contract DeployMockOracle is Script {
    function run() external returns (address addr) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        MockTruncGeoOracleMulti oracle = new MockTruncGeoOracleMulti();
        vm.stopBroadcast();
        console2.log("Mock oracle deployed at:", address(oracle));
        return address(oracle);
    }
} 