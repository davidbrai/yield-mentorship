// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20Wrapper} from "src/assignment-3/ERC20Wrapper.sol";
import {FunToken} from "src/assignment-3/FunToken.sol";

abstract contract ZeroState is Test {

    ERC20Wrapper wrapper;
    FunToken token;
    address USER = address(1);

    function setUp() public virtual {
        token = new FunToken();
        wrapper = new ERC20Wrapper(address(token), "Fun wrapper", "WFUN", 18);

        token.mint(USER, 5000);
        vm.prank(USER);
        token.approve(address(wrapper), 5000);
    }
}

contract ZeroStateTest is ZeroState {
    function testDepositingTokensReturnsEquivalentAmountOfWrappedTokens() public {
        assertEq(wrapper.balanceOf(USER), 0);
        
        vm.prank(USER);
        wrapper.deposit(3000);

        assertEq(wrapper.balanceOf(USER), 3000);
    }

    function testDepositingTokensMovesTokensToWrapper() public {
        vm.prank(USER);
        wrapper.deposit(3000);

        assertEq(token.balanceOf(address(wrapper)), 3000);
        assertEq(token.balanceOf(USER), 2000);
    }

    function testRevertsIfTransferFails() public {
        token.setFailTransfers(true);

        vm.expectRevert(ERC20Wrapper.TransferFailed.selector);
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
    function testBurnReturnsUnderlyingTokenToUser() public {
        assertEq(token.balanceOf(USER), 2000);

        vm.prank(USER);
        wrapper.burn(3000);

        assertEq(token.balanceOf(USER), 5000);
    }

    function testBurnBurnsWrappedTokens() public {
        assertEq(wrapper.balanceOf(USER), 3000);

        vm.prank(USER);
        wrapper.burn(3000);

        assertEq(wrapper.balanceOf(USER), 0);
    }

    function testBurnRevertsIfTransferFails() public {
        token.setFailTransfers(true);

        vm.expectRevert(ERC20Wrapper.TransferFailed.selector);
        vm.prank(USER);
        wrapper.burn(3000);
    }
}