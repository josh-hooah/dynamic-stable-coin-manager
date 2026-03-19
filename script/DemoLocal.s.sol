// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPoolManager} from "../src/mocks/MockPoolManager.sol";
import {StablePolicyController} from "../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../src/DynamicStableManagerHook.sol";

contract DemoLocalScript is Script {
    using PoolIdLibrary for PoolKey;
    address internal constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    struct DemoStats {
        uint256 succeeded;
        uint256 blocked;
        uint256 totalEffectiveFeeBps;
    }

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 dai = new MockERC20("Mock DAI", "mDAI", 18);
        MockPoolManager manager = new MockPoolManager();
        StablePolicyController controller = new StablePolicyController(deployer, 0, 0);
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(IPoolManager(address(manager)), controller);
        (address expectedHook, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(DynamicStableManagerHook).creationCode, constructorArgs);
        DynamicStableManagerHook hook = new DynamicStableManagerHook{salt: salt}(IPoolManager(address(manager)), controller);
        require(address(hook) == expectedHook, "hook-address-mismatch");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(dai)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });
        PoolId poolId = key.toId();

        StablePolicyController.PoolConfig memory cfg;
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = 10;
        cfg.band2Ticks = 20;
        cfg.feeNormalBps = 5;
        cfg.feeSoftBps = 20;
        cfg.feeHardBps = 75;
        cfg.maxSwapSoft = 1_000e6;
        cfg.maxSwapHard = 250e6;
        cfg.maxImpactBpsSoft = 80;
        cfg.maxImpactBpsHard = 25;
        cfg.cooldownSecondsHard = 15;
        cfg.hysteresisTicks = 2;
        cfg.flowWindowSeconds = 120;
        cfg.volatilityHardThreshold = 45;
        cfg.imbalanceHardThreshold = 5_000e6;
        cfg.admin = deployer;
        cfg.policyNonce = 1;

        controller.setPoolConfig(poolId, cfg);

        manager.setSlot0(poolId, uint160(1e18), 0, 0, 0);

        DemoStats memory normalStats;
        DemoStats memory stressStats;

        // Normal regime swaps.
        _simulateSwap(manager, hook, key, poolId, 4, -120e6, uint160(0.9998e18), normalStats);
        _simulateSwap(manager, hook, key, poolId, 7, -80e6, uint160(0.9995e18), normalStats);
        _simulateSwap(manager, hook, key, poolId, 9, -40e6, uint160(0.9995e18), normalStats);

        // Stress path into soft/hard depeg and blocked swaps.
        _simulateSwap(manager, hook, key, poolId, 13, -600e6, uint160(0.997e18), stressStats);
        _simulateSwap(manager, hook, key, poolId, 15, -1_500e6, uint160(0.997e18), stressStats);
        _simulateSwap(manager, hook, key, poolId, 30, -150e6, uint160(0.998e18), stressStats);
        _simulateSwap(manager, hook, key, poolId, 31, -140e6, uint160(0.998e18), stressStats);

        vm.stopBroadcast();

        console2.log("=== Dynamic Stable Manager Demo (Local) ===");
        console2.log("PoolId:");
        console2.logBytes32(PoolId.unwrap(poolId));
        console2.log("Normal succeeded", normalStats.succeeded);
        console2.log("Normal blocked", normalStats.blocked);
        console2.log("Stress succeeded", stressStats.succeeded);
        console2.log("Stress blocked", stressStats.blocked);

        uint256 totalSucceeded = normalStats.succeeded + stressStats.succeeded;
        uint256 weightedFee = normalStats.totalEffectiveFeeBps + stressStats.totalEffectiveFeeBps;
        uint256 avgFee = totalSucceeded == 0 ? 0 : weightedFee / totalSucceeded;
        console2.log("Average effective fee (bps)", avgFee);

        console2.log("Baseline unmanaged expectation under stress: all swaps accepted with static fee.");
        console2.log("Managed outcome under stress: blocked swaps and elevated effective fee.");
    }

    function _simulateSwap(
        MockPoolManager manager,
        DynamicStableManagerHook hook,
        PoolKey memory key,
        PoolId poolId,
        int24 tick,
        int256 amountSpecified,
        uint160 sqrtLimit,
        DemoStats memory stats
    ) internal {
        manager.setSlot0(poolId, uint160(1e18), tick, 0, 0);

        try manager.callBeforeSwap(
            msg.sender,
            IHooks(address(hook)),
            key,
            SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: sqrtLimit}),
            bytes("")
        ) returns (
            bytes4, BeforeSwapDelta, uint24 feeOverride
        ) {
            stats.succeeded += 1;
            uint24 feeHundredthBips = feeOverride & LPFeeLibrary.REMOVE_OVERRIDE_MASK;
            stats.totalEffectiveFeeBps += feeHundredthBips / 100;
        } catch {
            stats.blocked += 1;
        }
    }
}
