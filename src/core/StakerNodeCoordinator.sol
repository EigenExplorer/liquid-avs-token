// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";

import {StakerNode} from "./StakerNode.sol";
import {IOrchestrator} from "../interfaces/IOrchestrator.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

contract StakerNodeCoordinator is
    IStakerNodeCoordinator,
    AccessControlUpgradeable
{
    IOrchestrator public orchestrator;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    uint256 public maxNodes;

    address[] public stakerNodes;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize(Init calldata init) external initializer {
        __AccessControl_init();

        _grantRole(ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        orchestrator = init.orchestrator;
        delegationManager = init.delegationManager;
        strategyManager = init.strategyManager;
        maxNodes = init.maxNodes;
    }

    function addStakerNode(address _nodeAddress) external onlyRole(ADMIN_ROLE) {
        if (_nodeAddress == address(0)) {
            revert ZeroAddress();
        }

        if (stakerNodes.length >= maxNodes) {
            revert MaxNodesReached(maxNodes);
        }

        for (uint i = 0; i < stakerNodes.length; i++) {
            if (stakerNodes[i] == _nodeAddress) {
                revert NodeAlreadyRegistered(_nodeAddress);
            }
        }

        stakerNodes.push(_nodeAddress);
        emit StakerNodeAdded(_nodeAddress);
    }

    function removeStakerNode(
        address _nodeAddress
    ) external onlyRole(ADMIN_ROLE) {
        for (uint i = 0; i < stakerNodes.length; i++) {
            if (stakerNodes[i] == _nodeAddress) {
                stakerNodes[i] = stakerNodes[stakerNodes.length - 1];
                stakerNodes.pop();
                emit StakerNodeRemoved(_nodeAddress);
                return;
            }
        }
    }

    function isStakerNode(address _nodeAddress) public view returns (bool) {
        for (uint i = 0; i < stakerNodes.length; i++) {
            if (stakerNodes[i] == _nodeAddress) {
                return true;
            }
        }
        return false;
    }

    function getStakerNodesCount() external view returns (uint256) {
        return stakerNodes.length;
    }

    function setMaxNodes(uint256 _maxNodes) external onlyRole(ADMIN_ROLE) {
        maxNodes = _maxNodes;
        emit MaxNodesUpdated(_maxNodes);
    }
}
