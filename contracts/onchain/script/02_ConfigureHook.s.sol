// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {EigenDarkHook} from "../src/EigenDarkHook.sol";
import {EigenDarkVault} from "../src/EigenDarkVault.sol";
import {BaseScript} from "./base/BaseScript.sol";

/// @notice Configures the EigenDarkHook and EigenDarkVault for production use
contract ConfigureHookScript is BaseScript {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    function run() public {
        address hookAddress = vm.envAddress("EIGENDARK_HOOK");
        address vaultAddress = vm.envAddress("EIGENDARK_VAULT");
        
        // Use the owner's private key (the deployer)
        uint256 ownerKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address owner = vm.addr(ownerKey);
        
        EigenDarkHook hook = EigenDarkHook(hookAddress);
        EigenDarkVault vault = EigenDarkVault(vaultAddress);

        // Get attestor address from compute app private key
        // This is the address that signs settlements
        address attestorAddress;
        // Try to read ATTESTOR_ADDRESS directly
        try vm.envAddress("ATTESTOR_ADDRESS") returns (address addr) {
            require(addr != address(0), "ATTESTOR_ADDRESS cannot be zero");
            attestorAddress = addr;
        } catch {
            // Derive from private key if address not set
            bytes32 attestorKeyBytes = vm.envBytes32("ATTESTOR_PRIVATE_KEY");
            uint256 attestorKey = uint256(attestorKeyBytes);
            attestorAddress = vm.addr(attestorKey);
        }

        console.log("Hook:", hookAddress);
        console.log("Vault:", vaultAddress);
        console.log("Attestor:", attestorAddress);
        console.log("Owner:", owner);

        vm.startBroadcast(ownerKey);

        // Step 1: Set attestor on hook
        console.log("\n1. Setting attestor on hook...");
        hook.setAttestor(attestorAddress, true);
        console.log("   Attestor set:", attestorAddress);

        // Step 2: Link vault to hook
        console.log("\n2. Linking vault to hook...");
        vault.setHook(hookAddress);
        console.log("   Vault linked to hook");

        // Step 3: Register pool on vault (optional)
        // Using test tokens for now - in production, use real token addresses
        address token0;
        address token1;
        try vm.envAddress("POOL_TOKEN0") returns (address t0) {
            token0 = t0;
        } catch {
            token0 = address(0);
        }
        try vm.envAddress("POOL_TOKEN1") returns (address t1) {
            token1 = t1;
        } catch {
            token1 = address(0);
        }
        
        if (token0 != address(0) && token1 != address(0)) {
            console.log("\n3. Registering pool on vault...");
            PoolKey memory poolKey = PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: 3000, // 0.3% fee
                tickSpacing: 60,
                hooks: IHooks(hookAddress)
            });
            PoolId poolId = poolKey.toId();
            console.log("   Pool ID registered");
            
            vault.registerPool(poolKey);
            console.log("   Pool registered on vault");

            // Step 4: Configure pool on hook
            console.log("\n4. Configuring pool on hook...");
            EigenDarkHook.PoolConfigInput memory poolConfig = EigenDarkHook.PoolConfigInput({
                enabled: true,
                settlementsPaused: false,
                enclaveMeasurement: bytes32(0), // Allow any measurement for now
                maxAbsDelta0: type(uint128).max, // No limit for testing
                maxAbsDelta1: type(uint128).max, // No limit for testing
                maxSettlementAge: 3600, // 1 hour
                maxTwapDeviationBps: 10000, // 100% deviation allowed for testing
                minCheckedLiquidity: 0 // No minimum for testing
            });
            
            hook.configurePool(poolKey, poolConfig);
            console.log("   Pool configured on hook");
        } else {
            console.log("\n3. Skipping pool registration (POOL_TOKEN0/POOL_TOKEN1 not set)");
        }

        vm.stopBroadcast();

        console.log("\nHook configuration complete!");
    }
}

