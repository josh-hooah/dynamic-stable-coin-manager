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

## Unichain Sepolia Deploy

```bash
UNICHAIN_SEPOLIA_RPC_URL=<rpc> \
PRIVATE_KEY=<key> \
POOL_MANAGER=<v4_pool_manager> \
forge script script/DeployUnichainSepolia.s.sol:DeployUnichainSepoliaScript \
  --rpc-url $UNICHAIN_SEPOLIA_RPC_URL --broadcast -vv
```

Or run:

```bash
./scripts/deploy-unichain.sh
```

This prints tx hashes and Uniscan URLs, then stores:

- `STABLE_POLICY_CONTROLLER_ADDRESS`
- `DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS`

in `.env`.
