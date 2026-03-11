// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PolicyMath
/// @notice Deterministic policy math for stablecoin regime selection and guardrail calculations.
library PolicyMath {
    uint16 internal constant BPS_DENOMINATOR = 10_000;

    enum Regime {
        NORMAL,
        SOFT_DEPEG,
        HARD_DEPEG
    }

    enum ReasonCode {
        NORMAL,
        SOFT_DEPEG,
        HARD_DEPEG,
        COOLDOWN,
        MAX_SWAP_EXCEEDED,
        IMPACT_TOO_HIGH,
        CONFIG_DISABLED
    }

    struct RegimeInput {
        int24 pegTick;
        int24 currentTick;
        int24 band1Ticks;
        int24 band2Ticks;
        int24 hysteresisTicks;
        uint256 volatilityProxy;
        uint256 imbalanceProxy;
        uint256 volatilityHardThreshold;
        uint256 imbalanceHardThreshold;
        Regime previousRegime;
    }

    function absInt(
        int256 value
    ) internal pure returns (uint256) {
        return value < 0 ? uint256(-value) : uint256(value);
    }

    function absTickDistance(
        int24 a,
        int24 b
    ) internal pure returns (uint24) {
        int256 diff = int256(a) - int256(b);
        return uint24(absInt(diff));
    }

    function estimateImpactBps(
        uint160 currentSqrtPriceX96,
        uint160 sqrtPriceLimitX96
    ) internal pure returns (uint16) {
        if (currentSqrtPriceX96 == 0 || sqrtPriceLimitX96 == 0 || currentSqrtPriceX96 == sqrtPriceLimitX96) {
            return 0;
        }

        uint256 current = uint256(currentSqrtPriceX96);
        uint256 limit = uint256(sqrtPriceLimitX96);
        uint256 diff = current > limit ? current - limit : limit - current;
        uint256 bps = (diff * BPS_DENOMINATOR) / current;

        if (bps > type(uint16).max) return type(uint16).max;
        return uint16(bps);
    }

    function selectRegime(
        RegimeInput memory input
    ) internal pure returns (Regime regime, ReasonCode reasonCode, uint24 deviationTicks) {
        deviationTicks = absTickDistance(input.currentTick, input.pegTick);

        uint24 band1 = uint24(uint24(input.band1Ticks));
        uint24 band2 = uint24(uint24(input.band2Ticks));
        uint24 hyst = uint24(input.hysteresisTicks < 0 ? 0 : uint24(input.hysteresisTicks));

        uint24 softExit = hyst >= band1 ? 0 : band1 - hyst;
        uint24 hardExit = hyst >= band2 ? 0 : band2 - hyst;

        if (
            input.volatilityHardThreshold != 0 && input.volatilityProxy >= input.volatilityHardThreshold
                || input.imbalanceHardThreshold != 0 && input.imbalanceProxy >= input.imbalanceHardThreshold
        ) {
            return (Regime.HARD_DEPEG, ReasonCode.HARD_DEPEG, deviationTicks);
        }

        if (input.previousRegime == Regime.HARD_DEPEG) {
            if (deviationTicks > hardExit) return (Regime.HARD_DEPEG, ReasonCode.HARD_DEPEG, deviationTicks);
            if (deviationTicks > band1) return (Regime.SOFT_DEPEG, ReasonCode.SOFT_DEPEG, deviationTicks);
            return (Regime.NORMAL, ReasonCode.NORMAL, deviationTicks);
        }

        if (input.previousRegime == Regime.SOFT_DEPEG) {
            if (deviationTicks > band2) return (Regime.HARD_DEPEG, ReasonCode.HARD_DEPEG, deviationTicks);
            if (deviationTicks > softExit) return (Regime.SOFT_DEPEG, ReasonCode.SOFT_DEPEG, deviationTicks);
            return (Regime.NORMAL, ReasonCode.NORMAL, deviationTicks);
        }

        if (deviationTicks > band2) return (Regime.HARD_DEPEG, ReasonCode.HARD_DEPEG, deviationTicks);
        if (deviationTicks > band1) return (Regime.SOFT_DEPEG, ReasonCode.SOFT_DEPEG, deviationTicks);
        return (Regime.NORMAL, ReasonCode.NORMAL, deviationTicks);
    }
}
