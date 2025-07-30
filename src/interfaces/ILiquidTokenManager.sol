// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ILSTSwapRouter} from "../interfaces/ILSTSwapRouter.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ILiquidToken} from "./ILiquidToken.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";
import {ITokenRegistryOracle} from "./ITokenRegistryOracle.sol";
import {IWithdrawalManager} from "./IWithdrawalManager.sol";

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
        IWithdrawalManager withdrawalManager;
        ILSTSwapRouter lstSwapRouter;
        address initialOwner;
        address strategyController;
        address priceUpdater;
    }

    /// @notice Supported token information
    /// @param decimals The number of decimals for the token
    /// @param pricePerUnit The price per unit of the token in the unit of account (18 decimals)
    /// @param volatilityThreshold The allowed change ratio for price update, in 1e18. Must be 0 (disabled) or >= 0.01 * 1e18 and <= 1 * 1e18
    struct TokenInfo {
        uint256 decimals;
        uint256 pricePerUnit;
        uint256 volatilityThreshold;
    }

    /// @notice Represents an allocation of assets to a node for staking
    /// @param nodeId The ID of the staker node to allocate assets to
    /// @param assets Array of token addresses to stake
    /// @param amounts Array of amounts to stake for each asset
    struct NodeAllocation {
        uint256 nodeId;
        IERC20[] assets;
        uint256[] amounts;
    }

    /// @notice Represents allocation of assets to a node for staking, including a set of swaps swap
    /// @param nodeId The ID of the staker node to allocate assets to
    /// @param assetsToSwap Array of input tokens to swap from
    /// @param amountsToSwap Array of amounts to swap
    /// @param assetsToStake Array of output tokens to receive and stake
    struct NodeAllocationWithSwap {
        uint256 nodeId;
        IERC20[] assetsToSwap;
        uint256[] amountsToSwap;
        IERC20[] assetsToStake;
    }

    /// @notice Represents an intent to make a certain amount of funds available by calling staker node withdrawals
    /// @dev Redemptions are made by the manager to:
    ///     i. settle a set of user withdrawal requests
    ///     ii. partially withdraw a set of assets from nodes
    ///     iii. undelegate nodes from Operators (and hence withdraw all assets)
    /// @param requestIds Array of request IDs associated with this redemption
    /// @param withdrawalRoots Array of withdrawal roots from EigenLayer withdrawals
    /// @param receiver Contract that will receive the withdrawn funds (`LiquidToken` or `WithdrawalManager`)
    struct Redemption {
        bytes32[] requestIds;
        bytes32[] withdrawalRoots;
        IERC20[] assets;
        uint256[] withdrawableAmounts;
        address receiver;
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
    event LSTSwapRouterUpdated(address indexed oldLsr, address indexed newLsr, address updatedBy);

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

    /// @notice Emitted when a redemption is created due to node undelegation
    /// @dev `assets` is a 1D array since each withdrawal will have only 1 corresponding asset
    event RedemptionCreatedForNodeUndelegation(
        bytes32 redemptionId,
        bytes32 requestId,
        bytes32[] withdrawalRoots,
        IDelegationManagerTypes.Withdrawal[] withdrawals,
        IERC20[] assets,
        uint256 nodeId
    );

    /// @notice Emitted when a redemption is created to settle user withdrawals
    event RedemptionCreatedForUserWithdrawals(
        bytes32 redemptionId,
        bytes32[] requestIds,
        bytes32[] withdrawalRoots,
        IDelegationManagerTypes.Withdrawal[] withdrawals,
        IERC20[][] assets,
        uint256[] nodeIds
    );

    /// @notice Emitted when a redemption is created for rebalancing
    event RedemptionCreatedForRebalancing(
        bytes32 redemptionId,
        bytes32[] requestIds,
        bytes32[] withdrawalRoots,
        IDelegationManagerTypes.Withdrawal[] withdrawals,
        IERC20[][] assets,
        uint256[] nodeIds
    );

    /// @notice Emitted when a redemption is successfuly completed
    event RedemptionCompleted(
        bytes32 indexed redemptionId,
        IERC20[] assets,
        uint256[] requestedAmounts,
        uint256[] receivedAmounts
    );

    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error for zero amount
    error ZeroAmount();

    /// @notice Error for invalid staking amount
    error InvalidStakingAmount(uint256 amount);

    /// @notice Error thrown when an operation requires more tokens than are available
    error InsufficientBalance(IERC20 asset, uint256 required, uint256 available);

    /// @notice Error thrown when funds would be sent to an invalid receiver
    error InvalidReceiver(address receiver);

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

    /// @notice Error thrown when a withdrawal root doesn't match the expected value
    error InvalidWithdrawalRoot();

    /// @notice Error thrown when redemption amounts for user withdrawal settlement are not enough up to make the withdrawal requests whole
    error RequestsDoNotSettle(address asset, uint256 expectedAmount, uint256 requestAmount);

    /// @notice Error thrown when a withdrawal is missing when attempting redemption completion
    error WithdrawalMissing(bytes32 withdrawalRoot);

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

    /// @notice Undelegates a set of staker nodes from their operators and creates a set of redemptions
    /// @dev A separate redemption is created for each node, since undelegating a node on EL queues one withdrawal per strategy
    /// @dev On completing a redemption created from undelegation, the funds are transferred to `LiquidToken`
    /// @dev Caller should index the `RedemptionCreatedForNodeUndelegation` event to have the required data for redemption completion
    /// @param nodeIds The IDs of the staker nodes
    function undelegateNodes(uint256[] calldata nodeIds) external;

    /// @notice Allows rebalancing of funds by partially withdrawing assets from nodes and creating a redemption
    /// @dev On completing the redemption, the funds are transferred to `LiquidToken`
    /// @dev Caller should index the `RedemptionCreatedForRebalancing` event to have the required data for redemption completion
    /// @dev Strategies are always withdrawn into their respective assets, they are never converted
    /// @param nodeIds The ID of the nodes to withdraw from
    /// @param assets The array of assets to withdraw for each node
    /// @param amounts The amounts for `assets`
    function withdrawNodeAssets(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata amounts
    ) external;

    /// @notice Enables a set of user withdrawal requests to be fulfillable after 14 days by the respective users
    /// @dev The caller can allocate funds from both, unstaked and staked balances in the proportion it deems fit
    /// @dev This function accepts a settlement only if it will actually allocate enough funds per token to settle ALL user withdrawal requests
    /// @dev If any part of the settlement draws from unstaked balances, funds are transferred right away from `LiquidToken` to `WithdrawalManager`
    /// @dev If any part of the settlement draws from staked balances, a redemption is created on completion of which, funds are transferred to `WithdrawalManager`
    /// @dev Caller should index the `RedemptionCreatedForUserWithdrawals` event to have the required data for redemption completion
    /// @dev The function is not concerned with actual amounts withdrawn from EL after slashing, if any
    /// @dev The caller is free to decide how much of slashing loss to pass on to users --  more allocation from unstaked balances => less slashing impact
    /// @param requestIds The request IDs of the user withdrawal requests to be fulfilled
    /// @param ltAssets The assets that will be drawn from `LiquidToken`
    /// @param ltAmounts The amounts for `ltAssets`
    /// @param nodeIds The node IDs from which funds will be withdrawn
    /// @param elAssets The array of assets to be withdrawn for a given node from EigenLayer
    /// @param elAmounts The amounts for `elAssets`
    function settleUserWithdrawals(
        bytes32[] calldata requestIds,
        IERC20[] calldata ltAssets,
        uint256[] calldata ltAmounts,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elAmounts
    ) external;

    /// @notice Completes withdrawals on EigenLayer for a given redemption and transfers funds to the `receiver` of the redemption
    /// @dev The caller must make sure every `withdrawals[i][]` aligns with the corresponding `nodeIds[i]`
    /// @dev The caller must make sure every `assets[i][j][]` aligns with the corresponding `withdrawals[i][]`
    /// @dev The burden is on the caller to keep track of (node, withdrawal, asset) pairs via corresponding events emitted during redemption creation
    /// @dev A redemption can never be partially completed, ie. if any withdrawal is missing from the input, the fn will revert
    /// @dev Fn will revert if a withdrawal that wasn't part of the redemption is provided as input
    /// @param redemptionId The ID of the redemption to complete
    /// @param nodeIds The set of all node IDs concerned with the redemption
    /// @param withdrawals The set of EL Withdrawal structs concerned with the redemption per node ID
    /// @param assets The set of assets redeemed by the corresponding EL withdrawals
    function completeRedemption(
        bytes32 redemptionId,
        uint256[] calldata nodeIds,
        IDelegationManagerTypes.Withdrawal[][] calldata withdrawals,
        IERC20[][][] calldata assets
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

    /// @notice Returns the set of strategies for a given set of assets
    /// @param assets Set of assets to get the strategies for
    /// @return IStrategy Interfaces for the corresponding set of strategies
    function getTokensStrategies(IERC20[] memory assets) external view returns (IStrategy[] memory);

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
    function lstSwapRouter() external view returns (ILSTSwapRouter);
}
