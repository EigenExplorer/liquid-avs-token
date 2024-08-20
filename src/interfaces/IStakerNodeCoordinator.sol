// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakerNodeCoordinator {
    event StakerNodeAdded(address indexed nodeAddress);
    event TokensWithdrawnToNode(address indexed nodeAddress, uint256 amount);
}