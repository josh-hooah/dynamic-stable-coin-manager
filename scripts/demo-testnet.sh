#!/usr/bin/env bash
set -euo pipefail

: "${BASE_SEPOLIA_RPC_URL:?BASE_SEPOLIA_RPC_URL is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
: "${POOL_MANAGER:?POOL_MANAGER is required}"

forge script script/DeployBaseSepolia.s.sol:DeployBaseSepoliaScript \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --broadcast \
  -vv

RUN_JSON="$(ls -t broadcast/DeployBaseSepolia.s.sol/84532/run-*.json | head -n 1)"

if [[ -f "$RUN_JSON" ]]; then
  echo "Recent txs:"
  jq -r '.transactions[]?.hash' "$RUN_JSON" | while read -r hash; do
    if [[ -n "$hash" ]]; then
      echo "$hash https://sepolia.basescan.org/tx/$hash"
    fi
  done
else
  echo "No broadcast JSON found under broadcast/DeployBaseSepolia.s.sol/84532"
fi
