// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Permit} from "yield-utils-v2/token/ERC20Permit.sol";


/// @title An ERC20 wrapper for the ETH native token
/// @author davidbrai
/// @notice Accepts ETH and mints equivalent amount of WETH in return. Burning WETH will return the ETH.
contract ETHWrapper is ERC20Permit("Wrapped ETH", "WETH", 18) {
    
    error TransferFailed();

    /// @notice Function handling ETH receival. Mints WETH in the amount of ETH received.
    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @notice Burns WETH and returns the equivalent amount of ETH back
    /// @param amount of WETH to be burned
    function burn(uint amount) public {
        _burn(msg.sender, amount);

        (bool sent,) = msg.sender.call{value: amount}("");
        if (!sent) {
            revert TransferFailed();
        }
    }
}