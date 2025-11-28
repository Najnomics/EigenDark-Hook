// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script";
import {EigenDarkVault} from "../src/EigenDarkVault.sol";
import {EigenDarkHook} from "../src/EigenDarkHook.sol";

/// @notice Verifies deployed contracts on Etherscan
/// @dev Run this after deploying contracts. Requires ETHERSCAN_API_KEY in .env
contract VerifyContractsScript is Script {
    function run() public {
        // Read deployed addresses from environment or use known addresses
        address vaultAddress = vm.envOr("EIGENDARK_VAULT", address(0));
        address hookAddress = vm.envOr("EIGENDARK_HOOK", address(0));

        require(vaultAddress != address(0), "Vault address not set");
        require(hookAddress != address(0), "Hook address not set");

        console.log("Verifying EigenDarkVault at:", vaultAddress);
        console.log("Verifying EigenDarkHook at:", hookAddress);

        // Get constructor arguments
        address deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        if (vm.envOr("PRIVATE_KEY", bytes32(0)) != bytes32(0)) {
            deployer = vm.addr(uint256(vm.envBytes32("PRIVATE_KEY")));
        }

        // Verify Vault
        // Constructor: EigenDarkVault(address initialOwner)
        bytes memory vaultConstructorArgs = abi.encode(deployer);
        
        // Verify Hook
        // Constructor: EigenDarkHook(IPoolManager _poolManager, Config memory cfg, address initialOwner, IEigenDarkVault _vault)
        // We need to get the pool manager address and reconstruct the config
        address poolManager = vm.envOr("POOL_MANAGER_ADDRESS", address(0));
        if (poolManager == address(0)) {
            // Try to get from AddressConstants if available
            // For now, we'll need to set it manually
            revert("POOL_MANAGER_ADDRESS must be set in .env");
        }
        
        EigenDarkHook.Config memory cfg = EigenDarkHook.Config({attestationWindow: 1 hours});
        bytes memory hookConstructorArgs = abi.encode(
            poolManager,
            cfg.attestationWindow,
            deployer,
            vaultAddress
        );

        // Note: Actual verification is done via forge verify-contract command
        // This script just prepares the constructor arguments
        console.log("Vault constructor args (encoded):", vm.toString(vaultConstructorArgs));
        console.log("Hook constructor args (encoded):", vm.toString(hookConstructorArgs));
        console.log("\nTo verify, run:");
        console.log("forge verify-contract <VAULT_ADDRESS> EigenDarkVault --constructor-args $(cast abi-encode 'constructor(address)' <DEPLOYER>) --chain sepolia --etherscan-api-key $ETHERSCAN_API_KEY");
        console.log("forge verify-contract <HOOK_ADDRESS> EigenDarkHook --constructor-args $(cast abi-encode 'constructor(address,uint32,address,address)' <POOL_MANAGER> 3600 <DEPLOYER> <VAULT>) --chain sepolia --etherscan-api-key $ETHERSCAN_API_KEY");
    }
}

