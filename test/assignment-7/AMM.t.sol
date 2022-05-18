// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {AMM} from "src/assignment-7/AMM.sol";
import {ERC20Mock} from "yield-utils-v2/mocks/ERC20Mock.sol";

abstract contract ZeroState is Test {

    AMM amm;
    ERC20Mock token0;
    ERC20Mock token1;
    address alice = address(1);
    address bob = address(2);

    function setUp() public virtual {
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        token0 = new ERC20Mock("token0", "T0");
        token1 = new ERC20Mock("token1", "T1");

        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");

        amm = new AMM(token0, token1, "dex", "LP", 18);
        vm.label(address(amm), "AMM");

        vm.startPrank(alice);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function assertRelApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta // An 18 decimal fixed point number, where 1e18 == 100%
    ) internal virtual {
        if (b == 0) return assertEq(a, b); // If the expected is 0, actual must be too.

        uint256 percentDelta = ((a > b ? a - b : b - a) * 1e18) / b;

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", b);
            emit log_named_uint("      Actual", a);
            emit log_named_decimal_uint(" Max % Delta", maxPercentDelta, 18);
            emit log_named_decimal_uint("     % Delta", percentDelta, 18);
            fail();
        }
    }
}

contract ZeroStateTest is ZeroState {

    event Initialized(uint256 amount0, uint256 amount1);

    function testInit() public {
        token0.mint(alice, 5 ether);
        token1.mint(alice, 10 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Initialized(5 ether, 10 ether);
        uint z = amm.init(5 ether, 10 ether);

        assertEq(z, 50 * 1e36);
        assertEq(amm.balanceOf(alice), 50 * 1e36);
    }
}

abstract contract InitializedState is ZeroState {
    function setUp() public override virtual {
        super.setUp();

        token0.mint(alice, 99999 ether);
        token1.mint(alice, 99999 ether);

        vm.prank(alice);
        amm.init(5 ether, 10 ether);
    }
}

contract InitializedStateTest is InitializedState {

    event Mint(address indexed user, uint256 amount0, uint256 amount1, uint256 amountLP);
    event Burn(address indexed user, uint256 amount0, uint256 amount1, uint256 amountLP);
    event Sell0(address indexed user, uint256 amount0, uint256 amount1);
    event Sell1(address indexed user, uint256 amount0, uint256 amount1);

    function testRevertsIfCallingInitTwice() public {
        token0.mint(alice, 1 ether);
        token1.mint(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(AMM.AlreadyInitialized.selector);
        amm.init(1 ether, 1 ether);
    }

    function testMintSameAmountShouldMintSameAmountOfLPTokens() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Mint(alice, 5 ether, 10 ether, 50 * 1e36);
        uint z = amm.mint(5 ether, 10 ether);

        assertEq(z, 50 * 1e36);
        assertEq(amm.balanceOf(alice), 100 * 1e36);
    }

    function testMintDifferentAmount() public {
        vm.prank(alice);
        uint z = amm.mint(0.1234 ether, 0.2468 ether);

        assertEq(z, (0.1234/5) * 50 * 1e36);
    }

    function testMintRevertsIfWrongProportion() public {
        vm.prank(alice);
        vm.expectRevert(AMM.IncorrectProportion.selector);
        amm.mint(5 ether, 9 ether);
    }

    function testBurn() public {
        // Alice current LP token balance
        assertEq(amm.balanceOf(alice), 50 * 1e36);

        // Burn all alice tokens for easy calculation
        token0.burn(alice, token0.balanceOf(alice));
        token1.burn(alice, token1.balanceOf(alice));

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Burn(alice, 1 ether, 2 ether, 10 * 1e36);
        (uint x, uint y) = amm.burn(10 * 1e36);

        assertEq(x, 1 ether);
        assertEq(y, 2 ether);

        assertEq(token0.balanceOf(alice), 1 ether);
        assertEq(token1.balanceOf(alice), 2 ether);
    }

    function testSell0() public {
        token0.mint(bob, 10 ether);
        uint256 k = amm.reserve0() * amm.reserve1();

        // expected swap amount: (1*10)/(5+1) = 1.6666...
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Sell0(bob, 1 ether, uint(5) * 1e18 / 3);
        uint amount1 = amm.sell0(1 ether);
        
        assertEq(amount1, uint(5) * 1e18 / 3);
        assertEq(token1.balanceOf(bob), amount1);

        // constant product is maintained
        assertRelApproxEq(amm.reserve0() * amm.reserve1(), k, 0);

        vm.prank(bob);
        uint256 amount1_2 = amm.sell0(1 ether);
        
        assertLt(amount1_2, amount1);
        assertEq(token1.balanceOf(bob), amount1 + amount1_2);
    }

    function testFuzzConstantProductMaintained(uint256 amount) public {
        uint256 k = amm.reserve0() * amm.reserve1();
        amount = bound(amount, 0, 1e10 * amm.reserve0());
        
        token0.mint(bob, amount);
        
        vm.prank(bob);
        amm.sell0(amount);

        // constant product is maintained
        assertRelApproxEq(amm.reserve0() * amm.reserve1(), k, 1e10);
    }

    function testSell1() public {
        token1.mint(bob, 10 ether);
        uint256 k = amm.reserve0() * amm.reserve1();

        // expected swap amount: (1*5)/(10+1) = 0.45454545...
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Sell1(bob, uint(5) * 1e18 / 11, 1 ether);
        uint amount0 = amm.sell1(1 ether);
        
        assertEq(amount0, uint(5) * 1e18 / 11);
        assertEq(token0.balanceOf(bob), amount0);

        // constant product is maintained
        assertRelApproxEq(amm.reserve0() * amm.reserve1(), k, 0);

        vm.prank(bob);
        uint256 amount0_2 = amm.sell1(1 ether);
        
        assertLt(amount0_2, amount0);
        assertEq(token0.balanceOf(bob), amount0 + amount0_2);
    }
}