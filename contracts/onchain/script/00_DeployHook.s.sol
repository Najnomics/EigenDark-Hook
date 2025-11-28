// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {EigenDarkHook} from "../src/EigenDarkHook.sol";
import {IEigenDarkVault} from "../src/interfaces/IEigenDarkVault.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

/// @notice Mines the address and deploys the EigenDarkHook contract
contract DeployHookScript is BaseScript {

    function run() public {
        // Get pool manager address for the current chain
        IPoolManager _poolManager = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        
        // EigenDarkHook implements beforeSwap, afterSwap, beforeAddLiquidity, beforeRemoveLiquidity
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        EigenDarkHook.Config memory cfg = EigenDarkHook.Config({attestationWindow: 1 hours});

        address vaultAddress = vm.envAddress("EIGENDARK_VAULT");
        require(vaultAddress != address(0), "DeployHook: vault not set");
        IEigenDarkVault vault = IEigenDarkVault(vaultAddress);

        address deployer = deployerAddress;

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(_poolManager, cfg, deployer, vault);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(EigenDarkHook).creationCode, constructorArgs);

        console.log("Mined hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        EigenDarkHook hook = new EigenDarkHook{salt: salt}(_poolManager, cfg, deployer, vault);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");

        console.log("EigenDarkHook deployed at:", address(hook));
        console.log("Vault:", address(vault));
        console.log("Owner:", deployer);
    }
}
