# EigenDark Contract Deployments

This document tracks all deployed contracts for the EigenDark Hook project on Sepolia testnet.

## Network Information

- **Network**: Sepolia Testnet
- **Chain ID**: `11155111`
- **RPC URL**: Configure your own Alchemy/Infura endpoint (stored in `.env`)
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

### Test ERC20 Tokens

Used for Sepolia end-to-end settlement tests.

| Token | Symbol | Address | Notes |
|-------|--------|---------|-------|
| EigenDark Token0 | `EDT0` | `0xC0936f7E87607955C617F6491CCe1Eb1bebc1FD3` | Mintable test asset deployed with `forge create`. Initial 1,000 EDT0 minted to deployer; 500 EDT0 deposited into `EigenDarkVault`. |
| EigenDark Token1 | `EDT1` | `0xD384d3f622a2949219265E4467d3a8221e9f639C` | Mintable test asset deployed with `forge create`. Initial 1,000 EDT1 minted to deployer; 500 EDT1 deposited into `EigenDarkVault`. |

**Liquidity Setup**

- Approvals: both EDT0/EDT1 approve `0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70` (vault) for `1,000 * 10^18`.
- Vault Deposit Tx: `0xcbe9f5f5bc0e26a644c9d1a28d1b5e91747d3d25eb059a77d32432f7c5364585` (500 EDT0 / 500 EDT1).

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
# Sensitive values - DO NOT commit to repository
PRIVATE_KEY=<your_private_key>
RPC_URL=<your_rpc_endpoint>
ETHERSCAN_API_KEY=<your_etherscan_api_key>

# Deployment addresses (safe to commit)
EIGENDARK_VAULT=0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70
EIGENDARK_HOOK=0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0
POOL_MANAGER_ADDRESS=0x61b3f2011a92d183c7dbadbda940a7555ccf9227
```

**Note**: Sensitive values (private keys, API keys) should never be committed to the repository. Store them in `.env` which is gitignored.

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

