#!/bin/bash
# Verification script for EigenDark contracts on Sepolia

set -e

# Load environment variables
source .env

# Check for required variables
if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Error: ETHERSCAN_API_KEY not set in .env"
    echo "Get your API key from: https://etherscan.io/apis"
    exit 1
fi

if [ -z "$EIGENDARK_VAULT" ]; then
    echo "Error: EIGENDARK_VAULT not set in .env"
    exit 1
fi

if [ -z "$EIGENDARK_HOOK" ]; then
    echo "Error: EIGENDARK_HOOK not set in .env"
    exit 1
fi

# Get deployer address from private key
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)

echo "Verifying contracts on Sepolia..."
echo "Deployer: $DEPLOYER"
echo "Vault: $EIGENDARK_VAULT"
echo "Hook: $EIGENDARK_HOOK"
echo ""

# Verify Vault (simple constructor with just deployer address)
echo "Verifying EigenDarkVault..."
forge verify-contract \
    $EIGENDARK_VAULT \
    EigenDarkVault \
    --constructor-args $(cast abi-encode "constructor(address)" $DEPLOYER) \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version 0.8.30 \
    --watch

echo ""
echo "✅ Vault verified! View at: https://sepolia.etherscan.io/address/$EIGENDARK_VAULT#code"
echo ""

# For Hook, use the provided pool manager address or try to get it from chain
if [ -z "$POOL_MANAGER_ADDRESS" ]; then
    echo "Getting PoolManager address from chain..."
    POOL_MANAGER=$(cast call $EIGENDARK_HOOK "poolManager()(address)" --rpc-url $RPC_URL 2>/dev/null || echo "")
    
    if [ -z "$POOL_MANAGER" ] || [ "$POOL_MANAGER" == "0x0000000000000000000000000000000000000000" ]; then
        echo "Error: Could not get PoolManager from hook and POOL_MANAGER_ADDRESS not set in .env"
        exit 1
    fi
else
    POOL_MANAGER=$POOL_MANAGER_ADDRESS
fi

echo "PoolManager: $POOL_MANAGER"
echo ""

# Verify Hook
# Constructor: EigenDarkHook(IPoolManager _poolManager, Config memory cfg, address initialOwner, IEigenDarkVault _vault)
# Config struct: {uint32 attestationWindow} = 3600 (1 hour in seconds)
# Note: For a struct with a single field, we encode it directly as the uint32 value
echo "Verifying EigenDarkHook..."
CONSTRUCTOR_ARGS=$(cast abi-encode "f(address,uint32,address,address)" $POOL_MANAGER 3600 $DEPLOYER $EIGENDARK_VAULT)
forge verify-contract \
    $EIGENDARK_HOOK \
    EigenDarkHook \
    --constructor-args $CONSTRUCTOR_ARGS \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version 0.8.30 \
    --watch

echo ""
echo "✅ Hook verified! View at: https://sepolia.etherscan.io/address/$EIGENDARK_HOOK#code"
echo ""
echo "✅ All contracts verified!"
