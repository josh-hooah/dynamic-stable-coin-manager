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

print_phase() {
  printf "\n========== %s ==========\n" "$1"
}

print_phase "Phase 1/7 - Preflight + Trust Assumptions"
REACTIVE_RUNTIME_HITS="$(rg -n "\\bIReactive\\b|\\bAbstractPausableReactive\\b|REACTIVE_RPC_URL|REACTIVE_PRIVATE_KEY|reactive-smart-contract" src script scripts frontend shared test -S --glob '!scripts/demo-workflow.sh' || true)"
if [[ -z "$REACTIVE_RUNTIME_HITS" ]]; then
  echo "Reactive runtime integration: not detected in executable code paths."
else
  echo "Reactive references found (review manually):"
  echo "$REACTIVE_RUNTIME_HITS"
fi

echo "Assumption: PoolManager on Unichain Sepolia is provided via POOL_MANAGER in .env"

echo "[USER VIEW] This phase proves what dependencies and trust assumptions exist before any transaction runs."

print_phase "Phase 2/7 - Coverage Gate (100%)"
./scripts/verify_coverage.sh

echo "[USER VIEW] This phase proves every tracked policy branch is exercised before demo execution."

print_phase "Phase 3/7 - Local Lifecycle Demo"
./scripts/demo-local.sh

LOCAL_RUN_JSON="$(ls -t broadcast/DemoLocal.s.sol/31337/run-*.json 2>/dev/null | head -n 1 || true)"
if [[ -n "$LOCAL_RUN_JSON" && -f "$LOCAL_RUN_JSON" ]]; then
  echo "Local tx hashes:"
  jq -r '.transactions[]?.hash' "$LOCAL_RUN_JSON" | sed '/^null$/d;/^$/d' | sed 's/^/  /'
fi

echo "[USER VIEW] You see NORMAL -> SOFT -> HARD behaviors with allow/deny outcomes on deterministic guardrails."

print_phase "Phase 4/7 - Stress Regression Proof"
./scripts/demo-stress.sh

echo "[USER VIEW] This phase validates depeg behavior and blocked toxic-flow paths in automated tests."

print_phase "Phase 5/7 - Unichain Deployment + Demo"
./scripts/demo-testnet.sh

echo "[USER VIEW] You now have verifiable testnet tx hashes and explorer URLs for governance + policy execution."

print_phase "Phase 6/7 - Frontend Operator Flow"
echo "1) Run frontend: pnpm --dir frontend dev"
echo "2) Paste PoolManager, Controller, Hook from .env"
echo "3) Connect wallet and configure policy"
echo "4) Run normal and stress buttons, then refresh preview"
echo "5) Compare preview regime/reason/fee with the tx logs printed above"

echo "[USER VIEW] This phase maps operator actions to on-chain state transitions and policy outcomes."

print_phase "Phase 7/7 - Artifact Summary"
echo "Coverage report: lcov.info"
echo "Local broadcast: broadcast/DemoLocal.s.sol/31337"
echo "Unichain deploy broadcast: broadcast/DeployUnichainSepolia.s.sol/1301"
echo "Unichain demo broadcast: broadcast/DemoUnichain.s.sol/1301"

echo "End-to-end demo workflow completed."
