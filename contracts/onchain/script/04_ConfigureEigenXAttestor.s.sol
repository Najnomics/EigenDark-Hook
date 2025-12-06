// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {EigenDarkHook} from "../src/EigenDarkHook.sol";

/**
 * @title Configure EigenX Attestor
 * @notice Updates the hook with the enclave wallet address from EigenX deployment
 * @dev Run this after deploying the compute app to EigenX
 * 
 * Required env vars:
 * - EIGENDARK_HOOK: Address of the deployed hook
 * - PRIVATE_KEY: Owner's private key (for setAttestor call)
 * - EIGENX_ENCLAVE_ADDRESS: The EVM address from eigenx app info
 */
contract ConfigureEigenXAttestor is Script {
    function run() external {
        address hookAddr = vm.envAddress("EIGENDARK_HOOK");
        address enclaveAddr = vm.envAddress("EIGENX_ENCLAVE_ADDRESS");
        uint256 ownerKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        
        EigenDarkHook hook = EigenDarkHook(hookAddr);
        
        console.log("=== Configuring EigenX Attestor ===");
        console.log("Hook:", hookAddr);
        console.log("Enclave Address:", enclaveAddr);
        console.log("Owner:", vm.addr(ownerKey));
        
        vm.startBroadcast(ownerKey);
        
        // Remove old attestor if needed (optional - uncomment if you want to clean up)
        // address oldAttestor = vm.envOr("OLD_ATTESTOR_ADDRESS", address(0));
        // if (oldAttestor != address(0)) {
        //     console.log("Removing old attestor:", oldAttestor);
        //     hook.setAttestor(oldAttestor, false);
        // }
        
        // Add the EigenX enclave as an attestor
        console.log("Setting EigenX enclave as attestor...");
        hook.setAttestor(enclaveAddr, true);
        
        // Verify it was set
        bool isAttestor = hook.attestors(enclaveAddr);
        require(isAttestor, "Failed to set attestor");
        console.log("[OK] Attestor configured successfully");
        
        vm.stopBroadcast();
        
        console.log("=== Configuration Complete ===");
    }
}

