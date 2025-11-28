// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {EigenDarkVault} from "../src/EigenDarkVault.sol";

/// @notice Deploys the EigenDarkVault contract
contract DeployVaultScript is Script {
    function run() public {
        address deployer = msg.sender;
        if (vm.envOr("PRIVATE_KEY", bytes32(0)) != bytes32(0)) {
            deployer = vm.addr(uint256(vm.envBytes32("PRIVATE_KEY")));
        }

        vm.startBroadcast();
        EigenDarkVault vault = new EigenDarkVault(deployer);
        vm.stopBroadcast();

        console.log("EigenDarkVault deployed at:", address(vault));
        console.log("Owner:", deployer);
    }
}

