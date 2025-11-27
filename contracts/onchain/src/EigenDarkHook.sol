// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {IEigenDarkVault} from "./interfaces/IEigenDarkVault.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
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
    /// @notice Thrown when pool-level settlements are paused.
    error PoolSettlementsPaused();
    /// @notice Thrown when trying to set an empty vault address.
    error VaultRequired();
    /// @notice Thrown when settling for a pool that has not been configured.
    error PoolNotConfigured();
    /// @notice Thrown when a pool configuration references an unexpected hook.
    error InvalidPoolHook();
    /// @notice Thrown when a settlement exceeds per-pool risk limits.
    error DeltaLimitExceeded();
    /// @notice Thrown when a settlement exceeds TWAP deviation bounds.
    error TwapDeviationExceeded();
    /// @notice Thrown when the reported liquidity check is below the configured minimum.
    error InsufficientCheckedLiquidity();
    /// @notice Thrown when unauthorized liquidity actions are attempted.
    error PublicLiquidityNotAllowed();

    struct Config {
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
        bytes32 metadataHash;
        uint160 sqrtPriceX96;
        uint64 twapDeviationBps;
        uint128 checkedLiquidity;
    }

    bytes32 private constant SETTLEMENT_TYPEHASH = keccak256(
        "Settlement(bytes32 orderId,bytes32 poolId,address trader,int128 delta0,int128 delta1,uint64 submittedAt,bytes32 enclaveMeasurement,bytes32 metadataHash,uint160 sqrtPriceX96,uint64 twapDeviationBps,uint128 checkedLiquidity)"
    );

    struct PoolConfig {
        bool enabled;
        bool settlementsPaused;
        bytes32 enclaveMeasurement;
        uint128 maxAbsDelta0;
        uint128 maxAbsDelta1;
        uint64 maxSettlementAge;
        uint64 maxTwapDeviationBps;
        uint128 minCheckedLiquidity;
    }

    struct PoolConfigInput {
        bool enabled;
        bool settlementsPaused;
        bytes32 enclaveMeasurement;
        uint128 maxAbsDelta0;
        uint128 maxAbsDelta1;
        uint64 maxSettlementAge;
        uint64 maxTwapDeviationBps;
        uint128 minCheckedLiquidity;
    }

    Config public config;
    IEigenDarkVault public vault;
    mapping(bytes32 => bool) public settledOrders;
    bool public settlementsPaused;
    mapping(PoolId => PoolConfig) public poolConfigs;
    mapping(address => bool) public attestors;

    event ConfigUpdated(address indexed attestor, bytes32 indexed enclaveMeasurement, uint32 attestationWindow);
    event SettlementRecorded(
        bytes32 indexed orderId, PoolId indexed poolId, address indexed trader, int128 delta0, int128 delta1
    );
    event SettlementAudited(
        bytes32 indexed orderId,
        bytes32 metadataHash,
        uint160 sqrtPriceX96,
        uint64 twapDeviationBps,
        uint128 checkedLiquidity,
        address indexed attestor
    );
    event VaultUpdated(address indexed previousVault, address indexed newVault);
    event SettlementsPauseUpdated(bool paused);
    event PoolConfigured(
        PoolId indexed poolId,
        bool enabled,
        bool settlementsPaused,
        bytes32 enclaveMeasurement,
        uint128 maxAbsDelta0,
        uint128 maxAbsDelta1,
        uint64 maxSettlementAge,
        uint64 maxTwapDeviationBps,
        uint128 minCheckedLiquidity
    );
    event AttestorUpdated(address indexed attestor, bool allowed);

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
        permissions.afterSwap = true;
        permissions.beforeAddLiquidity = true;
        permissions.beforeRemoveLiquidity = true;
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

    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        pure
        override
        returns (bytes4, int128)
    {
        revert DirectSwapDisabled();
    }

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4)
    {
        revert PublicLiquidityNotAllowed();
    }

    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4)
    {
        revert PublicLiquidityNotAllowed();
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
            settlementsPaused: poolCfg.settlementsPaused,
            enclaveMeasurement: poolCfg.enclaveMeasurement,
            maxAbsDelta0: poolCfg.maxAbsDelta0,
            maxAbsDelta1: poolCfg.maxAbsDelta1,
            maxSettlementAge: poolCfg.maxSettlementAge,
            maxTwapDeviationBps: poolCfg.maxTwapDeviationBps,
            minCheckedLiquidity: poolCfg.minCheckedLiquidity
        });

        emit PoolConfigured(
            poolId,
            poolCfg.enabled,
            poolCfg.settlementsPaused,
            poolCfg.enclaveMeasurement,
            poolCfg.maxAbsDelta0,
            poolCfg.maxAbsDelta1,
            poolCfg.maxSettlementAge,
            poolCfg.maxTwapDeviationBps,
            poolCfg.minCheckedLiquidity
        );
    }

    function setAttestor(address attestor, bool allowed) external onlyOwner {
        require(attestor != address(0), "EigenDarkHook: INVALID_ATTESTOR");
        attestors[attestor] = allowed;
        emit AttestorUpdated(attestor, allowed);
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
        if (cfg.attestationWindow == 0) revert StaleAttestation();
        config = cfg;
        emit ConfigUpdated(address(0), bytes32(0), cfg.attestationWindow);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Settlements                                  */
    /* -------------------------------------------------------------------------- */

    function registerSettlement(Settlement calldata settlement, bytes calldata signature) external {
        Config memory localConfig = config;

        if (settlementsPaused) revert SettlementsPaused();
        if (settledOrders[settlement.orderId]) revert OrderAlreadySettled();

        if (block.timestamp < settlement.submittedAt) revert StaleAttestation();
        if (block.timestamp - settlement.submittedAt > localConfig.attestationWindow) revert StaleAttestation();
        _enforcePoolLimits(settlement);

        bytes32 digest = _hashTypedDataV4(_hashSettlement(settlement));
        address signer = ECDSA.recover(digest, signature);
        if (!attestors[signer]) revert InvalidAttestor();

        settledOrders[settlement.orderId] = true;
        vault.applySettlement(settlement.poolId, settlement.trader, settlement.delta0, settlement.delta1);
        emit SettlementRecorded(settlement.orderId, settlement.poolId, settlement.trader, settlement.delta0, settlement.delta1);
        emit SettlementAudited(
            settlement.orderId,
            settlement.metadataHash,
            settlement.sqrtPriceX96,
            settlement.twapDeviationBps,
            settlement.checkedLiquidity,
            signer
        );
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
                settlement.enclaveMeasurement,
                settlement.metadataHash,
                settlement.sqrtPriceX96,
                settlement.twapDeviationBps,
                settlement.checkedLiquidity
            )
        );
    }

    function _enforcePoolLimits(Settlement calldata settlement) private view {
        PoolConfig memory poolCfg = poolConfigs[settlement.poolId];
        if (!poolCfg.enabled) revert PoolNotConfigured();
        if (poolCfg.settlementsPaused) revert PoolSettlementsPaused();
        if (poolCfg.enclaveMeasurement != bytes32(0) && settlement.enclaveMeasurement != poolCfg.enclaveMeasurement) {
            revert InvalidMeasurement();
        }

        if (poolCfg.maxSettlementAge != 0 && block.timestamp - settlement.submittedAt > poolCfg.maxSettlementAge) {
            revert StaleAttestation();
        }

        if (poolCfg.maxAbsDelta0 != 0 && _absInt128(settlement.delta0) > poolCfg.maxAbsDelta0) {
            revert DeltaLimitExceeded();
        }

        if (poolCfg.maxAbsDelta1 != 0 && _absInt128(settlement.delta1) > poolCfg.maxAbsDelta1) {
            revert DeltaLimitExceeded();
        }

        if (poolCfg.maxTwapDeviationBps != 0 && settlement.twapDeviationBps > poolCfg.maxTwapDeviationBps) {
            revert TwapDeviationExceeded();
        }

        if (poolCfg.minCheckedLiquidity != 0 && settlement.checkedLiquidity < poolCfg.minCheckedLiquidity) {
            revert InsufficientCheckedLiquidity();
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

