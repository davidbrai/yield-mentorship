// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CollateralizedVault} from "src/assignment-5/CollateralizedVault.sol";
import {USDC} from "src/assignment-5/USDCMock.sol";
import {WETH9} from "src/assignment-5/WETH.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";
import {ChainlinkPriceFeedMock} from "src/assignment-5/ChainlinkPriceFeedMock.sol";

abstract contract ZeroState is Test {

    address USER = address(1);
    CollateralizedVault vault;
    USDC usdc;
    WETH9 weth;
    ChainlinkPriceFeedMock priceFeedMock;

    function setUp() public virtual {
        usdc = new USDC();
        weth = new WETH9();
        priceFeedMock = new ChainlinkPriceFeedMock();
        priceFeedMock.setPrice(500000000000000); // = 1/2000
        vault = new CollateralizedVault(address(usdc), address(weth), address(priceFeedMock));

        usdc.mint(address(vault), 1e27 * 1e6);
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

        // 6000 USDC was transfered to the USER
        assertEqDecimal(usdc.balanceOf(USER), 6000 * 1e6, 6);

        // Collateral is 3 WETH
        assertEq(vault.depositedCollateral(USER), 3 ether);

        // Debt is 6000 USDC
        assertEq(vault.debt(USER), 6000 * 1e6);
    }
}
