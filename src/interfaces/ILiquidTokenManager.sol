// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidToken} from "./ILiquidToken.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";

/// @title ILiquidTokenManager Interface
/// @notice Interface for the LiquidTokenManager contract
interface ILiquidTokenManager {
    /// @notice Initialization parameters for LiquidTokenManager
    struct Init {
        IERC20[] assets;
        TokenInfo[] tokenInfo;
        IStrategy [] strategies;
        ILiquidToken liquidToken;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
        address initialOwner;
        address strategyController;
        address priceUpdater;
    }

    /// @notice Struct to hold token information
    /// @param decimals The number of decimals for the token
    /// @param pricePerUnit The price per unit of the token
    /// @param strategy The strategy corresponding to the token
    struct TokenInfo {
        uint256 decimals;
        uint256 pricePerUnit;
    }

    /// @notice Represents an allocation of assets to a node
    struct NodeAllocation {
        uint256 nodeId;
        IERC20[] assets;
        uint256[] amounts;
    }

    /// @notice Emitted when a new token is set
    event TokenSet(
        IERC20 indexed token,
        uint256 decimals,
        uint256 initialPrice,
        address indexed strategy,
        address indexed setter
    );

    /// @notice Emitted when assets are staked to a node
    event AssetsStakedToNode(
        uint256 indexed nodeId,
        IERC20[] assets,
        uint256[] amounts,
        address indexed staker
    );

    /// @notice Emitted when assets are deposited to Eigenlayer
    event AssetsDepositedToEigenlayer(
        IERC20[] assets,
        uint256[] amounts,
        IStrategy[] strategies,
        address indexed depositor
    );

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error for invalid staking amount
    error InvalidStakingAmount(uint256 amount);

    /// @notice Error when asset already exists
    error TokenExists(address asset);

    /// @notice Error thrown when an operation is attempted on an unsupported token
    error TokenNotSupported(IERC20 token);

    /// @notice Error thrown when attempting to remove a token that is currently in use
    error TokenInUse(IERC20 token);

    /// @notice Emitted when a token is removed from the registry
    event TokenRemoved(IERC20 indexed token, address indexed remover);

    /// @notice Emitted when a token's price is updated
    event TokenPriceUpdated(IERC20 indexed token, uint256 oldPrice, uint256 newPrice, address indexed updater);

    /// @notice Error when strategy is not found
    error StrategyNotFound(address asset);

    /// @notice Error for mismatched array lengths
    error LengthMismatch(uint256 length1, uint256 length2);

    /// @notice Error for invalid node ID
    error InvalidNodeId(uint256 nodeId);

    /// @notice Error thrown when an invalid decimals value is provided
    error InvalidDecimals();

    /// @notice Error thrown when an invalid price is provided
    error InvalidPrice();

    /// @notice Initializes the LiquidTokenManager contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Adds a new token to the registry
    /// @param token The address of the token to add
    /// @param decimals The number of decimals for the token
    /// @param initialPrice The initial price for the token
    function addToken(
        IERC20 token,
        uint8 decimals,
        uint256 initialPrice,
        IStrategy strategy
    ) external;

    /// @notice Removes a token from the registry
    /// @param token The address of the token to remove
    function removeToken(IERC20 token) external;

    /// @notice Updates the price of a token
    /// @param token The address of the token to update
    /// @param newPrice The new price for the token
    function updatePrice(IERC20 token, uint256 newPrice) external;

    /// @notice Checks if a token is supported
    /// @param token The address of the token to check
    /// @return bool indicating whether the token is supported
    function tokenIsSupported(IERC20 token) external view returns (bool);

    /// @notice Converts a token amount to the unit of account
    /// @param token The address of the token to convert
    /// @param amount The amount of tokens to convert
    /// @return The converted amount in the unit of account
    function convertToUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);

    /// @notice Converts an amount in the unit of account to a token amount
    /// @param token The address of the token to convert to
    /// @param amount The amount in the unit of account to convert
    /// @return The converted amount in the specified token
    function convertFromUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);

    /// @notice Retrieves the list of supported tokens
    /// @return An array of addresses of supported tokens
    function getSupportedTokens() external view returns (IERC20[] memory);

    /// @notice Retrieves the information for a specific token
    /// @param token The address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(IERC20 token) external view returns (TokenInfo memory);

    /// @notice Returns the strategy for a given asset
    /// @param asset The asset to get the strategy for
    /// @return The IStrategy interface for the corresponding strategy
    function getTokenStrategy(IERC20 asset) external view returns (IStrategy);

    /// @notice Stakes assets to a specific node
    /// @param nodeId The ID of the node to stake to
    /// @param assets The assets to stake
    /// @param amounts The amounts of each asset to stake
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external;

    /// @notice Stakes assets to multiple nodes
    /// @param allocations The allocations of assets to nodes
    function stakeAssetsToNodes(NodeAllocation[] calldata allocations) external;

    /// @notice Gets the staked asset balance for all nodes
    /// @param asset The asset to check the balance for
    /// @return The total staked balance of the asset across all nodes
    function getStakedAssetBalance(IERC20 asset) external view returns (uint256);

    /// @notice Gets the staked asset balance for a specific node
    /// @param asset The asset to check the balance for
    /// @param nodeId The ID of the node
    /// @return The staked balance of the asset for the specific node
    function getStakedAssetBalanceNode(IERC20 asset, uint256 nodeId) external view returns (uint256);

    /// @notice Returns the StrategyManager contract
    /// @return The IStrategyManager interface
    function strategyManager() external view returns (IStrategyManager);

    /// @notice Returns the DelegationManager contract
    /// @return The IDelegationManager interface
    function delegationManager() external view returns (IDelegationManager);

    /// @notice Returns the StakerNodeCoordinator contract
    /// @return The IStakerNodeCoordinator interface
    function stakerNodeCoordinator()
        external
        view
        returns (IStakerNodeCoordinator);

    /// @notice Returns the LiquidToken contract
    /// @return The ILiquidToken interface
    function liquidToken() external view returns (ILiquidToken);
}
