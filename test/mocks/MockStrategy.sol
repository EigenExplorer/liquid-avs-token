// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/interfaces/IPauserRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStrategy is StrategyBase {
    using SafeERC20 for IERC20;

    constructor(
        IStrategyManager _strategyManager,
        IERC20 _underlyingToken
    ) StrategyBase(_strategyManager, IPauserRegistry(address(1)), "1.0.0") {
        underlyingToken = _underlyingToken;
    }

    function _beforeDeposit(IERC20 token, uint256 amount) internal virtual override {
        require(token == underlyingToken, "MockStrategy: Can only deposit underlyingToken");
    }

    function _beforeWithdrawal(address recipient, IERC20 token, uint256 amountShares) internal virtual override {
        require(token == underlyingToken, "MockStrategy: Can only withdraw underlyingToken");
    }

    function _afterWithdrawal(address recipient, IERC20 token, uint256 amountToSend) internal virtual override {
        token.safeTransfer(recipient, amountToSend);
    }
}