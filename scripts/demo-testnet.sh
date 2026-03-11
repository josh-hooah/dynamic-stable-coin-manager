#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${UNICHAIN_SEPOLIA_RPC_URL:?UNICHAIN_SEPOLIA_RPC_URL is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
: "${POOL_MANAGER:?POOL_MANAGER is required}"

EXPLORER_PREFIX="${UNICHAIN_SEPOLIA_EXPLORER_TX_PREFIX:-https://sepolia.uniscan.xyz/tx/}"

print_phase() {
  printf "\n========== %s ==========\n" "$1"
}

is_deployed() {
  local addr="$1"
  if [[ -z "$addr" ]]; then
    return 1
  fi
  local code
  code="$(cast code "$addr" --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" 2>/dev/null || echo "0x")"
  [[ "$code" != "0x" ]]
}

print_phase "Phase 1/4 - Deployment Check"
if is_deployed "${STABLE_POLICY_CONTROLLER_ADDRESS:-}" && is_deployed "${DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS:-}"; then
  echo "Using existing Unichain deployment from .env"
  echo "  STABLE_POLICY_CONTROLLER_ADDRESS=${STABLE_POLICY_CONTROLLER_ADDRESS}"
  echo "  DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS=${DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS}"
else
  echo "Missing deployment or bytecode not found. Deploying now..."
  ./scripts/deploy-unichain.sh

  # shellcheck disable=SC1091
  source .env
fi

print_phase "Phase 2/4 - On-Chain Policy Demo"
forge script script/DemoUnichain.s.sol:DemoUnichainScript \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
  --broadcast \
  -vv

RUN_JSON="$(ls -t broadcast/DemoUnichain.s.sol/1301/run-*.json | head -n 1)"

if [[ ! -f "$RUN_JSON" ]]; then
  echo "No broadcast JSON found under broadcast/DemoUnichain.s.sol/1301" >&2
  exit 1
fi

print_phase "Phase 3/4 - Transaction Proof"
echo "Demo transactions + explorer URLs:"
jq -r '.transactions[] | [(.hash // ""), (.transactionType // ""), (.contractName // .contractAddress // ""), (.function // "") ] | @tsv' "$RUN_JSON" \
  | while IFS=$'\t' read -r hash tx_type target function_name; do
      if [[ -n "$hash" ]]; then
        echo "  hash=$hash"
        echo "    type=$tx_type target=$target function=$function_name"
        echo "    url=${EXPLORER_PREFIX}${hash}"
      fi
    done

print_phase "Phase 4/4 - User Perspective Walkthrough"
echo "1) Open frontend console and paste addresses from .env"
echo "2) Connect wallet and set RPC to Unichain Sepolia"
echo "3) Click 'Configure Peg Bands + Fee Policy' to mirror setPoolConfig"
echo "4) Click 'Refresh Effective Regime' to read current policy view"
echo "5) Use local demo/stress for full swap-guard lifecycle proof"

echo
echo "Completed Unichain demo workflow."
