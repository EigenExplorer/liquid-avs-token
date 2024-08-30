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

/// @title LiquidTokenManager
/// @notice Manages liquid tokens and their staking to EigenLayer strategies
/// @dev Implements ILiquidTokenManager and uses OpenZeppelin's upgradeable contracts
contract LiquidTokenManager is
    ILiquidTokenManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_CONTROLLER_ROLE =
        keccak256("STRATEGY_CONTROLLER_ROLE");

    /// @notice The EigenLayer StrategyManager contract
    IStrategyManager public strategyManager;
    /// @notice The EigenLayer DelegationManager contract
    IDelegationManager public delegationManager;
    /// @notice The StakerNodeCoordinator contract
    IStakerNodeCoordinator public stakerNodeCoordinator;
    /// @notice The LiquidToken contract
    ILiquidToken public liquidToken;

    /// @notice Mapping of assets to their corresponding EigenLayer strategies
    mapping(IERC20 => IStrategy) public strategies;

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param init Initialization parameters
    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(STRATEGY_CONTROLLER_ROLE, init.strategyController);

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

        liquidToken = init.liquidToken;
        stakerNodeCoordinator = init.stakerNodeCoordinator;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;

        // Initialize strategies for each asset
        for (uint256 i = 0; i < init.assets.length; i++) {
            if (
                address(init.assets[i]) == address(0) ||
                address(init.strategies[i]) == address(0)
            ) {
                revert ZeroAddress();
            }

            if (address(strategies[init.assets[i]]) != address(0)) {
                revert StrategyAssetExists(address(init.assets[i]));
            }

            strategies[init.assets[i]] = init.strategies[i];
            emit StrategySet(init.assets[i], init.strategies[i], msg.sender);
        }
    }

    /// @notice Stakes assets to a specific node
    /// @param nodeId The ID of the node to stake to
    /// @param assets Array of asset addresses to stake
    /// @param amounts Array of amounts to stake for each asset
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        _stakeAssetsToNode(nodeId, assets, amounts);
    }

    /// @notice Stakes assets to multiple nodes
    /// @param allocations Array of NodeAllocation structs containing staking information
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

    /// @notice Internal function to stake assets to a node
    /// @param nodeId The ID of the node to stake to
    /// @param assets Array of asset addresses to stake
    /// @param amounts Array of amounts to stake for each asset
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

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
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
            depositAssets[i] = assets[i];
            depositAmounts[i] = amounts[i];
            assets[i].safeTransfer(address(node), amounts[i]);
        }

        emit AssetsStakedToNode(nodeId, assets, amounts, msg.sender);

        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(
            depositAssets,
            depositAmounts,
            strategiesForNode,
            address(node)
        );
    }

    /// @notice Sets or updates the strategy for a given asset
    /// @param asset The asset token address
    /// @param strategy The strategy contract address
    function setStrategy(
        IERC20 asset,
        IStrategy strategy
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) {
        if (address(asset) == address(0) || address(strategy) == address(0)) {
            revert ZeroAddress();
        }
        strategies[asset] = strategy;
        emit StrategySet(asset, strategy, msg.sender);
    }

    /// @notice Gets the staked balance of an asset for all nodes
    /// @param asset The asset token address
    /// @return The staked balance of the asset for all nodes
    function getStakedAssetBalance(IERC20 asset) public view returns (uint256) {
        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += _getStakedAssetBalanceNode(asset, nodes[i]);
        }

        return totalBalance;
    }

    /// @notice Gets the staked balance of an asset for a specific node
    /// @param asset The asset token address
    /// @param nodeId The ID of the node
    /// @return The staked balance of the asset for the node
    function getStakedAssetBalanceNode(
        IERC20 asset,
        uint256 nodeId
    ) public view returns (uint256) {
        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        if (address(node) == address(0)) {
            revert InvalidNodeId(nodeId);
        }

        return _getStakedAssetBalanceNode(asset, node);
    }

    /// @notice Gets the staked balance of an asset for a specific node
    /// @param asset The asset token address
    /// @param node The node to get the staked balance for
    /// @return The staked balance of the asset for the node
    function _getStakedAssetBalanceNode(
        IERC20 asset,
        IStakerNode node
    ) internal view returns (uint256) {
        IStrategy strategy = strategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }
        return strategy.userUnderlyingView(address(node));
    }
}
