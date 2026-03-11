# API

## StablePolicyController

- `setPoolConfig(PoolId, PoolConfig)`
- `queuePoolConfig(PoolId, PoolConfig)`
- `executeQueuedPoolConfig(PoolId, PoolConfig)`
- `getPoolConfig(PoolId)`
- `deriveRegime(PoolId, currentTick, volatilityProxy, imbalanceProxy, previousRegime)`

Events:
- `ConfigQueued(poolId, configHash, eta, policyNonce)`
- `ConfigSet(poolId, configHash, policyNonce)`

## DynamicStableManagerHook

- `beforeSwap(...)`
- `afterSwap(...)`
- `previewSwapPolicy(PoolKey, SwapParams)`
- `getRuntime(PoolId)`

Events:
- `PolicyTriggered(poolId, regime, reasonCode)`
