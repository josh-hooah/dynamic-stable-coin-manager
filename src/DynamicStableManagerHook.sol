// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {StablePolicyController} from "./StablePolicyController.sol";
import {PolicyMath} from "./libraries/PolicyMath.sol";

/// @title DynamicStableManagerHook
/// @notice Uniswap v4 swap hook that enforces deterministic stablecoin policy guardrails.
contract DynamicStableManagerHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    error ControllerZeroAddress();
    error MaxSwapExceeded(uint256 maxSwap, uint256 attemptedSwap);
    error ImpactTooHigh(uint16 maxImpactBps, uint16 estimatedImpactBps);
    error CooldownActive(uint256 nextAllowedAt);

    event PolicyTriggered(bytes32 indexed poolId, uint8 regime, uint8 reasonCode);

    struct PoolRuntime {
        int24 lastTick;
        int256 netFlowAccumulator;
        uint40 lastObservationTimestamp;
        uint40 windowStartTimestamp;
        uint40 nextHardSwapAllowedAt;
        PolicyMath.Regime lastRegime;
    }

    struct PolicyPreview {
        PolicyMath.Regime regime;
        PolicyMath.ReasonCode reasonCode;
        uint24 deviationTicks;
        uint16 selectedFeeBps;
        uint16 estimatedImpactBps;
        uint256 maxSwap;
        uint16 maxImpactBps;
        bool wouldRevert;
        bool dynamicFeeOverrideEnabled;
    }

    struct BeforeSwapContext {
        bytes32 poolIdRaw;
        StablePolicyController.PoolConfig cfg;
        uint160 sqrtPriceX96;
        int24 tick;
    }

    StablePolicyController public immutable controller;

    mapping(bytes32 poolId => PoolRuntime runtime) private _runtime;

    uint256 private _swapReentrancyLock;

    constructor(
        IPoolManager _poolManager,
        StablePolicyController _controller
    ) BaseHook(_poolManager) {
        if (address(_controller) == address(0)) revert ControllerZeroAddress();
        controller = _controller;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getRuntime(
        PoolId poolId
    ) external view returns (PoolRuntime memory) {
        return _runtime[PoolId.unwrap(poolId)];
    }

    function previewSwapPolicy(
        PoolKey calldata key,
        SwapParams calldata params
    ) external view returns (PolicyPreview memory preview) {
        PoolId poolId = key.toId();
        bytes32 poolIdRaw = PoolId.unwrap(poolId);

        StablePolicyController.PoolConfig memory cfg = controller.getPoolConfig(poolId);
        if (!cfg.enabled) {
            preview.regime = _runtime[poolIdRaw].lastRegime;
            preview.reasonCode = PolicyMath.ReasonCode.CONFIG_DISABLED;
            preview.dynamicFeeOverrideEnabled = key.fee.isDynamicFee();
            return preview;
        }

        (uint160 sqrtPriceX96, int24 tick,,) = StateLibrary.getSlot0(poolManager, poolId);

        PoolRuntime memory rt = _runtime[poolIdRaw];
        uint256 volatility =
            rt.lastObservationTimestamp == 0 ? 0 : PolicyMath.absInt(int256(tick) - int256(rt.lastTick));

        int256 nextFlow = rt.netFlowAccumulator;
        if (rt.windowStartTimestamp == 0 || block.timestamp - rt.windowStartTimestamp >= cfg.flowWindowSeconds) {
            nextFlow = params.amountSpecified;
        } else {
            nextFlow += params.amountSpecified;
        }

        uint256 imbalance = PolicyMath.absInt(nextFlow);

        (preview.regime, preview.reasonCode, preview.deviationTicks) = PolicyMath.selectRegime(
            PolicyMath.RegimeInput({
                pegTick: cfg.pegTick,
                currentTick: tick,
                band1Ticks: cfg.band1Ticks,
                band2Ticks: cfg.band2Ticks,
                hysteresisTicks: cfg.hysteresisTicks,
                volatilityProxy: volatility,
                imbalanceProxy: imbalance,
                volatilityHardThreshold: cfg.volatilityHardThreshold,
                imbalanceHardThreshold: cfg.imbalanceHardThreshold,
                previousRegime: rt.lastRegime
            })
        );

        if (preview.regime == PolicyMath.Regime.NORMAL) {
            preview.selectedFeeBps = cfg.feeNormalBps;
        } else if (preview.regime == PolicyMath.Regime.SOFT_DEPEG) {
            preview.selectedFeeBps = cfg.feeSoftBps;
            preview.maxSwap = cfg.maxSwapSoft;
            preview.maxImpactBps = cfg.maxImpactBpsSoft;
        } else {
            preview.selectedFeeBps = cfg.feeHardBps;
            preview.maxSwap = cfg.maxSwapHard;
            preview.maxImpactBps = cfg.maxImpactBpsHard;
        }

        preview.estimatedImpactBps = PolicyMath.estimateImpactBps(sqrtPriceX96, params.sqrtPriceLimitX96);
        preview.dynamicFeeOverrideEnabled = key.fee.isDynamicFee();

        uint256 absAmount = PolicyMath.absInt(params.amountSpecified);
        bool exceedsSwap = preview.maxSwap != 0 && absAmount > preview.maxSwap;
        bool exceedsImpact = preview.maxImpactBps != 0 && preview.estimatedImpactBps > preview.maxImpactBps;
        bool cooldown = preview.regime == PolicyMath.Regime.HARD_DEPEG && cfg.cooldownSecondsHard != 0
            && block.timestamp < rt.nextHardSwapAllowedAt;

        preview.wouldRevert = exceedsSwap || exceedsImpact || cooldown;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (_swapReentrancyLock != 0) revert();
        _swapReentrancyLock = 1;

        PoolId poolId = key.toId();
        BeforeSwapContext memory context;
        context.poolIdRaw = PoolId.unwrap(poolId);
        context.cfg = controller.getPoolConfig(poolId);

        if (!context.cfg.enabled) {
            emit PolicyTriggered(
                context.poolIdRaw,
                uint8(_runtime[context.poolIdRaw].lastRegime),
                uint8(PolicyMath.ReasonCode.CONFIG_DISABLED)
            );
            _swapReentrancyLock = 0;
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        (context.sqrtPriceX96, context.tick,,) = StateLibrary.getSlot0(poolManager, poolId);
        PoolRuntime storage rt = _runtime[context.poolIdRaw];
        (PolicyMath.Regime regime, PolicyMath.ReasonCode reasonCode) = _updateFlowAndSelectRegime(rt, context, params);

        uint16 selectedFeeBps = _enforceSwapGuards(context, rt, regime, params);

        rt.lastRegime = regime;
        rt.lastTick = context.tick;
        rt.lastObservationTimestamp = uint40(block.timestamp);

        emit PolicyTriggered(context.poolIdRaw, uint8(regime), uint8(reasonCode));

        uint24 feeOverride;
        if (key.fee.isDynamicFee()) {
            feeOverride = (uint24(selectedFeeBps) * 100) | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        }

        _swapReentrancyLock = 0;
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeOverride);
    }

    function _updateFlowAndSelectRegime(
        PoolRuntime storage rt,
        BeforeSwapContext memory context,
        SwapParams calldata params
    ) internal returns (PolicyMath.Regime regime, PolicyMath.ReasonCode reasonCode) {
        uint256 volatility =
            rt.lastObservationTimestamp == 0 ? 0 : PolicyMath.absInt(int256(context.tick) - int256(rt.lastTick));

        if (rt.windowStartTimestamp == 0 || block.timestamp - rt.windowStartTimestamp >= context.cfg.flowWindowSeconds)
        {
            rt.windowStartTimestamp = uint40(block.timestamp);
            rt.netFlowAccumulator = params.amountSpecified;
        } else {
            rt.netFlowAccumulator += params.amountSpecified;
        }

        uint256 imbalance = PolicyMath.absInt(rt.netFlowAccumulator);
        (regime, reasonCode,) = PolicyMath.selectRegime(
            PolicyMath.RegimeInput({
                pegTick: context.cfg.pegTick,
                currentTick: context.tick,
                band1Ticks: context.cfg.band1Ticks,
                band2Ticks: context.cfg.band2Ticks,
                hysteresisTicks: context.cfg.hysteresisTicks,
                volatilityProxy: volatility,
                imbalanceProxy: imbalance,
                volatilityHardThreshold: context.cfg.volatilityHardThreshold,
                imbalanceHardThreshold: context.cfg.imbalanceHardThreshold,
                previousRegime: rt.lastRegime
            })
        );
    }

    function _enforceSwapGuards(
        BeforeSwapContext memory context,
        PoolRuntime storage rt,
        PolicyMath.Regime regime,
        SwapParams calldata params
    ) internal returns (uint16 selectedFeeBps) {
        if (regime == PolicyMath.Regime.HARD_DEPEG && context.cfg.cooldownSecondsHard != 0) {
            if (block.timestamp < rt.nextHardSwapAllowedAt) {
                emit PolicyTriggered(context.poolIdRaw, uint8(regime), uint8(PolicyMath.ReasonCode.COOLDOWN));
                revert CooldownActive(rt.nextHardSwapAllowedAt);
            }
            rt.nextHardSwapAllowedAt = uint40(block.timestamp + context.cfg.cooldownSecondsHard);
        }

        uint256 absAmount = PolicyMath.absInt(params.amountSpecified);
        uint256 maxSwap = regime == PolicyMath.Regime.HARD_DEPEG
            ? context.cfg.maxSwapHard
            : (regime == PolicyMath.Regime.SOFT_DEPEG ? context.cfg.maxSwapSoft : 0);
        if (maxSwap != 0 && absAmount > maxSwap) {
            emit PolicyTriggered(context.poolIdRaw, uint8(regime), uint8(PolicyMath.ReasonCode.MAX_SWAP_EXCEEDED));
            revert MaxSwapExceeded(maxSwap, absAmount);
        }

        uint16 maxImpact = regime == PolicyMath.Regime.HARD_DEPEG
            ? context.cfg.maxImpactBpsHard
            : (regime == PolicyMath.Regime.SOFT_DEPEG ? context.cfg.maxImpactBpsSoft : 0);
        uint16 estimatedImpact = PolicyMath.estimateImpactBps(context.sqrtPriceX96, params.sqrtPriceLimitX96);
        if (maxImpact != 0 && estimatedImpact > maxImpact) {
            emit PolicyTriggered(context.poolIdRaw, uint8(regime), uint8(PolicyMath.ReasonCode.IMPACT_TOO_HIGH));
            revert ImpactTooHigh(maxImpact, estimatedImpact);
        }

        selectedFeeBps = regime == PolicyMath.Regime.NORMAL
            ? context.cfg.feeNormalBps
            : (regime == PolicyMath.Regime.SOFT_DEPEG ? context.cfg.feeSoftBps : context.cfg.feeHardBps);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        bytes32 poolIdRaw = PoolId.unwrap(poolId);

        (, int24 tick,,) = StateLibrary.getSlot0(poolManager, poolId);

        PoolRuntime storage rt = _runtime[poolIdRaw];
        rt.lastTick = tick;
        rt.lastObservationTimestamp = uint40(block.timestamp);

        return (BaseHook.afterSwap.selector, 0);
    }
}
