// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Permit} from "yield-utils-v2/token/ERC20Permit.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";

/// @title ERC20 wrapping an underlying ERC20 token
/// @author davidbrai
/// @notice Users can send a pre-specified ERC20 token and received wrapped tokens in return.
///     The wrapped tokens can be burned in order to withdraw the deposited tokens.
contract ERC20Wrapper is ERC20Permit {

    /// @notice The wrapped ERC20 token
    IERC20 public immutable token;

    error TransferFailed();

    /// @notice Initializes a new wrapper token
    /// @param token_ The address of the token to be wrapped
    /// @param name The named of the wrapper token (e.g. "Wrapped DAI")
    /// @param symbol A symbol for the wrapper token (e.g "WDAI")
    /// @param decimals Number of decimals for the wrapper token, should be same as the the underlying token
    constructor(address token_, string memory name, string memory symbol, uint8 decimals) ERC20Permit(name, symbol, decimals) {
        token = IERC20(token_);
    }

    /// @notice Deposit tokens into the contract and sends wrapped tokens back to the user
    /// @param amount The amount of tokens to wrap
    function deposit(uint amount) public {
        _mint(msg.sender, amount);

        bool success = token.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed();
        }
    }


    /// @notice Burns a specified amount of wrapped tokens and returns the underlying to the user
    /// @param amount The amount of tokens to burn
    function burn(uint amount) public {
        _burn(msg.sender, amount);

        bool success = token.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }
    }

}