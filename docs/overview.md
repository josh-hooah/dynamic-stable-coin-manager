# Overview

Dynamic Stablecoin Manager is a Uniswap v4 hook stack for stable pools.

Core idea:
- detect depeg risk from deterministic on-chain signals
- tighten policy under stress
- keep normal swaps cheap when peg is healthy

Components:
- `DynamicStableManagerHook`: swap-time policy enforcement
- `StablePolicyController`: governance-owned policy storage
- `PolicyMath`: deterministic regime math

No keepers, no offchain trigger network, no core oracle dependency.
