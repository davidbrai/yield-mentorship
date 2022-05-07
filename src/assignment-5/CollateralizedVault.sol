// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "yield-utils-v2/token/IERC20.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";

interface IERC20WithDecimals is IERC20 {
    function decimals() external view returns (uint8);
}

contract CollateralizedVault is Ownable {

    IERC20WithDecimals public immutable underlying;
    IERC20WithDecimals public immutable collateral;
    AggregatorV3Interface public immutable priceFeed;

    mapping(address => uint256) public depositedCollateral;
    mapping(address => uint256) public debt;

    error TooMuchDebt();
    error UserDebtIsSufficientlyCollateralized();

    constructor(address underlying_, address collateral_, address daiEthPriceFeed) {
        underlying = IERC20WithDecimals(underlying_);
        collateral = IERC20WithDecimals(collateral_);
        priceFeed = AggregatorV3Interface(daiEthPriceFeed);
    }

    /// @param collateralAmount amount of WETH to collateralize
    /// @return underlyingAmount amount of DAI lent to the user

    //TODO checks-effects-interactions
    function deposit(uint256 collateralAmount) public returns (uint256 underlyingAmount) {
        depositedCollateral[msg.sender] += collateralAmount;
        collateral.transferFrom(msg.sender, address(this), collateralAmount);

        uint daiEthPrice = uint(getDaiEthPrice()); // 374560000000000 ~ 1/2700     DAI/ETH
        uint8 priceDecimals = priceFeed.decimals();

        // amount DAI = collateral (ETH) / (DAI/ETH) 
        underlyingAmount = (collateralAmount * 10**priceDecimals) / daiEthPrice;
        underlyingAmount = scaleInteger(underlyingAmount, collateral.decimals(), underlying.decimals());

        underlying.transfer(msg.sender, underlyingAmount);
        debt[msg.sender] += underlyingAmount;
    }

    function scaleInteger(uint256 x, uint8 fromDecimals, uint8 toDecimals) public pure returns (uint256) {
        if (toDecimals >= fromDecimals) {
            return x * 10**(toDecimals - fromDecimals);
        } else {
            return x / 10**(fromDecimals - toDecimals);
        }
    }

    function repayDebt(uint256 amount) public {
        debt[msg.sender] -= amount;
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(uint256 amount) public {
        uint256 requiredCollateral = getRequiredCollateral(msg.sender);

        if (depositedCollateral[msg.sender] - amount < requiredCollateral) {
            revert TooMuchDebt();
        }

        depositedCollateral[msg.sender] -= amount;
        collateral.transfer(msg.sender, amount);
    }

    function liquidateUser(address user) onlyOwner public {
        uint256 requiredCollateral = getRequiredCollateral(user);
        if (depositedCollateral[user] >= requiredCollateral) {
            revert UserDebtIsSufficientlyCollateralized();
        }

        delete debt[user];
        delete depositedCollateral[user];
    }

    function getRequiredCollateral(address user) public view returns (uint256) {
        uint256 userDebt = debt[user];
        uint daiEthPrice = uint(getDaiEthPrice());
        uint8 priceDecimals = priceFeed.decimals();

        uint256 requiredCollateral = (userDebt * daiEthPrice) / 10**priceDecimals;
        return requiredCollateral;
    }

    function getDaiEthPrice() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return price;
    }
}