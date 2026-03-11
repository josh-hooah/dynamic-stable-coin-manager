// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PolicyMath} from "./libraries/PolicyMath.sol";

/// @title StablePolicyController
/// @notice Governance-owned policy store for deterministic stablecoin swap guardrails.
contract StablePolicyController {
    uint16 public constant MAX_BPS = 10_000;

    error Unauthorized();
    error InvalidConfig();
    error TimelockEnabled();
    error TimelockDisabled();
    error PendingConfigNotReady();
    error PendingConfigMismatch();
    error UpdateTooFrequent(uint256 nextUpdateAt);

    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event TimelockSecondsSet(uint64 oldTimelockSeconds, uint64 newTimelockSeconds);
    event GlobalMinUpdateIntervalSet(uint64 oldInterval, uint64 newInterval);
    event ConfigQueued(bytes32 indexed poolId, bytes32 indexed configHash, uint64 eta, uint64 policyNonce);
    event ConfigSet(bytes32 indexed poolId, bytes32 configHash, uint64 policyNonce);

    struct PoolConfig {
        bool enabled;
        int24 pegTick;
        int24 band1Ticks;
        int24 band2Ticks;
        uint16 feeNormalBps;
        uint16 feeSoftBps;
        uint16 feeHardBps;
        uint256 maxSwapSoft;
        uint256 maxSwapHard;
        uint16 maxImpactBpsSoft;
        uint16 maxImpactBpsHard;
        uint32 cooldownSecondsHard;
        int24 hysteresisTicks;
        uint32 flowWindowSeconds;
        uint32 volatilityHardThreshold;
        uint256 imbalanceHardThreshold;
        address admin;
        uint64 minUpdateInterval;
        uint64 policyNonce;
        uint64 lastUpdatedAt;
    }

    struct PendingConfig {
        bytes32 configHash;
        uint64 eta;
        uint64 policyNonce;
    }

    address public owner;
    uint64 public timelockSeconds;
    uint64 public globalMinUpdateInterval;

    mapping(bytes32 poolId => PoolConfig config) private _poolConfigs;
    mapping(bytes32 poolId => PendingConfig pending) private _pendingConfigs;

    constructor(
        address initialOwner,
        uint64 initialTimelockSeconds,
        uint64 initialGlobalMinUpdateInterval
    ) {
        if (initialOwner == address(0)) revert InvalidConfig();
        owner = initialOwner;
        timelockSeconds = initialTimelockSeconds;
        globalMinUpdateInterval = initialGlobalMinUpdateInterval;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setOwner(
        address newOwner
    ) external onlyOwner {
        if (newOwner == address(0)) revert InvalidConfig();
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    function setTimelockSeconds(
        uint64 newTimelockSeconds
    ) external onlyOwner {
        emit TimelockSecondsSet(timelockSeconds, newTimelockSeconds);
        timelockSeconds = newTimelockSeconds;
    }

    function setGlobalMinUpdateInterval(
        uint64 newInterval
    ) external onlyOwner {
        emit GlobalMinUpdateIntervalSet(globalMinUpdateInterval, newInterval);
        globalMinUpdateInterval = newInterval;
    }

    function setPoolConfig(
        PoolId poolId,
        PoolConfig calldata nextConfig
    ) external {
        _assertPoolAdmin(PoolId.unwrap(poolId));
        if (timelockSeconds != 0) revert TimelockEnabled();
        _applyConfig(PoolId.unwrap(poolId), nextConfig);
    }

    function queuePoolConfig(
        PoolId poolId,
        PoolConfig calldata nextConfig
    ) external {
        bytes32 poolIdRaw = PoolId.unwrap(poolId);
        _assertPoolAdmin(poolIdRaw);
        if (timelockSeconds == 0) revert TimelockDisabled();
        _validateConfig(poolIdRaw, nextConfig);

        bytes32 configHash = _hashConfig(nextConfig);
        uint64 eta = uint64(block.timestamp + timelockSeconds);

        _pendingConfigs[poolIdRaw] =
            PendingConfig({configHash: configHash, eta: eta, policyNonce: nextConfig.policyNonce});

        emit ConfigQueued(poolIdRaw, configHash, eta, nextConfig.policyNonce);
    }

    function executeQueuedPoolConfig(
        PoolId poolId,
        PoolConfig calldata nextConfig
    ) external {
        bytes32 poolIdRaw = PoolId.unwrap(poolId);
        _assertPoolAdmin(poolIdRaw);
        if (timelockSeconds == 0) revert TimelockDisabled();
        PendingConfig memory pending = _pendingConfigs[poolIdRaw];
        if (pending.eta == 0 || block.timestamp < pending.eta) revert PendingConfigNotReady();

        bytes32 configHash = _hashConfig(nextConfig);
        if (pending.configHash != configHash || pending.policyNonce != nextConfig.policyNonce) {
            revert PendingConfigMismatch();
        }

        delete _pendingConfigs[poolIdRaw];
        _applyConfig(poolIdRaw, nextConfig);
    }

    function deriveRegime(
        PoolId poolId,
        int24 currentTick,
        uint256 volatilityProxy,
        uint256 imbalanceProxy,
        PolicyMath.Regime previousRegime
    )
        external
        view
        returns (
            PolicyMath.Regime regime,
            PolicyMath.ReasonCode reasonCode,
            uint24 deviationTicks,
            uint16 selectedFeeBps,
            uint256 maxSwap,
            uint16 maxImpactBps,
            uint32 cooldownSecondsHard
        )
    {
        PoolConfig memory cfg = _poolConfigs[PoolId.unwrap(poolId)];
        if (!cfg.enabled) {
            return (
                previousRegime,
                PolicyMath.ReasonCode.CONFIG_DISABLED,
                PolicyMath.absTickDistance(currentTick, cfg.pegTick),
                0,
                0,
                0,
                0
            );
        }

        (regime, reasonCode, deviationTicks) = PolicyMath.selectRegime(
            PolicyMath.RegimeInput({
                pegTick: cfg.pegTick,
                currentTick: currentTick,
                band1Ticks: cfg.band1Ticks,
                band2Ticks: cfg.band2Ticks,
                hysteresisTicks: cfg.hysteresisTicks,
                volatilityProxy: volatilityProxy,
                imbalanceProxy: imbalanceProxy,
                volatilityHardThreshold: cfg.volatilityHardThreshold,
                imbalanceHardThreshold: cfg.imbalanceHardThreshold,
                previousRegime: previousRegime
            })
        );

        if (regime == PolicyMath.Regime.NORMAL) {
            selectedFeeBps = cfg.feeNormalBps;
        } else if (regime == PolicyMath.Regime.SOFT_DEPEG) {
            selectedFeeBps = cfg.feeSoftBps;
            maxSwap = cfg.maxSwapSoft;
            maxImpactBps = cfg.maxImpactBpsSoft;
        } else {
            selectedFeeBps = cfg.feeHardBps;
            maxSwap = cfg.maxSwapHard;
            maxImpactBps = cfg.maxImpactBpsHard;
            cooldownSecondsHard = cfg.cooldownSecondsHard;
        }
    }

    function getPoolConfig(
        PoolId poolId
    ) external view returns (PoolConfig memory) {
        return _poolConfigs[PoolId.unwrap(poolId)];
    }

    function getPoolConfigById(
        bytes32 poolId
    ) external view returns (PoolConfig memory) {
        return _poolConfigs[poolId];
    }

    function getPendingConfig(
        bytes32 poolId
    ) external view returns (PendingConfig memory) {
        return _pendingConfigs[poolId];
    }

    function _assertPoolAdmin(
        bytes32 poolId
    ) internal view {
        if (msg.sender == owner) return;

        address poolAdmin = _poolConfigs[poolId].admin;
        if (poolAdmin == address(0) || msg.sender != poolAdmin) revert Unauthorized();
    }

    function _applyConfig(
        bytes32 poolId,
        PoolConfig calldata nextConfig
    ) internal {
        _validateConfig(poolId, nextConfig);

        PoolConfig storage current = _poolConfigs[poolId];
        if (current.lastUpdatedAt != 0) {
            uint64 updateInterval = current.minUpdateInterval;
            if (globalMinUpdateInterval > updateInterval) updateInterval = globalMinUpdateInterval;
            uint256 nextUpdateAt = uint256(current.lastUpdatedAt) + uint256(updateInterval);
            if (block.timestamp < nextUpdateAt) revert UpdateTooFrequent(nextUpdateAt);
        }

        PoolConfig memory applied = nextConfig;
        applied.lastUpdatedAt = uint64(block.timestamp);

        _poolConfigs[poolId] = applied;

        emit ConfigSet(poolId, _hashConfig(applied), applied.policyNonce);
    }

    function _validateConfig(
        bytes32 poolId,
        PoolConfig calldata nextConfig
    ) internal view {
        PoolConfig memory current = _poolConfigs[poolId];

        if (nextConfig.band1Ticks <= 0) revert InvalidConfig();
        if (nextConfig.band2Ticks <= nextConfig.band1Ticks) revert InvalidConfig();
        if (nextConfig.hysteresisTicks < 0 || nextConfig.hysteresisTicks >= nextConfig.band1Ticks) {
            revert InvalidConfig();
        }

        if (nextConfig.feeNormalBps > MAX_BPS || nextConfig.feeSoftBps > MAX_BPS || nextConfig.feeHardBps > MAX_BPS) {
            revert InvalidConfig();
        }
        if (!(nextConfig.feeNormalBps <= nextConfig.feeSoftBps && nextConfig.feeSoftBps <= nextConfig.feeHardBps)) {
            revert InvalidConfig();
        }

        if (nextConfig.maxImpactBpsSoft > MAX_BPS || nextConfig.maxImpactBpsHard > MAX_BPS) revert InvalidConfig();

        if (
            nextConfig.maxSwapHard != 0 && nextConfig.maxSwapSoft != 0
                && nextConfig.maxSwapHard > nextConfig.maxSwapSoft
        ) {
            revert InvalidConfig();
        }

        if (nextConfig.flowWindowSeconds == 0) revert InvalidConfig();

        uint64 expectedNonce = current.policyNonce == 0 ? 1 : current.policyNonce + 1;
        if (nextConfig.policyNonce != expectedNonce) revert InvalidConfig();
    }

    function _hashConfig(
        PoolConfig memory config
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(config));
    }
}
