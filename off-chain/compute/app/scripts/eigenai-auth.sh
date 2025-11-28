#!/usr/bin/env bash
# Helper script to get and sign EigenAI grant message

set -e

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Default to deployer address if not set
WALLET_ADDRESS="${WALLET_ADDRESS:-0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd}"
PRIVATE_KEY="${PRIVATE_KEY:-885193e06bfcfbff6348f1b9caf486a18c2b927e66382223d7c1cafa9858bb72}"

echo "🔐 EigenAI Grant Authentication"
echo "================================"
echo "Wallet: $WALLET_ADDRESS"
echo ""

# Step 1: Get grant message
echo "📨 Step 1: Getting grant message..."
GRANT_RESPONSE=$(curl -s "https://determinal-api.eigenarcade.com/message?address=$WALLET_ADDRESS")
GRANT_MESSAGE=$(echo "$GRANT_RESPONSE" | jq -r '.message')

if [ "$GRANT_MESSAGE" == "null" ] || [ -z "$GRANT_MESSAGE" ]; then
  echo "❌ Failed to get grant message"
  echo "Response: $GRANT_RESPONSE"
  exit 1
fi

echo "✅ Grant message received:"
echo "   $GRANT_MESSAGE"
echo ""

# Step 2: Sign the message
echo "✍️  Step 2: Signing message..."
SIGNATURE=$(cast wallet sign --private-key "$PRIVATE_KEY" "$GRANT_MESSAGE")

if [ -z "$SIGNATURE" ]; then
  echo "❌ Failed to sign message"
  exit 1
fi

echo "✅ Message signed:"
echo "   $SIGNATURE"
echo ""

# Step 3: Check grant status
echo "🔍 Step 3: Checking grant status..."
GRANT_STATUS=$(curl -s "https://determinal-api.eigenarcade.com/checkGrant?address=$WALLET_ADDRESS")
TOKEN_COUNT=$(echo "$GRANT_STATUS" | jq -r '.tokenCount')
HAS_GRANT=$(echo "$GRANT_STATUS" | jq -r '.hasGrant')

echo "Grant Status:"
echo "  Has Grant: $HAS_GRANT"
echo "  Token Count: $TOKEN_COUNT"
echo ""

# Step 4: Test API call
if [ "$HAS_GRANT" == "true" ] && [ "$TOKEN_COUNT" -gt 0 ]; then
  echo "🧪 Step 4: Testing EigenAI API call..."
  TEST_RESPONSE=$(curl -s -X POST https://determinal-api.eigenarcade.com/api/chat/completions \
    -H "Content-Type: application/json" \
    -d "{
      \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}],
      \"model\": \"gpt-oss-120b-f16\",
      \"max_tokens\": 50,
      \"seed\": 42,
      \"grantMessage\": \"$GRANT_MESSAGE\",
      \"grantSignature\": \"$SIGNATURE\",
      \"walletAddress\": \"$WALLET_ADDRESS\"
    }")
  
  ERROR=$(echo "$TEST_RESPONSE" | jq -r '.error // empty')
  if [ -n "$ERROR" ]; then
    echo "❌ API call failed:"
    echo "$TEST_RESPONSE" | jq .
    exit 1
  fi
  
  CONTENT=$(echo "$TEST_RESPONSE" | jq -r '.choices[0].message.content')
  TOKENS_USED=$(echo "$TEST_RESPONSE" | jq -r '.usage.total_tokens')
  
  echo "✅ API call successful!"
  echo "   Response: ${CONTENT:0:100}..."
  echo "   Tokens used: $TOKENS_USED"
  echo ""
else
  echo "⚠️  No active grant found. Visit https://determinal.eigenarcade.com to get free tokens."
  echo ""
fi

# Export for use in other scripts
export GRANT_MESSAGE
export GRANT_SIGNATURE="$SIGNATURE"
export WALLET_ADDRESS

echo "✅ Authentication complete!"
echo ""
echo "You can now use these in your API calls:"
echo "  GRANT_MESSAGE=\"$GRANT_MESSAGE\""
echo "  GRANT_SIGNATURE=\"$SIGNATURE\""
echo "  WALLET_ADDRESS=\"$WALLET_ADDRESS\""

