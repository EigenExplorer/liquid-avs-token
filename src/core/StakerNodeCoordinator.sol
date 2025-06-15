// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";

import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/**
 * @title StakerNodeCoordinator
 * @notice Coordinates the creation, init, management and upgradeability of staker nodes
 */
contract StakerNodeCoordinator is IStakerNodeCoordinator, AccessControlUpgradeable {
    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Role identifier for node creation operations
    bytes32 public constant STAKER_NODE_CREATOR_ROLE = keccak256("STAKER_NODE_CREATOR_ROLE");

    /// @notice Role identifier for node delegation operations
    bytes32 public constant STAKER_NODES_DELEGATOR_ROLE = keccak256("STAKER_NODES_DELEGATOR_ROLE");

    /// @notice EigenLayer contracts
    ILiquidTokenManager public override liquidTokenManager;
    IStrategyManager public override strategyManager;
    IDelegationManager public override delegationManager;

    /// @notice OZ and v1 LAT contracts
    UpgradeableBeacon public upgradeableBeacon;
    IStakerNode[] private stakerNodes;

    uint256 public override maxNodes;

    /// @notice v2 LAT contracts
    IWithdrawalManager public override withdrawalManager;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IStakerNodeCoordinator
    function initialize(Init calldata init) external override initializer {
        __AccessControl_init();

        // Zero address checks
        if (
            address(init.initialOwner) == address(0) ||
            address(init.pauser) == address(0) ||
            address(init.stakerNodeCreator) == address(0) ||
            address(init.stakerNodesDelegator) == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            address(init.withdrawalManager) == address(0) ||
            address(init.strategyManager) == address(0) ||
            address(init.delegationManager) == address(0)
        ) {
            revert ZeroAddress();
        }

        if (init.maxNodes == 0) {
            revert ZeroAmount();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(STAKER_NODE_CREATOR_ROLE, init.stakerNodeCreator);
        _grantRole(STAKER_NODES_DELEGATOR_ROLE, init.stakerNodesDelegator);

        liquidTokenManager = init.liquidTokenManager;
        withdrawalManager = init.withdrawalManager;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        maxNodes = init.maxNodes;
        _registerStakerNodeImplementation(init.stakerNodeImplementation);
    }

    /// @notice Registers the initial staker node implementation
    /// @dev Called by `initialize`
    function _registerStakerNodeImplementation(
        address _implementationContract
    ) internal notZeroAddress(_implementationContract) {
        if (address(upgradeableBeacon) != address(0)) {
            revert BeaconImplementationAlreadyExists();
        }

        upgradeableBeacon = new UpgradeableBeacon(_implementationContract);

        upgradeableBeacon.transferOwnership(address(this));

        emit NodeImplementationChanged(address(upgradeableBeacon), _implementationContract, true);
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IStakerNodeCoordinator
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

        address beaconAddr = address(upgradeableBeacon);
        BeaconProxy proxy = new BeaconProxy(beaconAddr, "");
        IStakerNode node = IStakerNode(payable(proxy));

        _initializeStakerNode(node, nodeId);

        unchecked {
            stakerNodes.push(node);
        }

        emit NodeCreated(nodeId, node, msg.sender);

        return node;
    }

    /// @inheritdoc IStakerNodeCoordinator
    function upgradeStakerNodeImplementation(
        address _implementationContract
    ) public override onlyRole(DEFAULT_ADMIN_ROLE) notZeroAddress(_implementationContract) {
        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }
        if (_implementationContract.code.length == 0) revert NotAContract();

        upgradeableBeacon.upgradeTo(_implementationContract);

        uint256 nodeCount = stakerNodes.length;
        unchecked {
            for (uint256 i = 0; i < nodeCount; i++) {
                _initializeStakerNode(IStakerNode(stakerNodes[i]), i);
            }
        }

        emit NodeImplementationChanged(address(upgradeableBeacon), _implementationContract, false);
    }

    /// @dev Called by `createStakerNode` and `upgradeStakerNodeImplementation`
    function _initializeStakerNode(IStakerNode node, uint256 nodeId) internal {
        uint64 initializedVersion = node.getInitializedVersion();
        if (initializedVersion == 0) {
            node.initialize(IStakerNode.Init(IStakerNodeCoordinator(address(this)), nodeId));

            initializedVersion = node.getInitializedVersion();
            emit NodeInitialized(address(node), initializedVersion, nodeId);
        }
    }

    /// @inheritdoc IStakerNodeCoordinator
    function setMaxNodes(uint256 _maxNodes) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 nodeCount = stakerNodes.length;
        if (_maxNodes < nodeCount) {
            revert MaxNodesLowerThanCurrent(nodeCount, _maxNodes);
        }

        uint256 oldMaxNodes = maxNodes;
        maxNodes = _maxNodes;
        emit MaxNodesUpdated(oldMaxNodes, _maxNodes, msg.sender);
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

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
    function getNodeById(uint256 nodeId) public view override returns (IStakerNode) {
        if (nodeId >= stakerNodes.length) {
            revert NodeIdOutOfRange(nodeId);
        }
        return stakerNodes[nodeId];
    }

    /// @notice Checks if an address has the STAKER_NODES_DELEGATOR_ROLE
    /// @param _address Address to check
    /// @return bool True if the address has the role, false otherwise
    function hasStakerNodeDelegatorRole(address _address) public view override returns (bool) {
        return hasRole(STAKER_NODES_DELEGATOR_ROLE, _address);
    }

    /// @notice Checks if a caller is the liquid token manager
    /// @param caller Address to check
    /// @return bool True if the caller is the liquid token manager, false otherwise
    function hasLiquidTokenManagerRole(address caller) public view override returns (bool) {
        return caller == address(liquidTokenManager);
    }

    // ------------------------------------------------------------------------------
    // Misc
    // ------------------------------------------------------------------------------

    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
