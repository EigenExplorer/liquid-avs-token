// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IStakerNode.sol";

interface IEigenlayerStrategy {
    function deposit(uint256 amount) external;
}

interface IEigenlayerOperator {
    function delegate(address operator) external;
}

contract StakerNode is IStakerNode, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public avsToken;
    IEigenlayerStrategy public strategy;
    IEigenlayerOperator public eigenlayerOperator;

    event Delegated(address indexed operator);
    event DepositedToStrategy(uint256 amount);

    constructor(
        address _avsToken,
        address _strategy,
        address _eigenlayerOperator
    ) Ownable(msg.sender) {
        avsToken = IERC20(_avsToken);
        strategy = IEigenlayerStrategy(_strategy);
        eigenlayerOperator = IEigenlayerOperator(_eigenlayerOperator);
    }

    function delegateToOperator(address operator) external onlyOwner {
        eigenlayerOperator.delegate(operator);
        emit Delegated(operator);
    }

    function depositToStrategy(uint256 amount) external onlyOwner {
        require(
            avsToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        avsToken.approve(address(strategy), amount);
        strategy.deposit(amount);

        emit DepositedToStrategy(amount);
    }

    function withdrawTokens(
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(
            avsToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        avsToken.safeTransfer(recipient, amount);
    }
}
