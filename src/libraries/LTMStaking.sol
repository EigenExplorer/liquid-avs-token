// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";

library LTMStaking {
    using SafeERC20 for IERC20;

    function validateStakingInputs(
        IERC20[] memory assets,
        uint256[] memory amounts,
        mapping(IERC20 => IStrategy) storage tokenStrategies
    ) external view returns (IStrategy[] memory strategies) {
        require(assets.length == amounts.length, "LengthMismatch");

        strategies = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            require(amounts[i] != 0, "InvalidStakingAmount");
            IStrategy strategy = tokenStrategies[assets[i]];
            require(address(strategy) != address(0), "StrategyNotFound");
            strategies[i] = strategy;
        }
    }

    function transferAssetsFromLiquidToken(
        IERC20[] memory assets,
        uint256[] memory amounts,
        ILiquidToken liquidToken
    ) external {
        liquidToken.transferAssets(assets, amounts, address(this));
    }

    function transferAssetsToNode(
        IERC20[] memory assets,
        uint256[] memory amounts,
        address nodeAddress
    ) external returns (uint256[] memory actualAmounts) {
        actualAmounts = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balance = assets[i].balanceOf(address(this));
            actualAmounts[i] = balance < amounts[i] ? balance : amounts[i];
            assets[i].safeTransfer(nodeAddress, actualAmounts[i]);
        }
    }

    function executeNodeDeposit(
        IStakerNode node,
        IERC20[] memory assets,
        uint256[] memory amounts,
        IStrategy[] memory strategies
    ) external {
        node.depositAssets(assets, amounts, strategies);
    }
}