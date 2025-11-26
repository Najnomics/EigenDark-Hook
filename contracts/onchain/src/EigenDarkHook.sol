// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

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

    Config public config;
    mapping(bytes32 => bool) public settledOrders;

    event ConfigUpdated(address indexed attestor, bytes32 indexed enclaveMeasurement, uint32 attestationWindow);
    event SettlementRecorded(
        bytes32 indexed orderId, PoolId indexed poolId, address indexed trader, int128 delta0, int128 delta1
    );

    constructor(IPoolManager _poolManager, Config memory cfg, address initialOwner)
        BaseHook(_poolManager)
        Ownable(initialOwner)
        EIP712("EigenDarkSettlement", "0.1")
    {
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

        if (settlement.enclaveMeasurement != localConfig.enclaveMeasurement) revert InvalidMeasurement();
        if (settledOrders[settlement.orderId]) revert OrderAlreadySettled();

        if (block.timestamp < settlement.submittedAt) revert StaleAttestation();
        if (block.timestamp - settlement.submittedAt > localConfig.attestationWindow) revert StaleAttestation();

        bytes32 digest = _hashTypedDataV4(_hashSettlement(settlement));
        address signer = ECDSA.recover(digest, signature);
        if (signer != localConfig.attestor) revert InvalidAttestor();

        settledOrders[settlement.orderId] = true;
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
}

