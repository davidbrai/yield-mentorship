// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CollateralizedVault} from "src/assignment-5/CollateralizedVault.sol";
import {Dai} from "src/assignment-5/DAI.sol";
import {WETH9} from "src/assignment-5/WETH.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";
import {ChainlinkPriceFeedMock} from "src/assignment-5/ChainlinkPriceFeedMock.sol";

abstract contract ZeroState is Test {

    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Liquidate(address indexed user, uint256 debtAmount, uint256 collateralAmount);

    using stdStorage for StdStorage;

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

        setDaiBalance(address(vault), 10000 ether);
        setWethBalance(USER, 10 ether);
        vm.prank(USER);
        weth.approve(address(vault), 10 ether);
    }

    function setDaiBalance(address dst, uint256 balance) public {
        stdstore
            .target(address(dai))
            .sig(dai.balanceOf.selector)
            .with_key(dst)
            .depth(0)
            .checked_write(balance);
    }

    function setWethBalance(address dst, uint256 balance) public {
        stdstore
            .target(address(weth))
            .sig(weth.balanceOf.selector)
            .with_key(dst)
            .depth(0)
            .checked_write(balance);
    }
}

contract ZeroStateTest is ZeroState {

    function testDeposit() public {
        vm.prank(USER);
        vm.expectEmit(true, true, true, true);
        emit Deposit(USER, 3 ether);
        vault.deposit(3 ether);

        // 3 WETH was transfered to the vault
        assertEq(weth.balanceOf(USER), 7 ether);
        assertEq(weth.balanceOf(address(vault)), 3 ether);

        // User collateral is recorded
        assertEq(vault.deposits(USER), 3 ether);
    }

    function testDepositMultipleTimesAccumulatesCollateral() public {
        vm.startPrank(USER);

        vault.deposit(1 ether);
        vault.deposit(1 ether);

        assertEq(weth.balanceOf(address(vault)), 2 ether);
        assertEq(vault.deposits(USER), 2 ether);
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

abstract contract DepositedCollateralState is ZeroState {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(USER);
        vault.deposit(3 ether);

        vm.prank(USER);
        dai.approve(address(vault), type(uint256).max);
    }
}

contract DepositedCollateralStateTest is DepositedCollateralState {
    function testBorrow() public {
        vm.prank(USER);
        vm.expectEmit(true, true, true, true);
        emit Borrow(USER, 6000 * 1e18);
        vault.borrow(6000 * 1e18);

        // 6000 DAI was transfered to the USER
        assertEqDecimal(dai.balanceOf(USER), 6000 * 1e18, 18);

        // User debt is recorded
        assertEq(vault.borrows(USER), 6000 * 1e18);
    }

    function testBorrowMultipleTimesAccumulatesDebt() public {
        vm.startPrank(USER);

        vault.borrow(5 * 1e18);
        vault.borrow(10 * 1e18);

        assertEqDecimal(dai.balanceOf(USER), 15 * 1e18, 18);
        assertEq(vault.borrows(USER), 15 * 1e18);
    }

    function testRevertsWhenTryingToBorrowTooMuch() public {
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.NotEnoughCollateral.selector);
        vault.borrow(6000 * 1e18 + 1);
    }
}

abstract contract BorrowedState is DepositedCollateralState {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(USER);
        vault.borrow(6000 * 1e18);
    }
}

contract BorrowedStateTest is BorrowedState {
    function testRepayDebt() public {
        assertEq(vault.borrows(USER), 3 * 2000 ether);

        vm.prank(USER);
        vm.expectEmit(true, true, true, true);
        emit Repay(USER, 2000 ether);
        vault.repay(2000 ether);

        assertEq(vault.borrows(USER), 2 * 2000 ether);
        assertEq(dai.balanceOf(USER), 2 * 2000 ether);
    }

    function testRepayTooMuchDebtReverts() public {
        vm.prank(USER);
        vm.expectRevert(stdError.arithmeticError);
        vault.repay(6001 ether);
    }

    function testCantWithdrawCollateral() public {
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdraw(1);
    }

    function testCanWithdrawEntireCollateralIfPaidAllDebt() public {
        assertEq(weth.balanceOf(USER), 7 ether);
        assertEq(vault.borrows(USER), 6000 * 1e18);
        assertEq(vault.deposits(USER), 3 ether);

        // Repay entire debt
        vm.startPrank(USER);
        vault.repay(3 * 2000 ether);
        // No more debt
        assertEq(vault.borrows(USER), 0);
        // But also no more DAI
        assertEq(dai.balanceOf(USER), 0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(USER, 3 ether);
        vault.withdraw(3 ether);
        // WETH is returned to user
        assertEq(weth.balanceOf(USER), 10 ether);
    }

    function testOnlyOwnerCanLiquidate() public {
        vm.prank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        vault.liquidate(USER);
    }

    function testOwnerCantLiquidateIfDebtIsCollateralized() public {
        vm.expectRevert(CollateralizedVault.UserDebtIsSufficientlyCollateralized.selector);
        vault.liquidate(USER);
    }

    function testOwnerCanLiquidateIfDebtIsUnderCollateralized() public {
        // WETH went down, now only $1000, DAI/ETH = 1/1000
        priceFeedMock.setPrice(1e18 / 1000);

        // Need 6 WETH
        assertEq(vault.getRequiredCollateral(vault.borrows(USER)), 6 ether);
        // But only 3 is deposited
        assertEq(vault.deposits(USER), 3 ether);

        // liquidate user
        vm.expectEmit(true, true, true, true);
        emit Liquidate(USER, 6000 ether, 3 ether);
        vault.liquidate(USER);

        assertEq(vault.deposits(USER), 0);
        assertEq(vault.borrows(USER), 0);
    }
}

abstract contract PartiallyRepaidDebtState is BorrowedState {
    function setUp() virtual override public {
        super.setUp();

        // Repay 2 thirds of debt
        vm.prank(USER);
        vault.repay(2 * 2000 ether);
    }
}

contract PartiallyRepaidDebtStateTest is PartiallyRepaidDebtState {

    function testWithdrawPartialCollateral() public {
        // 1 third debt left
        assertEq(vault.borrows(USER), 2000 ether);

        vm.prank(USER);
        vault.withdraw(2 ether);
        // WETH is returned to user
        assertEq(weth.balanceOf(USER), 9 ether);
    }

    function testRevertWhenTryingToWithdrawTooMuch() public {
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdraw(2 ether + 1);
    }

    function testCanWithdrawLessIfPriceMovedNegatively() public {
        // WETH went down, now only $1000, price = 1/1000
        priceFeedMock.setPrice(1e18 / 1000);

        // can't withdraw 2 WETH
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdraw(2 ether);

        // but 1 WETH is OK
        vm.prank(USER);
        vault.withdraw(1 ether);
    }

    function testCanWithdrawMoreIfPriceMovePositively() public {
        // WETH went up 25%, now at $2500, price = 1/2500
        priceFeedMock.setPrice(1e18 / 2500);

        // User has debt of 2000 DAI, that's 0.8 WETH
        assertEq(vault.borrows(USER), 2000 ether);

        // User currently has 3 WETH as collateral
        assertEq(vault.deposits(USER), 3 ether);

        // User needs to leave 0.8 WETH collateral, so can withdraw 2.2 WETH
        // Making sure he can't withdraw more than that first
        vm.prank(USER);
        vm.expectRevert(CollateralizedVault.TooMuchDebt.selector);
        vault.withdraw(2.2 ether + 1);

        // And checking that he can withdraw 2.2 WETH
        vm.prank(USER);
        vault.withdraw(2.2 ether);
    }
}