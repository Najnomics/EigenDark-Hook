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

# For Hook, we need to get the pool manager address from the deployment
# We can query it from the hook's storage or use AddressConstants
# Let's get it from the RPC
echo "Getting PoolManager address from chain..."
POOL_MANAGER=$(cast call $EIGENDARK_HOOK "poolManager()(address)" --rpc-url $RPC_URL 2>/dev/null || echo "")

if [ -z "$POOL_MANAGER" ] || [ "$POOL_MANAGER" == "0x0000000000000000000000000000000000000000" ]; then
    echo "Could not get PoolManager from hook. Please set POOL_MANAGER_ADDRESS in .env"
    echo "You can find it at: https://docs.uniswap.org/contracts/v4/reference/deployments"
    if [ -z "$POOL_MANAGER_ADDRESS" ]; then
        exit 1
    fi
    POOL_MANAGER=$POOL_MANAGER_ADDRESS
fi

echo "PoolManager: $POOL_MANAGER"
echo ""

# Verify Hook
# Constructor: EigenDarkHook(IPoolManager _poolManager, Config memory cfg, address initialOwner, IEigenDarkVault _vault)
# Config struct: {uint32 attestationWindow} = 3600 (1 hour in seconds)
echo "Verifying EigenDarkHook..."
# Note: For struct encoding, we need to encode it properly
# The Config struct is just {uint32 attestationWindow}
forge verify-contract \
    $EIGENDARK_HOOK \
    EigenDarkHook \
    --constructor-args $(cast abi-encode "constructor(address,(uint32),address,address)" $POOL_MANAGER 3600 $DEPLOYER $EIGENDARK_VAULT) \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version 0.8.30 \
    --watch

echo ""
echo "✅ Hook verified! View at: https://sepolia.etherscan.io/address/$EIGENDARK_HOOK#code"
echo ""
echo "✅ All contracts verified!"
