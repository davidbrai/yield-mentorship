// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CollateralizedVault} from "src/assignment-5/CollateralizedVault.sol";
import {Dai} from "src/assignment-5/DAI.sol";
import {WETH9} from "src/assignment-5/WETH.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";
import {ChainlinkPriceFeedMock} from "src/assignment-5/ChainlinkPriceFeedMock.sol";

abstract contract ZeroState is Test {

    address USER = address(1);
    CollateralizedVault vault;
    Dai dai;
    WETH9 weth;
    ChainlinkPriceFeedMock priceFeedMock;

    function setUp() public virtual {
        dai = new Dai(block.chainid);
        weth = new WETH9();
        priceFeedMock = new ChainlinkPriceFeedMock();
        priceFeedMock.setPrice(500000000000000); // = 1/2000
        vault = new CollateralizedVault(address(dai), address(weth), address(priceFeedMock));

        dai.mint(address(vault), 10000 ether);
        weth.mint(USER, 10 ether);
        vm.prank(USER);
        weth.approve(address(vault), 10 ether);
    }
}

contract ZeroStateTest is ZeroState {
    function testDeposit() public {
        vm.prank(USER);
        vault.deposit(3 ether);

        // 3 WETH was transfered to the vault
        assertEq(weth.balanceOf(USER), 7 ether);
        assertEq(weth.balanceOf(address(vault)), 3 ether);

        // 6000 DAI was transfered to the USER
        assertEqDecimal(dai.balanceOf(USER), 3 * 2000 ether, 18);

        assertEq(vault.depositedCollateral(USER), 3 ether);
        assertEq(vault.debt(USER), 3 * 2000 ether);
    }

    function testScaleInteger() public {
        // scale 12.345 from 6 decimals to 18
        uint256 from = (12345 * 1e6) / 1e3;
        uint256 to = vault.scaleInteger(from, 6, 18);

        assertEq(to, (12345 * 1e18) / 1e3);

        // test reverse
        assertEq(vault.scaleInteger(to, 18, 6), from);
    }
}

abstract contract DepositedState is ZeroState {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(USER);
        vault.deposit(3 ether);

        vm.prank(USER);
        dai.approve(address(vault), type(uint256).max);
    }
}

contract DepositedStateTest is DepositedState {
    function testRepayDebt() public {
        assertEq(vault.debt(USER), 3 * 2000 ether);

        vm.prank(USER);
        vault.repayDebt(2000 ether);

        assertEq(vault.debt(USER), 2 * 2000 ether);
        assertEq(dai.balanceOf(USER), 2 * 2000 ether);
    }

    function testRepayTooMuchDebtReverts() public {
        vm.prank(USER);
        vm.expectRevert(stdError.arithmeticError);
        vault.repayDebt(6001 ether);
    }

    function testCantWithdrawCollateral() public {
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdrawCollateral(1);
    }

    function testCanWithdrawEntireCollateralIfPaidAllDebt() public {
        assertEq(weth.balanceOf(USER), 7 ether);
        assertEq(vault.debt(USER), 3 * 2000 ether);
        assertEq(vault.depositedCollateral(USER), 3 ether);

        // Repay entire debt
        vm.startPrank(USER);
        vault.repayDebt(3 * 2000 ether);
        // No more debt
        assertEq(vault.debt(USER), 0);
        // But also no more DAI
        assertEq(dai.balanceOf(USER), 0);

        vault.withdrawCollateral(3 ether);
        // WETH is returned to user
        assertEq(weth.balanceOf(USER), 10 ether);
    }

    function testOwnerCantLiquidateIfDebtIsCollateralized() public {
        vm.expectRevert(CollateralizedVault.UserDebtIsSufficientlyCollateralized.selector);
        vault.liquidateUser(USER);
    }

    function testOwnerCanLiquidateIfDebtIsUnderCollateralized() public {
        // WETH went down, now only $1000, DAI/ETH = 1/1000
        priceFeedMock.setPrice(1e18 / 1000);

        // Need 6 WETH
        assertEq(vault.getRequiredCollateral(USER), 6 ether);
        // But only 3 is deposited
        assertEq(vault.depositedCollateral(USER), 3 ether);

        // liquidate user
        vault.liquidateUser(USER);

        assertEq(vault.depositedCollateral(USER), 0);
        assertEq(vault.debt(USER), 0);
    }
}

abstract contract PartiallyRepaidDebtState is DepositedState {
    function setUp() virtual override public {
        super.setUp();

        // Repay 2 thirds of debt
        vm.prank(USER);
        vault.repayDebt(2 * 2000 ether);
    }
}

contract PartiallyRepaidDebtStateTest is PartiallyRepaidDebtState {

    function testWithdrawPartialCollateral() public {
        // 1 third debt left
        assertEq(vault.debt(USER), 2000 ether);

        vm.prank(USER);
        vault.withdrawCollateral(2 ether);
        // WETH is returned to user
        assertEq(weth.balanceOf(USER), 9 ether);
    }

    function testRevertWhenTryingToWithdrawTooMuch() public {
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdrawCollateral(2 ether + 1);
    }

    function testCanWithdrawLessIfPriceMovedNegatively() public {
        // WETH went down, now only $1000, price = 1/1000
        priceFeedMock.setPrice(1e18 / 1000);

        // can't withdraw 2 WETH
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdrawCollateral(2 ether);

        // but 1 WETH is OK
        vm.prank(USER);
        vault.withdrawCollateral(1 ether);
    }

    function testCanWithdrawMoreIfPriceMovePositively() public {
        // WETH went up 25%, now at $2500, price = 1/2500
        priceFeedMock.setPrice(1e18 / 2500);

        // User has debt of 2000 DAI, that's 0.8 WETH
        assertEq(vault.debt(USER), 2000 ether);

        // User currently has 3 WETH as collateral
        assertEq(vault.depositedCollateral(USER), 3 ether);

        // User needs to leave 0.8 WETH collateral, so can withdraw 2.2 WETH
        // Making sure he can't withdraw more than that first
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdrawCollateral(2.2 ether + 1);

        // And checking that he can withdraw 2.2 WETH
        vm.prank(USER);
        vault.withdrawCollateral(2.2 ether);
    }
}