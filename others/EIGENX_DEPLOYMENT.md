# EigenX Compute App Deployment

## Deployment Information

**Deployment Date**: December 6, 2025  
**Network**: Sepolia Testnet  
**Status**: ✅ Running

### App Details

- **App ID**: `0xDb88d54e7594540290d339E2f3FcE2364b522cea`
- **App Name**: `eigendark-compute`
- **Public IP**: `104.198.14.111`
- **Instance Type**: `g1-standard-4t` (4 vCPUs, 16 GB memory, TDX)
- **Status**: Running

### Enclave Wallet Addresses

- **EVM Address**: `0xDA6D5b0298B9C91a657Ab8fDf86454B8cD4ef3aA` (path: m/44'/60'/0'/0/0)
- **Solana Address**: `DnhuUegZV5f2Ci5LrXVgwQEghepLV8eKRdzxf74f2C85` (path: m/44'/501'/0'/0')

**✅ CONFIGURED**: The EVM address has been set as an attestor on the `EigenDarkHook` contract.

### Docker Image

- **Image**: `najnomics/eigendark-compute:latest-eigenx`
- **Digest**: `sha256:78cdd8581fa4cb9b9d2722d8fda52fa8ffe56e9960367b52d31bfeb0a4921470`

### Hook Configuration

The EigenX enclave address has been configured as an attestor on the hook:

- **Hook Address**: `0x12982838e8cd12e8d8d4dee9A4DE6Ac8B7164AC0`
- **Enclave Attestor**: `0xDA6D5b0298B9C91a657Ab8fDf86454B8cD4ef3aA`
- **Configuration Script**: `contracts/onchain/script/04_ConfigureEigenXAttestor.s.sol`
- **Status**: ✅ Configured

### Attestation Measurement

The attestation measurement can be retrieved from:
1. The app's health endpoint: `http://104.198.14.111/health` (or port 8080)
2. EigenX app info (may require additional queries)

**Note**: The measurement in the `.env` file is currently a placeholder (`0x0000...`). The actual measurement should be retrieved from the running instance once it's fully operational.

### Configuration Updates Required

1. **Update Gateway `.env`** (if using the deployed compute app):
   - `EIGEN_COMPUTE_URL=http://104.198.14.111:8080` (verify the actual port)
   - `ATTESTATION_MEASUREMENT=<retrieved from health endpoint>`

2. **Update Compute App `.env`** (if redeploying):
   - `GATEWAY_WEBHOOK_URL` should point to your gateway's public URL (not `host.docker.internal`)
   - If your gateway is running locally, you'll need to expose it publicly (e.g., using ngrok, a VPS, or a cloud service)

### Health Check

```bash
curl http://104.198.14.111/health
# Or try port 8080:
curl http://104.198.14.111:8080/health
```

### View Logs

```bash
export PATH="$HOME/bin:$PATH"
eigenx app logs 0xDb88d54e7594540290d339E2f3FcE2364b522cea
```

### View App Info

```bash
export PATH="$HOME/bin:$PATH"
eigenx app info 0xDb88d54e7594540290d339E2f3FcE2364b522cea
```

### Next Steps

1. ✅ **Deploy compute app to EigenX** - Complete
2. ✅ **Configure hook with enclave address** - Complete
3. ⏳ **Retrieve attestation measurement** - Get from health endpoint
4. ⏳ **Update gateway configuration** - Point to deployed compute app
5. ⏳ **Test end-to-end flow** - Submit order through gateway → compute app → hook

### Important Notes

- The compute app is running in a TEE (Trusted Execution Environment) on EigenX
- The enclave wallet (`0xDA6D5b0298B9C91a657Ab8fDf86454B8cD4ef3aA`) signs all settlements
- The hook verifies these signatures before allowing settlements
- For local testing, you can still run the compute app locally via Docker
- For production, use the deployed EigenX instance
