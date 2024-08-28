// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";

import {IStakerNode} from "./IStakerNode.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

/// @title IStakerNodeCoordinator
/// @notice Interface for the StakerNodeCoordinator contract
interface IStakerNodeCoordinator {
    /// @notice Initialization parameters for the StakerNodeCoordinator
    struct Init {
        ILiquidTokenManager liquidTokenManager;
        IDelegationManager delegationManager;
        IStrategyManager strategyManager;
        uint256 maxNodes;
        address initialOwner;
        address pauser;
        address unpauser;
        address stakerNodeOperator;
        address stakerNodeCreator;
        address stakerNodesDelegator;
    }

    /// @notice Emitted when a new staker node is created
    /// @param nodeId The ID of the newly created node
    /// @param node The IStakerNode interface of the newly created node
    event StakerNodeCreated(uint256 nodeId, IStakerNode node);

    /// @notice Emitted when a staker node is removed
    /// @param node The IStakerNode interface of the removed node
    event StakerNodeRemoved(IStakerNode node);

    /// @notice Emitted when the maximum number of nodes is updated
    /// @param maxNodes The new maximum number of nodes
    event MaxNodesUpdated(uint256 maxNodes);

    /// @notice Emitted when a new staker node implementation is registered
    /// @param upgradeableBeaconAddress The address of the upgradeable beacon
    /// @param implementationContract The address of the new implementation contract
    event RegisteredStakerNodeImplementation(address upgradeableBeaconAddress, address implementationContract);

    /// @notice Emitted when the staker node implementation is upgraded
    /// @param implementationContract The address of the new implementation contract
    /// @param nodesCount The number of nodes upgraded
    event UpgradedStakerNodeImplementation(address implementationContract, uint256 nodesCount);

    /// @notice Emitted when a node is initialized
    /// @param nodeAddress The address of the initialized node
    /// @param initializedVersion The version of the initialization
    event NodeInitialized(address nodeAddress, uint64 initializedVersion);

    error UnsupportedAsset(IERC20 asset);
    error Unauthorized();
    error InsufficientFunds();
    error Paused();
    error ZeroAmount();
    error ZeroAddress();
    error BeaconImplementationAlreadyExists();
    error NoBeaconImplementationExists();
    error TooManyStakerNodes(uint256 maxNodes);
    error NodeIdOutOfRange(uint256 nodeId);
    error NodeAlreadyRegistered(address nodeAddress);
    error NotOwner();

    /// @notice Initializes the StakerNodeCoordinator contract
    /// @param init Struct containing initialization parameters
    function initialize(Init calldata init) external;

    /// @notice Creates a new staker node
    /// @return The IStakerNode interface of the newly created staker node
    function createStakerNode() external returns (IStakerNode);

    /// @notice Registers the initial staker node implementation
    /// @param _implementationContract Address of the implementation contract
    function registerStakerNodeImplementation(address _implementationContract) external;

    /// @notice Upgrades the staker node implementation
    /// @param _implementationContract Address of the new implementation contract
    function upgradeStakerNodeImplementation(address _implementationContract) external;

    /// @notice Sets the maximum number of staker nodes
    /// @param _maxNodes New maximum number of nodes
    function setMaxNodes(uint256 _maxNodes) external;

    /// @notice Checks if an account has the STAKER_NODE_OPERATOR_ROLE
    /// @param account Address to check
    /// @return True if the account has the role, false otherwise
    function hasStakerNodeOperatorRole(address account) external view returns (bool);

    /// @notice Checks if an address has the STAKER_NODES_DELEGATOR_ROLE
    /// @param _address Address to check
    /// @return True if the address has the role, false otherwise
    function hasStakerNodeDelegatorRole(address _address) external view returns (bool);

    /// @notice Checks if a caller is the liquid token manager
    /// @param caller Address to check
    /// @return True if the caller is the liquid token manager, false otherwise
    function hasLiquidTokenManagerRole(address caller) external view returns (bool);

    /// @notice Retrieves all staker nodes
    /// @return An array of all IStakerNode interfaces
    function getAllNodes() external view returns (IStakerNode[] memory);

    /// @notice Gets the total number of staker nodes
    /// @return The number of staker nodes
    function getStakerNodesCount() external view returns (uint256);

    /// @notice Retrieves a staker node by its ID
    /// @param nodeId The ID of the staker node
    /// @return The IStakerNode interface of the staker node
    function getNodeById(uint256 nodeId) external view returns (IStakerNode);

    /// @notice Gets the delegation manager contract
    /// @return The IDelegationManager interface
    function delegationManager() external view returns (IDelegationManager);

    /// @notice Gets the strategy manager contract
    /// @return The IStrategyManager interface
    function strategyManager() external view returns (IStrategyManager);

    /// @notice Gets the liquid token manager contract
    /// @return The ILiquidTokenManager interface
    function liquidTokenManager() external view returns (ILiquidTokenManager);

    /// @notice Gets the maximum number of nodes allowed
    /// @return The maximum number of nodes
    function maxNodes() external view returns (uint256);
}