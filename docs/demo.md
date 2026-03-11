# Demo Guide

## One-click local demo

```bash
make demo-local
```

Expected:
- normal swaps pass under low fee
- stress swaps trigger stricter policy
- some swaps blocked by deterministic guardrails

## Stress suite

```bash
make demo-stress
```

Runs integration path to show normal -> soft -> hard transitions and blocked transactions.

## Testnet demo

```bash
BASE_SEPOLIA_RPC_URL=... PRIVATE_KEY=... POOL_MANAGER=... make demo-testnet
```

Output includes tx hashes and explorer links.
