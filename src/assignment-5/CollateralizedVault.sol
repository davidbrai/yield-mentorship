// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "yield-utils-v2/token/IERC20.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}

/// @title Collateralized Vault
/// @author davidbrai
/// @notice A vault that allows to borrow a token against a collateral
///     If a debt position is not sufficiently collateralized, e.g when the market price
///     of the collateral went down, then the user's collateral may be liquidated.
///     In case of a liquidation, the users debt and collateral are nullified.
/// @dev The Vault uses Chainlink price feeds to determine the value of the collateral compared to the debt
contract CollateralizedVault is Ownable {

    /// @notice ERC20 token which can be borrowed from the vault
    IERC20WithDecimals public immutable underlying;

    /// @notice ERC20 token which can be used as collateral
    IERC20WithDecimals public immutable collateral;

    /// @notice Chainlink priceFeed of underlying / collateral
    ///     e.g. if underlying is DAI and collateral is WETH, priceFeed is for DAI/WETH
    AggregatorV3Interface public immutable priceFeed;

    /// @notice deposited collateral per user in the vault, of `collateral` token
    mapping(address => uint256) public depositedCollateral;

    /// @notice Mapping of current debt per user, of `underlying` token
    mapping(address => uint256) public debt;

    error TooMuchDebt();
    error NotEnoughCollateral();
    error UserDebtIsSufficientlyCollateralized();

    /// @notice Initalizes a new CollateralizedVault
    /// @param underlying_ ERC20 token which can be borrowed from the vault
    /// @param collateral_ ERC20 token which can be used as collateral
    /// @param priceFeed_ Chainlink priceFeed of underlying / collateral
    constructor(address underlying_, address collateral_, address priceFeed_) {
        underlying = IERC20WithDecimals(underlying_);
        collateral = IERC20WithDecimals(collateral_);
        priceFeed = AggregatorV3Interface(priceFeed_);
    }

    /// @notice Deposits additional collateral into the vault
    /// @param collateralAmount amount of `collateral` token to deposit
    function deposit(uint256 collateralAmount) public {
        depositedCollateral[msg.sender] += collateralAmount;

        collateral.transferFrom(msg.sender, address(this), collateralAmount);
    }

    /// @notice Borrows `underlying` token from the Vault
    ///     Only allowed to borrow up to the value of the collateral
    /// @param amount The amount of `underlying` token to borrow
    function borrow(uint256 amount) public {
        uint256 maxDebt = getMaxAllowedDebt(depositedCollateral[msg.sender]);
        if (debt[msg.sender] + amount > maxDebt) {
            revert NotEnoughCollateral();
        }

        debt[msg.sender] += amount;

        underlying.transfer(msg.sender, amount);
    }

    /// @notice Pays back an open debt
    /// @param amount The amount of `underlying` token to pay back
    function repayDebt(uint256 amount) public {
        debt[msg.sender] -= amount;

        underlying.transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraws part of the collateral
    ///     Only allowed to withdraw as long as the collateral left is higher in value than the debt
    /// @param amount The amount of `collateral` token to withdraw
    function withdrawCollateral(uint256 amount) public {
        uint256 requiredCollateral = getRequiredCollateral(debt[msg.sender]);

        if (depositedCollateral[msg.sender] - amount < requiredCollateral) {
            revert TooMuchDebt();
        }

        depositedCollateral[msg.sender] -= amount;

        collateral.transfer(msg.sender, amount);
    }

    /// @notice Admin: liquidate a user debt if the collateral value falls below the debt
    /// @param user The user to liquidate
    /// @dev Only admin is allowed to liquidate
    function liquidateUser(address user) onlyOwner public {
        uint256 requiredCollateral = getRequiredCollateral(debt[user]);
        if (depositedCollateral[user] >= requiredCollateral) {
            revert UserDebtIsSufficientlyCollateralized();
        }

        delete debt[user];
        delete depositedCollateral[user];
    }

    /// @notice Returns the maximum allowed debt for the given `collateralAmount`
    function getMaxAllowedDebt(uint256 collateralAmount) public view returns (uint256 underlyingAmount) {
        underlyingAmount = (collateralAmount * 10**priceFeed.decimals()) / getPrice();
        underlyingAmount = scaleInteger(underlyingAmount, collateral.decimals(), underlying.decimals());
    }

    /// @notice Returns the required amount of collateral in order to borrow `borrowAmount`
    function getRequiredCollateral(uint256 borrowAmount) public view returns (uint256 requiredCollateral) {
        requiredCollateral = (borrowAmount * getPrice()) / 10**priceFeed.decimals();
        requiredCollateral = scaleInteger(requiredCollateral, underlying.decimals(), collateral.decimals());
    }

    /// @dev Scales a fixed point interger from `fromDecimals` to `toDecimals`
    function scaleInteger(uint256 x, uint8 fromDecimals, uint8 toDecimals) public pure returns (uint256) {
        if (toDecimals >= fromDecimals) {
            return x * 10**(toDecimals - fromDecimals);
        } else {
            return x / 10**(fromDecimals - toDecimals);
        }
    }

    /// @notice Returns the price of the underlying token in collateral token units
    function getPrice() public view returns (uint) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return toUint256(price);
    }

    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }
}