#!/usr/bin/env bash
set -euo pipefail

RPC_URL="http://127.0.0.1:8545"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

anvil --silent --port 8545 >/tmp/dsm-anvil.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID >/dev/null 2>&1 || true' EXIT

sleep 2

PRIVATE_KEY="$PRIVATE_KEY" forge script script/DemoLocal.s.sol:DemoLocalScript \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vv
