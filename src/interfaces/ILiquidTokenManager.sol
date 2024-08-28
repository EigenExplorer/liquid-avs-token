// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidToken} from "./ILiquidToken.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";

interface ILiquidTokenManager {
    struct Init {
        IERC20[] assets;
        IStrategy[] strategies;
        ILiquidToken liquidToken;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
        address admin;
        address strategyController;
    }

    struct NodeAllocation {
        uint256 nodeId;
        IERC20[] assets;
        uint256[] amounts;
    }

    // Events
    event StrategyAdded(address indexed asset, address indexed strategy);
    event StakedAssetsToNode(
        uint256 indexed nodeId,
        IERC20[] assets,
        uint256[] amounts
    );
    event DepositedToEigenlayer(
        IERC20[] assets,
        uint256[] amounts,
        IStrategy[] strategies
    );

    // Errors
    error ZeroAddress();
    error InvalidStakingAmount(uint256 amount);
    error StrategyAssetExists(address asset);
    error StrategyNotFound(address asset);
    error LengthMismatch(uint256 length1, uint256 length2);
    error InvalidNodeId(uint256 nodeId);

    // Initialization
    function initialize(Init memory init) external;

    // Strategy Management
    function setStrategy(IERC20 asset, IStrategy strategy) external;

    // Staking Management
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external;

    function stakeAssetsToNodes(NodeAllocation[] calldata allocations) external;

    // View Functions
    function getStakedAssetBalance(
        IERC20 asset,
        uint256 nodeId
    ) external view returns (uint256);

    // State Variables
    function strategyManager() external view returns (IStrategyManager);
    function delegationManager() external view returns (IDelegationManager);
    function stakerNodeCoordinator()
        external
        view
        returns (IStakerNodeCoordinator);
    function liquidToken() external view returns (ILiquidToken);
    function strategies(IERC20 asset) external view returns (IStrategy);
}
