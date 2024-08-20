// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOrchestrator {
    // Events
    event StrategyAdded(address indexed asset, address indexed strategy);
    event StakedAssetsToNode(
        uint256 indexed nodeId,
        IERC20[] assets,
        uint256[] amounts
    );

    // Errors
    error ZeroAddress();
    error InvalidStakingAmount(uint256 amount);
    error StrategyNotFound(address asset);
    error LengthMismatch(uint256 length1, uint256 length2);

    // Initialization
    function initialize(
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        address admin,
        address strategyController
    ) external;

    // Strategy Management
    function setStrategy(IERC20 asset, IStrategy strategy) external;

    // Staking Management
    function getStakedAssetBalance(
        IERC20 asset,
        uint256 nodeId
    ) external view returns (uint256);
}
