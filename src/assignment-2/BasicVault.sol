// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "yield-utils-v2/token/IERC20.sol";

/// @title Vault holding ERC20 tokens for users
/// @author davidbrai
/// @notice The vault allows users to deposit and withdraw token of a specific ERC20 contract. The contracts keeps track of balances.
contract BasicVault {

    /// @notice ERC20 token which this vault holds tokens for
    IERC20 immutable public token;

    /// @notice Mapping from address to balance representing the balance of each user
    mapping(address => uint) public balances;

    error BalanceTooLow();
    error TransferFailed();

    /// @notice This event is emitted when a user deposits tokens
    event Deposit(address from, uint amount);

    /// @notice This event is emitted when a user withdraws tokens
    event Withdraw(address to, uint amount);

    /// @notice Initalizes a new vault
    /// @param _token The address of an ERC20 token contract
    constructor(IERC20 _token) {
        token = _token;
    }

    /// @notice Deposits tokens from the user into the vault
    /// @dev Updates the balances mapping with the amount of tokens
    /// @param amount The amount of tokens to deposit
    function deposit(uint amount) public {
        bool success = token.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed();
        }
        
        balances[msg.sender] += amount;

        emit Deposit(msg.sender, amount);
    }

    /// @notice Withdraws tokens back to the user
    /// @dev Updates the balances mapping with the amount of tokens
    /// @param amount The amount of tokens to be withdrawn
    function withdraw(uint amount) public {
        if (balances[msg.sender] < amount) {
            revert BalanceTooLow();
        }

        balances[msg.sender] -= amount;
        bool success = token.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }
        
        emit Withdraw(msg.sender, amount);
    }
}
