// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IEigenDarkVault} from "./interfaces/IEigenDarkVault.sol";

/**
 * @title EigenDarkVault
 * @notice Holds token reserves for EigenDark pools and executes net settlements on hook instructions.
 * @dev This implementation does **not** rely on FHE. All balances are standard ERC20 transfers.
 */
contract EigenDarkVault is IEigenDarkVault, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    struct Pool {
        IERC20 token0;
        IERC20 token1;
        bool exists;
        uint256 total0;
        uint256 total1;
    }

    mapping(PoolId => Pool) public pools;
    address public hook;

    event PoolRegistered(PoolId indexed poolId, address token0, address token1);
    event Deposited(PoolId indexed poolId, address indexed from, uint256 amount0, uint256 amount1);
    event Withdrawn(PoolId indexed poolId, address indexed to, uint256 amount0, uint256 amount1);
    event HookUpdated(address indexed newHook);
    event SettlementApplied(PoolId indexed poolId, address indexed trader, int128 delta0, int128 delta1);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /* -------------------------------------------------------------------------- */
    /*                              Admin functions                               */
    /* -------------------------------------------------------------------------- */

    function registerPool(PoolKey calldata key) external onlyOwner {
        PoolId poolId = key.toId();
        Pool storage pool = pools[poolId];
        require(!pool.exists, "EigenDarkVault: POOL_EXISTS");

        address token0Addr = Currency.unwrap(key.currency0);
        address token1Addr = Currency.unwrap(key.currency1);
        require(token0Addr != address(0) && token1Addr != address(0), "EigenDarkVault: NATIVE_UNSUPPORTED");

        pool.token0 = IERC20(token0Addr);
        pool.token1 = IERC20(token1Addr);
        pool.exists = true;

        emit PoolRegistered(poolId, token0Addr, token1Addr);
    }

    function setHook(address newHook) external onlyOwner {
        require(newHook != address(0), "EigenDarkVault: INVALID_HOOK");
        hook = newHook;
        emit HookUpdated(newHook);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidity management                            */
    /* -------------------------------------------------------------------------- */

    function deposit(PoolKey calldata key, uint256 amount0, uint256 amount1) external nonReentrant {
        Pool storage pool = _requirePool(key.toId());
        if (amount0 > 0) {
            pool.token0.safeTransferFrom(msg.sender, address(this), amount0);
            pool.total0 += amount0;
        }
        if (amount1 > 0) {
            pool.token1.safeTransferFrom(msg.sender, address(this), amount1);
            pool.total1 += amount1;
        }
        emit Deposited(key.toId(), msg.sender, amount0, amount1);
    }

    function withdraw(PoolId poolId, address to, uint256 amount0, uint256 amount1) external onlyOwner nonReentrant {
        Pool storage pool = _requirePool(poolId);
        if (amount0 > 0) {
            require(pool.total0 >= amount0, "EigenDarkVault: INSUFFICIENT_TOKEN0");
            pool.total0 -= amount0;
            pool.token0.safeTransfer(to, amount0);
        }
        if (amount1 > 0) {
            require(pool.total1 >= amount1, "EigenDarkVault: INSUFFICIENT_TOKEN1");
            pool.total1 -= amount1;
            pool.token1.safeTransfer(to, amount1);
        }
        emit Withdrawn(poolId, to, amount0, amount1);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Settlement execution                             */
    /* -------------------------------------------------------------------------- */

    modifier onlyHook() {
        require(msg.sender == hook, "EigenDarkVault: UNAUTHORIZED_HOOK");
        _;
    }

    function applySettlement(PoolId poolId, address trader, int128 delta0, int128 delta1)
        external
        override
        onlyHook
        nonReentrant
    {
        Pool storage pool = _requirePool(poolId);

        _applyDeltaToken0(pool, delta0, trader);
        _applyDeltaToken1(pool, delta1, trader);

        emit SettlementApplied(poolId, trader, delta0, delta1);
    }

    function _applyDeltaToken0(Pool storage pool, int128 delta, address trader) private {
        if (delta == 0) return;
        if (delta > 0) {
            uint256 amount = uint256(int256(delta));
            require(pool.total0 >= amount, "EigenDarkVault: INSUFFICIENT_TOKEN0");
            pool.total0 -= amount;
            pool.token0.safeTransfer(trader, amount);
        } else {
            uint256 amount = uint256(int256(-delta));
            pool.token0.safeTransferFrom(trader, address(this), amount);
            pool.total0 += amount;
        }
    }

    function _applyDeltaToken1(Pool storage pool, int128 delta, address trader) private {
        if (delta == 0) return;
        if (delta > 0) {
            uint256 amount = uint256(int256(delta));
            require(pool.total1 >= amount, "EigenDarkVault: INSUFFICIENT_TOKEN1");
            pool.total1 -= amount;
            pool.token1.safeTransfer(trader, amount);
        } else {
            uint256 amount = uint256(int256(-delta));
            pool.token1.safeTransferFrom(trader, address(this), amount);
            pool.total1 += amount;
        }
    }

    function _requirePool(PoolId poolId) private view returns (Pool storage pool) {
        pool = pools[poolId];
        require(pool.exists, "EigenDarkVault: UNKNOWN_POOL");
    }
}

