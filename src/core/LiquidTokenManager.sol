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

import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

contract LiquidTokenManager is
    ILiquidTokenManager,
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
    IStakerNodeCoordinator public stakerNodeCoordinator;
    ILiquidToken public liquidToken;

    mapping(IERC20 => IStrategy) public strategies;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        Init memory init
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STRATEGY_CONTROLLER_ROLE, init.strategyController);
        _grantRole(STRATEGY_ADMIN_ROLE, init.admin);

        if (
            address(init.strategyManager) == address(0) ||
            address(init.delegationManager) == address(0) ||
            address(init.liquidToken) == address(0)
        ) {
            revert ZeroAddress();
        }

        if (init.assets.length != init.strategies.length) {
            revert LengthMismatch(init.assets.length, init.strategies.length);
        }

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        liquidToken = init.liquidToken;

        // Initialize strategies for each asset
        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            
            if (address(strategies[init.assets[i]]) != address(0)) {
                revert StrategyAssetExists(address(init.assets[i]));
            }

            strategies[init.assets[i]] = init.strategies[i];
            emit StrategyAdded(address(init.assets[i]), address(init.strategies[i]));
        }
    }

    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) public onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        _stakeAssetsToNode(nodeId, assets, amounts);
    }

    function stakeAssetsToNodes(
        NodeAllocation[] calldata allocations
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        for (uint256 i = 0; i < allocations.length; i++) {
            NodeAllocation memory allocation = allocations[i];
            _stakeAssetsToNode(
                allocation.nodeId,
                allocation.assets,
                allocation.amounts
            );
        }
    }

    function _stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256 assetsLength = assets.length;
        uint256 amountsLength = amounts.length;

        if (assetsLength != amountsLength) {
            revert LengthMismatch(assetsLength, amountsLength);
        }

        IStakerNode node = IStakerNode(
            stakerNodeCoordinator.getNodeById(nodeId)
        );
        if (address(node) == address(0)) {
            revert InvalidNodeId(nodeId);
        }

        IStrategy[] memory strategiesForNode = new IStrategy[](assetsLength);
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            if (amounts[i] == 0) {
                revert InvalidStakingAmount(amounts[i]);
            }
            IStrategy strategy = strategies[asset];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(asset));
            }
            strategiesForNode[i] = strategy;
        }

        liquidToken.transferAssets(assets, amounts);

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        for (uint256 i = 0; i < assetsLength; i++) {
            (IERC20 depositAsset, uint256 depositAmount) = _parseDeposits(
                assets[i],
                amounts[i]
            );
            depositAssets[i] = depositAsset;
            depositAmounts[i] = depositAmount;
            depositAsset.safeTransfer(address(node), depositAmount);
        }

        emit StakedAssetsToNode(nodeId, assets, amounts);

        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit DepositedToEigenlayer(
            depositAssets,
            depositAmounts,
            strategiesForNode
        );
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

    // ------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------

    function _parseDeposits(
        IERC20 asset,
        uint256 amount
    ) internal pure returns (IERC20 depositAsset, uint256 depositAmount) {
        depositAsset = asset;
        depositAmount = amount;
    }
}
