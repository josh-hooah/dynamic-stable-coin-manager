// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @notice Minimal extsload-capable pool manager mock used for hook testing.
contract MockPoolManager {
    mapping(bytes32 slot => bytes32 value) private _slots;

    function setSlot(
        bytes32 slot,
        bytes32 value
    ) external {
        _slots[slot] = value;
    }

    function setSlot0(
        PoolId poolId,
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    ) external {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), StateLibrary.POOLS_SLOT));

        uint256 packed = uint256(sqrtPriceX96);
        uint24 tickRaw = uint24(uint256(int256(tick)) & 0xFFFFFF);

        packed |= uint256(tickRaw) << 160;
        packed |= uint256(protocolFee) << 184;
        packed |= uint256(lpFee) << 208;

        _slots[stateSlot] = bytes32(packed);
    }

    function extsload(
        bytes32 slot
    ) external view returns (bytes32 value) {
        return _slots[slot];
    }

    function extsload(
        bytes32 startSlot,
        uint256 nSlots
    ) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i = 0; i < nSlots; i++) {
            values[i] = _slots[bytes32(uint256(startSlot) + i)];
        }
    }

    function extsload(
        bytes32[] calldata slots
    ) external view returns (bytes32[] memory values) {
        values = new bytes32[](slots.length);
        for (uint256 i = 0; i < slots.length; i++) {
            values[i] = _slots[slots[i]];
        }
    }

    function callBeforeSwap(
        address swapper,
        IHooks hooks,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        return hooks.beforeSwap(swapper, key, params, hookData);
    }

    function callAfterSwap(
        address swapper,
        IHooks hooks,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128) {
        return hooks.afterSwap(swapper, key, params, delta, hookData);
    }
}
