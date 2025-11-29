// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {EigenDarkHook} from "../src/EigenDarkHook.sol";
import {BaseScript} from "./base/BaseScript.sol";

/// @notice Updates attestor to match compute app and configures a test pool
contract UpdateAttestorAndConfigurePoolScript is BaseScript {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    function run() public {
        address hookAddress = vm.envAddress("EIGENDARK_HOOK");
        EigenDarkHook hook = EigenDarkHook(hookAddress);
        
        // Get the compute app's attestor address (from its private key)
        uint256 computeAppKey = uint256(vm.envBytes32("COMPUTE_APP_ATTESTOR_KEY"));
        address computeAppAttestor = vm.addr(computeAppKey);
        
        // Get owner key
        uint256 ownerKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address owner = vm.addr(ownerKey);

        console.log("Hook:", hookAddress);
        console.log("Compute App Attestor:", computeAppAttestor);
        console.log("Owner:", owner);

        vm.startBroadcast(ownerKey);

        // Step 1: Remove old attestor and add compute app attestor
        console.log("\n1. Updating attestor to match compute app...");
        // Remove old attestor if needed
        address oldAttestor = vm.envOr("OLD_ATTESTOR_ADDRESS", address(0));
        if (oldAttestor != address(0)) {
            hook.setAttestor(oldAttestor, false);
            console.log("   Removed old attestor:", oldAttestor);
        }
        // Add compute app attestor
        hook.setAttestor(computeAppAttestor, true);
        console.log("   Added compute app attestor:", computeAppAttestor);

        // Step 2: Configure a pool for testing
        // We'll use a dummy poolId that matches what the compute app generates
        // The compute app generates poolId from tokenIn-tokenOut pair
        // For testing, we'll configure a pool that accepts any poolId by using a known one
        console.log("\n2. Configuring test pool...");
        
        // Use the poolId that the compute app generates (from logs: 0x658e5d6f2e7fbc94953680ca040d50c5ddccadb5f0f05772399fffea45f88b28)
        // This is for tokenIn=0x0000...0000, tokenOut=0x0000...0001
        // We need to create a PoolKey that generates this poolId
        // For now, let's configure it with a minimal setup that allows testing
        
        // Create a minimal pool key - we'll use placeholder addresses
        // The actual poolId is computed from the token addresses, so we need to match what compute app uses
        address token0 = address(0x0000000000000000000000000000000000000000);
        address token1 = address(0x0000000000000000000000000000000001);
        
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });
        
        PoolId poolId = poolKey.toId();
        console.log("   Pool ID configured");
        
        EigenDarkHook.PoolConfigInput memory poolConfig = EigenDarkHook.PoolConfigInput({
            enabled: true,
            settlementsPaused: false,
            enclaveMeasurement: bytes32(0), // Allow any measurement for testing
            maxAbsDelta0: type(uint128).max, // No limit for testing
            maxAbsDelta1: type(uint128).max, // No limit for testing
            maxSettlementAge: 3600, // 1 hour
            maxTwapDeviationBps: 10000, // 100% deviation allowed for testing
            minCheckedLiquidity: 0 // No minimum for testing
        });
        
        hook.configurePool(poolKey, poolConfig);
        console.log("   Pool configured on hook");

        vm.stopBroadcast();

        console.log("\nAttestor and pool configuration complete!");
    }
}

