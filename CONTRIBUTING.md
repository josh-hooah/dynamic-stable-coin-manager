# Contributing

## Setup

```bash
make bootstrap
make build
make test
```

## Workflow

1. Create a feature branch.
2. Add tests for behavior changes.
3. Keep dependency versions pinned.
4. Run `make ci` before opening PR.

## Commit Style

Use conventional commit prefixes:
- `feat:`
- `fix:`
- `test:`
- `docs:`
- `chore:`

## Security-sensitive Changes

Any change affecting hook permissions, fee logic, guardrails, or access control must include:
- threat analysis
- regression tests
- migration/rollout notes
