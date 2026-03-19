// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {PolicyMath} from "../src/libraries/PolicyMath.sol";
import {StablePolicyController} from "../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../src/DynamicStableManagerHook.sol";
import {MockPoolManager} from "../src/mocks/MockPoolManager.sol";

contract DynamicStableManagerHookTest is Test {
    using PoolIdLibrary for PoolKey;

    event PolicyTriggered(bytes32 indexed poolId, uint8 regime, uint8 reasonCode);

    MockPoolManager internal manager;
    StablePolicyController internal controller;
    DynamicStableManagerHook internal hook;

    PoolKey internal key;
    PoolId internal poolId;

    function setUp() external {
        manager = new MockPoolManager();
        controller = new StablePolicyController(address(this), 0, 0);
        hook = _deployHook(IPoolManager(address(manager)), controller);

        key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: hook
        });
        poolId = key.toId();

        manager.setSlot0(poolId, uint160(1e18), 0, 0, 0);

        controller.setPoolConfig(poolId, _baseConfig(1));
    }

    function _deployHook(
        IPoolManager poolManager,
        StablePolicyController policyController
    ) internal returns (DynamicStableManagerHook deployedHook) {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, policyController);
        (address expectedHookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(DynamicStableManagerHook).creationCode, constructorArgs);
        deployedHook = new DynamicStableManagerHook{salt: salt}(poolManager, policyController);
        assertEq(address(deployedHook), expectedHookAddress, "hook-address-mismatch");
    }

    function _baseConfig(
        uint64 nonce
    ) internal view returns (StablePolicyController.PoolConfig memory cfg) {
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = 10;
        cfg.band2Ticks = 25;
        cfg.feeNormalBps = 5;
        cfg.feeSoftBps = 25;
        cfg.feeHardBps = 100;
        cfg.maxSwapSoft = 500e6;
        cfg.maxSwapHard = 100e6;
        cfg.maxImpactBpsSoft = 60;
        cfg.maxImpactBpsHard = 20;
        cfg.cooldownSecondsHard = 120;
        cfg.hysteresisTicks = 2;
        cfg.flowWindowSeconds = 120;
        cfg.volatilityHardThreshold = 40;
        cfg.imbalanceHardThreshold = 2_000e6;
        cfg.admin = address(this);
        cfg.minUpdateInterval = 0;
        cfg.policyNonce = nonce;
    }

    function _swapParams(
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal pure returns (SwapParams memory params) {
        params = SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: sqrtPriceLimitX96});
    }

    function test_PermissionAddressValidationRevertsForProductionHookDeployedWithoutMinedAddress() external {
        vm.expectRevert();
        new DynamicStableManagerHook(IPoolManager(address(manager)), controller);
    }

    function test_ConstructorRevertsWhenControllerIsZeroAddress() external {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(IPoolManager(address(manager)), StablePolicyController(address(0)));
        (, bytes32 salt) = HookMiner.find(address(this), flags, type(DynamicStableManagerHook).creationCode, constructorArgs);
        vm.expectRevert(DynamicStableManagerHook.ControllerZeroAddress.selector);
        new DynamicStableManagerHook{salt: salt}(IPoolManager(address(manager)), StablePolicyController(address(0)));
    }

    function test_GetHookPermissionsEnablesOnlySwapCallbacks() external view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);

        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }

    function test_BeforeSwapWithStaticFeePoolReturnsNoOverride() external {
        PoolKey memory staticFeeKey = key;
        staticFeeKey.fee = 500;

        vm.prank(address(manager));
        (, BeforeSwapDelta delta, uint24 feeOverride) =
            hook.beforeSwap(address(this), staticFeeKey, _swapParams(-100e6, uint160(0.999e18)), bytes(""));

        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(feeOverride, 0);
    }

    function test_BeforeSwapRevertsWhenReentrancyLockIsSet() external {
        vm.store(address(hook), bytes32(uint256(1)), bytes32(uint256(1)));

        vm.prank(address(manager));
        vm.expectRevert();
        hook.beforeSwap(address(this), key, _swapParams(-100e6, uint160(0.999e18)), bytes(""));
    }

    function test_BeforeSwapInNormalRegimeReturnsDynamicFeeOverride() external {
        vm.expectEmit(true, false, false, true, address(hook));
        emit PolicyTriggered(
            PoolId.unwrap(poolId), uint8(PolicyMath.Regime.NORMAL), uint8(PolicyMath.ReasonCode.NORMAL)
        );

        vm.prank(address(manager));
        (bytes4 selector, BeforeSwapDelta delta, uint24 feeOverride) =
            hook.beforeSwap(address(this), key, _swapParams(-100e6, uint160(0.999e18)), bytes(""));

        assertEq(selector, hook.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);

        uint24 expected = uint24(5 * 100) | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        assertEq(feeOverride, expected);
    }

    function test_RevertsWhenSoftMaxSwapExceeded() external {
        manager.setSlot0(poolId, uint160(1e18), 15, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(
            abi.encodeWithSelector(DynamicStableManagerHook.MaxSwapExceeded.selector, uint256(500e6), uint256(501e6))
        );
        hook.beforeSwap(address(this), key, _swapParams(-501e6, uint160(0.998e18)), bytes(""));
    }

    function test_RevertsWhenEstimatedImpactExceedsHardLimit() external {
        manager.setSlot0(poolId, uint160(1e18), 50, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(
            abi.encodeWithSelector(DynamicStableManagerHook.ImpactTooHigh.selector, uint16(20), uint16(1500))
        );
        hook.beforeSwap(address(this), key, _swapParams(-10e6, uint160(0.85e18)), bytes(""));
    }

    function test_HardCooldownBlocksBackToBackSwaps() external {
        manager.setSlot0(poolId, uint160(1e18), 40, 0, 0);

        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, _swapParams(-10e6, uint160(0.9995e18)), bytes(""));

        vm.prank(address(manager));
        vm.expectRevert(abi.encodeWithSelector(DynamicStableManagerHook.CooldownActive.selector, block.timestamp + 120));
        hook.beforeSwap(address(this), key, _swapParams(-10e6, uint160(0.9995e18)), bytes(""));
    }

    function test_DisabledConfigSkipsEnforcement() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(2);
        cfg.enabled = false;
        controller.setPoolConfig(poolId, cfg);

        manager.setSlot0(poolId, uint160(1e18), 80, 0, 0);

        vm.prank(address(manager));
        (, BeforeSwapDelta delta, uint24 feeOverride) =
            hook.beforeSwap(address(this), key, _swapParams(-2_000e6, uint160(0.1e18)), bytes(""));

        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(feeOverride, 0);
    }

    function test_PreviewSwapPolicy_ConfigDisabledReturnsDisabledReason() external {
        StablePolicyController.PoolConfig memory cfg = _baseConfig(2);
        cfg.enabled = false;
        controller.setPoolConfig(poolId, cfg);

        DynamicStableManagerHook.PolicyPreview memory preview = hook.previewSwapPolicy(
            key, _swapParams(-100e6, uint160(0.999e18))
        );

        assertEq(uint8(preview.regime), uint8(PolicyMath.Regime.NORMAL));
        assertEq(uint8(preview.reasonCode), uint8(PolicyMath.ReasonCode.CONFIG_DISABLED));
        assertTrue(preview.dynamicFeeOverrideEnabled);
        assertFalse(preview.wouldRevert);
    }

    function test_PreviewSwapPolicy_NormalSoftHardSelections() external {
        manager.setSlot0(poolId, uint160(1e18), 5, 0, 0);
        DynamicStableManagerHook.PolicyPreview memory normalPreview = hook.previewSwapPolicy(
            key, _swapParams(-100e6, uint160(0.999e18))
        );
        assertEq(uint8(normalPreview.regime), uint8(PolicyMath.Regime.NORMAL));
        assertEq(normalPreview.selectedFeeBps, 5);
        assertEq(normalPreview.maxSwap, 0);
        assertEq(normalPreview.maxImpactBps, 0);
        assertFalse(normalPreview.wouldRevert);

        manager.setSlot0(poolId, uint160(1e18), 15, 0, 0);
        DynamicStableManagerHook.PolicyPreview memory softPreview = hook.previewSwapPolicy(
            key, _swapParams(-501e6, uint160(0.999e18))
        );
        assertEq(uint8(softPreview.regime), uint8(PolicyMath.Regime.SOFT_DEPEG));
        assertEq(softPreview.selectedFeeBps, 25);
        assertEq(softPreview.maxSwap, 500e6);
        assertEq(softPreview.maxImpactBps, 60);
        assertTrue(softPreview.wouldRevert);

        manager.setSlot0(poolId, uint160(1e18), 50, 0, 0);
        DynamicStableManagerHook.PolicyPreview memory hardPreview = hook.previewSwapPolicy(
            key, _swapParams(-10e6, uint160(0.85e18))
        );
        assertEq(uint8(hardPreview.regime), uint8(PolicyMath.Regime.HARD_DEPEG));
        assertEq(hardPreview.selectedFeeBps, 100);
        assertEq(hardPreview.maxSwap, 100e6);
        assertEq(hardPreview.maxImpactBps, 20);
        assertTrue(hardPreview.wouldRevert);
    }

    function test_PreviewSwapPolicy_UsesFlowWindowAccumulatorAndReset() external {
        manager.setSlot0(poolId, uint160(1e18), 5, 0, 0);

        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, _swapParams(-100e6, uint160(0.999e18)), bytes(""));

        DynamicStableManagerHook.PolicyPreview memory withinWindow = hook.previewSwapPolicy(
            key, _swapParams(-75e6, uint160(0.999e18))
        );
        assertEq(uint8(withinWindow.regime), uint8(PolicyMath.Regime.NORMAL));

        vm.warp(block.timestamp + 121);
        DynamicStableManagerHook.PolicyPreview memory afterWindow = hook.previewSwapPolicy(
            key, _swapParams(-75e6, uint160(0.999e18))
        );
        assertEq(uint8(afterWindow.regime), uint8(PolicyMath.Regime.NORMAL));
    }

    function test_PreviewSwapPolicy_HardCooldownSurfacesAsWouldRevert() external {
        manager.setSlot0(poolId, uint160(1e18), 40, 0, 0);

        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, _swapParams(-50e6, uint160(0.9999e18)), bytes(""));

        DynamicStableManagerHook.PolicyPreview memory preview = hook.previewSwapPolicy(
            key, _swapParams(-50e6, uint160(0.9999e18))
        );
        assertEq(uint8(preview.regime), uint8(PolicyMath.Regime.HARD_DEPEG));
        assertTrue(preview.wouldRevert);
    }

    function test_PreviewSwapPolicy_StaticFeeKeyReportsDynamicOverrideDisabled() external {
        PoolKey memory staticFeeKey = key;
        staticFeeKey.fee = 500;
        manager.setSlot0(poolId, uint160(1e18), 5, 0, 0);

        DynamicStableManagerHook.PolicyPreview memory preview = hook.previewSwapPolicy(
            staticFeeKey, _swapParams(-100e6, uint160(0.999e18))
        );
        assertFalse(preview.dynamicFeeOverrideEnabled);
    }

    function test_AfterSwapRefreshesRuntimeTick() external {
        manager.setSlot0(poolId, uint160(1e18), 12, 0, 0);

        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, _swapParams(-100e6, uint160(0.999e18)), bytes(""));

        manager.setSlot0(poolId, uint160(1e18), 14, 0, 0);

        vm.prank(address(manager));
        hook.afterSwap(address(this), key, _swapParams(-100e6, uint160(0.999e18)), BalanceDelta.wrap(0), bytes(""));

        DynamicStableManagerHook.PoolRuntime memory runtime = hook.getRuntime(poolId);
        assertEq(runtime.lastTick, 14);
    }
}
