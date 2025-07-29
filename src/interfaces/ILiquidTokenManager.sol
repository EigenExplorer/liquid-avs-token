// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ILSTSwapRouter} from "../interfaces/ILSTSwapRouter.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ILiquidToken} from "./ILiquidToken.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";
import {ITokenRegistryOracle} from "./ITokenRegistryOracle.sol";

/// @title ILiquidTokenManager Interface
/// @notice Interface for the LiquidTokenManager contract
interface ILiquidTokenManager {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Initialization parameters for LiquidTokenManager
    struct Init {
        ILiquidToken liquidToken;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
        ITokenRegistryOracle tokenRegistryOracle;
        ILSTSwapRouter lstSwapRouter;
        address initialOwner;
        address strategyController;
        address priceUpdater;
    }

    /// @notice Supported token information
    /// @param decimals The number of decimals for the token
    /// @param pricePerUnit The price per unit of the token
    /// @param volatilityThreshold The allowed change ratio for price update, in 1e18. Must be 0 (disabled) or >= 0.01 * 1e18 and <= 1 * 1e18.
    struct TokenInfo {
        uint256 decimals;
        uint256 pricePerUnit;
        uint256 volatilityThreshold;
    }

    /// @notice Represents an allocation of assets to a node
    struct NodeAllocation {
        uint256 nodeId;
        IERC20[] assets;
        uint256[] amounts;
    }

    /// @notice Represents an allocation of assets to a node with swap
    struct NodeAllocationWithSwap {
        uint256 nodeId;
        IERC20[] assetsToSwap;
        uint256[] amountsToSwap;
        IERC20[] assetsToStake;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a new token is set
    event TokenAdded(
        IERC20 indexed token,
        uint256 decimals,
        uint256 initialPrice,
        uint256 volatilityThreshold,
        address indexed strategy,
        address indexed setter
    );

    /// @notice Emitted when a token's price is updated
    event TokenPriceUpdated(IERC20 indexed token, uint256 oldPrice, uint256 newPrice, address indexed updater);

    /// @notice Emitted when the volatility threshold for an asset is updated
    event VolatilityThresholdUpdated(
        IERC20 indexed asset,
        uint256 oldThreshold,
        uint256 newThreshold,
        address indexed updatedBy
    );

    /// @notice Emitted when a price update fails due to change exceeding the volatility threshold
    event VolatilityCheckFailed(IERC20 indexed token, uint256 oldPrice, uint256 newPrice, uint256 changeRatio);

    /// @notice Emitted when assets are staked to a node
    event AssetsStakedToNode(uint256 indexed nodeId, IERC20[] assets, uint256[] amounts, address indexed staker);

    /// @notice Emitted when assets are deposited to Eigenlayer
    event AssetsDepositedToEigenlayer(
        IERC20[] assets,
        uint256[] amounts,
        IStrategy[] strategies,
        address indexed depositor
    );

    /// @notice Emitted when a staker node is delegated to an operator
    event NodeDelegated(uint256 nodeId, address indexed operator);

    /// @notice Emitted when a staker node is undelegated from its current operator
    event NodeUndelegated(uint256 nodeId, address indexed operator);

    /// @notice Emitted when a token is removed from the registry
    event TokenRemoved(IERC20 indexed token, address indexed remover);

    /// @notice Emitted when LSTSwapRouter contract is updated
    event LSTSwapRouterUpdated(address indexed oldLSR, address indexed newLSR, address updatedBy);

    /// @notice Emitted when assets are swapped and staked to a node
    event AssetsSwappedAndStakedToNode(
        uint256 indexed nodeId,
        IERC20[] assetsSwapped,
        uint256[] amountsSwapped,
        IERC20[] assetsStaked,
        uint256[] amountsStaked,
        address indexed initiator
    );

    /// @notice Emitted when a swap is executed
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 indexed nodeId
    );

    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================

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

    /// @notice Error thrown when price source configuration is invalid
    error InvalidPriceSource();

    /// @notice Error when token price fetch fails during token addition
    error TokenPriceFetchFailed();

    /// @notice Error when strategy is not found
    error StrategyNotFound(address asset);

    /// @notice Error when token is not found for a strategy
    error TokenForStrategyNotFound(address strategy);

    /// @notice Error for mismatched array lengths
    error LengthMismatch(uint256 length1, uint256 length2);

    /// @notice Error for invalid node ID
    error InvalidNodeId(uint256 nodeId);

    /// @notice Error thrown when an invalid decimals value is provided
    error InvalidDecimals();

    /// @notice Error thrown when an address is not a valid contract
    error NotAContract();

    /// @notice Error thrown when a strategy is already assigned to another token
    error StrategyAlreadyAssigned(address strategy, address existingToken);

    /// @notice Error thrown when an invalid price is provided
    error InvalidPrice();

    /// @notice Error thrown when an invalid volatility threshold is provided
    error InvalidThreshold();

    /// @notice Error thrown when a price update fails due to change exceeding the volatility threshold
    error VolatilityThresholdHit(IERC20 token, uint256 changeRatio);

    /// @notice Error thrown when ETH is used as tokenIn or tokenOut (only allowed as bridge asset)
    error ETHNotSupportedAsDirectToken(address token);

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Initializes the LiquidTokenManager contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Updates the LSTSwapRouter contract address
    /// @param newLSTSwapRouter The new LSR contract address
    function updateLSTSwapRouter(address newLSTSwapRouter) external;

    /// @notice Adds a new token to the registry and configures its price sources
    /// @param token Address of the token to add
    /// @param decimals Number of decimals for the token
    /// @param volatilityThreshold Volatility threshold for price updates
    /// @param strategy Strategy corresponding to the token
    /// @param primaryType Source type (1=Chainlink, 2=Curve, 3=Protocol, 0=native tokens handled differently)
    /// @param primarySource Primary source address
    /// @param needsArg Whether fallback fn needs args
    /// @param fallbackSource Address of the fallback source contract
    /// @param fallbackFn Function selector for fallback
    function addToken(
        IERC20 token,
        uint8 decimals,
        uint256 volatilityThreshold,
        IStrategy strategy,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn
    ) external;

    /// @notice Removes a token from the registry
    /// @param token Address of the token to remove
    function removeToken(IERC20 token) external;

    /// @notice Updates the price of a token
    /// @param token Address of the token to update
    /// @param newPrice New price for the token
    function updatePrice(IERC20 token, uint256 newPrice) external;

    /// @notice Updates the volatility threshold for price updates
    /// @param asset The asset to update threshold for
    /// @param newThreshold The new volatility threshold (in 1e18 precision)
    function setVolatilityThreshold(IERC20 asset, uint256 newThreshold) external;

    /// @notice Delegate a set of staker nodes to a corresponding set of operators
    /// @param nodeIds The IDs of the staker nodes
    /// @param operators The addresses of the operators
    /// @param approverSignatureAndExpiries The signatures authorizing the delegations
    /// @param approverSalts The salts used in the signatures
    function delegateNodes(
        uint256[] calldata nodeIds,
        address[] calldata operators,
        ISignatureUtilsMixinTypes.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) external;

    /// @notice Stakes assets to a specific node
    /// @param nodeId The ID of the node to stake to
    /// @param assets Array of asset addresses to stake
    /// @param amounts Array of amounts to stake for each asset
    function stakeAssetsToNode(uint256 nodeId, IERC20[] memory assets, uint256[] memory amounts) external;

    /// @notice Stakes assets to multiple nodes
    /// @param allocations Array of NodeAllocation structs containing staking information
    function stakeAssetsToNodes(NodeAllocation[] calldata allocations) external;

    /// @notice Swaps multiple assets and stakes them to multiple nodes
    /// @param allocationsWithSwaps Array of node allocations with swap instructions
    function swapAndStakeAssetsToNodes(NodeAllocationWithSwap[] calldata allocationsWithSwaps) external;

    /// @notice Swaps assets and stakes them to a single node
    /// @param nodeId The node ID to stake to
    /// @param assetsToSwap Array of input tokens to swap from
    /// @param amountsToSwap Array of amounts to swap
    /// @param assetsToStake Array of output tokens to receive and stake
    function swapAndStakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assetsToSwap,
        uint256[] memory amountsToSwap,
        IERC20[] memory assetsToStake
    ) external;

    /// @notice Retrieves the list of supported tokens
    /// @return An array of addresses of supported tokens
    function getSupportedTokens() external view returns (IERC20[] memory);

    /// @notice Retrieves the information for a specific token
    /// @param token Address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(IERC20 token) external view returns (TokenInfo memory);

    /// @notice Returns the strategy for a given asset
    /// @param asset Asset to get the strategy for
    /// @return IStrategy Interface for the corresponding strategy
    function getTokenStrategy(IERC20 asset) external view returns (IStrategy);

    /// @notice Returns the token for a given strategy
    /// @param strategy Strategy to get the token for
    /// @return IERC20 Interface for the corresponding token
    function getStrategyToken(IStrategy strategy) external view returns (IERC20);

    /// @notice Gets the staked deposits balance of an asset for all nodes
    /// @dev This corresponds to the asset value of `depositShares` which does not factor in any slashing
    /// @param asset The asset to check the balance for
    /// @return The total staked balance of the asset across all nodes
    function getDepositAssetBalance(IERC20 asset) external view returns (uint256);

    /// @notice Gets the staked deposits balance of an asset for a specific node
    /// @dev This corresponds to the asset value of `depositShares` which does not factor in any slashing
    /// @param asset The asset to check the balance for
    /// @param nodeId The ID of the node
    /// @return The staked balance of the asset for the specific node
    function getDepositAssetBalanceNode(IERC20 asset, uint256 nodeId) external view returns (uint256);

    /// @notice Gets the withdrawable balance of an asset for all nodes
    /// @dev This corresponds to the asset value of `withdrawableShares` which is `depositShares` minus slashing if any
    /// @param asset The asset token address
    function getWithdrawableAssetBalance(IERC20 asset) external view returns (uint256);

    /// @notice Gets the withdrawable balance of an asset for a specific node
    /// @dev This corresponds to the asset value of `withdrawableShares` which is `depositShares` minus slashing if any
    /// @param asset The asset token address
    /// @param nodeId The ID of the node
    function getWithdrawableAssetBalanceNode(IERC20 asset, uint256 nodeId) external view returns (uint256);

    /// @notice Checks if a token is supported
    /// @param token Address of the token to check
    /// @return bool indicating whether the token is supported
    function tokenIsSupported(IERC20 token) external view returns (bool);

    /// @notice Converts a token amount to the unit of account
    /// @param token Address of the token to convert
    /// @param amount Amount of tokens to convert
    /// @return The converted amount in the unit of account
    function convertToUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);

    /// @notice Converts an amount in the unit of account to a token amount
    /// @param token Address of the token to convert to
    /// @param amount Amount in the unit of account to convert
    /// @return The converted amount in the specified token
    function convertFromUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);

    /// @notice Check if a strategy is supported
    /// @param strategy The strategy address
    /// @return True if the strategy is supported
    function isStrategySupported(IStrategy strategy) external view returns (bool);

    /// @notice Returns the token registry oracle contract
    /// @return The ITokenRegistryOracle interface
    function tokenRegistryOracle() external view returns (ITokenRegistryOracle);

    /// @notice Returns the StrategyManager contract
    /// @return The IStrategyManager interface
    function strategyManager() external view returns (IStrategyManager);

    /// @notice Returns the DelegationManager contract
    /// @return The IDelegationManager interface
    function delegationManager() external view returns (IDelegationManager);

    /// @notice Returns the StakerNodeCoordinator contract
    /// @return The IStakerNodeCoordinator interface
    function stakerNodeCoordinator() external view returns (IStakerNodeCoordinator);

    /// @notice Returns the LiquidToken contract
    /// @return The ILiquidToken interface
    function liquidToken() external view returns (ILiquidToken);

    /// @notice Returns the LSTSwapRouter contract
    /// @return The ILSTSwapRouter interface
    function LSTSwapRouter() external view returns (ILSTSwapRouter);
}