// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {EigenDarkHook} from "../src/EigenDarkHook.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract EigenDarkHookTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenDarkHook hook;
    PoolKey poolKey;
    PoolId poolId;
    Currency currency0;
    Currency currency1;

    bytes32 constant MEASUREMENT = keccak256("measurement");
    uint256 constant ATTESTOR_PK = 0xA11CE;
    address attestor = vm.addr(ATTESTOR_PK);

    function setUp() public {
        deployArtifactsAndLabel();
        (currency0, currency1) = deployCurrencyPair();

        EigenDarkHook.Config memory cfg =
            EigenDarkHook.Config({attestor: attestor, enclaveMeasurement: MEASUREMENT, attestationWindow: 1 hours});

        // Hook addresses require the permission bits encoded into the address.
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(poolManager, cfg, address(this));
        deployCodeTo("EigenDarkHook.sol:EigenDarkHook", constructorArgs, flags);
        hook = EigenDarkHook(flags);

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = poolKey.toId();
    }

    function testRegisterSettlement() public {
        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes memory signature = _signSettlement(settlement);

        vm.expectEmit(true, true, true, true);
        emit EigenDarkHook.SettlementRecorded(
            settlement.orderId, settlement.poolId, settlement.trader, settlement.delta0, settlement.delta1
        );

        hook.registerSettlement(settlement, signature);
        assertTrue(hook.settledOrders(settlement.orderId));
    }

    function testRegisterSettlementRevertsOnReplay() public {
        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes memory signature = _signSettlement(settlement);
        hook.registerSettlement(settlement, signature);

        vm.expectRevert(EigenDarkHook.OrderAlreadySettled.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testRegisterSettlementRevertsOnBadSignature() public {
        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes32 digest = hook.previewSettlementDigest(settlement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_PK + 1, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(EigenDarkHook.InvalidAttestor.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testRegisterSettlementRevertsOnStaleAttestation() public {
        vm.warp(10 hours);
        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        settlement.submittedAt = uint64(block.timestamp - 2 hours);
        bytes memory signature = _signSettlement(settlement);

        vm.expectRevert(EigenDarkHook.StaleAttestation.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testDirectSwapIsBlocked() public {
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0});
        vm.expectRevert(EigenDarkHook.DirectSwapDisabled.selector);
        vm.prank(address(poolManager));
        hook.beforeSwap(address(this), poolKey, params, "");
    }

    /* -------------------------------------------------------------------------- */
    /*                                   utils                                    */
    /* -------------------------------------------------------------------------- */

    function _defaultSettlement() internal view returns (EigenDarkHook.Settlement memory) {
        return EigenDarkHook.Settlement({
            orderId: keccak256("order-1"),
            poolId: poolId,
            trader: address(0xBEEF),
            delta0: int128(int256(1e18)),
            delta1: -int128(int256(2e18)),
            submittedAt: uint64(block.timestamp),
            enclaveMeasurement: MEASUREMENT
        });
    }

    function _signSettlement(EigenDarkHook.Settlement memory settlement) internal view returns (bytes memory) {
        bytes32 digest = hook.previewSettlementDigest(settlement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_PK, digest);
        return abi.encodePacked(r, s, v);
    }

}

