// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {StablePolicyController} from "../src/StablePolicyController.sol";
import {PolicyMath} from "../src/libraries/PolicyMath.sol";

contract StablePolicyControllerTest is Test {
    StablePolicyController internal controller;
    PoolId internal poolId = PoolId.wrap(bytes32(uint256(1)));

    address internal owner = address(this);
    address internal poolAdmin = address(0xA11CE);

    function setUp() external {
        controller = new StablePolicyController(owner, 0, 0);
    }

    function _baseConfig(
        uint64 nonce
    ) internal view returns (StablePolicyController.PoolConfig memory cfg) {
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = 10;
        cfg.band2Ticks = 25;
        cfg.feeNormalBps = 5;
        cfg.feeSoftBps = 30;
        cfg.feeHardBps = 100;
        cfg.maxSwapSoft = 1_000e6;
        cfg.maxSwapHard = 250e6;
        cfg.maxImpactBpsSoft = 40;
        cfg.maxImpactBpsHard = 15;
        cfg.cooldownSecondsHard = 30;
        cfg.hysteresisTicks = 3;
        cfg.flowWindowSeconds = 120;
        cfg.volatilityHardThreshold = 60;
        cfg.imbalanceHardThreshold = 1_000_000e6;
        cfg.admin = poolAdmin;
        cfg.minUpdateInterval = 0;
        cfg.policyNonce = nonce;
        cfg.lastUpdatedAt = 0;
    }

    function test_SetPoolConfigStoresAndCanReadBack() external {
        controller.setPoolConfig(poolId, _baseConfig(1));

        StablePolicyController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
        assertTrue(cfg.enabled);
        assertEq(cfg.band1Ticks, 10);
        assertEq(cfg.policyNonce, 1);
        assertGt(cfg.lastUpdatedAt, 0);
    }

    function test_ConstructorRevertsWhenInitialOwnerIsZero() external {
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        new StablePolicyController(address(0), 0, 0);
    }

    function test_SetOwnerUpdatesOwner() external {
        address nextOwner = address(0xB0B);
        controller.setOwner(nextOwner);
        assertEq(controller.owner(), nextOwner);
    }

    function test_SetOwnerRevertsWhenZeroAddress() external {
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setOwner(address(0));
    }

    function test_OnlyOwnerGateIsEnforcedForOwnerFunctions() external {
        vm.prank(address(0xBEEF));
        vm.expectRevert(StablePolicyController.Unauthorized.selector);
        controller.setOwner(address(0xCAFE));

        vm.prank(address(0xBEEF));
        vm.expectRevert(StablePolicyController.Unauthorized.selector);
        controller.setTimelockSeconds(1);

        vm.prank(address(0xBEEF));
        vm.expectRevert(StablePolicyController.Unauthorized.selector);
        controller.setGlobalMinUpdateInterval(1);
    }

    function test_PoolAdminCanUpdatePoolConfig() external {
        controller.setPoolConfig(poolId, _baseConfig(1));

        StablePolicyController.PoolConfig memory cfg = _baseConfig(2);
        vm.prank(poolAdmin);
        controller.setPoolConfig(poolId, cfg);

        assertEq(controller.getPoolConfig(poolId).policyNonce, 2);
    }

    function test_RevertWhenBand2NotGreaterThanBand1() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        cfg.band2Ticks = cfg.band1Ticks;
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertWhenFeeOrderingInvalid() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        cfg.feeSoftBps = 2;
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertOnUnauthorizedAdminUpdate() external {
        controller.setPoolConfig(poolId, _baseConfig(1));

        StablePolicyController.PoolConfig memory cfg = _baseConfig(2);
        vm.prank(address(0xBEEF));
        vm.expectRevert(StablePolicyController.Unauthorized.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertOnUnauthorizedUpdateWhenPoolAdminUnset() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        vm.prank(address(0xBEEF));
        vm.expectRevert(StablePolicyController.Unauthorized.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertOnNonceMismatch() external {
        controller.setPoolConfig(poolId, _baseConfig(1));

        StablePolicyController.PoolConfig memory cfg = _baseConfig(99);
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertWhenTimelockEnabledAndSetPoolConfigCalledDirectly() external {
        controller.setTimelockSeconds(60);
        vm.expectRevert(StablePolicyController.TimelockEnabled.selector);
        controller.setPoolConfig(poolId, _baseConfig(1));
    }

    function test_QueueRevertsWhenTimelockDisabled() external {
        vm.expectRevert(StablePolicyController.TimelockDisabled.selector);
        controller.queuePoolConfig(poolId, _baseConfig(1));
    }

    function test_ExecuteRevertsWhenTimelockDisabled() external {
        vm.expectRevert(StablePolicyController.TimelockDisabled.selector);
        controller.executeQueuedPoolConfig(poolId, _baseConfig(1));
    }

    function test_DeriveRegimeReturnsDisabledReasonWhenConfigDisabled() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        cfg.enabled = false;
        controller.setPoolConfig(poolId, cfg);

        (, PolicyMath.ReasonCode reason,, uint16 feeBps,,,) =
            controller.deriveRegime(poolId, 10, 0, 0, PolicyMath.Regime.NORMAL);
        assertEq(uint8(reason), uint8(PolicyMath.ReasonCode.CONFIG_DISABLED));
        assertEq(feeBps, 0);
    }

    function test_TimelockQueueAndExecute() external {
        controller.setTimelockSeconds(60);

        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        controller.queuePoolConfig(poolId, cfg);

        vm.expectRevert(StablePolicyController.PendingConfigNotReady.selector);
        controller.executeQueuedPoolConfig(poolId, cfg);

        vm.warp(block.timestamp + 61);
        controller.executeQueuedPoolConfig(poolId, cfg);

        StablePolicyController.PoolConfig memory applied = controller.getPoolConfig(poolId);
        assertEq(applied.policyNonce, 1);
    }

    function test_ExecuteQueuedConfigRevertsOnHashMismatch() external {
        controller.setTimelockSeconds(60);

        StablePolicyController.PoolConfig memory queued = _baseConfig(1);
        controller.queuePoolConfig(poolId, queued);

        StablePolicyController.PoolConfig memory altered = _baseConfig(1);
        altered.feeHardBps = 120;

        vm.warp(block.timestamp + 61);
        vm.expectRevert(StablePolicyController.PendingConfigMismatch.selector);
        controller.executeQueuedPoolConfig(poolId, altered);
    }

    function test_GetPoolConfigByIdAndPendingConfigViews() external {
        controller.setTimelockSeconds(60);
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        controller.queuePoolConfig(poolId, cfg);

        bytes32 poolIdRaw = PoolId.unwrap(poolId);
        StablePolicyController.PendingConfig memory pending = controller.getPendingConfig(poolIdRaw);
        assertEq(pending.policyNonce, 1);
        assertGt(pending.eta, block.timestamp);

        vm.warp(block.timestamp + 61);
        controller.executeQueuedPoolConfig(poolId, cfg);

        StablePolicyController.PoolConfig memory byId = controller.getPoolConfigById(poolIdRaw);
        assertEq(byId.policyNonce, 1);
    }

    function test_RevertWhenMaxImpactBpsAboveMax() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        cfg.maxImpactBpsSoft = 10_001;
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertWhenMaxSwapHardIsGreaterThanMaxSwapSoft() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        cfg.maxSwapSoft = 50;
        cfg.maxSwapHard = 51;
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_RevertWhenFlowWindowSecondsIsZero() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(1);
        cfg.flowWindowSeconds = 0;
        vm.expectRevert(StablePolicyController.InvalidConfig.selector);
        controller.setPoolConfig(poolId, cfg);
    }

    function test_UpdateFrequencyCapEnforced() external {
        controller.setGlobalMinUpdateInterval(100);
        controller.setPoolConfig(poolId, _baseConfig(1));

        StablePolicyController.PoolConfig memory cfg = _baseConfig(2);

        vm.expectRevert(
            abi.encodeWithSelector(StablePolicyController.UpdateTooFrequent.selector, block.timestamp + 100)
        );
        controller.setPoolConfig(poolId, cfg);

        vm.warp(block.timestamp + 100);
        controller.setPoolConfig(poolId, cfg);
        assertEq(controller.getPoolConfig(poolId).policyNonce, 2);
    }
}
