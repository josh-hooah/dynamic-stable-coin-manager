# Security

## Trust Model

- PoolManager correctness is assumed.
- Controller owner/admin can change policy and can misconfigure it.

## Main Risks

- boundary griefing to induce regime flapping
- manipulation attempts to force hard regime
- policy misconfiguration causing over-restriction (DoS)
- governance key compromise

## Mitigations

- hysteresis around bands
- optional cooldown in hard regime
- config validation bounds
- nonce sequencing and update interval controls
- optional timelock workflow

## Invariants

- hook entrypoints callable only by PoolManager
- config nonce monotonic per pool
- band ordering: `band2 > band1 > 0`
- fee ordering: `normal <= soft <= hard`

Residual risk remains; system is not attack-proof.
