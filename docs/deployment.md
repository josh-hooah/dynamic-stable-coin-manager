# Deployment

## Bootstrap

```bash
make bootstrap
```

This initializes submodules and enforces pinned Uniswap refs.

## Local Deploy

```bash
PRIVATE_KEY=<anvil_key> forge script script/DeployLocal.s.sol:DeployLocalScript \
  --rpc-url http://127.0.0.1:8545 --broadcast -vv
```

## Base Sepolia Deploy

```bash
BASE_SEPOLIA_RPC_URL=<rpc> \
PRIVATE_KEY=<key> \
POOL_MANAGER=<v4_pool_manager> \
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepoliaScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast -vv
```

Use `scripts/demo-testnet.sh` to print tx hashes with BaseScan URLs.
