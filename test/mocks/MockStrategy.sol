// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/permissions/PauserRegistry.sol";

contract MockStrategy is StrategyBase {
    using SafeERC20 for IERC20;

    constructor(IStrategyManager _strategyManager) StrategyBase(_strategyManager) {}

    function initialize(IERC20 _underlyingToken, IPauserRegistry _pauserRegistry) public initializer override {
        _initializeStrategyBase(_underlyingToken, _pauserRegistry);
    }

    function _beforeDeposit(IERC20 token, uint256 amount) internal virtual override {
        require(token == underlyingToken, "MockStrategy: Can only deposit underlyingToken");
    }

    function _beforeWithdrawal(
        address recipient,
        IERC20 token,
        uint256 amountShares
    ) internal virtual override {
        require(token == underlyingToken, "MockStrategy: Can only withdraw underlyingToken");
    }

    function _afterWithdrawal(address recipient, IERC20 token, uint256 amountToSend) internal virtual override {
        token.safeTransfer(recipient, amountToSend);
    }
}