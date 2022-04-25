// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/test.sol";
import "src/SimpleRegistry.sol";

contract SimpleRegisterTest is Test {

    event NameClaimed(string name, address owner);
    event NameReleased(string name, address owner);

    SimpleRegistry registry;
    address USER = address(0xaabbccdd);
    address OTHER_USER = address(0x11223344);

    function setUp() public {
        registry = new SimpleRegistry();
    }

    function testClaim() public {
        assertEq(registry.owners("vitalik"), address(0));

        vm.prank(USER);
        registry.claim("vitalik");

        assertEq(registry.owners("vitalik"), USER);
    }

    function testRelease() public {
        vm.prank(USER);
        registry.claim("vitalik");
        assertEq(registry.owners("vitalik"), USER);

        vm.prank(USER);
        registry.release("vitalik");
        assertEq(registry.owners("vitalik"), address(0));
    }

    function testOnlyOwnerCanRelease() public {
        vm.prank(USER);
        registry.claim("vitalik");

        vm.prank(OTHER_USER);
        vm.expectRevert(SimpleRegistry.Unauthorized.selector);
        registry.release("vitalik");
    }

    function testCantClaimAlreadyClaimedName() public {
        registry.claim("vitalik");

        vm.expectRevert(SimpleRegistry.AlreadyClaimed.selector);
        registry.claim("vitalik");
    }

    function testEmitsNameClaimedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit NameClaimed("vitalik", USER);

        vm.prank(USER);
        registry.claim("vitalik");
    }

    function testEmitsNameReleaseEvent() public {
        vm.prank(USER);
        registry.claim("vitalik");

        vm.expectEmit(true, true, true, true);
        emit NameReleased("vitalik", USER);

        vm.prank(USER);
        registry.release("vitalik");
    }
}