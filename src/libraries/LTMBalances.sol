// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

library LTMBalances {
    using Math for uint256;

    function getDepositBalance(
        IERC20 asset,
        IStakerNode node,
        bool inElShares,
        mapping(IERC20 => IStrategy) storage tokenStrategies
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        require(address(strategy) != address(0), "StrategyNotFound");

        return inElShares ? strategy.shares(address(node)) : strategy.userUnderlyingView(address(node));
    }

    function getWithdrawableBalance(
        IERC20 asset,
        IStakerNode node,
        bool inElShares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IDelegationManager delegationManager
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        require(address(strategy) != address(0), "StrategyNotFound");

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;

        (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(address(node), strategies);

        if (withdrawableShares[0] == 0) return 0;

        return inElShares ? withdrawableShares[0] : strategy.sharesToUnderlyingView(withdrawableShares[0]);
    }

    function getAllDepositBalances(
        IERC20 asset,
        bool inElShares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IStakerNodeCoordinator stakerNodeCoordinator
    ) external view returns (uint256 totalBalance) {
        IStrategy strategy = tokenStrategies[asset];
        require(address(strategy) != address(0), "StrategyNotFound");

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        totalBalance = 0;

        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += inElShares
                ? strategy.shares(address(nodes[i]))
                : strategy.userUnderlyingView(address(nodes[i]));
        }
    }

    function getAllWithdrawableBalances(
        IERC20 asset,
        bool inElShares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IStakerNodeCoordinator stakerNodeCoordinator,
        IDelegationManager delegationManager
    ) external view returns (uint256 totalBalance) {
        IStrategy strategy = tokenStrategies[asset];
        require(address(strategy) != address(0), "StrategyNotFound");

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        totalBalance = 0;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;

        for (uint256 i = 0; i < nodes.length; i++) {
            (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(
                address(nodes[i]),
                strategies
            );

            if (withdrawableShares[0] > 0) {
                totalBalance += inElShares
                    ? withdrawableShares[0]
                    : strategy.sharesToUnderlyingView(withdrawableShares[0]);
            }
        }
    }

    function getWithdrawableAmount(
        IERC20 asset,
        uint256 amount,
        bool inElShares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IStakerNodeCoordinator stakerNodeCoordinator,
        IDelegationManager delegationManager
    ) external view returns (uint256) {
        // Direct implementation instead of calling other functions
        IStrategy strategy = tokenStrategies[asset];
        require(address(strategy) != address(0), "StrategyNotFound");

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalDepositBalance = 0;
        uint256 totalWithdrawableBalance = 0;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;

        // Calculate total deposit balance and withdrawable balance in one loop
        for (uint256 i = 0; i < nodes.length; i++) {
            address nodeAddress = address(nodes[i]);

            // Add deposit balance
            totalDepositBalance += inElShares ? strategy.shares(nodeAddress) : strategy.userUnderlyingView(nodeAddress);

            // Add withdrawable balance
            (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(nodeAddress, strategies);

            if (withdrawableShares[0] > 0) {
                totalWithdrawableBalance += inElShares
                    ? withdrawableShares[0]
                    : strategy.sharesToUnderlyingView(withdrawableShares[0]);
            }
        }

        if (totalDepositBalance == 0 || totalWithdrawableBalance == 0) return 0;

        return amount.mulDiv(totalWithdrawableBalance, totalDepositBalance);
    }
}