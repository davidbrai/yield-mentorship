// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/assignment-2/BasicVault.sol";
import "./ERC20MockWithFailedTransfers.sol";

abstract contract ZeroState is Test {
    BasicVault public v;
    ERC20MockWithFailedTransfers token;

    function setUp() public virtual {
        token = new ERC20MockWithFailedTransfers("Walkie Talkie", "WOKTOK");
        v = new BasicVault(token);
    }
}

contract ZeroStateTest is ZeroState {

    address USER = address(1);

    function testUserCantDepositWithoutApproval() public {
        vm.prank(USER);
        vm.expectRevert("ERC20: Insufficient approval");
        v.deposit(1);
    }

    function testUserCantWithdraw() public {
        vm.prank(USER);
        vm.expectRevert(BasicVault.BalanceTooLow.selector);
        v.withdraw(1);
    }
}

abstract contract UserApproved is ZeroState {
    address USER = address(1);

    function setUp() public override virtual {
        super.setUp();

        vm.prank(USER);
        token.approve(address(v), 99999999);
    }
}

contract UserApprovedTest is UserApproved {
    function testUserCantDepositWithoutTokens() public {
        vm.prank(USER);
        vm.expectRevert("ERC20: Insufficient balance");
        v.deposit(1);
    }
}

abstract contract UserWithTokens is UserApproved {
    function setUp() public override virtual {
        super.setUp();

        token.mint(USER, 100);
    }
}

contract UserWithTokensTest is UserWithTokens {

    event Deposit(address from, uint amount);

    function testUserCanDeposit() public {
        vm.prank(USER);
        v.deposit(10);

        assertEq(token.balanceOf(USER), 90);
        assertEq(token.balanceOf(address(v)), 210);
    }

    function testUserCantDepositMoreThanTheyHave() public {
        vm.prank(USER);
        vm.expectRevert("ERC20: Insufficient balance");
        v.deposit(1000);
    }

    function testDepositEmitsEvent() public {
        vm.prank(USER);
        vm.expectEmit(true, true, true, true);
        emit Deposit(USER, 10);
        v.deposit(10);
    }

    function testDepositRevertsIfTransferReturnsFalse() public {
        token.setFailTransfers(true);
        vm.expectRevert(BasicVault.TransferFailed.selector);
        vm.prank(USER);
        v.deposit(10);
    }
}

abstract contract UserDeposited is UserWithTokens {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(USER);
        v.deposit(50);
    }
}

contract UserDepositedTest is UserDeposited {

    event Withdraw(address to, uint amount);

    function testUserCanWithdraw() public {
        vm.prank(USER);
        v.withdraw(50);

        assertEq(token.balanceOf(USER), 100);
    }

    function testUserCantWithdrawMoreThanDeposited() public {
        vm.prank(USER);
        vm.expectRevert(BasicVault.BalanceTooLow.selector);
        v.withdraw(150);
    }

    function testUserCantWithdrawMoreThanDepositedWithSeveralWithdrawals() public {
        vm.startPrank(USER);
        v.withdraw(25);

        vm.expectRevert(BasicVault.BalanceTooLow.selector);
        v.withdraw(26);
    }

    function testWithdrawalEmitsEvent() public {
        vm.prank(USER);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(USER, 20);
        v.withdraw(20);
    }

    function testWithdrawRevertsIfTransferFails() public {
        token.setFailTransfers(true);

        vm.prank(USER);
        vm.expectRevert(BasicVault.TransferFailed.selector);
        v.withdraw(10);
    }
}