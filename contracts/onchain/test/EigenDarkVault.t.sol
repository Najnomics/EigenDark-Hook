// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {EigenDarkVault} from "../src/EigenDarkVault.sol";

contract EigenDarkVaultTest is Test {
    TestToken token0;
    TestToken token1;
    EigenDarkVault vault;
    PoolKey poolKey;
    PoolId poolId;
    address lp = address(0xBEEF);
    address trader = address(0xCAFE);

    function setUp() public {
        token0 = new TestToken("Token0", "TK0");
        token1 = new TestToken("Token1", "TK1");
        token0.mint(address(this), 1_000 ether);
        token1.mint(address(this), 1_000 ether);

        vault = new EigenDarkVault(address(this));

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        poolId = poolKey.toId();

        vault.registerPool(poolKey);
        vault.setHook(address(this));

        token0.transfer(lp, 100 ether);
        token1.transfer(lp, 100 ether);
        vm.startPrank(lp);
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function testDepositAndTotals() public {
        vm.prank(lp);
        vault.deposit(poolKey, 10 ether, 20 ether);

        (,,, uint256 total0, uint256 total1) = vault.pools(poolId);
        assertEq(total0, 10 ether);
        assertEq(total1, 20 ether);
    }

    function testWithdrawByOwner() public {
        vm.prank(lp);
        vault.deposit(poolKey, 15 ether, 15 ether);

        vault.withdraw(poolId, address(this), 5 ether, 10 ether);

        (,,, uint256 total0, uint256 total1) = vault.pools(poolId);
        assertEq(total0, 10 ether);
        assertEq(total1, 5 ether);
    }

    function testApplySettlementPaysOutAndPullsIn() public {
        vm.prank(lp);
        vault.deposit(poolKey, 30 ether, 40 ether);

        token1.transfer(trader, 50 ether);
        vm.prank(trader);
        token1.approve(address(vault), type(uint256).max);

        vault.applySettlement(poolId, trader, int128(int256(5 ether)), -int128(int256(7 ether)));

        assertEq(token0.balanceOf(trader), 5 ether);
        assertEq(token1.balanceOf(trader), 43 ether); // started 50, paid in 7

        (,,, uint256 total0, uint256 total1) = vault.pools(poolId);
        assertEq(total0, 25 ether);
        assertEq(total1, 47 ether);
    }

    function testApplySettlementRevertsWhenNotHook() public {
        address other = address(0x1234);
        vm.prank(other);
        vm.expectRevert("EigenDarkVault: UNAUTHORIZED_HOOK");
        vault.applySettlement(poolId, trader, 1, 1);
    }
}

contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

