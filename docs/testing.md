# Testing

Test suites:
- unit tests: policy math, controller, hook behavior
- edge tests: band boundaries, cooldown boundaries, invalid config, unauthorized updates
- fuzz tests: deterministic regime, bounds invariants, disabled policy behavior
- integration-style tests: managed lifecycle normal -> stress path

Commands:

```bash
make test
make fuzz
make test-integration
make coverage
```

CI enforces:
- dependency pin integrity
- format check
- build + test + coverage
