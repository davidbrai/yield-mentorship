// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IERC20 } from "yield-utils-v2/token/IERC20.sol";
import { IUniswapV2Pair } from "src/assignment-10/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "src/assignment-10/interfaces/IUniswapV2Factory.sol";
import { CollateralizedVault } from "src/assignment-10/CollateralizedVault.sol";
import { AMM } from "src/assignment-7/AMM.sol";
import { TransferHelper } from "yield-utils-v2/token/TransferHelper.sol";

contract FlashLoanLiquidator {

    using TransferHelper for IERC20;

    IERC20 immutable public dai;
    IERC20 immutable public weth;
    IUniswapV2Factory immutable public uniswapFactory;
    CollateralizedVault immutable public vault;
    AMM immutable public amm;

    address public permissionedPair;

    error UnauthorizedInitiator();
    error UnauthorizedMsgSender();

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

        bytes memory data = abi.encode(SwapParams({vaultUser: user, liquidator: msg.sender}));

        IUniswapV2Pair pair = IUniswapV2Pair(uniswapFactory.getPair(address(dai), address(weth)));
        permissionedPair = address(pair);
        
        pair.swap(debt, 0, address(this), data);
    }

    function uniswapV2Call(address sender, uint amount0, uint /*_amount1*/, bytes calldata data) external {
        if (msg.sender != permissionedPair) {
            revert UnauthorizedMsgSender();
        }
        if (sender != address(this)) {
            revert UnauthorizedInitiator();
        }

        SwapParams memory params = abi.decode(data, (SwapParams));
        
        // Liquidate user: send DAI, recv WETH
        dai.approve(address(vault), amount0);
        uint256 receivedWeth = vault.liquidate(params.vaultUser);

        // Swap WETH for DAI
        weth.approve(address(amm), receivedWeth);
        uint256 receivedDai = amm.sell1(receivedWeth);

        // Repay flash loan
        uint256 amountWithFee = amount0 + flashFee(amount0);
        dai.safeTransfer(msg.sender, amountWithFee);

        // Send liquidation initiator the remaining DAI
        dai.safeTransfer(params.liquidator, receivedDai - amountWithFee);
    }

    function flashFee(uint256 amount) public pure returns (uint256 fee) {
        fee = ((3 * amount) / 997) + 1;
    }
}