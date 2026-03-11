// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPoolManager} from "../src/mocks/MockPoolManager.sol";
import {StablePolicyController} from "../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../src/DynamicStableManagerHook.sol";

contract DeployLocalScript is Script {
    using PoolIdLibrary for PoolKey;
    address internal constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

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

        DynamicStableManagerHook hook =
            new DynamicStableManagerHook{salt: salt}(IPoolManager(address(manager)), controller);
        require(address(hook) == expectedHook, "hook-address-mismatch");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(dai)),
            fee: 0x800000,
            tickSpacing: 1,
            hooks: hook
        });

        PoolId poolId = key.toId();

        StablePolicyController.PoolConfig memory cfg;
        cfg.enabled = true;
        cfg.pegTick = 0;
        cfg.band1Ticks = 10;
        cfg.band2Ticks = 25;
        cfg.feeNormalBps = 5;
        cfg.feeSoftBps = 25;
        cfg.feeHardBps = 80;
        cfg.maxSwapSoft = 1_000_000e6;
        cfg.maxSwapHard = 250_000e6;
        cfg.maxImpactBpsSoft = 80;
        cfg.maxImpactBpsHard = 25;
        cfg.cooldownSecondsHard = 60;
        cfg.hysteresisTicks = 2;
        cfg.flowWindowSeconds = 120;
        cfg.volatilityHardThreshold = 50;
        cfg.imbalanceHardThreshold = 10_000_000e6;
        cfg.admin = deployer;
        cfg.policyNonce = 1;

        controller.setPoolConfig(poolId, cfg);

        manager.setSlot0(poolId, uint160(1e18), 0, 0, 0);

        usdc.mint(deployer, 10_000_000e6);
        dai.mint(deployer, 10_000_000 ether);

        vm.stopBroadcast();

        console2.log("Deployer", deployer);
        console2.log("MockPoolManager", address(manager));
        console2.log("StablePolicyController", address(controller));
        console2.log("DynamicStableManagerHook", address(hook));
        console2.log("USDC", address(usdc));
        console2.log("DAI", address(dai));
        console2.logBytes32(PoolId.unwrap(poolId));
    }
}
