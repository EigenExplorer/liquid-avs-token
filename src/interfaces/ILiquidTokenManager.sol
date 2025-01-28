// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {ILiquidToken} from "./ILiquidToken.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";

/// @title ILiquidTokenManager Interface
/// @notice Interface for the LiquidTokenManager contract
interface ILiquidTokenManager {
    /// @notice Initialization parameters for LiquidTokenManager
    struct Init {
        IERC20[] assets;
        IStrategy[] strategies;
        ILiquidToken liquidToken;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
        address initialOwner;
        address strategyController;
    }

    /// @notice Represents an allocation of assets to a node
    struct NodeAllocation {
        uint256 nodeId;
        IERC20[] assets;
        uint256[] amounts;
    }

    /// @notice Emitted when a new strategy is set for an asset
    event StrategySet(IERC20 indexed asset, IStrategy indexed strategy, address indexed setter);

    /// @notice Emitted when assets are staked to a node
    event AssetsStakedToNode(
        uint256 indexed nodeId,
        IERC20[] assets,
        uint256[] amounts,
        address indexed staker
    );

    /// @notice Emitted when assets are deposited to Eigenlayer
    event AssetsDepositedToEigenlayer(
        IERC20[] assets,
        uint256[] amounts,
        IStrategy[] strategies,
        address indexed depositor
    );

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error for invalid staking amount
    error InvalidStakingAmount(uint256 amount);

    /// @notice Error when strategy asset already exists
    error StrategyAssetExists(address asset);

    /// @notice Error when strategy is not found
    error StrategyNotFound(address asset);

    /// @notice Error for mismatched array lengths
    error LengthMismatch(uint256 length1, uint256 length2);

    /// @notice Error for invalid node ID
    error InvalidNodeId(uint256 nodeId);

    /// @notice Initializes the LiquidTokenManager contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Sets the strategy for an asset
    /// @param asset The asset to set the strategy for
    /// @param strategy The strategy to set
    function setStrategy(IERC20 asset, IStrategy strategy) external;

    /// @notice Stakes assets to a specific node
    /// @param nodeId The ID of the node to stake to
    /// @param assets The assets to stake
    /// @param amounts The amounts of each asset to stake
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external;

    /// @notice Stakes assets to multiple nodes
    /// @param allocations The allocations of assets to nodes
    function stakeAssetsToNodes(NodeAllocation[] calldata allocations) external;

    /// @notice Gets the staked asset balance for all nodes
    /// @param asset The asset to check the balance for
    /// @return The total staked balance of the asset across all nodes
    function getStakedAssetBalance(IERC20 asset) external view returns (uint256);

    /// @notice Gets the staked asset balance for a specific node
    /// @param asset The asset to check the balance for
    /// @param nodeId The ID of the node
    /// @return The staked balance of the asset for the specific node
    function getStakedAssetBalanceNode(IERC20 asset, uint256 nodeId) external view returns (uint256);

    /// @notice Delegate a set of staker nodes to a corresponding set of operators
    /// @param nodeIds The IDs of the staker nodes
    /// @param operators The addresses of the operators
    /// @param approverSignatureAndExpiries The signatures authorizing the delegations
    /// @param approverSalts The salts used in the signatures
    function delegateNodesToOperators(
        uint256[] calldata nodeIds,
        address[] calldata operators,
        ISignatureUtils.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) external;

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateNodesFromOperators(
        uint256[] calldata nodeIds
    ) external;

    /// @notice Returns the StrategyManager contract
    /// @return The IStrategyManager interface
    function strategyManager() external view returns (IStrategyManager);

    /// @notice Returns the DelegationManager contract
    /// @return The IDelegationManager interface
    function delegationManager() external view returns (IDelegationManager);

    /// @notice Returns the StakerNodeCoordinator contract
    /// @return The IStakerNodeCoordinator interface
    function stakerNodeCoordinator()
        external
        view
        returns (IStakerNodeCoordinator);

    /// @notice Returns the LiquidToken contract
    /// @return The ILiquidToken interface
    function liquidToken() external view returns (ILiquidToken);

    /// @notice Returns the strategy for a given asset
    /// @param asset The asset to get the strategy for
    /// @return The IStrategy interface for the asset
    function strategies(IERC20 asset) external view returns (IStrategy);
}
