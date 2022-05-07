// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {FractionalWrapper} from "src/assignment-4/FractionalWrapper.sol";
import {YearnVaultMock} from "src/assignment-4/YearnVaultMock.sol";
import {FunToken} from "src/assignment-3/FunToken.sol";

abstract contract ZeroState is Test {
    
    FractionalWrapper wrapper;
    YearnVaultMock yvToken;
    FunToken token;
    uint256 constant RAY = 1e27;

    address USER = address(1);

    function setUp() public virtual {
        token = new FunToken();
        yvToken = new YearnVaultMock(address(token), "Yearn Vault Mock", "YVMock", token.decimals());
        yvToken.setPricePerShareMock(2 * RAY);
        wrapper = new FractionalWrapper(address(token), address(yvToken), "Fractional Wrapper", "FracWrap", yvToken.decimals());

        token.mint(USER, 5000);
        vm.prank(USER);
        token.approve(address(wrapper), 5000);
    }
}

contract ZeroStateTest is ZeroState {
    function testDepositingIntoWrapperSendsTokensToYVault() public {
        vm.prank(USER);
        wrapper.deposit(3000);

        assertEq(token.balanceOf(USER), 2000);
        assertEq(token.balanceOf(address(wrapper)), 0);
        assertEq(token.balanceOf(address(yvToken)), 3000);
    }

    function testDepositingIntoWrapperReturnsCorrectAmountOfWrapperShares() public {
        vm.prank(USER);
        wrapper.deposit(3000);

        assertEq(wrapper.balanceOf(USER), 1500);
    }

    function testDepositingIntoWrapperSendsYearnVaultSharesIntoWrapper() public {
        vm.prank(USER);
        wrapper.deposit(3000);

        assertEq(yvToken.balanceOf(address(wrapper)), 1500);
    }

    function testReturnsNumberOfWrapperTokensSentToUser() public {
        vm.prank(USER);
        uint256 tokens = wrapper.deposit(3000);

        assertEq(tokens, 1500);
    }

    function testNumSharesWhenPriceHasFractions() public {
        // 12.345 = 12345 / 1000; => RAY * 12345 / 1000
        yvToken.setPricePerShareMock((RAY * 12345) / 1000);

        vm.prank(USER);
        wrapper.deposit(3000);

        // 3000 / 12.345 = 243.013365735
        assertEq(wrapper.balanceOf(USER), 243);
    }

    function testRevertsIfTransferFails() public {
        token.setFailTransfers(true);

        vm.expectRevert(FractionalWrapper.TransferFailed.selector);
        vm.prank(USER);
        wrapper.deposit(3000);
    }
}

abstract contract UserDepositedState is ZeroState {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(USER);
        wrapper.deposit(3000);
    }
}

contract UserDepositedStateTest is UserDepositedState {
    function testWithdrawSendsUnderlyingTokenToUser() public {
        assertEq(token.balanceOf(USER), 2000);

        vm.prank(USER);
        wrapper.withdraw(1500);

        assertEq(token.balanceOf(USER), 5000);
    }

    function testWithdrawReturnsTheNumberOfUnderlyingTokensSentToUser() public {
        vm.prank(USER);
        uint256 tokens = wrapper.withdraw(1500);

        assertEq(tokens, 3000);
    }

    function testWithdrawAfterPriceIncreasedShouldResultInMoreTokens() public {
        yvToken.setPricePerShareMock(3 * RAY);

        // Vault made a lot of profit
        token.mint(address(yvToken), 1000000);

        vm.prank(USER);
        wrapper.withdraw(1500);

        // price went from 2 to 3, so user should get x1.5 tokens
        // 2000 + 3000 * 1.5 = 6500
        assertEq(token.balanceOf(USER), 6500);
    }

    function testWithdrawRevertsIfTransferFails() public {
        token.setFailTransfers(true);

        vm.expectRevert(FractionalWrapper.TransferFailed.selector);
        vm.prank(USER);
        wrapper.withdraw(1500);
    }
}