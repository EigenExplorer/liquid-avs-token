// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract LiquidAvsToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public avsToken;
    address public strategyManager;

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _avsToken
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        avsToken = _avsToken;
    }

    function setStrategyManager(address _strategyManager) external onlyOwner {
        strategyManager = _strategyManager;
    }

    function deposit(uint256 amount) external returns (uint256) {
        require(amount > 0, "Deposit amount must be greater than 0");
        uint256 shares = calculateShares(amount);

        avsToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount, shares);
        return shares;
    }

    function withdraw(uint256 shares) external returns (uint256) {
        require(shares > 0, "Withdraw shares must be greater than 0");
        require(balanceOf(msg.sender) >= shares, "Insufficient balance");

        uint256 amount = calculateAmount(shares);
        _burn(msg.sender, shares);
        avsToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, shares);
        return amount;
    }

    function withdrawToNode(address node, uint256 amount) external {
        require(
            msg.sender == strategyManager,
            "Only strategy manager can withdraw to nodes"
        );
        require(
            amount <= avsToken.balanceOf(address(this)),
            "Insufficient balance"
        );

        avsToken.safeTransfer(node, amount);
    }
    
    function calculateShares(uint256 amount) public view returns (uint256) {
        if (totalSupply() == 0) {
            return amount;
        }
        return (amount * totalSupply()) / avsToken.balanceOf(address(this));
    }

    function calculateAmount(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (shares * avsToken.balanceOf(address(this))) / totalSupply();
    }
}