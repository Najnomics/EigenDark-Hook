# Local Testing Guide

## Running the Compute App Locally

### Prerequisites
- Docker installed and running
- `.env` file configured with:
  - `HOOK_ADDRESS`: Deployed hook address on Sepolia
  - `VAULT_ADDRESS`: Deployed vault address on Sepolia
  - `ATTESTOR_PRIVATE_KEY`: Private key for signing settlements
  - `CHAIN_ID`: 11155111 (Sepolia)
  - Other required environment variables

### Build and Run

```bash
# Build the Docker image
docker build --platform linux/amd64 -t eigendark/compute:local .

# Run the container
docker run -d --name eigendark-compute-local \
  --platform linux/amd64 \
  -p 8080:8080 \
  --env-file .env \
  eigendark/compute:local

# Check logs
docker logs -f eigendark-compute-local
```

### Test Endpoints

#### Health Check
```bash
curl http://localhost:8080/health | jq .
```

Expected response:
```json
{
  "status": "ok",
  "measurement": "0x...",
  "hook": "0x...",
  "pendingOrders": 0,
  "timestamp": 1234567890
}
```

#### Metrics
```bash
curl http://localhost:8080/metrics | jq .
```

Expected response:
```json
{
  "pending": 0,
  "stats": {
    "queued": 0,
    "processing": 0,
    "settled": 0,
    "failed": 0
  }
}
```

#### Submit Order
```bash
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -H "x-api-key: trusted-gateway" \
  -d '{
    "trader": "0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd",
    "tokenIn": "0x0000000000000000000000000000000000000000",
    "tokenOut": "0x0000000000000000000000000000000001",
    "amount": "1000000000000000",
    "limitPrice": "2000",
    "payload": "encrypted_order_data_here"
  }' | jq .
```

Expected response:
```json
{
  "orderId": "uuid-here",
  "status": "processing"
}
```

#### Check Order Status
```bash
curl http://localhost:8080/orders/{orderId} | jq .
```

### Test Results

✅ **Health endpoint**: Working
✅ **Metrics endpoint**: Working
✅ **Order submission**: Working
✅ **Order processing**: Working
✅ **Settlement creation**: Working
✅ **EIP-712 signing**: Working
✅ **BigInt serialization**: Fixed
⚠️ **Gateway webhook**: Expected to fail (gateway not running locally)

### Known Issues

1. **Gateway webhook connection refused**: This is expected when testing the compute app in isolation. The gateway service needs to be running on port 4000 for webhooks to work.

2. **Large amounts may exceed int128**: Very large order amounts (e.g., > 1 ETH) may cause int128 overflow errors. Use smaller amounts for testing (e.g., 0.001 ETH = "1000000000000000").

### Next Steps

1. Start the gateway service locally to test the full flow
2. Test with real Pyth price feeds
3. Test settlement submission to the on-chain hook
4. Test end-to-end flow: Gateway → Compute → Hook

### Stopping the Container

```bash
docker stop eigendark-compute-local
docker rm eigendark-compute-local
```

