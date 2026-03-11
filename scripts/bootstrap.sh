#!/usr/bin/env bash
set -euo pipefail

EXPECTED_V4_PERIPHERY="3779387e5d296f39df543d23524b050f89a62917"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[bootstrap] Syncing submodules"
git submodule sync --recursive
git submodule update --init --recursive

echo "[bootstrap] Pinning v4-periphery to ${EXPECTED_V4_PERIPHERY}"
git -C lib/v4-periphery fetch --tags --force
git -C lib/v4-periphery checkout "$EXPECTED_V4_PERIPHERY"
git -C lib/v4-periphery submodule update --init --recursive

EXPECTED_V4_CORE="$(git -C lib/v4-periphery rev-parse :lib/v4-core)"

echo "[bootstrap] Pinning v4-core to ${EXPECTED_V4_CORE}"
git -C lib/v4-core fetch --tags --force
git -C lib/v4-core checkout "$EXPECTED_V4_CORE"

ACTUAL_V4_PERIPHERY="$(git -C lib/v4-periphery rev-parse HEAD)"
ACTUAL_V4_CORE="$(git -C lib/v4-core rev-parse HEAD)"

if [[ "$ACTUAL_V4_PERIPHERY" != "$EXPECTED_V4_PERIPHERY" ]]; then
  echo "[bootstrap] ERROR: v4-periphery mismatch: expected=$EXPECTED_V4_PERIPHERY actual=$ACTUAL_V4_PERIPHERY" >&2
  exit 1
fi

if [[ "$ACTUAL_V4_CORE" != "$EXPECTED_V4_CORE" ]]; then
  echo "[bootstrap] ERROR: v4-core mismatch: expected=$EXPECTED_V4_CORE actual=$ACTUAL_V4_CORE" >&2
  exit 1
fi

echo "[bootstrap] Dependency pin verification passed"
