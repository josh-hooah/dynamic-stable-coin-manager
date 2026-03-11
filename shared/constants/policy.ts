export const DEFAULT_POLICY = {
  enabled: true,
  pegTick: 0,
  band1Ticks: 10,
  band2Ticks: 25,
  feeNormalBps: 5,
  feeSoftBps: 25,
  feeHardBps: 80,
  maxSwapSoft: 1_000_000n * 10n ** 6n,
  maxSwapHard: 250_000n * 10n ** 6n,
  maxImpactBpsSoft: 80,
  maxImpactBpsHard: 25,
  cooldownSecondsHard: 60,
  hysteresisTicks: 2,
  flowWindowSeconds: 120,
  volatilityHardThreshold: 50,
  imbalanceHardThreshold: 10_000_000n * 10n ** 6n,
  minUpdateInterval: 0,
  policyNonce: 1
} as const;

export const REGIME_LABELS: Record<number, string> = {
  0: "NORMAL",
  1: "SOFT_DEPEG",
  2: "HARD_DEPEG"
};

export const REASON_LABELS: Record<number, string> = {
  0: "NORMAL",
  1: "SOFT_DEPEG",
  2: "HARD_DEPEG",
  3: "COOLDOWN",
  4: "MAX_SWAP_EXCEEDED",
  5: "IMPACT_TOO_HIGH",
  6: "CONFIG_DISABLED"
};
