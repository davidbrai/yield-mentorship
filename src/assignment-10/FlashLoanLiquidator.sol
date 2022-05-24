// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IERC20 } from "yield-utils-v2/token/IERC20.sol";
import { IUniswapV2Pair } from "src/assignment-10/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "src/assignment-10/interfaces/IUniswapV2Factory.sol";
import { CollateralizedVault } from "src/assignment-10/CollateralizedVault.sol";
import { AMM } from "src/assignment-7/AMM.sol";

import "forge-std/console2.sol";

contract FlashLoanLiquidator {

    IERC20 immutable public dai;
    IERC20 immutable public weth;
    IUniswapV2Factory immutable public uniswapFactory;
    CollateralizedVault immutable public vault;
    AMM immutable public amm;

    struct SwapParams {
        address vaultUser;
        address liquidator;
    }

    constructor(address dai_, address weth_, address uniswapFactory_, address vault_, address amm_) {
        dai = IERC20(dai_);
        weth = IERC20(weth_);
        uniswapFactory = IUniswapV2Factory(uniswapFactory_);
        vault = CollateralizedVault(vault_);
        amm = AMM(amm_);
    }

    function liquidate(address user) public {
        uint256 debt = vault.borrows(user);

        // initiate flash loan
        bytes memory data = abi.encode(SwapParams({vaultUser: user, liquidator: msg.sender}));

        IUniswapV2Pair pair = IUniswapV2Pair(uniswapFactory.getPair(address(dai), address(weth)));
        pair.swap(debt, 0, address(this), data);
    }

    function uniswapV2Call(address /*_sender*/, uint _amount0, uint /*_amount1*/, bytes calldata _data) external {
        // TODO perform checks

        SwapParams memory params = abi.decode(_data, (SwapParams));

        // perform logic
        
        // liquidate user, send DAI, recv WETH
        dai.approve(address(vault), _amount0);
        uint256 receivedWeth = vault.liquidate(params.vaultUser);

        // swap WETH for DAI
        weth.approve(address(amm), receivedWeth);
        uint256 receivedDai = amm.sell1(receivedWeth);
        console2.log("receivedDai:", receivedDai);

        uint256 amountWithFee = _amount0 + flashFee(_amount0);

        // pay back uniswap
        // TODO send exactly the required 0.3%
        dai.transfer(msg.sender, amountWithFee);

        // send liquidation initiator the remaining dai
        dai.transfer(params.liquidator, receivedDai - amountWithFee);
    }

    function flashFee(uint256 amount) public pure returns (uint256 fee) {
        fee = ((3 * amount) / 997) + 1;
    }
}