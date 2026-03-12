# Demo Guide

## Full workflow (recommended)

```bash
make demo-workflow
```

Detailed walkthrough:
- `docs/e2e-workflow.md`

Phases included:
- preflight assumptions (including reactive integration check)
- 100% coverage gate
- local lifecycle swaps
- stress regression
- Unichain deployment check/deploy
- Unichain policy demo with explorer-linked tx hashes
- operator/user walkthrough mapping frontend actions to tx flow

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
UNICHAIN_SEPOLIA_RPC_URL=... PRIVATE_KEY=... POOL_MANAGER=... make demo-testnet
```

Output includes tx hashes and explorer links.
