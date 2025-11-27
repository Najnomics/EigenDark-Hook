// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {IEigenDarkVault} from "./interfaces/IEigenDarkVault.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/**
 * @title EigenDarkHook
 * @notice Base Uniswap v4 hook that only allows privately-settled swaps coming from EigenCompute TEEs.
 *         Settlement proofs are verified via EIP-712 signatures produced by a trusted attestor.
 *         This contract currently emits settlement events and blocks public swaps to guarantee privacy.
 */
contract EigenDarkHook is BaseHook, Ownable, EIP712 {
    using PoolIdLibrary for PoolKey;

    /// @notice Thrown when someone tries to swap directly through the public pool.
    error DirectSwapDisabled();
    /// @notice Thrown when an attestation is signed by an unexpected key.
    error InvalidAttestor();
    /// @notice Thrown when an attestation carries an unexpected enclave measurement.
    error InvalidMeasurement();
    /// @notice Thrown when the settlement proof is older than the allowed window.
    error StaleAttestation();
    /// @notice Thrown when attempting to reuse an orderId.
    error OrderAlreadySettled();
    /// @notice Thrown when settlements are paused by governance.
    error SettlementsPaused();
    /// @notice Thrown when trying to set an empty vault address.
    error VaultRequired();
    /// @notice Thrown when settling for a pool that has not been configured.
    error PoolNotConfigured();
    /// @notice Thrown when a pool configuration references an unexpected hook.
    error InvalidPoolHook();
    /// @notice Thrown when a settlement exceeds per-pool risk limits.
    error DeltaLimitExceeded();

    struct Config {
        address attestor;
        bytes32 enclaveMeasurement;
        uint32 attestationWindow; // seconds
    }

    struct Settlement {
        bytes32 orderId;
        PoolId poolId;
        address trader;
        int128 delta0;
        int128 delta1;
        uint64 submittedAt;
        bytes32 enclaveMeasurement;
    }

    bytes32 private constant SETTLEMENT_TYPEHASH = keccak256(
        "Settlement(bytes32 orderId,bytes32 poolId,address trader,int128 delta0,int128 delta1,uint64 submittedAt,bytes32 enclaveMeasurement)"
    );

    struct PoolConfig {
        bool enabled;
        uint128 maxAbsDelta0;
        uint128 maxAbsDelta1;
        uint64 maxSettlementAge;
    }

    struct PoolConfigInput {
        bool enabled;
        uint128 maxAbsDelta0;
        uint128 maxAbsDelta1;
        uint64 maxSettlementAge;
    }

    Config public config;
    IEigenDarkVault public vault;
    mapping(bytes32 => bool) public settledOrders;
    bool public settlementsPaused;
    mapping(PoolId => PoolConfig) public poolConfigs;

    event ConfigUpdated(address indexed attestor, bytes32 indexed enclaveMeasurement, uint32 attestationWindow);
    event SettlementRecorded(
        bytes32 indexed orderId, PoolId indexed poolId, address indexed trader, int128 delta0, int128 delta1
    );
    event VaultUpdated(address indexed previousVault, address indexed newVault);
    event SettlementsPauseUpdated(bool paused);
    event PoolConfigured(
        PoolId indexed poolId, bool enabled, uint128 maxAbsDelta0, uint128 maxAbsDelta1, uint64 maxSettlementAge
    );

    constructor(IPoolManager _poolManager, Config memory cfg, address initialOwner, IEigenDarkVault _vault)
        BaseHook(_poolManager)
        Ownable(initialOwner)
        EIP712("EigenDarkSettlement", "0.1")
    {
        if (address(_vault) == address(0)) revert VaultRequired();
        vault = _vault;
        _setConfig(cfg);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Hooks                                     */
    /* -------------------------------------------------------------------------- */

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions.beforeSwap = true;
        return permissions;
    }

    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert DirectSwapDisabled();
    }

    /* -------------------------------------------------------------------------- */
    /*                              Admin functions                               */
    /* -------------------------------------------------------------------------- */

    function updateConfig(Config calldata cfg) external onlyOwner {
        _setConfig(cfg);
    }

    function configurePool(PoolKey calldata key, PoolConfigInput calldata poolCfg) external onlyOwner {
        if (address(key.hooks) != address(this)) revert InvalidPoolHook();
        PoolId poolId = key.toId();

        poolConfigs[poolId] = PoolConfig({
            enabled: poolCfg.enabled,
            maxAbsDelta0: poolCfg.maxAbsDelta0,
            maxAbsDelta1: poolCfg.maxAbsDelta1,
            maxSettlementAge: poolCfg.maxSettlementAge
        });

        emit PoolConfigured(poolId, poolCfg.enabled, poolCfg.maxAbsDelta0, poolCfg.maxAbsDelta1, poolCfg.maxSettlementAge);
    }

    function setVault(IEigenDarkVault newVault) external onlyOwner {
        if (address(newVault) == address(0)) revert VaultRequired();
        address oldVault = address(vault);
        vault = newVault;
        emit VaultUpdated(oldVault, address(newVault));
    }

    function setSettlementsPaused(bool paused) external onlyOwner {
        settlementsPaused = paused;
        emit SettlementsPauseUpdated(paused);
    }

    function _setConfig(Config memory cfg) internal {
        if (cfg.attestor == address(0)) revert InvalidAttestor();
        if (cfg.attestationWindow == 0) revert StaleAttestation();

        config = cfg;
        emit ConfigUpdated(cfg.attestor, cfg.enclaveMeasurement, cfg.attestationWindow);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Settlements                                  */
    /* -------------------------------------------------------------------------- */

    function registerSettlement(Settlement calldata settlement, bytes calldata signature) external {
        Config memory localConfig = config;

        if (settlementsPaused) revert SettlementsPaused();
        if (settlement.enclaveMeasurement != localConfig.enclaveMeasurement) revert InvalidMeasurement();
        if (settledOrders[settlement.orderId]) revert OrderAlreadySettled();

        if (block.timestamp < settlement.submittedAt) revert StaleAttestation();
        if (block.timestamp - settlement.submittedAt > localConfig.attestationWindow) revert StaleAttestation();
        _enforcePoolLimits(settlement);

        bytes32 digest = _hashTypedDataV4(_hashSettlement(settlement));
        address signer = ECDSA.recover(digest, signature);
        if (signer != localConfig.attestor) revert InvalidAttestor();

        settledOrders[settlement.orderId] = true;
        vault.applySettlement(settlement.poolId, settlement.trader, settlement.delta0, settlement.delta1);
        emit SettlementRecorded(settlement.orderId, settlement.poolId, settlement.trader, settlement.delta0, settlement.delta1);
    }

    function previewSettlementDigest(Settlement calldata settlement) external view returns (bytes32) {
        return _hashTypedDataV4(_hashSettlement(settlement));
    }

    function _hashSettlement(Settlement calldata settlement) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SETTLEMENT_TYPEHASH,
                settlement.orderId,
                PoolId.unwrap(settlement.poolId),
                settlement.trader,
                settlement.delta0,
                settlement.delta1,
                settlement.submittedAt,
                settlement.enclaveMeasurement
            )
        );
    }

    function _enforcePoolLimits(Settlement calldata settlement) private view {
        PoolConfig memory poolCfg = poolConfigs[settlement.poolId];
        if (!poolCfg.enabled) revert PoolNotConfigured();

        if (poolCfg.maxSettlementAge != 0 && block.timestamp - settlement.submittedAt > poolCfg.maxSettlementAge) {
            revert StaleAttestation();
        }

        if (poolCfg.maxAbsDelta0 != 0 && _absInt128(settlement.delta0) > poolCfg.maxAbsDelta0) {
            revert DeltaLimitExceeded();
        }

        if (poolCfg.maxAbsDelta1 != 0 && _absInt128(settlement.delta1) > poolCfg.maxAbsDelta1) {
            revert DeltaLimitExceeded();
        }
    }

    function _absInt128(int128 value) private pure returns (uint128) {
        int256 casted = int256(value);
        if (casted < 0) {
            casted = -casted;
        }
        return uint128(uint256(casted));
    }
}

