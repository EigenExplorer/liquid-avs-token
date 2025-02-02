// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {IStakerNode} from "./IStakerNode.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/// @title IStakerNodeCoordinator Interface
/// @notice Interface for the StakerNodeCoordinator contract
interface IStakerNodeCoordinator {
    /// @notice Initialization parameters for StakerNodeCoordinator
    struct Init {
        ILiquidTokenManager liquidTokenManager;
        IWithdrawalManager withdrawalManager;
        IDelegationManager delegationManager;
        IStrategyManager strategyManager;
        uint256 maxNodes;
        address initialOwner;
        address pauser;
        address stakerNodeCreator;
        address stakerNodesDelegator;
    }

    /// @notice Emitted when a new staker node is created
    event NodeCreated(uint256 indexed nodeId, IStakerNode indexed node, address indexed creator);

    /// @notice Emitted when the staker node implementation is changed
    event NodeImplementationChanged(address indexed upgradeableBeaconAddress, address indexed implementationContract, bool isInitialRegistration);

    /// @notice Emitted when the maximum number of nodes is updated
    event MaxNodesUpdated(uint256 oldMaxNodes, uint256 newMaxNodes, address indexed updater);

    /// @notice Error thrown when trying to set maxNodes lower than the current number of nodes0
    error MaxNodesLowerThanCurrent(uint256 currentNodeCount, uint256 newMaxNodes);

    /// @notice Emitted when a node is initialized
    event NodeInitialized(address indexed nodeAddress, uint64 initializedVersion, uint256 indexed nodeId);

    /// @notice Error for unsupported asset
    error UnsupportedAsset(IERC20 asset);

    /// @notice Error for insufficient funds
    error InsufficientFunds();

    /// @notice Error when contract is paused
    error Paused();

    /// @notice Error for zero amount
    error ZeroAmount();

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error when beacon implementation already exists
    error BeaconImplementationAlreadyExists();

    /// @notice Error when no beacon implementation exists
    error NoBeaconImplementationExists();

    /// @notice Error when maximum number of staker nodes is reached
    error TooManyStakerNodes(uint256 maxNodes);

    /// @notice Error when node ID is out of range
    error NodeIdOutOfRange(uint256 nodeId);

    /// @notice Error when node is already registered
    error NodeAlreadyRegistered(address nodeAddress);

    /// @notice Error when caller is not the owner
    error NotOwner();

    /// @notice Initializes the StakerNodeCoordinator contract
    /// @param init Initialization parameters
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

    /// @notice Gets the withdrawal manager contract
    /// @return The IWithdrawalManager interface
    function withdrawalManager() external view returns (IWithdrawalManager);

    /// @notice Gets the maximum number of nodes allowed
    /// @return The maximum number of nodes
    function maxNodes() external view returns (uint256);
}