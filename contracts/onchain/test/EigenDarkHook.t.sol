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
import {IEigenDarkVault} from "../src/interfaces/IEigenDarkVault.sol";

contract EigenDarkHookTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenDarkHook hook;
    MockVault vault;
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

        vault = new MockVault();

        // Hook addresses require the permission bits encoded into the address.
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144));
        bytes memory constructorArgs = abi.encode(poolManager, cfg, address(this), IEigenDarkVault(address(vault)));
        deployCodeTo("EigenDarkHook.sol:EigenDarkHook", constructorArgs, flags);
        hook = EigenDarkHook(flags);
        vault.setHook(address(hook));

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = poolKey.toId();

        hook.configurePool(
            poolKey,
            EigenDarkHook.PoolConfigInput({
                enabled: true,
                maxAbsDelta0: type(uint128).max,
                maxAbsDelta1: type(uint128).max,
                maxSettlementAge: 0
            })
        );
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
        assertEq(PoolId.unwrap(vault.lastPool()), PoolId.unwrap(poolId));
        assertEq(vault.lastTrader(), settlement.trader);
        assertEq(vault.lastDelta0(), settlement.delta0);
        assertEq(vault.lastDelta1(), settlement.delta1);
    }

    function testRegisterSettlementRevertsOnReplay() public {
        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes memory signature = _signSettlement(settlement);
        hook.registerSettlement(settlement, signature);

        vm.expectRevert(EigenDarkHook.OrderAlreadySettled.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testRegisterSettlementRevertsWhenPoolNotConfigured() public {
        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        settlement.poolId = PoolId.wrap(bytes32("unconfigured"));
        bytes memory signature = _signSettlement(settlement);

        vm.expectRevert(EigenDarkHook.PoolNotConfigured.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testRegisterSettlementRevertsWhenDeltaTooLarge() public {
        hook.configurePool(
            poolKey,
            EigenDarkHook.PoolConfigInput({
                enabled: true,
                maxAbsDelta0: uint128(5e17),
                maxAbsDelta1: type(uint128).max,
                maxSettlementAge: 0
            })
        );

        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes memory signature = _signSettlement(settlement);

        vm.expectRevert(EigenDarkHook.DeltaLimitExceeded.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testConfigurePoolRequiresHookAddress() public {
        PoolKey memory wrongKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(this)));
        vm.expectRevert(EigenDarkHook.InvalidPoolHook.selector);
        hook.configurePool(
            wrongKey,
            EigenDarkHook.PoolConfigInput({
                enabled: true,
                maxAbsDelta0: type(uint128).max,
                maxAbsDelta1: type(uint128).max,
                maxSettlementAge: 0
            })
        );
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

    function testSettlementFailsWhenPaused() public {
        hook.setSettlementsPaused(true);

        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes memory signature = _signSettlement(settlement);

        vm.expectRevert(EigenDarkHook.SettlementsPaused.selector);
        hook.registerSettlement(settlement, signature);
    }

    function testOwnerCanUpdateVault() public {
        MockVault newVault = new MockVault();
        newVault.setHook(address(hook));

        hook.setVault(newVault);

        EigenDarkHook.Settlement memory settlement = _defaultSettlement();
        bytes memory signature = _signSettlement(settlement);

        hook.registerSettlement(settlement, signature);
        assertEq(newVault.lastTrader(), settlement.trader);
        assertEq(PoolId.unwrap(newVault.lastPool()), PoolId.unwrap(settlement.poolId));
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

contract MockVault is IEigenDarkVault {
    PoolId private _lastPool;
    address private _lastTrader;
    int128 private _lastDelta0;
    int128 private _lastDelta1;
    address public hook;

    modifier onlyHook() {
        require(msg.sender == hook, "MockVault: not hook");
        _;
    }

    function setHook(address hook_) external {
        hook = hook_;
    }

    function applySettlement(PoolId poolId, address trader, int128 delta0, int128 delta1) external override onlyHook {
        _lastPool = poolId;
        _lastTrader = trader;
        _lastDelta0 = delta0;
        _lastDelta1 = delta1;
    }

    function lastPool() external view returns (PoolId) {
        return _lastPool;
    }

    function lastTrader() external view returns (address) {
        return _lastTrader;
    }

    function lastDelta0() external view returns (int128) {
        return _lastDelta0;
    }

    function lastDelta1() external view returns (int128) {
        return _lastDelta1;
    }
}

