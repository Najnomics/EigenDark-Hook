# EigenDark Contract Deployments

This document tracks all deployed contracts for the EigenDark Hook project on Sepolia testnet.

## Network Information

- **Network**: Sepolia Testnet
- **Chain ID**: `11155111`
- **RPC URL**: `https://eth-sepolia.g.alchemy.com/v2/FlEUrYqZ9gYvgFxtEVA6zWB0zrQwGL4N`
- **Explorer**: https://sepolia.etherscan.io

## Deployed Contracts

### EigenDarkVault

**Purpose**: Holds token reserves for EigenDark pools and executes net settlements on hook instructions.

- **Address**: `0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70`
- **Status**: ✅ Verified
- **Etherscan**: https://sepolia.etherscan.io/address/0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70#code
- **Contract**: `EigenDarkVault.sol`
- **Owner**: `0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd`
- **Constructor Args**: 
  - `initialOwner`: `0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd`
- **Deployment Tx**: See broadcast files in `broadcast/00_DeployVault.s.sol/11155111/`

### EigenDarkHook

**Purpose**: Uniswap V4 hook that only allows privately-settled swaps coming from EigenCompute TEEs. Settlement proofs are verified via EIP-712 signatures.

- **Address**: `0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0`
- **Status**: ✅ Verified
- **Etherscan**: https://sepolia.etherscan.io/address/0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0#code
- **Contract**: `EigenDarkHook.sol`
- **Owner**: `0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd`
- **Vault**: `0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70`
- **PoolManager**: `0x61b3f2011a92d183c7dbadbda940a7555ccf9227`
- **Constructor Args**:
  - `_poolManager`: `0x61b3f2011a92d183c7dbadbda940a7555ccf9227`
  - `cfg.attestationWindow`: `3600` (1 hour)
  - `initialOwner`: `0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd`
  - `_vault`: `0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70`
- **Deployment Tx**: See broadcast files in `broadcast/00_DeployHook.s.sol/11155111/`
- **Hook Permissions**:
  - `beforeSwap`: ✅ Enabled
  - `afterSwap`: ✅ Enabled
  - `beforeAddLiquidity`: ✅ Enabled
  - `beforeRemoveLiquidity`: ✅ Enabled

## External Dependencies

### Uniswap V4 Core Contracts

- **PoolManager**: `0x61b3f2011a92d183c7dbadbda940a7555ccf9227`
  - Source: Uniswap V4 canonical deployment on Sepolia
  - Reference: https://docs.uniswap.org/contracts/v4/reference/deployments

## Deployment Accounts

- **Deployer Address**: `0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd`
- **Deployer Account**: Used for contract deployment and initial ownership

## Verification Status

| Contract | Address | Status | Verified On |
|----------|---------|--------|--------------|
| EigenDarkVault | `0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70` | ✅ Verified | Sepolia Etherscan |
| EigenDarkHook | `0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0` | ✅ Verified | Sepolia Etherscan |

## Post-Deployment Configuration

After deployment, the following configuration steps are required:

### 1. Link Vault to Hook

```solidity
// Call on EigenDarkVault
vault.setHook(0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0);
```

### 2. Configure Attestors

```solidity
// Call on EigenDarkHook
hook.setAttestor(attestorAddress, true);
```

### 3. Register Pools

```solidity
// Call on EigenDarkVault
vault.registerPool(poolKey);

// Call on EigenDarkHook
hook.configurePool(poolKey, poolConfig);
```

## Deployment Scripts

- **Vault Deployment**: `script/00_DeployVault.s.sol`
- **Hook Deployment**: `script/00_DeployHook.s.sol`
- **Verification**: `scripts/verify.sh`

## Environment Variables

Required environment variables for deployment (stored in `.env`):

```bash
PRIVATE_KEY=885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72
RPC_URL=https://eth-sepolia.g.alchemy.com/v2/FlEUrYqZ9gYvgFxtEVA6zWB0zrQwGL4N
EIGENDARK_VAULT=0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70
EIGENDARK_HOOK=0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0
POOL_MANAGER_ADDRESS=0x61b3f2011a92d183c7dbadbda940a7555ccf9227
ETHERSCAN_API_KEY=PRPS7NDEPG461YQJ92AUEFSAKZIZT7EMWM
```

## Quick Links

- **EigenDarkVault on Etherscan**: https://sepolia.etherscan.io/address/0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70
- **EigenDarkHook on Etherscan**: https://sepolia.etherscan.io/address/0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0
- **Deployer Address**: https://sepolia.etherscan.io/address/0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd

## Deployment History

- **2024-12-XX**: Initial deployment of EigenDarkVault and EigenDarkHook to Sepolia testnet
- **2024-12-XX**: Contracts verified on Etherscan

## Notes

- All contracts are deployed on Sepolia testnet
- Contracts are verified and publicly viewable on Etherscan
- Owner address has full administrative control over both contracts
- Hook is configured to block public swaps and liquidity operations
- Vault must be linked to hook before settlements can be processed

