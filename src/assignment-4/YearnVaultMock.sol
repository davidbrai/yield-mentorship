// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Permit} from "yield-utils-v2/token/ERC20Permit.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";

interface IYearnVault {
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 maxShares) external returns (uint256);
    function pricePerShare() external view returns (uint256);
}


/// @title A mock of a Yearn Vault with a settable `pricePerShare`
/// @author davidbrai
/// @notice This mock of a Yearn Vault is used for testing purposes.
///     A user can deposit tokens of `token` into the vault and receive "shares",
///     which are Yearn Vault tokens, according to the price set by `pricePerShare`
/// @dev Use `setPricePerShare` for changing `pricePerShare`
contract YearnVaultMock is IYearnVault, ERC20Permit {
    
    uint256 constant RAY = 10 ** 27;

    // Start by default with price per share of 1.0, i.e 1 underlying token = 1 yvToken
    uint256 public pricePerShareMock = RAY;
    IERC20 public immutable token;

    error TransferFailed();

    /// @notice Initializes a YearnVaultMock
    /// @param token_ The underlying token that the vault tries to increase
    /// @param name The ERC20 name for the Yearn Vault token
    /// @param symbol The ERC20 symbol for the Yearn Vault token
    /// @param decimals The number of decimals for the Yearn Vault token
    constructor(address token_, string memory name, string memory symbol, uint8 decimals) ERC20Permit(name, symbol, decimals) {
        token = IERC20(token_);
    }

    /// @notice Returns the current pricePerShare
    /// @dev This is a fixed point integer with 27 decimals (ray)
    function pricePerShare() external view returns (uint256) {
        return pricePerShareMock;
    }

    /// @notice Deposit underlying token and get yvTokens in return
    /// @dev Uses `pricePerShareMock` to determine the conversion rate
    /// @param amount The amount of underlying token to deposit
    /// @return The amount of yvToken shares sent to the user
    function deposit(uint256 amount) external returns (uint256) {
        uint256 numShares = rdiv(amount, pricePerShareMock);
        
        _mint(msg.sender, numShares);

        bool success = token.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed();
        }

        return numShares;
    }

    /// @notice Withdraws underlying token by sending yvTokens back to the vault
    /// @dev Uses `pricePerShareMock` to determine the conversion rate
    /// @param numShares The amount of yvTokens to return to the vault
    /// @return The amount of underlying tokens sent to the user
    function withdraw(uint256 numShares) external returns (uint256) {
        uint256 amount = rmul(numShares, pricePerShareMock);
        
        _burn(msg.sender, numShares);

        bool success = token.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }

        return amount;
    }

    /// @notice Set the vault's pricePerShare
    /// @param pricePerShareMock_ is a fixed point integer with 27 decimals (ray), i.e 1.0 is represented as 1e27
    function setPricePerShareMock(uint256 pricePerShareMock_) public {
        pricePerShareMock = pricePerShareMock_;
    }

    /// @dev Divides a ray number by a non ray divisor
    /// @param x A number to be divided. Should be a fixed point integer with 27 decimals (ray)
    /// @param y The divisor, a regular integer
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * RAY) / y;
    }

    /// @dev Multiply a number by a fixed point integer with 27 decimals (ray)
    function rmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / RAY;
    }

}