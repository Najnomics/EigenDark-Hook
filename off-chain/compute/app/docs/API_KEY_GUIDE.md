# EigenAI API Key Guide

## Understanding EigenAI Authentication

EigenAI supports **two authentication methods**:

1. **Traditional API Key** (for UI/frontend integration)
2. **Wallet-Based Grant System** (for programmatic/backend use)

## Option 1: Get Traditional API Key

If you need a traditional API key format (for UI components that expect `X-API-Key` header):

### Steps:

1. **Visit the Onboarding Page:**
   ```
   https://onboarding.eigencloud.xyz/
   ```

2. **Request API Key Access:**
   - Sign up or log in
   - Navigate to API Keys section
   - Generate a new API key
   - Copy and store it securely

3. **Use in API Calls:**
   ```bash
   curl -X POST https://eigenai.eigencloud.xyz/v1/chat/completions \
     -H "X-API-Key: YOUR_API_KEY_HERE" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "gpt-oss-120b-f16",
       "messages": [{"role": "user", "content": "Hello!"}]
     }'
   ```

## Option 2: Use Wallet-Based Auth (Current Setup)

You already have this set up! Your credentials:

**Wallet Address:**
```
0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd
```

**Grant Status:**
- ✅ Active grant
- ✅ 999,900 tokens available
- ✅ Authentication working

**How to Use:**
```typescript
import { createEigenAIClient } from "./eigenai.js";

const client = createEigenAIClient(
  "0x<your_private_key>",
  "0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd"
);

const response = await client.chatCompletions("Hello!");
```

## For UI Components

If your UI component requires a traditional API key format, you have two options:

### A. Update UI to Support Wallet Auth

Modify the UI to:
1. Connect wallet
2. Get grant message
3. Sign message
4. Use grant-based authentication

### B. Create API Key Proxy

Create a backend service that:
1. Accepts wallet-based auth
2. Generates a session token/API key
3. Maps it to your wallet grant
4. Proxies requests to EigenAI

### C. Get API Key from Onboarding

Visit https://onboarding.eigencloud.xyz/ and request an API key if available.

## Current Status

✅ **Wallet-based authentication is working**
- Grant active: 999,900 tokens
- Test API call successful
- Ready for backend integration

⚠️ **For UI components:**
- Check onboarding.eigencloud.xyz for API key
- Or update UI to use wallet-based auth
- Or create a proxy service

## Quick Reference

**Direct EigenAI Endpoints:**
- Mainnet: `https://eigenai.eigencloud.xyz/v1/chat/completions`
- Sepolia: `https://eigenai-sepolia.eigencloud.xyz/v1/chat/completions`

**Grant API Endpoints:**
- Server: `https://determinal-api.eigenarcade.com`
- Get message: `/message?address=YOUR_ADDRESS`
- Check grant: `/checkGrant?address=YOUR_ADDRESS`
- Chat completions: `/api/chat/completions`

## Next Steps

1. **For Backend/Compute App:** ✅ Already set up with wallet auth
2. **For UI/Frontend:** 
   - Visit https://onboarding.eigencloud.xyz/ to get API key
   - Or implement wallet connection in UI
   - Or use the backend proxy approach

