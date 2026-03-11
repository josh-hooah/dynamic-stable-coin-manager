// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DynamicStableManagerHook} from "../DynamicStableManagerHook.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StablePolicyController} from "../StablePolicyController.sol";

/// @notice Local-demo/testing variant that bypasses hook permission address checks.
contract DynamicStableManagerHookUnsafe is DynamicStableManagerHook {
    constructor(
        IPoolManager manager,
        StablePolicyController controller
    ) DynamicStableManagerHook(manager, controller) {}

    function validateHookAddress(
        BaseHook
    ) internal pure override {}
}
