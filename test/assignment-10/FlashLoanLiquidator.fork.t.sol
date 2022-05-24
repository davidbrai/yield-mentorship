// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { IERC20 } from "yield-utils-v2/token/IERC20.sol";
import { FlashLoanLiquidator } from "src/assignment-10/FlashLoanLiquidator.sol";
import { CollateralizedVault } from "src/assignment-10/CollateralizedVault.sol";
import { ChainlinkPriceFeedMock } from "src/assignment-5/ChainlinkPriceFeedMock.sol";
import { AMM } from "src/assignment-7/AMM.sol";

abstract contract ZeroState is Test {

    using stdStorage for StdStorage;

    FlashLoanLiquidator liquidator;

    // @dev mainnet addresses
    IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address uniV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    CollateralizedVault vault;
    ChainlinkPriceFeedMock oracle;
    AMM amm;

    address alice = address(1);
    address bob = address(2);

    function setUp() virtual public {
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        oracle = new ChainlinkPriceFeedMock();
        oracle.setPrice(1e18 / 2000); // 1 WETH = 2000 DAI

        // underlying: DAI, collateral: WETH
        vault = new CollateralizedVault(address(dai), address(weth), address(oracle));
        setDaiBalance(address(vault), 10000 * 1e18);

        amm = new AMM(dai, weth, "dex", "LP", 18);
        
        liquidator = new FlashLoanLiquidator(address(dai), address(weth), uniV2Factory, address(vault), address(amm));
        vm.label(address(liquidator), "FlashLoanLiquidator");

        setWethBalance(alice, 1 ether);
    }

    function initAMM(uint256 wethPrice) internal {
        setDaiBalance(address(this), wethPrice * 1e18 * 100);
        setWethBalance(address(this), 100 ether);
        dai.approve(address(amm), type(uint256).max);
        weth.approve(address(amm), type(uint256).max);
        amm.init(wethPrice * 1e18 * 100, 100 ether);
    }

    function setDaiBalance(address dst, uint256 balance) internal {
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
    function testUnauthorizedCallbackSenderIsReverted() public {
        vm.expectRevert(FlashLoanLiquidator.UnauthorizedMsgSender.selector);
        liquidator.uniswapV2Call(address(0x0), 123, 123, "");
    }

    function testUnauthorizedCallbackInitiatorIsReverted() public {
        vm.prank(liquidator.permissionedPair());
        vm.expectRevert(FlashLoanLiquidator.UnauthorizedInitiator.selector);
        liquidator.uniswapV2Call(address(0x0), 123, 123, "");
    }

    function testRevertsIfDebtPositionIsNotUndercollateralized() public {
        // Alice deposits 1 WETH, and borrows 66% * 2000 DAI = 1320 DAI against it
        vm.startPrank(alice);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether);
        vault.borrow(1320 * 1e18);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(FlashLoanLiquidator.NotUndercollateralized.selector);
        liquidator.liquidate(alice);
    }
}

abstract contract UndercollateralizedDebtState is ZeroState {
    function setUp() public virtual override {
        super.setUp();

        // Alice deposits 1 WETH, and borrows 66% * 2000 DAI = 1320 DAI against it
        vm.startPrank(alice);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether);
        vault.borrow(1320 * 1e18);
        vm.stopPrank();
    }
}

contract UndercollateralizedDebtStateTest is UndercollateralizedDebtState {
    event Liquidate(address indexed liquidator, address indexed liquidatee, uint256 profit);

    function testLiquidate() public {
        // Then price of WETH falls so vault becomes undercollateralized
        oracle.setPrice(1e18 / 1600);
        initAMM(1600);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Liquidate(bob, alice, 260186500094342433239);
        liquidator.liquidate(alice);

        assertEq(dai.balanceOf(bob), 260186500094342433239);
    }

    function testRevertsIfNoProfit() public {
        // oracle WETH price is at $1600
        oracle.setPrice(1e18 / 1600);

        // but AMM is at $1000
        initAMM(1000);

        vm.prank(bob);
        vm.expectRevert(stdError.arithmeticError);
        liquidator.liquidate(alice);
    }
}