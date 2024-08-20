// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Orchestrator is 
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256("STRATEGY_CONTROLLER_ROLE");
    bytes32 public constant STRATEGY_ADMIN_ROLE = keccak256("STRATEGY_ADMIN_ROLE");

    // Contracts
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    // Mappings
    mapping(IERC20 => IStrategy) public strategies;

    // Events
    event StrategyAdded(address indexed asset, address indexed strategy);
    event StakedAssetsToNode(uint256 indexed nodeId, IERC20[] assets, uint256[] amounts);

    // Errors
    error ZeroAddress();
    error InvalidStakingAmount(uint256 amount);
    error StrategyNotFound(address asset);
    error LengthMismatch(uint256 length1, uint256 length2);

    function initialize(
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        address admin,
        address strategyController
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (address(_strategyManager) == address(0) || address(_delegationManager) == address(0) ||
            admin == address(0) || strategyController == address(0)) {
            revert ZeroAddress();
        }

        strategyManager = _strategyManager;
        delegationManager = _delegationManager;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STRATEGY_CONTROLLER_ROLE, strategyController);
        _grantRole(STRATEGY_ADMIN_ROLE, admin);
    }

    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) public onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        if (assets.length != amounts.length) {
            revert LengthMismatch(assets.length, amounts.length);
        }

        IStrategy[] memory strategiesForNode = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            if (amounts[i] == 0) {
                revert InvalidStakingAmount(amounts[i]);
            }
            IStrategy strategy = strategies[assets[i]];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(assets[i]));
            }
            strategiesForNode[i] = strategy;
            
            assets[i].safeTransferFrom(msg.sender, address(this), amounts[i]);
            assets[i].safeApprove(address(strategyManager), amounts[i]);
        }

        strategyManager.depositIntoStrategyWithSignature(assets, amounts, strategiesForNode, nodeId, abi.encodePacked(nodeId));

        emit StakedAssetsToNode(nodeId, assets, amounts);
    }

    function setStrategy(IERC20 asset, IStrategy strategy) external onlyRole(STRATEGY_ADMIN_ROLE) {
        if (address(asset) == address(0) || address(strategy) == address(0)) {
            revert ZeroAddress();
        }
        strategies[asset] = strategy;
        emit StrategyAdded(address(asset), address(strategy));
    }

    function getStakedAssetBalance(IERC20 asset, uint256 nodeId) public view returns (uint256) {
        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }
        return strategy.userUnderlyingView(address(uint160(nodeId)));
    }
}