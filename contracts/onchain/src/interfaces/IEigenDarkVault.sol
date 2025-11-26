// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title IEigenDarkVault
 * @notice Minimal interface the hook uses to settle token flows against the vault.
 */
interface IEigenDarkVault {
    /**
     * @notice Applies a net token delta for a trader against a specific pool.
     * @dev Positive deltas send tokens from the vault to the trader, negative deltas pull tokens from the trader.
     * @param poolId     Pool identifier (matches Uniswap v4 PoolId)
     * @param trader     Recipient or payer address
     * @param delta0     Net token0 amount (signed)
     * @param delta1     Net token1 amount (signed)
     */
    function applySettlement(PoolId poolId, address trader, int128 delta0, int128 delta1) external;
}

