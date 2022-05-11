// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Permit} from "yield-utils-v2/token/ERC20Permit.sol";

contract USDC is ERC20Permit("USDC", "USDC", 6) {

    function mint(address dst, uint wad) public {
        _mint(dst, wad);
    }
}