// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

/**
 * @title StakerNodeCoordinator
 * @notice Coordinates the creation and management of staker nodes
 * @dev Manages the upgradeability and initialization of staker nodes
 */
contract StakerNodeCoordinator is
    IStakerNodeCoordinator,
    AccessControlUpgradeable
{
    ILiquidTokenManager public override liquidTokenManager;
    IStrategyManager public override strategyManager;
    IDelegationManager public override delegationManager;
    uint256 public override maxNodes;

    UpgradeableBeacon public upgradeableBeacon;
    IStakerNode[] private stakerNodes;

    bytes32 public constant STAKER_NODES_DELEGATOR_ROLE =
        keccak256("STAKER_NODES_DELEGATOR_ROLE");
    bytes32 public constant STAKER_NODE_CREATOR_ROLE =
        keccak256("STAKER_NODE_CREATOR_ROLE");

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the StakerNodeCoordinator contract
    /// @param init Struct containing initialization parameters
    /// @dev This function can only be called once due to the initializer modifier
    function initialize(Init calldata init) external override initializer {
        __AccessControl_init();

        // Zero address checks
        if (init.initialOwner == address(0)) {
            revert("Initial owner cannot be the zero address");
        }
        if (init.stakerNodeCreator == address(0)) {
            revert("Staker node creator cannot be the zero address");
        }
        if (init.stakerNodesDelegator == address(0)) {
            revert("Staker nodes delegator cannot be the zero address");
        }
        if (address(init.liquidTokenManager) == address(0)) {
            revert("LiquidTokenManager cannot be the zero address");
        }
        if (address(init.strategyManager) == address(0)) {
            revert("StrategyManager cannot be the zero address");
        }
        if (address(init.delegationManager) == address(0)) {
            revert("DelegationManager cannot be the zero address");
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(STAKER_NODE_CREATOR_ROLE, init.stakerNodeCreator);
        _grantRole(STAKER_NODES_DELEGATOR_ROLE, init.stakerNodesDelegator);

        liquidTokenManager = init.liquidTokenManager;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        maxNodes = init.maxNodes;
    }

    /// @notice Creates a new staker node
    /// @dev Only callable by accounts with STAKER_NODE_CREATOR_ROLE
    /// @return The IStakerNode interface of the newly created staker node
    function createStakerNode()
        public
        override
        notZeroAddress(address(upgradeableBeacon))
        onlyRole(STAKER_NODE_CREATOR_ROLE)
        returns (IStakerNode)
    {
        uint256 nodeId = stakerNodes.length;

        if (nodeId >= maxNodes) {
            revert TooManyStakerNodes(maxNodes);
        }

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        IStakerNode node = IStakerNode(payable(proxy));

        initializeStakerNode(node, nodeId);

        stakerNodes.push(node);

        emit NodeCreated(nodeId, node, msg.sender);

        return node;
    }

    /// @notice Initializes a staker node
    /// @param node The staker node to initialize
    /// @param nodeId The ID of the staker node
    /// @dev This function is internal and called during node creation and upgrades
    function initializeStakerNode(IStakerNode node, uint256 nodeId) internal {
        uint64 initializedVersion = node.getInitializedVersion();
        if (initializedVersion == 0) {
            node.initialize(
                IStakerNode.Init(IStakerNodeCoordinator(address(this)), nodeId)
            );

            initializedVersion = node.getInitializedVersion();
            emit NodeInitialized(address(node), initializedVersion, nodeId);
        }
    }

    /// @notice Registers the initial staker node implementation
    /// @param _implementationContract Address of the implementation contract
    /// @dev Can only be called once by an account with DEFAULT_ADMIN_ROLE
    function registerStakerNodeImplementation(
        address _implementationContract
    )
        public
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        notZeroAddress(_implementationContract)
    {
        if (address(upgradeableBeacon) != address(0)) {
            revert BeaconImplementationAlreadyExists();
        }

        upgradeableBeacon = new UpgradeableBeacon(
            _implementationContract,
            address(this)
        );

        emit NodeImplementationChanged(address(upgradeableBeacon), _implementationContract, true);
    }

    /// @notice Upgrades the staker node implementation
    /// @param _implementationContract Address of the new implementation contract
    /// @dev Can only be called by an account with DEFAULT_ADMIN_ROLE
    function upgradeStakerNodeImplementation(
        address _implementationContract
    )
        public
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        notZeroAddress(_implementationContract)
    {
        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }

        upgradeableBeacon.upgradeTo(_implementationContract);

        uint256 nodeCount = stakerNodes.length;

        for (uint256 i = 0; i < nodeCount; i++) {
            initializeStakerNode(IStakerNode(stakerNodes[i]), i);
        }

        emit NodeImplementationChanged(address(upgradeableBeacon), _implementationContract, false);
    }

    /// @notice Sets the maximum number of staker nodes
    /// @param _maxNodes New maximum number of nodes
    /// @dev Can only be called by an account with DEFAULT_ADMIN_ROLE
    function setMaxNodes(
        uint256 _maxNodes
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 nodeCount = stakerNodes.length;
        if (_maxNodes < nodeCount) {
            revert MaxNodesLowerThanCurrent(nodeCount, _maxNodes);
        }

        uint256 oldMaxNodes = maxNodes;
        maxNodes = _maxNodes;
        emit MaxNodesUpdated(oldMaxNodes, _maxNodes, msg.sender);
    }

    /// @notice Checks if an address has the STAKER_NODES_DELEGATOR_ROLE
    /// @param _address Address to check
    /// @return bool True if the address has the role, false otherwise
    function hasStakerNodeDelegatorRole(
        address _address
    ) public view override returns (bool) {
        return hasRole(STAKER_NODES_DELEGATOR_ROLE, _address);
    }

    /// @notice Checks if a caller is the liquid token manager
    /// @param caller Address to check
    /// @return bool True if the caller is the liquid token manager, false otherwise
    function hasLiquidTokenManagerRole(
        address caller
    ) public view override returns (bool) {
        return caller == address(liquidTokenManager);
    }

    /// @notice Retrieves all staker nodes
    /// @return An array of all IStakerNode interfaces
    function getAllNodes() public view override returns (IStakerNode[] memory) {
        return stakerNodes;
    }

    /// @notice Gets the total number of staker nodes
    /// @return uint256 The number of staker nodes
    function getStakerNodesCount() public view override returns (uint256) {
        return stakerNodes.length;
    }

    /// @notice Retrieves a staker node by its ID
    /// @param nodeId The ID of the staker node
    /// @return The IStakerNode interface of the staker node
    function getNodeById(
        uint256 nodeId
    ) public view override returns (IStakerNode) {
        if (nodeId >= stakerNodes.length) {
            revert NodeIdOutOfRange(nodeId);
        }
        return stakerNodes[nodeId];
    }


    /// @notice Delegate a set of staker nodes to a corresponding set of operators
    /// @param nodeIds The IDs of the staker nodes
    /// @param operators The addresses of the operators
    /// @param approverSignatureAndExpiries The signatures authorizing the delegations
    /// @param approverSalts The salts used in the signatures
    function delegateStakerNodes(
        uint256[] calldata nodeIds,
        address[] calldata operators,
        ISignatureUtils.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    )
        external
        override
        onlyRole(STAKER_NODES_DELEGATOR_ROLE)
    {
        uint256 arrayLength = nodeIds.length;

        if (
            operators.length != arrayLength ||
            approverSignatureAndExpiries.length != arrayLength ||
            approverSalts.length != arrayLength
        ) {
            revert LengthMismatch();
        }

        for (uint256 i = 0; i < arrayLength; i++) {
            IStakerNode node = getNodeById((nodeIds[i]));
            node.delegate(operators[i], approverSignatureAndExpiries[i], approverSalts[i]);
        }
    }

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateStakerNodes(
        uint256[] calldata nodeIds
    )
        external
        override
        onlyRole(STAKER_NODES_DELEGATOR_ROLE)
    {
        for (uint256 i = 0; i < nodeIds.length; i++) {
            IStakerNode node = getNodeById((nodeIds[i]));
            node.undelegate();
        }
    }

    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
