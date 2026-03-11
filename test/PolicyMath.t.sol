// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PolicyMath} from "../src/libraries/PolicyMath.sol";

contract PolicyMathTest is Test {
    function _input(
        int24 tick,
        PolicyMath.Regime previous
    ) internal pure returns (PolicyMath.RegimeInput memory data) {
        data = PolicyMath.RegimeInput({
            pegTick: 0,
            currentTick: tick,
            band1Ticks: 10,
            band2Ticks: 20,
            hysteresisTicks: 3,
            volatilityProxy: 0,
            imbalanceProxy: 0,
            volatilityHardThreshold: 0,
            imbalanceHardThreshold: 0,
            previousRegime: previous
        });
    }

    function test_BoundaryAtBand1RemainsNormal() external {
        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(_input(10, PolicyMath.Regime.NORMAL));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.NORMAL));
    }

    function test_BoundaryAtBand2RemainsSoft() external {
        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(_input(20, PolicyMath.Regime.NORMAL));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.SOFT_DEPEG));
    }

    function test_OutsideBand2GoesHard() external {
        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(_input(21, PolicyMath.Regime.NORMAL));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.HARD_DEPEG));
    }

    function test_HysteresisKeepsSoftUntilExitBand() external {
        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(_input(8, PolicyMath.Regime.SOFT_DEPEG));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.SOFT_DEPEG));

        (regime,,) = PolicyMath.selectRegime(_input(7, PolicyMath.Regime.SOFT_DEPEG));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.NORMAL));
    }

    function test_HysteresisKeepsHardUntilExitBand() external {
        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(_input(18, PolicyMath.Regime.HARD_DEPEG));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.HARD_DEPEG));

        (regime,,) = PolicyMath.selectRegime(_input(17, PolicyMath.Regime.HARD_DEPEG));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.SOFT_DEPEG));
    }

    function test_PreviousHardCanReturnToNormalInsideBand1() external {
        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(_input(10, PolicyMath.Regime.HARD_DEPEG));
        assertEq(uint8(regime), uint8(PolicyMath.Regime.NORMAL));
    }

    function test_VolatilityProxyForcesHard() external {
        PolicyMath.RegimeInput memory data = _input(2, PolicyMath.Regime.NORMAL);
        data.volatilityProxy = 10;
        data.volatilityHardThreshold = 10;

        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(data);
        assertEq(uint8(regime), uint8(PolicyMath.Regime.HARD_DEPEG));
    }

    function test_ImbalanceProxyForcesHard() external {
        PolicyMath.RegimeInput memory data = _input(2, PolicyMath.Regime.NORMAL);
        data.imbalanceProxy = 1_000;
        data.imbalanceHardThreshold = 1_000;

        (PolicyMath.Regime regime,,) = PolicyMath.selectRegime(data);
        assertEq(uint8(regime), uint8(PolicyMath.Regime.HARD_DEPEG));
    }

    function test_ImpactEstimateAtZeroLimitReturnsZero() external {
        assertEq(PolicyMath.estimateImpactBps(1e18, 0), 0);
    }

    function test_ImpactEstimateCapsToUint16Max() external {
        assertEq(PolicyMath.estimateImpactBps(1, type(uint160).max), type(uint16).max);
    }
}
