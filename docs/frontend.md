# Frontend

Location: `frontend/`

Stack:
- React + TypeScript + Vite
- `viem` for EVM calls
- shared ABIs/types from `/shared`

Capabilities:
- set addresses (pool manager/controller/hook)
- configure policy (`setPoolConfig`)
- run normal and stress demos (mock manager slot0 mutation)
- preview active regime and effective constraints

Run locally (with Node/pnpm installed):

```bash
pnpm --dir frontend dev
```
