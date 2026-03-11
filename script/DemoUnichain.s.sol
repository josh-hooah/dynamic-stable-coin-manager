// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {StablePolicyController} from "../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../src/DynamicStableManagerHook.sol";
import {PolicyMath} from "../src/libraries/PolicyMath.sol";

contract DemoUnichainScript is Script {
    using PoolIdLibrary for PoolKey;

    address internal constant DEMO_TOKEN0 = address(0x0000000000000000000000000000000000001000);
    address internal constant DEMO_TOKEN1 = address(0x0000000000000000000000000000000000002000);

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        StablePolicyController controller = StablePolicyController(vm.envAddress("STABLE_POLICY_CONTROLLER_ADDRESS"));
        DynamicStableManagerHook hook = DynamicStableManagerHook(vm.envAddress("DYNAMIC_STABLE_MANAGER_HOOK_ADDRESS"));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(DEMO_TOKEN0),
            currency1: Currency.wrap(DEMO_TOKEN1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });
        PoolId poolId = key.toId();

        StablePolicyController.PoolConfig memory current = controller.getPoolConfig(poolId);
        uint64 nextNonce = current.policyNonce == 0 ? 1 : current.policyNonce + 1;

        StablePolicyController.PoolConfig memory cfg;
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
        cfg.admin = deployer;
        cfg.minUpdateInterval = 0;
        cfg.policyNonce = nextNonce;

        vm.startBroadcast(deployerPk);

        if (controller.timelockSeconds() != 0) controller.setTimelockSeconds(0);
        if (controller.globalMinUpdateInterval() != 0) controller.setGlobalMinUpdateInterval(0);

        controller.setPoolConfig(poolId, cfg);

        vm.stopBroadcast();

        _printScenario(controller, poolId, "NORMAL scenario", 0, 0, 0);
        _printScenario(controller, poolId, "SOFT_DEPEG scenario", 15, 0, 0);
        _printScenario(controller, poolId, "HARD_DEPEG scenario", 40, 0, 0);
        _printScenario(controller, poolId, "VOLATILITY_FORCED_HARD", 0, 50, 0);

        DynamicStableManagerHook.PolicyPreview memory preview = hook.previewSwapPolicy(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100e6, sqrtPriceLimitX96: uint160(0.999e18)})
        );

        console2.log("Preview regime", uint8(preview.regime));
        console2.log("Preview reasonCode", uint8(preview.reasonCode));
        console2.log("Preview selectedFeeBps", preview.selectedFeeBps);
        console2.log("Preview wouldRevert", preview.wouldRevert ? "true" : "false");
        console2.log("Preview dynamicFeeOverrideEnabled", preview.dynamicFeeOverrideEnabled ? "true" : "false");
        console2.logBytes32(PoolId.unwrap(poolId));
    }

    function _printScenario(
        StablePolicyController controller,
        PoolId poolId,
        string memory label,
        int24 tick,
        uint256 volatility,
        uint256 imbalance
    ) internal view {
        (
            PolicyMath.Regime regime,
            PolicyMath.ReasonCode reason,
            uint24 deviation,
            uint16 feeBps,
            uint256 maxSwap,
            uint16 maxImpact,

        ) = controller.deriveRegime(poolId, tick, volatility, imbalance, PolicyMath.Regime.NORMAL);

        console2.log(label);
        console2.log("regime", uint8(regime));
        console2.log("reason", uint8(reason));
        console2.log("deviationTicks", deviation);
        console2.log("selectedFeeBps", feeBps);
        console2.log("maxSwap", maxSwap);
        console2.log("maxImpactBps", maxImpact);
    }
}
