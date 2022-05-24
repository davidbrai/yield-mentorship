// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IERC20 } from "yield-utils-v2/token/IERC20.sol";
import { IUniswapV2Pair } from "src/assignment-10/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "src/assignment-10/interfaces/IUniswapV2Factory.sol";
import { CollateralizedVault } from "src/assignment-10/CollateralizedVault.sol";
import { AMM } from "src/assignment-7/AMM.sol";
import { TransferHelper } from "yield-utils-v2/token/TransferHelper.sol";

/// @title Flash loan liquidator
/// @author davidbrai
/// @notice Uses a flash loan in order to liquidate an undercollateralized debt position and keep the arbitrage
/// @dev Uses UniswapV2Pair for flash swaps
contract FlashLoanLiquidator {

    using TransferHelper for IERC20;

    /******************
     * Immutables
     ******************/

    IERC20 immutable public underlying;
    IERC20 immutable public collateral;
    IUniswapV2Factory immutable public uniswapFactory;
    CollateralizedVault immutable public vault;
    AMM immutable public amm;


    /******************
     * Storage
     ******************/

    /// @dev Security: this is used to make sure the callback is only called by the expected UniV2 pair contract
    address public permissionedPair;

    /******************
     * Events
     ******************/
    event Liquidate(address indexed liquidator, address indexed liquidatee, uint256 profit);

    /******************
     * Errors
     ******************/

    error UnauthorizedInitiator();
    error UnauthorizedMsgSender();

    struct SwapParams {
        address vaultUser;
        address liquidator;
    }

    /// @notice Creates a new FlashLoanLiquidator
    /// @param underlying_ ERC20 token address of the asset being borrowed
    /// @param collateral_ ERC20 token address of the collateral asset
    /// @param uniswapFactory_ address of UniswapV2Factory, used for finding UniswapV2Pair contracts to use for flash swaps
    /// @param vault_ A CollateralizedVault contract against which to liquidate
    /// @param amm_ An AMM for swapping the `collateral_` back into `underlying_`
    constructor(address underlying_, address collateral_, address uniswapFactory_, address vault_, address amm_) {
        underlying = IERC20(underlying_);
        collateral = IERC20(collateral_);
        uniswapFactory = IUniswapV2Factory(uniswapFactory_);
        vault = CollateralizedVault(vault_);
        amm = AMM(amm_);
    }

    /// @notice Takes a flash loan of `underlying` and liquidates an undercollateralized user debt position
    ///     Then is swaps the `collateral` back into `underlying` tokens, repays the flash loan, and send
    ///     the profit back to who invoked this function.
    /// @dev UniswapV2Pair is used for flash loaning `underlying`
    /// @param user The debt position to liquidate in `vault`
    function liquidate(address user) public {
        uint256 debt = vault.borrows(user);

        // params we want to be available in the flash loan callback (`uniswapV2Call`)
        bytes memory data = abi.encode(SwapParams({vaultUser: user, liquidator: msg.sender}));

        IUniswapV2Pair pair = IUniswapV2Pair(uniswapFactory.getPair(address(underlying), address(collateral)));
        permissionedPair = address(pair);

        pair.swap(debt, 0, address(this), data);
    }

    /// @notice Callback function from UniswapV2Pair flash swap
    /// @dev This function is meant to be called only by UniswapV2Pair
    /// @param sender The address of who invoked the flash swap, this should always be this contract
    /// @param amount0 Amount of `underlying` that was borrowed from the UniswapV2Pair
    /// @param data Encoded SwapParams
    function uniswapV2Call(address sender, uint amount0, uint /*_amount1*/, bytes calldata data) external {
        if (msg.sender != permissionedPair) {
            revert UnauthorizedMsgSender();
        }
        if (sender != address(this)) {
            revert UnauthorizedInitiator();
        }

        SwapParams memory params = abi.decode(data, (SwapParams));
        
        // Liquidate user: send DAI, recv WETH
        underlying.approve(address(vault), amount0);
        uint256 receivedWeth = vault.liquidate(params.vaultUser);

        // Swap WETH for DAI
        collateral.approve(address(amm), receivedWeth);
        uint256 receivedDai = amm.sell1(receivedWeth);

        // Repay flash loan
        uint256 amountWithFee = amount0 + flashFee(amount0);
        underlying.safeTransfer(msg.sender, amountWithFee);

        // Send liquidation initiator the remaining DAI
        uint256 profit = receivedDai - amountWithFee;
        underlying.safeTransfer(params.liquidator, profit);

        emit Liquidate(params.liquidator, params.vaultUser, profit);
    }

    /// @notice The UniswapV2Pair flash swap fee (0.300902708 %)
    function flashFee(uint256 amount) public pure returns (uint256 fee) {
        fee = ((3 * amount) / 997) + 1;
    }
}