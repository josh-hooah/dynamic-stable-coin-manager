#!/usr/bin/env bash
set -euo pipefail

forge test --match-path test/integration/DynamicStableManager.integration.t.sol -vv
