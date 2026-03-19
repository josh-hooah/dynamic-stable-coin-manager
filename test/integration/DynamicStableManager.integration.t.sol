// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {StablePolicyController} from "../../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../../src/DynamicStableManagerHook.sol";
import {MockPoolManager} from "../../src/mocks/MockPoolManager.sol";

contract DynamicStableManagerIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;

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
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: hook
        });
        poolId = key.toId();

        manager.setSlot0(poolId, uint160(1e18), 0, 0, 0);

        StablePolicyController.PoolConfig memory cfg;
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = 10;
        cfg.band2Ticks = 20;
        cfg.feeNormalBps = 4;
        cfg.feeSoftBps = 20;
        cfg.feeHardBps = 75;
        cfg.maxSwapSoft = 1_000e6;
        cfg.maxSwapHard = 250e6;
        cfg.maxImpactBpsSoft = 70;
        cfg.maxImpactBpsHard = 25;
        cfg.cooldownSecondsHard = 10;
        cfg.hysteresisTicks = 2;
        cfg.flowWindowSeconds = 90;
        cfg.volatilityHardThreshold = 50;
        cfg.imbalanceHardThreshold = 10_000e6;
        cfg.admin = address(this);
        cfg.minUpdateInterval = 0;
        cfg.policyNonce = 1;

        controller.setPoolConfig(poolId, cfg);
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

    function _beforeSwap(
        int24 tick,
        int256 amountSpecified,
        uint160 limit
    ) internal returns (bool ok) {
        manager.setSlot0(poolId, uint160(1e18), tick, 0, 0);
        vm.prank(address(manager));
        try hook.beforeSwap(address(this), key, SwapParams(true, amountSpecified, limit), bytes("")) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function test_ManagedLifecycle_NormalThenStress() external {
        bool normal1 = _beforeSwap(5, -100e6, uint160(0.9995e18));
        bool normal2 = _beforeSwap(8, -200e6, uint160(0.999e18));

        bool soft1 = _beforeSwap(14, -400e6, uint160(0.995e18));
        bool softBlocked = _beforeSwap(15, -1_100e6, uint160(0.995e18));

        bool hard1 = _beforeSwap(30, -100e6, uint160(0.999e18));
        bool hardCooldownBlocked = _beforeSwap(30, -80e6, uint160(0.999e18));

        vm.warp(block.timestamp + 11);
        bool hard2 = _beforeSwap(32, -90e6, uint160(0.999e18));

        assertTrue(normal1 && normal2 && soft1 && hard1 && hard2);
        assertFalse(softBlocked);
        assertFalse(hardCooldownBlocked);
    }
}
