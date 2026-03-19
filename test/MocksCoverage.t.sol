// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {StablePolicyController} from "../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../src/DynamicStableManagerHook.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPoolManager} from "../src/mocks/MockPoolManager.sol";

contract MocksCoverageTest is Test {
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
            currency0: Currency.wrap(address(0xABC1)),
            currency1: Currency.wrap(address(0xABC2)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();

        StablePolicyController.PoolConfig memory cfg;
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = 10;
        cfg.band2Ticks = 20;
        cfg.feeNormalBps = 5;
        cfg.feeSoftBps = 25;
        cfg.feeHardBps = 100;
        cfg.maxSwapSoft = 1_000e6;
        cfg.maxSwapHard = 300e6;
        cfg.maxImpactBpsSoft = 70;
        cfg.maxImpactBpsHard = 25;
        cfg.cooldownSecondsHard = 0;
        cfg.hysteresisTicks = 2;
        cfg.flowWindowSeconds = 120;
        cfg.volatilityHardThreshold = 0;
        cfg.imbalanceHardThreshold = 0;
        cfg.admin = address(this);
        cfg.policyNonce = 1;
        controller.setPoolConfig(poolId, cfg);
        manager.setSlot0(poolId, uint160(1e18), 0, 0, 0);

        assertEq(address(hook.controller()), address(controller));
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

    function test_DynamicStableManagerHook_DeploysWithMinedAddress() external {
        DynamicStableManagerHook deployedHook = _deployHook(IPoolManager(address(manager)), controller);
        assertEq(address(deployedHook.controller()), address(controller));
    }

    function test_MockERC20_AllBranches() external {
        MockERC20 token = new MockERC20("Mock USD", "mUSD", 6);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        address carol = address(0xCA101);

        assertEq(token.name(), "Mock USD");
        assertEq(token.symbol(), "mUSD");
        assertEq(token.decimals(), 6);

        token.mint(alice, 1_000_000);
        assertEq(token.totalSupply(), 1_000_000);
        assertEq(token.balanceOf(alice), 1_000_000);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 400_000));
        assertEq(token.balanceOf(alice), 600_000);
        assertEq(token.balanceOf(bob), 400_000);

        vm.prank(bob);
        assertTrue(token.approve(address(this), 300_000));
        assertEq(token.allowance(bob, address(this)), 300_000);

        // Cover the allowance decrement branch.
        assertTrue(token.transferFrom(bob, carol, 100_000));
        assertEq(token.allowance(bob, address(this)), 200_000);
        assertEq(token.balanceOf(bob), 300_000);
        assertEq(token.balanceOf(carol), 100_000);

        // Cover the max-allowance branch where allowance should not decrement.
        vm.prank(bob);
        assertTrue(token.approve(address(this), type(uint256).max));
        assertTrue(token.transferFrom(bob, carol, 50_000));
        assertEq(token.allowance(bob, address(this)), type(uint256).max);
        assertEq(token.balanceOf(bob), 250_000);
        assertEq(token.balanceOf(carol), 150_000);
    }

    function test_MockPoolManager_AllMethods() external {
        bytes32 slotA = bytes32(uint256(0x100));
        bytes32 slotB = bytes32(uint256(0x101));
        bytes32 valueA = keccak256("slot-a");
        bytes32 valueB = bytes32(uint256(0xBEEF));

        manager.setSlot(slotA, valueA);
        manager.setSlot(slotB, valueB);

        assertEq(manager.extsload(slotA), valueA);
        assertEq(manager.extsload(slotB), valueB);

        bytes32[] memory range = manager.extsload(slotA, 2);
        assertEq(range.length, 2);
        assertEq(range[0], valueA);
        assertEq(range[1], valueB);

        bytes32[] memory slots = new bytes32[](3);
        slots[0] = slotA;
        slots[1] = slotB;
        slots[2] = bytes32(uint256(0x102));
        bytes32[] memory lookedUp = manager.extsload(slots);
        assertEq(lookedUp.length, 3);
        assertEq(lookedUp[0], valueA);
        assertEq(lookedUp[1], valueB);
        assertEq(lookedUp[2], bytes32(0));

        manager.setSlot0(poolId, uint160(1_234_567), -7, 3, 9);
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), StateLibrary.POOLS_SLOT));
        assertTrue(manager.extsload(stateSlot) != bytes32(0));

        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -10e6, sqrtPriceLimitX96: uint160(0.999e18)});
        (bytes4 selector, BeforeSwapDelta delta, uint24 feeOverride) =
            manager.callBeforeSwap(address(this), IHooks(address(hook)), key, params, bytes(""));
        assertEq(selector, hook.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(feeOverride & LPFeeLibrary.REMOVE_OVERRIDE_MASK, 500);

        (bytes4 afterSelector, int128 hookDelta) = manager.callAfterSwap(
            address(this), IHooks(address(hook)), key, params, BalanceDelta.wrap(0), bytes("")
        );
        assertEq(afterSelector, hook.afterSwap.selector);
        assertEq(hookDelta, 0);
    }
}
