# Contract Verification on Etherscan

## Why Verify?

Verifying contracts on Etherscan provides:
- **Transparency**: Users can view and audit the source code
- **Trust**: Builds confidence in the deployed contracts
- **Interactivity**: Enables interaction via Etherscan's UI
- **Security**: Allows community verification of contract integrity

## Prerequisites

1. **Etherscan API Key**: Get one from https://etherscan.io/apis
2. **Deployed Contract Addresses**: Already deployed on Sepolia
3. **Constructor Arguments**: Needed for verification

## Quick Start

1. Add your Etherscan API key to `.env`:
   ```bash
   ETHERSCAN_API_KEY=your_api_key_here
   ```

2. Run the verification script:
   ```bash
   cd contracts/onchain
   ./scripts/verify.sh
   ```

## Manual Verification

If the script doesn't work, you can verify manually:

### Verify Vault

```bash
forge verify-contract \
  0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70 \
  EigenDarkVault \
  --constructor-args $(cast abi-encode "constructor(address)" 0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd) \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --compiler-version 0.8.30
```

### Verify Hook

First, get the PoolManager address. For Sepolia, you can find it in:
- Uniswap V4 docs: https://docs.uniswap.org/contracts/v4/reference/deployments
- Or query it from AddressConstants in the codebase

Then verify:
```bash
forge verify-contract \
  0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0 \
  EigenDarkHook \
  --constructor-args $(cast abi-encode "constructor(address,(uint32),address,address)" <POOL_MANAGER> 3600 0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd 0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70) \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --compiler-version 0.8.30
```

## Deployed Addresses (Sepolia)

- **EigenDarkVault**: `0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70`
- **EigenDarkHook**: `0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0`
- **Owner**: `0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd`

## Troubleshooting

- **"Contract already verified"**: The contract is already verified, no action needed
- **"Constructor arguments mismatch"**: Double-check the constructor arguments match the deployment
- **"Compiler version mismatch"**: Ensure you're using Solidity 0.8.30
- **"API key invalid"**: Check your Etherscan API key is correct and has sufficient quota

## After Verification

Once verified, you can:
- View source code on Etherscan
- Interact with contracts via Etherscan UI
- Share verified contract links with users
- Build trust with the community

