# EigenAI Integration Guide

This document explains how to use EigenAI with wallet-based authentication via the deTERMinal grant system.

## Overview

EigenAI uses a **grant-based authentication system** that allows access via wallet signatures instead of traditional API keys. This provides a more decentralized and user-friendly authentication method.

## Getting Started

### Step 1: Get Free Grant Tokens

1. Visit [deTERMinal](https://determinal.eigenarcade.com)
2. Connect your X (Twitter) account
3. Receive **1M inference tokens** for free
4. Your Ethereum address is automatically registered for grants

### Step 2: Use the EigenAI Client

The compute app includes an `EigenAIClient` class that handles authentication automatically:

```typescript
import { createEigenAIClient } from "./eigenai.js";

// Initialize client with your wallet
const client = createEigenAIClient(
  "0x<your_private_key>",
  "0x<your_wallet_address>"
);

// Check grant status
const status = await client.checkGrant();
console.log(`Token count: ${status.tokenCount}`);
console.log(`Has grant: ${status.hasGrant}`);

// Make a chat completion request
const response = await client.chatCompletions("Hello, how are you?", {
  model: "gpt-oss-120b-f16",
  max_tokens: 150,
  seed: 42,
});

console.log(response.choices[0].message.content);
```

## API Reference

### EigenAIClient Class

#### Constructor

```typescript
new EigenAIClient(privateKey: `0x${string}`, walletAddress: `0x${string}`)
```

#### Methods

##### `checkGrant(): Promise<GrantStatusResponse>`

Check if your wallet has an active grant and token balance.

**Returns:**
```typescript
{
  success: boolean;
  tokenCount: number;
  address: string;
  hasGrant: boolean;
}
```

##### `chatCompletions(userMessage: string, options?): Promise<ChatCompletionResponse>`

Make a chat completion request to EigenAI.

**Parameters:**
- `userMessage`: The user's message
- `options`: Optional configuration
  - `model`: Model to use (default: `"gpt-oss-120b-f16"`)
  - `max_tokens`: Maximum tokens to generate (default: `150`)
  - `seed`: Random seed for reproducibility
  - `temperature`: Sampling temperature (0-2)

**Returns:**
```typescript
{
  id: string;
  created: number;
  model: string;
  choices: Array<{
    message: { role: string; content: string };
    finish_reason: string;
  }>;
  usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
  signature?: string; // Cryptographic signature for verification
}
```

## Available Models

- `gpt-oss-120b-f16` - GPT-style open source model (120B parameters)
- `qwen3-32b-128k-bf16` - Qwen3 model (32B parameters, 128k context)

## Authentication Flow

The client automatically handles the authentication flow:

1. **Get Grant Message**: Calls `/message` endpoint with your wallet address
2. **Sign Message**: Signs the message with your private key using EIP-191
3. **Make Request**: Includes signed message in the API request

## Example: Using in Compute App

```typescript
// In your compute app server.ts or order processing logic
import { createEigenAIClient } from "./eigenai.js";
import { config } from "./config.js";

// Initialize EigenAI client
const eigenAI = createEigenAIClient(
  config.attestorPrivateKey, // Or a dedicated AI key
  config.attestorAddress     // Wallet address
);

// Use in order processing
async function processOrderWithAI(order: EncryptedOrder) {
  // Check if we have grant tokens
  const grantStatus = await eigenAI.checkGrant();
  if (!grantStatus.hasGrant || grantStatus.tokenCount === 0) {
    logger.warn("No EigenAI grant available, skipping AI features");
    return processOrderNormally(order);
  }

  // Use AI for intelligent order matching or analysis
  const analysis = await eigenAI.chatCompletions(
    `Analyze this trade order: ${JSON.stringify(order)}`,
    {
      model: "gpt-oss-120b-f16",
      max_tokens: 500,
      seed: 42, // Deterministic for reproducibility
    }
  );

  // Use AI response in your logic
  logger.info({ analysis: analysis.choices[0].message.content }, "AI analysis complete");
  
  return processOrderWithAnalysis(order, analysis);
}
```

## Direct API Usage (without client)

If you prefer to use the API directly:

### Step 1: Get Grant Message

```bash
curl "https://determinal-api.eigenarcade.com/message?address=YOUR_ETHEREUM_ADDRESS"
```

**Response:**
```json
{
  "success": true,
  "message": "Sign this message to authenticate your grant request for: 0x...",
  "address": "YOUR_ETHEREUM_ADDRESS"
}
```

### Step 2: Sign the Message

```bash
# Using cast (from foundry)
MESSAGE="Sign this message to authenticate your grant request for: 0x..."
SIGNATURE=$(cast wallet sign --private-key $PRIVATE_KEY "$MESSAGE")
```

### Step 3: Make API Call

```bash
curl -X POST https://determinal-api.eigenarcade.com/api/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "model": "gpt-oss-120b-f16",
    "max_tokens": 150,
    "seed": 42,
    "grantMessage": "Sign this message to authenticate your grant request for: 0x...",
    "grantSignature": "0x...",
    "walletAddress": "YOUR_ETHEREUM_ADDRESS"
  }'
```

## Error Handling

Common errors and solutions:

### No Grant Available

**Error:** `tokenCount: 0` or `hasGrant: false`

**Solution:** 
1. Visit [deTERMinal](https://determinal.eigenarcade.com)
2. Connect your X account
3. Claim your free grant

### Insufficient Tokens

**Error:** API returns error about insufficient tokens

**Solution:** 
- Check your token balance: `await client.checkGrant()`
- Request more tokens or wait for grant refresh

### Invalid Signature

**Error:** Authentication failed

**Solution:**
- Ensure you're signing the exact message returned from `/message`
- Verify your private key matches the wallet address
- Check that the signature format is correct (`0x...`)

## Security Considerations

1. **Private Key Storage**: Never commit private keys to version control
2. **Environment Variables**: Store keys in `.env` file (gitignored)
3. **TEE Isolation**: In EigenCompute TEE, keys are automatically secured
4. **Signature Verification**: EigenAI responses include cryptographic signatures for verification

## Resources

- [deTERMinal](https://determinal.eigenarcade.com) - Get free grant tokens
- [Grant API Integration README](https://github.com/scotthconner/eigenx-determinal-token-grants) - Official documentation
- [EigenAI Documentation](https://docs.eigenlayer.xyz/eigenai) - Full EigenAI docs
- [Try EigenAI](https://deterministicinference.com/) - Interactive demo

## Integration with EigenDark

For the EigenDark project, EigenAI can be used for:

1. **Intelligent Order Matching**: Analyze order patterns and optimize matching
2. **Risk Analysis**: AI-powered risk assessment for large trades
3. **Price Prediction**: Analyze market conditions for better execution
4. **Anomaly Detection**: Identify suspicious trading patterns

All AI processing happens inside the TEE, ensuring privacy and determinism.

