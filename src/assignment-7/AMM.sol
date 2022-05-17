// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Permit} from "yield-utils-v2/token/ERC20Permit.sol";
import {IERC20} from "yield-utils-v2/token/IERC20.sol";
import {TransferHelper} from "yield-utils-v2/token/TransferHelper.sol";

/// @title A constant product automated market maker
/// @author davidbrai
/// @notice Facilitates trades between 2 ERC20 tokens by maintaining a constant ratio of their reserves
///     The AMM itself is also an ERC20 of LP (liquidity provider) tokens, which represent the ownership
///     of the tokens reserves.
/// @dev Explain to a developer any extra details
contract AMM is ERC20Permit {

    using TransferHelper for IERC20;

    /******************
     * Immutables
     ******************/

    /// @notice First ERC20 token of this AMM
    IERC20 public immutable token0;

    /// @notice Second ERC20 token of this AMM
    IERC20 public immutable token1;

    /******************
     * Storage
     ******************/

    /// @notice Amount of `token0` currently held by the contract
    uint256 public reserve0;

    /// @notice Amount of `token1` currently held by the contract
    uint256 public reserve1;

    /******************
     * Events
     ******************/

    /// @notice Event emitted when first initalizing the AMM
    event Initialized(uint256 amount0, uint256 amount1);

    /// @notice Event emitted when a user deposits tokens into the AMM and gets LP tokens in return
    event Mint(address indexed user, uint256 amount0, uint256 amount1, uint256 amountLP);

    /// @notice Event emitted when a user burns their LP tokens in return for tokens from the reserve
    event Burn(address indexed user, uint256 amount0, uint256 amount1, uint256 amountLP);

    /// @notice Event emitted when a user sells `token0` into the AMM in return for `token1`
    event Sell0(address indexed user, uint256 amount0, uint256 amount1);

    /// @notice Event emitted when a user sells `token1` into the AMM in return for `token0`
    event Sell1(address indexed user, uint256 amount0, uint256 amount1);

    /******************
     * Errors
     ******************/

    error AlreadyInitialized();
    error IncorrectProportion();

    /// @notice Creates a new AMM
    /// @param token0_ First ERC20 token address of this AMM
    /// @param token1_ Second ERC20 token address of this AMM
    /// @param name The name of the AMM LP tokens
    /// @param symbol The symbol of the AMM LP tokens
    /// @param decimals The decimal numbers of the AMM LP tokens
    constructor(
        IERC20 token0_,
        IERC20 token1_,
        string memory name, 
        string memory symbol, 
        uint8 decimals) ERC20Permit(name, symbol, decimals) {

        token0 = token0_;
        token1 = token1_;
    }

    /// @notice Deposits the initial token reserves into the AMM
    ///     The initalize exchange rate of the AMM will be set by the ratio between the token amounts
    /// @dev This function can only be called once, will revert if called twice
    /// @param amount0 Amount of `token0` to deposit
    /// @param amount1 Amount of `token1` to deposit
    /// @return lpTokens Amount of `lpTokens` minted to the user
    function init(uint256 amount0, uint256 amount1) public returns (uint256 lpTokens) {
        if (_totalSupply != 0) {
            revert AlreadyInitialized();
        }

        lpTokens = amount0 * amount1;

        reserve0 = amount0;
        reserve1 = amount1;

        _mint(msg.sender, lpTokens);

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        emit Initialized(amount0, amount1);
    }

    /// @notice Deposits additional tokens into the AMM and mints new LP tokens
    ///     The ratio between the token amounts must match the current reserve ratio
    /// @param amount0 Amount of `token0` to deposit
    /// @param amount1 Amount of `token1` to deposit
    /// @return lpTokens Amount of `lpTokens` minted to the user
    function mint(uint256 amount0, uint256 amount1) public returns (uint256 lpTokens) {
        // Cache variables to reduce SLOADs
        uint256 reserve0_ = reserve0;
        uint256 reserve1_ = reserve1;

        // Check proportion:
        //     reserve0 / reserve1 == amount0 / amount1
        //     reserve0 * amount1 == reserve1 * amount0
        if (amount0 * reserve1_ != amount1 * reserve0_) {
            revert IncorrectProportion();
        }

        // Mint LP tokens
        // z = totalSupply * amount0 / reserve0
        lpTokens = (amount0 * _totalSupply) / reserve0;

        reserve0 = reserve0_ + amount0;
        reserve1 = reserve1_ + amount1;

        _mint(msg.sender, lpTokens);

        // transfers tokens into AMM
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        emit Mint(msg.sender, amount0, amount1, lpTokens);
    }

    /// @notice Burns LP tokens and gets back reserve tokens
    /// @param lpTokens Amount of LP tokens to burn
    /// @return amount0 Amount of `token0` sent to the user
    /// @return amount1 Amount of `token1` sent to the user
    function burn(uint256 lpTokens) public returns (uint256 amount0, uint256 amount1) {
        // Cache variables to reduce SLOADs
        uint256 reserve0_ = reserve0;
        uint256 reserve1_ = reserve1;

        // calculate amounts
        amount0 = (reserve0_ * lpTokens) / _totalSupply;
        amount1 = (reserve1_ * lpTokens) / _totalSupply;

        // updates reserves
        reserve0 = reserve0_ - amount0;
        reserve1 = reserve1_ - amount1;
        
        // burn
        _burn(msg.sender, lpTokens);

        // send underlying to user
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        emit Burn(msg.sender, amount0, amount1, lpTokens);
    }

    /// @notice Sells a specified amount of `token0` and gets some `token1`
    ///     while maintaining the same product of reserve tokens
    /// @dev In order the maintain constant product, `amount1 is calculated as follows:
    ///     notation:
    ///       x0, y0 = reserve0, reserve1
    ///       x, y = amount0, amount1
    ///       k = x0 * y0
    ///     constant product requirement:
    ///       k = (x0 + x) * (y0 - y)
    ///     solve for y:
    ///       x0*y0 - x0*y + x*y0 - x*y = k
    ///       k - x0*y + x*y0 - x*y = k
    ///       - x0*y + x*y0 - x*y = 0
    ///       x*y0 = x0*y + x*y = y * (x0+x)
    ///       y = (x * y0) / (x0 + x)
    /// @param amount0 Amount of `token0` to sell into the AMM
    /// @return amount1 Amount of `token1` received back from the AMM
    function sell0(uint256 amount0) public returns (uint256 amount1) {
        // Cache variables to reduce SLOADs
        uint256 reserve0_ = reserve0;
        uint256 reserve1_ = reserve1;
        
        amount1 = (amount0 * reserve1_) / (reserve0_ + amount0);

        // update reserve
        reserve0 = reserve0_ + amount0;
        reserve1 = reserve1_ - amount1;

        // send amount0 to amm
        token0.safeTransferFrom(msg.sender, address(this), amount0);

        // send amount1 to user
        token1.safeTransfer(msg.sender, amount1);

        emit Sell0(msg.sender, amount0, amount1);
    }

    /// @notice Sells a specified amount of `token1` and gets some `token0`
    ///     while maintaining the same product of reserve tokens
    /// @dev Same calculation as in sell0 but swap the tokens
    /// @param amount1 Amount of `token1` to sell into the AMM
    /// @return amount0 Amount of `token0` received back from the AMM
    function sell1(uint256 amount1) public returns (uint256 amount0) {
        uint256 reserve0_ = reserve0;
        uint256 reserve1_ = reserve1;

        amount0 = (amount1 * reserve0_) / (reserve1_ + amount1);

        // update reserve
        reserve0 = reserve0_ - amount0;
        reserve1 = reserve1_ + amount1;

        // send amount1 to amm
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        // send amount0 to user
        token0.safeTransfer(msg.sender, amount0);

        emit Sell1(msg.sender, amount0, amount1);
    }
}