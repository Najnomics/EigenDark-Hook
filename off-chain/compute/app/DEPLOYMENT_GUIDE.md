# EigenCompute Deployment Guide

This guide walks through deploying the EigenDark compute app to EigenX following the official EigenCloud documentation.

## Prerequisites Checklist

- [x] Docker installed and running
- [x] EigenX CLI installed (`/Users/najnomics/bin/eigenx`)
- [ ] EigenX authentication completed
- [ ] Docker registry login completed
- [ ] EigenCompute subscription active
- [ ] Sepolia testnet ETH for deployment transactions

## Step-by-Step Deployment

### Step 1: Authenticate with EigenX

You need to authenticate with EigenX using your private key. You have three options:

#### Option A: Store key in OS keyring (Recommended)
```bash
export PATH="$HOME/bin:$PATH"
eigenx auth login
# Enter your private key when prompted
```

#### Option B: Use environment variable
```bash
export PATH="$HOME/bin:$PATH"
export EIGENX_PRIVATE_KEY=0x<your_private_key>
```

#### Option C: Use flag per command
```bash
export PATH="$HOME/bin:$PATH"
eigenx <command> --private-key 0x<your_private_key>
```

**Verify authentication:**
```bash
eigenx auth whoami
```

Expected output:
```
Address: 0x...
Source: stored credentials (sepolia)
```

### Step 2: Get Testnet ETH (if needed)

Check your wallet address from Step 1, then get Sepolia ETH from:
- [Google Cloud Faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia)
- [Alchemy Faucet](https://sepoliafaucet.com/)

### Step 3: Login to Docker Registry

Login to Docker Hub (or your preferred registry):
```bash
docker login
# Enter your Docker Hub username and password
```

**Note:** The deployment will push the Docker image to your registry, so you need to be logged in.

### Step 4: Subscribe to EigenCompute

Before deploying, you need an EigenCompute subscription:

```bash
export PATH="$HOME/bin:$PATH"
eigenx billing subscribe
```

This will open a payment portal. Enter your payment method and subscribe.

**Note:** Testnet deployments may be free or have promotional pricing. Check the EigenCloud billing documentation for current pricing.

### Step 5: Verify Environment Configuration

Ensure you're on Sepolia testnet:
```bash
export PATH="$HOME/bin:$PATH"
eigenx env set sepolia
```

Verify the environment:
```bash
eigenx env get
# Should show: sepolia
```

### Step 6: Update .env File

Ensure your `.env` file in `off-chain/compute/app/` has the correct values:

```bash
cd off-chain/compute/app
cat .env
```

Required values:
- `HOOK_ADDRESS=0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0` ✅ (deployed)
- `VAULT_ADDRESS=0xcEe7Afa935b01854d097C1f0AE6A8Cb886671B70` ✅ (deployed)
- `CHAIN_ID=11155111` ✅ (Sepolia)
- `ATTESTOR_PRIVATE_KEY=0x...` (needs to be set - this will be the enclave's wallet)
- `ATTESTATION_MEASUREMENT=0x...` (will be set after deployment)

**Important:** The `ATTESTOR_PRIVATE_KEY` should be a new private key that will be used by the enclave to sign settlements. This key will be stored securely in the TEE.

### Step 7: Generate Attestor Key (if needed)

If you don't have an attestor key yet, generate one:

```bash
# Generate a new private key
openssl rand -hex 32
# Output: <your_new_private_key>
# Add 0x prefix: 0x<your_new_private_key>
```

Add this to your `.env` file as `ATTESTOR_PRIVATE_KEY`.

### Step 8: Deploy to EigenX

Navigate to the compute app directory and deploy:

```bash
cd off-chain/compute/app
export PATH="$HOME/bin:$PATH"

# Option 1: Use the deployment script
chmod +x scripts/deploy-eigenx.sh
ENV_FILE=.env IMAGE_TAG=eigendark/compute:latest scripts/deploy-eigenx.sh

# Option 2: Manual deployment
pnpm install --frozen-lockfile
pnpm build
docker buildx build --platform=linux/amd64 -t eigendark/compute:latest .
docker push eigendark/compute:latest
eigenx app deploy --path . --env .env
```

### Step 9: Monitor Deployment

After deployment starts, monitor the status:

```bash
# View app information
eigenx app info

# View real-time logs
eigenx app logs

# List all apps
eigenx app list
```

### Step 10: Get Deployment Details

Once deployed, you'll receive:
- **App ID**: Unique identifier for your app
- **Instance IP**: Public IP address of the TEE instance
- **Measurement Hash**: Cryptographic measurement of the deployed enclave
- **Enclave Wallet Address**: Address derived from the enclave's private key

**Extract the measurement hash:**
```bash
eigenx app info | grep -i measurement
# Or check the deployment logs
```

### Step 11: Update Hook Configuration

After deployment, update the on-chain hook with the attestor address:

1. Get the enclave wallet address from `eigenx app info`
2. Call `hook.setAttestor(enclaveAddress, true)` on the deployed hook
3. Update the measurement hash in pool configurations if using per-pool measurements

**Example:**
```bash
# Using cast (from foundry)
cast send 0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0 \
  "setAttestor(address,bool)" \
  0x<enclave_wallet_address> \
  true \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

### Step 12: Update Gateway Configuration

Update the gateway's `.env` file with:
- `EIGEN_TEE_URL`: The instance IP from Step 10
- `ATTESTATION_MEASUREMENT`: The measurement hash from Step 10

## Troubleshooting

### Docker Build Fails

Ensure your Dockerfile targets `linux/amd64`:
```dockerfile
FROM --platform=linux/amd64 node:18-bullseye-slim
```

### Deployment Transaction Fails

Check your ETH balance:
```bash
eigenx auth whoami
# Check the address on Sepolia explorer
```

Get more Sepolia ETH if needed.

### Image Push Fails

Ensure you're logged into Docker:
```bash
docker login
```

### App Not Starting

Check app logs:
```bash
eigenx app logs
```

Common issues:
- Port conflicts - ensure `PORT=8080` in `.env`
- Missing environment variables
- Application crashes - check logs for errors

### Authentication Issues

If authentication fails:
```bash
# Clear stored credentials and re-authenticate
eigenx auth logout
eigenx auth login
```

## Post-Deployment Checklist

- [ ] App deployed successfully
- [ ] Measurement hash obtained
- [ ] Enclave wallet address obtained
- [ ] Hook configured with attestor address
- [ ] Gateway configured with TEE URL and measurement
- [ ] Health check endpoint responding
- [ ] Test order submission working

## Next Steps After Deployment

1. **Configure Hook**: Set attestor, register pools, link vault
2. **Test Order Flow**: Submit test order through gateway → TEE → hook
3. **Monitor**: Set up monitoring for TEE uptime and settlement success rate
4. **Document**: Update deployment docs with actual measurement and addresses

## References

- [EigenX Quickstart Guide](https://docs.eigenlayer.xyz/eigencompute/get-started/quickstart)
- [EigenCompute Concepts](https://docs.eigenlayer.xyz/eigencompute/concepts/eigencompute-overview)
- [Port Configuration](https://docs.eigenlayer.xyz/eigencompute/howto/configure/expose-ports)
- [CLI Commands Reference](https://docs.eigenlayer.xyz/eigencompute/reference/cli-commands/authentication)

