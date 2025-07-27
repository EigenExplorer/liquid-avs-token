// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISfrxETH {
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);
}