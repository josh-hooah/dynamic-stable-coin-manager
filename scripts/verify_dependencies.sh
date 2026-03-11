#!/usr/bin/env bash
set -euo pipefail

EXPECTED_V4_PERIPHERY_PREFIX="3779387"

ACTUAL_V4_PERIPHERY="$(git -C lib/v4-periphery rev-parse --short HEAD)"
EXPECTED_V4_CORE="$(git -C lib/v4-periphery rev-parse :lib/v4-core)"
ACTUAL_V4_CORE="$(git -C lib/v4-core rev-parse HEAD)"

if [[ "$ACTUAL_V4_PERIPHERY" != "$EXPECTED_V4_PERIPHERY_PREFIX" ]]; then
  echo "v4-periphery HEAD mismatch. expected prefix=$EXPECTED_V4_PERIPHERY_PREFIX actual=$ACTUAL_V4_PERIPHERY" >&2
  exit 1
fi

if [[ "$ACTUAL_V4_CORE" != "$EXPECTED_V4_CORE" ]]; then
  echo "v4-core HEAD mismatch. expected=$EXPECTED_V4_CORE actual=$ACTUAL_V4_CORE" >&2
  exit 1
fi

echo "Dependency integrity verified"
