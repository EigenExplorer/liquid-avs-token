// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IToken {
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);

    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 shares) external returns (uint256);
    function withdrawToNode(address node, uint256 amount) external;
    function calculateShares(uint256 amount) external view returns (uint256);
    function calculateAmount(uint256 shares) external view returns (uint256);
}
