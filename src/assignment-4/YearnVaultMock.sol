// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Permit} from "yield-utils-v2/token/ERC20Permit.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";

interface IYearnVault {
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 maxShares) external returns (uint256);
    // function pricePerShare() external view returns (uint256);
}

contract YearnVaultMock is IYearnVault, ERC20Permit {
    
    uint256 constant RAY = 10 ** 27;
    uint256 public pricePerShareMock = RAY;
    IERC20 public immutable token;

    error TransferFailed();

    constructor(address token_, string memory name, string memory symbol, uint8 decimals) ERC20Permit(name, symbol, decimals) {
        token = IERC20(token_);
    }

    function pricePerShare() external view returns (uint256) {
        return pricePerShareMock;
    }

    function deposit(uint256 amount) external returns (uint256) {
        uint256 numShares = rdiv(amount, pricePerShareMock);
        
        _mint(msg.sender, numShares);

        bool success = token.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed();
        }

        return numShares;
    }

    function withdraw(uint256 numShares) external returns (uint256) {
        uint256 amount = rmul(numShares, pricePerShareMock);
        
        _burn(msg.sender, numShares);

        bool success = token.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }

        return amount;
    }

    function setPricePerShareMock(uint256 pricePerShareMock_) public {
        pricePerShareMock = pricePerShareMock_;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * RAY) / y;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / RAY;
    }

}