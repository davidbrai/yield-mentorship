// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20MockWithFailedTransfers} from "../assignment-2/ERC20MockWithFailedTransfers.sol";

contract FunToken is ERC20MockWithFailedTransfers("Fun token", "FUN") {}