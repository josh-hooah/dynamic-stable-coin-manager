# End-to-End Workflow

This document is the canonical walkthrough for proving the full Dynamic Stable Manager lifecycle.

## Objective

Show, with reproducible commands and artifacts, that the system:

- deploys deterministically
- enforces regime-based policy deterministically
- tightens controls under stress
- exposes a usable operator flow in the frontend
- emits verifiable transaction evidence on testnet

## Perspectives

System perspective:
- deployment, configuration, policy evaluation, guardrail enforcement, and regression checks.

User perspective:
- connect wallet, set policy, run normal/stress flows, inspect regime outputs, verify tx receipts.

## Workflow Phases

### 1. Preflight and assumptions

Command:

```bash
make demo-workflow
```

What happens:
- checks for Reactive runtime integration in executable code paths
- confirms trust assumptions and network wiring from `.env`

Evidence:
- terminal log block `Phase 1/7`

### 2. Coverage gate

What happens:
- runs `scripts/verify_coverage.sh`
- enforces 100% line and branch coverage for tracked production contracts

Evidence:
- terminal log: `Coverage verification passed`
- `lcov.info`

### 3. Local lifecycle simulation

What happens:
- runs local scenario script (`scripts/demo-local.sh`)
- executes normal-path and stress-path swaps against the local mock manager/hook
- outputs counts of allowed vs blocked swaps and effective fee behavior

Evidence:
- terminal logs from `DemoLocalScript`
- dry-run transaction file under `broadcast/DemoLocal.s.sol/31337/dry-run/`

### 4. Stress regression tests

What happens:
- runs integration stress tests (`scripts/demo-stress.sh`)
- verifies managed lifecycle behavior in tests

Evidence:
- passing integration test output

### 5. Unichain deployment check and deploy

What happens:
- checks whether controller/hook are already deployed and have bytecode
- deploys if missing (`scripts/deploy-unichain.sh`)
- writes deployed addresses into `.env`

Evidence:
- deployment tx hashes
- explorer URLs (`https://sepolia.uniscan.xyz/tx/<hash>`)
- updated `.env` keys:
  - `STABLE_POLICY_CONTROLLER_ADDRESS`
  - `DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS`

### 6. Unichain policy demo

What happens:
- runs `script/DemoUnichain.s.sol`
- applies/upgrades pool policy config on testnet
- prints deterministic regime outputs for normal/soft/hard/volatility-forced scenarios
- prints preview policy output from hook read path

Evidence:
- tx hash(es) from `broadcast/DemoUnichain.s.sol/1301/run-latest.json`
- explorer URL printout from `scripts/demo-testnet.sh`

### 7. Frontend operator walkthrough

What happens:
- maps user button clicks to on-chain actions and reads
- confirms where to paste addresses and how to verify outcomes against receipts

Evidence:
- operator checklist in script output
- frontend reads matching controller/hook state

## Judge/Reviewer Checklist

- Did coverage pass at 100%? (`make coverage`)
- Did local normal/stress show both allowed and blocked outcomes? (`make demo-local`)
- Did integration stress tests pass? (`make demo-stress`)
- Are Unichain controller/hook deployed and recorded in `.env`? (`make demo-testnet`)
- Are tx hashes and explorer links printed for verification? (`make demo-testnet`)
- Can a user follow the frontend flow and observe matching policy state? (`make demo-workflow`)

## Single-command proof run

```bash
make demo-workflow
```

This is the primary command for end-to-end system proof.

## Latest Testnet Evidence (March 12, 2026)

Deployed contracts used by the workflow:
- `STABLE_POLICY_CONTROLLER_ADDRESS=0x3af9941a36beb758c31beea2774ad7abadfc0b1f`
- `DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS=0x3de5b7d2b4af038c738784f29ba3095020bd80c0`

Deployment txs:
- `https://sepolia.uniscan.xyz/tx/0xd97ae06b49d4803585c7a21fcb2b8ea7d6175e42633851cedd499fbb0f659baa`
- `https://sepolia.uniscan.xyz/tx/0x99ac7c9a89f2798f9cbd6bd69b1a0623fcf5d05c6ab85caaaa864792e42c7f99`

Latest policy-demo tx:
- `https://sepolia.uniscan.xyz/tx/0xdbaf941b4e1d9924a9e9387c7965e72da4e8943e897a40ebb9d5e9cdbc8df971`
