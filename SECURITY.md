# Security Policy

## Supported Versions

This repository is pre-mainnet and actively changing.

## Reporting a Vulnerability

Report vulnerabilities privately to the maintainers before public disclosure.

Include:
- affected contract/module
- attack preconditions
- proof-of-concept steps
- estimated impact

## Threat Model Summary

- PoolManager correctness is assumed.
- Governance/admin keys are trusted to update policy.
- Hook guardrails can intentionally block swaps in stress modes.
- Misconfiguration is a real operational risk.

## Known Risk Areas

- address-bit permission mistakes during deployment
- overly strict caps causing liveness reduction
- threshold tuning around hysteresis boundaries
- governance key compromise or rushed policy edits

## Mitigation Controls

- constructor hook permission validation
- owner/admin access controls
- optional timelock and update interval controls
- strict parameter bounds
- fuzz and edge-case test coverage
