// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {StablePolicyController} from "../src/StablePolicyController.sol";
import {DynamicStableManagerHook} from "../src/DynamicStableManagerHook.sol";

contract DeployUnichainSepoliaScript is Script {
    string internal constant UNICHAIN_SEPOLIA_EXPLORER = "https://sepolia.uniscan.xyz/tx/";
    address internal constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER");

        vm.startBroadcast(deployerPk);

        StablePolicyController controller = new StablePolicyController(deployer, 3600, 300);

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManagerAddress), controller);

        (address expectedHook, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(DynamicStableManagerHook).creationCode, constructorArgs);

        DynamicStableManagerHook hook = new DynamicStableManagerHook{salt: salt}(IPoolManager(poolManagerAddress), controller);
        require(address(hook) == expectedHook, "hook-address-mismatch");

        vm.stopBroadcast();

        console2.log("Network: Unichain Sepolia (chainId 1301)");
        console2.log("Deployer", deployer);
        console2.log("PoolManager", poolManagerAddress);
        console2.log("StablePolicyController", address(controller));
        console2.log("DynamicStableManagerHook", address(hook));
        console2.log("Explorer prefix", UNICHAIN_SEPOLIA_EXPLORER);
    }
}
