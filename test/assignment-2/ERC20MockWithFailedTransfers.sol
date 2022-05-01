// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "yield-utils-v2/mocks/ERC20Mock.sol";


contract ERC20MockWithFailedTransfers is ERC20Mock {

    bool public failTransfers = false;

    constructor(
        string memory name,
        string memory symbol
    ) ERC20Mock(name, symbol) {}

    function _transfer(address src, address dst, uint wad) internal virtual override returns (bool) {
        if (failTransfers) {
            return false;
        } else {
            return super._transfer(src, dst, wad);
        }
    }

    function setFailTransfers(bool _failTransfers) public {
        failTransfers = _failTransfers;
    }
}
