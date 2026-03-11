// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {StablePolicyController} from "../../src/StablePolicyController.sol";
import {PolicyMath} from "../../src/libraries/PolicyMath.sol";

contract PolicyFuzzTest is Test {
    StablePolicyController internal controller;
    PoolId internal poolId = PoolId.wrap(bytes32(uint256(999)));

    function setUp() external {
        controller = new StablePolicyController(address(this), 0, 0);
    }

    function _config(
        uint64 nonce,
        int24 band1,
        int24 band2,
        uint16 feeNormal,
        uint16 feeSoft,
        uint16 feeHard
    ) internal view returns (StablePolicyController.PoolConfig memory cfg) {
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = band1;
        cfg.band2Ticks = band2;
        cfg.feeNormalBps = feeNormal;
        cfg.feeSoftBps = feeSoft;
        cfg.feeHardBps = feeHard;
        cfg.maxSwapSoft = 1000e6;
        cfg.maxSwapHard = 250e6;
        cfg.maxImpactBpsSoft = 60;
        cfg.maxImpactBpsHard = 20;
        cfg.cooldownSecondsHard = 60;
        cfg.hysteresisTicks = 1;
        cfg.flowWindowSeconds = 120;
        cfg.volatilityHardThreshold = 0;
        cfg.imbalanceHardThreshold = 0;
        cfg.admin = address(this);
        cfg.minUpdateInterval = 0;
        cfg.policyNonce = nonce;
    }

    function testFuzz_RegimeSelectionDeterministic(
        int24 tick,
        uint256 vol,
        uint256 imbalance
    ) external {
        PolicyMath.RegimeInput memory input = PolicyMath.RegimeInput({
            pegTick: 0,
            currentTick: tick,
            band1Ticks: 10,
            band2Ticks: 20,
            hysteresisTicks: 2,
            volatilityProxy: vol % 500,
            imbalanceProxy: imbalance % 1e24,
            volatilityHardThreshold: 300,
            imbalanceHardThreshold: 9e23,
            previousRegime: PolicyMath.Regime.SOFT_DEPEG
        });

        (PolicyMath.Regime r1, PolicyMath.ReasonCode c1, uint24 d1) = PolicyMath.selectRegime(input);
        (PolicyMath.Regime r2, PolicyMath.ReasonCode c2, uint24 d2) = PolicyMath.selectRegime(input);

        assertEq(uint8(r1), uint8(r2));
        assertEq(uint8(c1), uint8(c2));
        assertEq(d1, d2);
    }

    function testFuzz_InvalidBandOrderingAlwaysReverts(
        int24 band1,
        int24 band2
    ) external {
        StablePolicyController.PoolConfig memory cfg = _config(1, band1, band2, 5, 25, 100);

        bool valid = band1 > 1 && band2 > band1;
        if (!valid) {
            vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        }

        controller.setPoolConfig(poolId, cfg);

        if (valid) {
            StablePolicyController.PoolConfig memory out = controller.getPoolConfig(poolId);
            assertGt(out.band2Ticks, out.band1Ticks);
        }
    }

    function testFuzz_FeeBoundsInvariant(
        uint16 feeNormal,
        uint16 feeSoft,
        uint16 feeHard
    ) external {
        StablePolicyController.PoolConfig memory cfg = _config(1, 10, 20, feeNormal, feeSoft, feeHard);

        bool valid =
            feeNormal <= 10_000 && feeSoft <= 10_000 && feeHard <= 10_000 && feeNormal <= feeSoft && feeSoft <= feeHard;
        if (!valid) {
            vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        }

        controller.setPoolConfig(poolId, cfg);

        if (valid) {
            StablePolicyController.PoolConfig memory out = controller.getPoolConfig(poolId);
            assertLe(out.feeNormalBps, out.feeSoftBps);
            assertLe(out.feeSoftBps, out.feeHardBps);
        }
    }

    function testFuzz_DisabledConfigNoEnforcementReason(
        int24 tick
    ) external {
        StablePolicyController.PoolConfig memory cfg = _config(1, 10, 20, 5, 25, 100);
        cfg.enabled = false;
        controller.setPoolConfig(poolId, cfg);

        (, PolicyMath.ReasonCode reason,, uint16 selectedFeeBps,,,) =
            controller.deriveRegime(poolId, tick, 0, 0, PolicyMath.Regime.NORMAL);

        assertEq(uint8(reason), uint8(PolicyMath.ReasonCode.CONFIG_DISABLED));
        assertEq(selectedFeeBps, 0);
    }

    function testFuzz_NoUnexpectedRevertsForValidConfig(
        int24 pegTick,
        int24 tick,
        int24 band1,
        int24 spread,
        uint16 feeNormal,
        uint16 feeSoft,
        uint16 feeHard
    ) external {
        band1 = int24(bound(band1, 2, 200));
        spread = int24(bound(spread, 1, 200));

        feeNormal = uint16(bound(feeNormal, 0, 200));
        feeSoft = uint16(bound(feeSoft, feeNormal, 400));
        feeHard = uint16(bound(feeHard, feeSoft, 2_000));

        StablePolicyController.PoolConfig memory cfg = _config(1, band1, band1 + spread, feeNormal, feeSoft, feeHard);
        cfg.pegTick = pegTick;

        controller.setPoolConfig(poolId, cfg);

        controller.deriveRegime(poolId, tick, 0, 0, PolicyMath.Regime.NORMAL);
    }
}
