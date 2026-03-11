#!/usr/bin/env bash
set -euo pipefail

mkdir -p shared/abi

forge inspect StablePolicyController abi > shared/abi/StablePolicyController.json
forge inspect DynamicStableManagerHook abi > shared/abi/DynamicStableManagerHook.json
forge inspect MockPoolManager abi > shared/abi/MockPoolManager.json

echo "ABIs exported to shared/abi"
