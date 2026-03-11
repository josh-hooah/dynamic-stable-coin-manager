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

forge script script/DeployUnichainSepolia.s.sol:DeployUnichainSepoliaScript \
  --rpc-url "$UNICHAIN_SEPOLIA_RPC_URL" \
  --broadcast \
  -vv

RUN_JSON="$(ls -t broadcast/DeployUnichainSepolia.s.sol/1301/run-*.json | head -n 1)"

if [[ ! -f "$RUN_JSON" ]]; then
  echo "No broadcast JSON found under broadcast/DeployUnichainSepolia.s.sol/1301" >&2
  exit 1
fi

echo "Recent deployment txs:"
jq -r '.transactions[]?.hash' "$RUN_JSON" | while read -r hash; do
  if [[ -n "$hash" && "$hash" != "null" ]]; then
    echo "  $hash ${EXPLORER_PREFIX}${hash}"
  fi
done

CONTROLLER_ADDR="$(jq -r '.transactions[] | select((.contractName // "") | test("StablePolicyController")) | .contractAddress' "$RUN_JSON" | tail -n 1)"
HOOK_ADDR="$(jq -r '.transactions[] | select((.contractName // "") | test("DynamicStableManagerHook$|DynamicStableManagerHook")) | .contractAddress' "$RUN_JSON" | tail -n 1)"

if [[ -z "$CONTROLLER_ADDR" || "$CONTROLLER_ADDR" == "null" ]]; then
  echo "Unable to parse StablePolicyController address from $RUN_JSON" >&2
  exit 1
fi

if [[ -z "$HOOK_ADDR" || "$HOOK_ADDR" == "null" ]]; then
  echo "Unable to parse DynamicStableManagerHook address from $RUN_JSON" >&2
  exit 1
fi

upsert_env() {
  local key="$1"
  local value="$2"
  local env_file=".env"

  if [[ ! -f "$env_file" ]]; then
    touch "$env_file"
  fi

  awk -v key="$key" -v value="$value" '
    BEGIN { updated = 0 }
    {
      if ($0 ~ ("^" key "=")) {
        print key "=" value
        updated = 1
      } else {
        print $0
      }
    }
    END {
      if (updated == 0) print key "=" value
    }
  ' "$env_file" > "${env_file}.tmp"

  mv "${env_file}.tmp" "$env_file"
}

upsert_env "STABLE_POLICY_CONTROLLER_ADDRESS" "$CONTROLLER_ADDR"
upsert_env "DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS" "$HOOK_ADDR"

echo "Stored deployment addresses in .env"
echo "  STABLE_POLICY_CONTROLLER_ADDRESS=$CONTROLLER_ADDR"
echo "  DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS=$HOOK_ADDR"
