// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IOrchestrator} from "../interfaces/IOrchestrator.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";

contract StakerNodeCoordinator is
    IStakerNodeCoordinator,
    AccessControlUpgradeable
{
    IOrchestrator public override orchestrator;
    IStrategyManager public override strategyManager;
    IDelegationManager public override delegationManager;
    uint256 public override maxNodes;

    UpgradeableBeacon public upgradeableBeacon;
    address[] private stakerNodes;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant STAKER_NODE_OPERATOR_ROLE =
        keccak256("STAKER_NODE_OPERATOR_ROLE");
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

        _grantRole(ADMIN_ROLE, init.initialOwner);
        _grantRole(STAKER_NODE_OPERATOR_ROLE, init.stakerNodeOperator);
        _grantRole(STAKER_NODE_CREATOR_ROLE, init.stakerNodeCreator);
        _grantRole(STAKER_NODES_DELEGATOR_ROLE, init.stakerNodesDelegator);

        orchestrator = init.orchestrator;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        maxNodes = init.maxNodes;
    }

    /// @notice Creates a new staker node
    /// @dev Only callable by accounts with STAKER_NODE_CREATOR_ROLE
    /// @return Address of the newly created staker node
    function createStakerNode()
        public
        override
        notZeroAddress(address(upgradeableBeacon))
        onlyRole(STAKER_NODE_CREATOR_ROLE)
        returns (address)
    {
        uint256 nodeId = stakerNodes.length;

        if (nodeId >= maxNodes) {
            revert TooManyStakerNodes(maxNodes);
        }

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        address node = address(proxy);

        initializeStakerNode(IStakerNode(node), nodeId);

        stakerNodes.push(node);

        emit StakerNodeCreated(nodeId, node);

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
            emit NodeInitialized(address(node), initializedVersion);
        }
    }

    /// @notice Registers the initial staker node implementation
    /// @param _implementationContract Address of the implementation contract
    /// @dev Can only be called once by an account with ADMIN_ROLE
    function registerStakerNodeImplementation(
        address _implementationContract
    )
        public
        override
        onlyRole(ADMIN_ROLE)
        notZeroAddress(_implementationContract)
    {
        if (address(upgradeableBeacon) != address(0)) {
            revert BeaconImplementationAlreadyExists();
        }

        upgradeableBeacon = new UpgradeableBeacon(
            _implementationContract,
            address(this)
        );

        emit RegisteredStakerNodeImplementation(
            address(upgradeableBeacon),
            _implementationContract
        );
    }

    /// @notice Upgrades the staker node implementation
    /// @param _implementationContract Address of the new implementation contract
    /// @dev Can only be called by an account with ADMIN_ROLE
    function upgradeStakerNodeImplementation(
        address _implementationContract
    )
        public
        override
        onlyRole(ADMIN_ROLE)
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

        emit UpgradedStakerNodeImplementation(
            _implementationContract,
            nodeCount
        );
    }

    /// @notice Sets the maximum number of staker nodes
    /// @param _maxNodes New maximum number of nodes
    /// @dev Can only be called by an account with ADMIN_ROLE
    function setMaxNodes(
        uint256 _maxNodes
    ) public override onlyRole(ADMIN_ROLE) {
        maxNodes = _maxNodes;
        emit MaxNodesUpdated(_maxNodes);
    }

    /// @notice Checks if an account has the STAKER_NODE_OPERATOR_ROLE
    /// @param account Address to check
    /// @return bool True if the account has the role, false otherwise
    function hasStakerNodeOperatorRole(
        address account
    ) external view override returns (bool) {
        return hasRole(STAKER_NODE_OPERATOR_ROLE, account);
    }

    /// @notice Checks if an address has the STAKER_NODES_DELEGATOR_ROLE
    /// @param _address Address to check
    /// @return bool True if the address has the role, false otherwise
    function hasStakerNodeDelegatorRole(
        address _address
    ) public view override returns (bool) {
        return hasRole(STAKER_NODES_DELEGATOR_ROLE, _address);
    }

    /// @notice Checks if a caller is the orchestrator
    /// @param caller Address to check
    /// @return bool True if the caller is the orchestrator, false otherwise
    function hasOrchestratorRole(
        address caller
    ) public view override returns (bool) {
        return caller == address(orchestrator);
    }

    /// @notice Retrieves all staker node addresses
    /// @return address[] Array of all staker node addresses
    function getAllNodes() public view override returns (address[] memory) {
        return stakerNodes;
    }

    /// @notice Gets the total number of staker nodes
    /// @return uint256 The number of staker nodes
    function getStakerNodesCount() public view override returns (uint256) {
        return stakerNodes.length;
    }

    /// @notice Retrieves a staker node address by its ID
    /// @param nodeId The ID of the staker node
    /// @return address The address of the staker node
    function getNodeById(
        uint256 nodeId
    ) public view override returns (address) {
        if (nodeId >= stakerNodes.length) {
            revert NodeIdOutOfRange(nodeId);
        }
        return stakerNodes[nodeId];
    }

    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
