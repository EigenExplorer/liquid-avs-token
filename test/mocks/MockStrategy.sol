// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStrategy is IStrategy {
    using SafeERC20 for IERC20;

    IERC20 public underlyingToken;
    IStrategyManager public strategyManager;
    mapping(address => uint256) public shares;
    uint256 public totalShares;

    constructor(IStrategyManager _strategyManager, IERC20 _token) {
        underlyingToken = _token;
        strategyManager = _strategyManager;
    }

    function deposit(IERC20 token, uint256 amount) external override returns (uint256) {
        require(token == underlyingToken, "Wrong token");
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 newShares = amount;
        shares[msg.sender] += newShares;
        totalShares += newShares;
        return newShares;
    }

    function withdraw(
        address recipient,
        IERC20 token,
        uint256 amountShares
    ) external override {
        require(token == underlyingToken, "Wrong token");
        shares[msg.sender] -= amountShares;
        totalShares -= amountShares;
        token.safeTransfer(recipient, amountShares);
    }

    function sharesToUnderlying(uint256 amountShares) external view override returns (uint256) {
        return amountShares;
    }

    function underlyingToShares(uint256 amountUnderlying) external view override returns (uint256) {
        return amountUnderlying;
    }

    function sharesToUnderlyingView(uint256 amountShares) external pure override returns (uint256) {
        return amountShares;
    }

    function underlyingToSharesView(uint256 amountUnderlying) external pure override returns (uint256) {
        return amountUnderlying;
    }

    function userUnderlying(address user) external override returns (uint256) {
        return shares[user];
    }

    function userUnderlyingView(address user) external view override returns (uint256) {
        return shares[user];
    }

    function explanation() external pure override returns (string memory) {
        return "MockStrategy for testing";
    }
}
