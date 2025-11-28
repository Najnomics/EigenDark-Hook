# Quick Start: Deploy EigenCompute App

## Generated Attestor Key

A new attestor private key has been generated for you:
```
0x4f70cdd523b0c5d08419cbf2abcf897f659c73cea5c441a8a81b0aa62ac3801f
```

**⚠️ IMPORTANT:** Save this key securely! This will be used by the enclave to sign settlements.

## Immediate Next Steps

### 1. Add EigenX to PATH (if not already done)

```bash
export PATH="$HOME/bin:$PATH"
# Or add to ~/.zshrc permanently:
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 2. Authenticate with EigenX

```bash
eigenx auth login
# Enter your wallet private key when prompted
# (This is different from the attestor key above)
```

**Verify:**
```bash
eigenx auth whoami
```

### 3. Login to Docker

```bash
docker login
# Enter your Docker Hub credentials
```

### 4. Subscribe to EigenCompute

```bash
eigenx billing subscribe
# Follow the payment portal instructions
```

### 5. Update .env File

Update `off-chain/compute/app/.env` with the attestor key:

```bash
cd off-chain/compute/app
# Edit .env and set:
ATTESTOR_PRIVATE_KEY=0x4f70cdd523b0c5d08419cbf2abcf897f659c73cea5c441a8a81b0aa62ac3801f
```

The deployed addresses are already set:
- ✅ HOOK_ADDRESS=0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0
- ✅ VAULT_ADDRESS=0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70

### 6. Deploy!

```bash
cd off-chain/compute/app
export PATH="$HOME/bin:$PATH"
chmod +x scripts/deploy-eigenx.sh
ENV_FILE=.env IMAGE_TAG=eigendark/compute:latest ./scripts/deploy-eigenx.sh
```

### 7. Get Deployment Info

After deployment completes:

```bash
eigenx app info
eigenx app logs
```

**Extract the measurement hash and enclave wallet address from the output.**

### 8. Configure Hook

Once you have the enclave wallet address, configure the hook:

```bash
# Using cast (from foundry)
cast send 0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0 \
  "setAttestor(address,bool)" \
  <ENCLAVE_WALLET_ADDRESS> \
  true \
  --rpc-url <YOUR_RPC_URL> \
  --private-key <YOUR_DEPLOYER_KEY>
```

## Full Documentation

See `DEPLOYMENT_GUIDE.md` for detailed instructions and troubleshooting.

