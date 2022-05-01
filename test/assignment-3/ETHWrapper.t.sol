// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ETHWrapper} from "src/assignment-3/ETHWrapper.sol";

abstract contract ZeroState is Test {

    ETHWrapper wrapper;
    address USER = address(1);

    function setUp() public virtual {
        wrapper = new ETHWrapper();

        vm.deal(USER, 10 ether);
    }
}

contract ZeroStateTest is ZeroState {

    function testSendingETHToWrapperMintsWrappedTokens() public {
        vm.prank(USER);
        (bool sent,) = payable(wrapper).call{value: 1 ether}("");
        require(sent);

        assertEq(wrapper.balanceOf(USER), 1 ether);
    }
}

abstract contract UserWithWrappedETHState is ZeroState {
    
    function setUp() public virtual override {
        super.setUp();

        vm.prank(USER);
        (bool sent,) = payable(wrapper).call{value: 1 ether}("");
        require(sent);
    }
}

contract UserWithWRappedEthStateTest is UserWithWrappedETHState {

    function testBurningWrappedTokenWithdrawsETH() public {
        assertEq(USER.balance, 9 ether);

        vm.prank(USER);
        wrapper.burn(1 ether);

        assertEq(USER.balance, 10 ether);
    }

    function testBurningWrappedTokenBurnsIt() public {
        vm.prank(USER);
        wrapper.burn(1 ether);

        assertEq(wrapper.balanceOf(USER), 0);
    }

}