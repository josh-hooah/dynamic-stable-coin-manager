// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DynamicStableManagerHook} from "../../src/DynamicStableManagerHook.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StablePolicyController} from "../../src/StablePolicyController.sol";

/// @notice Test-only hook that bypasses hook-address permission validation.
contract TestDynamicStableManagerHook is DynamicStableManagerHook {
    constructor(
        IPoolManager manager,
        StablePolicyController controller
    ) DynamicStableManagerHook(manager, controller) {}

    function validateHookAddress(
        BaseHook
    ) internal pure override {}
}
