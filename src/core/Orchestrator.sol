// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOrchestrator} from "../interfaces/IOrchestrator.sol";

contract Orchestrator is
    IOrchestrator,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_CONTROLLER_ROLE =
        keccak256("STRATEGY_CONTROLLER_ROLE");
    bytes32 public constant STRATEGY_ADMIN_ROLE =
        keccak256("STRATEGY_ADMIN_ROLE");

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    mapping(IERC20 => IStrategy) public strategies;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        address admin,
        address strategyController
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (
            address(_strategyManager) == address(0) ||
            address(_delegationManager) == address(0) ||
            admin == address(0) ||
            strategyController == address(0)
        ) {
            revert ZeroAddress();
        }

        strategyManager = _strategyManager;
        delegationManager = _delegationManager;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STRATEGY_CONTROLLER_ROLE, strategyController);
        _grantRole(STRATEGY_ADMIN_ROLE, admin);
    }

    function setStrategy(
        IERC20 asset,
        IStrategy strategy
    ) external onlyRole(STRATEGY_ADMIN_ROLE) {
        if (address(asset) == address(0) || address(strategy) == address(0)) {
            revert ZeroAddress();
        }
        strategies[asset] = strategy;
        emit StrategyAdded(address(asset), address(strategy));
    }

    function getStakedAssetBalance(
        IERC20 asset,
        uint256 nodeId
    ) public view returns (uint256) {
        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }
        return strategy.userUnderlyingView(address(uint160(nodeId)));
    }
}
