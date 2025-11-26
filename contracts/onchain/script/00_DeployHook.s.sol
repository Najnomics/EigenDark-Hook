// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {EigenDarkHook} from "../src/EigenDarkHook.sol";
import {IEigenDarkVault} from "../src/interfaces/IEigenDarkVault.sol";

/// @notice Mines the address and deploys the EigenDarkHook contract
contract DeployHookScript is BaseScript {
    function run() public {
        // EigenDarkHook only implements beforeSwap, so we only need that flag in the address.
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        EigenDarkHook.Config memory cfg = EigenDarkHook.Config({
            attestor: deployerAddress,
            enclaveMeasurement: bytes32(uint256(0xE1E1)),
            attestationWindow: 1 hours
        });

        address vaultAddress = vm.envAddress("EIGENDARK_VAULT");
        require(vaultAddress != address(0), "DeployHook: vault not set");
        IEigenDarkVault vault = IEigenDarkVault(vaultAddress);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager, cfg, deployerAddress, vault);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(EigenDarkHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        EigenDarkHook hook = new EigenDarkHook{salt: salt}(poolManager, cfg, deployerAddress, vault);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
