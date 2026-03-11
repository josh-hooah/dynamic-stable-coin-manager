# Policy Model

## Inputs

- `deviationTicks = abs(currentTick - pegTick)`
- `volatilityProxy = abs(currentTick - previousTick)`
- `imbalanceProxy = abs(netFlowAccumulator)`

## Regimes

- `NORMAL`: inside band1
- `SOFT_DEPEG`: outside band1, not beyond band2
- `HARD_DEPEG`: outside band2 or proxy threshold breach

## Hysteresis

Used to reduce flapping around thresholds:
- soft exits at `band1 - hysteresis`
- hard exits at `band2 - hysteresis`

## Constraints

By regime:
- fee schedule (`feeNormalBps`, `feeSoftBps`, `feeHardBps`)
- `maxSwapSoft`, `maxSwapHard`
- `maxImpactBpsSoft`, `maxImpactBpsHard`
- `cooldownSecondsHard`
