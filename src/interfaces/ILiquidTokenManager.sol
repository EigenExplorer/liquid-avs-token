// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";

import {ILiquidToken} from "./ILiquidToken.sol";
import {IWithdrawalManager} from "./IWithdrawalManager.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";
import {ITokenRegistryOracle} from "./ITokenRegistryOracle.sol";

/// @title ILiquidTokenManager Interface
/// @notice Interface for the LiquidTokenManager contract
interface ILiquidTokenManager {
    /// @notice Initialization parameters for LiquidTokenManager
    /// @param liquidToken The LiquidToken contract address
    /// @param strategyManager The EigenLayer StrategyManager contract address
    /// @param delegationManager The EigenLayer DelegationManager contract address
    /// @param stakerNodeCoordinator The StakerNodeCoordinator contract address
    /// @param tokenRegistryOracle The TokenRegistryOracle contract address
    /// @param withdrawalManager The WithdrawalManager contract address
    /// @param initialOwner The address that will be granted DEFAULT_ADMIN_ROLE
    /// @param strategyController The address that will be granted STRATEGY_CONTROLLER_ROLE
    /// @param priceUpdater The address that will be granted PRICE_UPDATER_ROLE
    struct Init {
        ILiquidToken liquidToken;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
        ITokenRegistryOracle tokenRegistryOracle;
        IWithdrawalManager withdrawalManager;
        address initialOwner;
        address strategyController;
        address priceUpdater;
    }

    /// @notice Struct to hold token information
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

    /// @notice Represents an intent to make a certain amount of funds available by calling staker node withdrawals
    /// @dev Redemptions are made by the manager to:
    ///     i. settle a set of user withdrawal requests
    ///     ii. partially withdraw a set of assets from nodes
    ///     iii. undelegate nodes from Operators (and hence withdraw all assets)
    /// @param requestIds Array of request IDs associated with this redemption
    /// @param withdrawalRoots Array of withdrawal roots from EigenLayer withdrawals
    /// @param receiver Address that will receive the withdrawn funds
    struct Redemption {
        bytes32[] requestIds;
        bytes32[] withdrawalRoots;
        address receiver;
    }

    /// @notice Emitted when a new token is set
    event TokenAdded(
        IERC20 indexed token,
        uint256 decimals,
        uint256 initialPrice,
        uint256 volatilityThreshold,
        address indexed strategy,
        address indexed setter
    );

    /// @notice Emitted when assets are staked to a specific node
    /// @param nodeId ID of the node receiving the stake
    /// @param assets Array of token addresses being staked
    /// @param amounts Array of amounts being staked
    /// @param staker Address initiating the stake action
    event AssetsStakedToNode(
        uint256 indexed nodeId,
        IERC20[] assets,
        uint256[] amounts,
        address indexed staker
    );

    /// @notice Emitted when assets are deposited to EigenLayer strategies
    /// @param assets Array of token addresses being deposited
    /// @param amounts Array of amounts being deposited
    /// @param strategies Array of strategies receiving the deposits
    /// @param depositor Address of the staker node making the deposit
    event AssetsDepositedToEigenlayer(
        IERC20[] assets,
        uint256[] amounts,
        IStrategy[] strategies,
        address indexed depositor
    );

    /// @notice Emitted when a staker node is delegated to an operator
    /// @param nodeId ID of the node being delegated
    /// @param operator Address of the operator receiving delegation
    event NodeDelegated(uint256 nodeId, address indexed operator);

    /// @notice Emitted when a staker node is undelegated from its current operator
    /// @param nodeId ID of the node being undelegated
    /// @param operator Address of the operator losing delegation
    event NodeUndelegated(uint256 nodeId, address indexed operator);

    /// @notice Emitted when a redemption is created due to node undelegation
    /// @param redemptionId Unique identifier for the redemption
    /// @param requestId ID of the withdrawal request
    /// @param withdrawalRoots Array of EL withdrawal roots
    /// @param withdrawals Array of EL Withdrawal structs (required for completing withdrawal on EL)
    /// @param assets Array of assets redeemed against corresponding withdrawals (required for completing withdrawal on EL)
    /// @param nodeId ID of the node being undelegated
    event RedemptionCreatedForNodeUndelegation(
        bytes32 redemptionId,
        bytes32 requestId,
        bytes32[] withdrawalRoots,
        IDelegationManagerTypes.Withdrawal[] withdrawals,
        IERC20[][] assets,
        uint256 nodeId
    );

    /// @notice Emitted when a redemption is created to settle user withdrawals
    /// @param redemptionId Unique identifier for the redemption
    /// @param requestIds Array of user withdrawal request IDs
    /// @param withdrawalRoots Array of EL withdrawal roots
    /// @param withdrawals Array of EL Withdrawal structs, required for completing withdrawal on EL
    /// @param assets Array of assets redeemed against corresponding withdrawals (required for completing withdrawal on EL)
    /// @param nodeIds Array of node IDs involved in the withdrawal
    event RedemptionCreatedForUserWithdrawals(
        bytes32 redemptionId,
        bytes32[] requestIds,
        bytes32[] withdrawalRoots,
        IDelegationManagerTypes.Withdrawal[] withdrawals,
        IERC20[][] assets,
        uint256[] nodeIds
    );

    /// @notice Emitted when a redemption is created for rebalancing
    /// @param redemptionId Unique identifier for the redemption
    /// @param requestIds Array of request IDs
    /// @param withdrawalRoots Array of EL withdrawal roots
    /// @param withdrawals Array of EL Withdrawal structs, required for completing withdrawal on EL
    /// @param assets Array of assets redeemed against corresponding withdrawals (required for completing withdrawal on EL)
    /// @param nodeIds Array of node IDs involved in the rebalancing
    event RedemptionCreatedForRebalancing(
        bytes32 redemptionId,
        bytes32[] requestIds,
        bytes32[] withdrawalRoots,
        IDelegationManagerTypes.Withdrawal[] withdrawals,
        IERC20[][] assets,
        uint256[] nodeIds
    );

    /// @notice Emitted when a redemption is successfuly completed
    /// @param redemptionId Unique identifier of the completed redemption
    /// @param assets Array of token addresses involved in the redemption
    /// @param requestedAmounts Array of originally requested share amounts for each asset
    /// @param receivedAmounts Array of actually received share amounts for each asset after any slashing
    event RedemptionCompleted(
        bytes32 indexed redemptionId,
        IERC20[] assets,
        uint256[] requestedAmounts,
        uint256[] receivedAmounts
    );

    /// @notice Emitted when a token is removed from the system
    /// @param token Address of the removed token
    /// @param remover Address that executed the removal
    event TokenRemoved(IERC20 indexed token, address indexed remover);

    /// @notice Emitted when a token's price is updated
    /// @param token Address of the token
    /// @param oldPrice Previous price in unit of account
    /// @param newPrice New price in unit of account
    /// @param updater Address that updated the price
    event TokenPriceUpdated(
        IERC20 indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        address indexed updater
    );

    /// @notice Emitted when a token's volatility threshold is updated
    /// @param asset Address of the token
    /// @param oldThreshold Previous volatility threshold
    /// @param newThreshold New volatility threshold
    /// @param updatedBy Address that updated the threshold
    event VolatilityThresholdUpdated(
        IERC20 indexed asset,
        uint256 oldThreshold,
        uint256 newThreshold,
        address indexed updatedBy
    );

    /// @notice Emitted when a price update fails the volatility check
    /// @param token Address of the token
    /// @param oldPrice Previous price in unit of account
    /// @param newPrice Attempted new price in unit of account
    /// @param changeRatio The calculated change ratio that exceeded the threshold
    event VolatilityCheckFailed(
        IERC20 indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 changeRatio
    );

    /// @notice Error thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Error thrown when an invalid (zero) staking amount is provided
    /// @param amount The invalid amount that was provided
    error InvalidStakingAmount(uint256 amount);

    /// @notice Error thrown when an operation requires more tokens than are available
    /// @param asset The token address
    /// @param required The amount required
    /// @param available The amount available
    error InsufficientBalance(
        IERC20 asset,
        uint256 required,
        uint256 available
    );

    /// @notice Error thrown when attempting to add a token that already exists
    /// @param asset Address of the existing token
    error TokenExists(address asset);

    /// @notice Error thrown when an operation is attempted on an unsupported token
    /// @param token Address of the unsupported token
    error TokenNotSupported(IERC20 token);

    /// @notice Error thrown when attempting to remove a token that is currently in use
    /// @param token Address of the token in use
    error TokenInUse(IERC20 token);

    /// @notice Error thrown when price source configuration is invalid
    error InvalidPriceSource();

    /// @notice Error thrown when a strategy is not found for a given asset
    /// @param asset Address of the asset without a strategy
    error StrategyNotFound(address asset);

    /// @notice Error thrown when array lengths don't match in function parameters
    /// @param length1 Length of the first array
    /// @param length2 Length of the second array
    error LengthMismatch(uint256 length1, uint256 length2);

    /// @notice Error thrown when an invalid node ID is provided
    /// @param nodeId The invalid node ID
    error InvalidNodeId(uint256 nodeId);

    /// @notice Error thrown when invalid token decimals are provided
    error InvalidDecimals();

    /// @notice Error thrown when an invalid price is provided (e.g., zero)
    error InvalidPrice();

    /// @notice Error thrown when an invalid volatility threshold is provided
    error InvalidThreshold();

    /// @notice Error thrown when a withdrawal root doesn't match the expected value
    error InvalidWithdrawalRoot();

    /// @notice Error thrown when funds would be sent to an invalid receiver
    /// @param receiver The invalid receiver address
    error InvalidReceiver(address receiver);

    /// @notice Error thrown when attempting to stake assets to a node that is not delegated
    error NodeIsNotDelegated();

    /// @notice Error thrown when a redemption's amounts don't match the withdrawal requests
    /// @param asset The token address
    /// @param expectedAmount The amount expected
    /// @param requestAmount The amount requested
    error RequestsDoNotSettle(
        address asset,
        uint256 expectedAmount,
        uint256 requestAmount
    );

    /// @notice Error thrown when a required withdrawal root is missing during redemption completion
    /// @param withdrawalRoot The missing withdrawal root
    error WithdrawalRootMissing(bytes32 withdrawalRoot);

    /// @notice Error thrown when a price update exceeds the volatility threshold
    /// @param token The token address
    /// @param changeRatio The change ratio that exceeded the threshold
    error VolatilityThresholdHit(IERC20 token, uint256 changeRatio);

    /// @notice Initializes the LiquidTokenManager contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Adds a new token to the registry and configures its price sources
    /// @param token Address of the token to add
    /// @param decimals Number of decimals for the token
    /// @param volatilityThreshold Volatility threshold for price updates
    /// @param strategy Strategy corresponding to the token
    /// @param primaryType Source type (1=Chainlink, 2=Curve, 3=BTC-chained, 4=Protocol)
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
    function convertToUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Converts an amount in the unit of account to a token amount
    /// @param token The address of the token to convert to
    /// @param amount The amount in the unit of account to convert
    /// @return The converted amount in the specified token
    function convertFromUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Retrieves the list of supported tokens
    /// @return An array of addresses of supported tokens
    function getSupportedTokens() external view returns (IERC20[] memory);

    /// @notice Retrieves the information for a specific token
    /// @param token The address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(
        IERC20 token
    ) external view returns (TokenInfo memory);

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

    /// @notice Delegate a set of staker nodes to a corresponding set of operators
    /// @param nodeIds The IDs of the staker nodes
    /// @param operators The addresses of the operators
    /// @param approverSignatureAndExpiries The signatures authorizing the delegations
    /// @param approverSalts The salts used in the signatures
    function delegateNodes(
        uint256[] memory nodeIds,
        address[] memory operators,
        ISignatureUtilsMixinTypes.SignatureWithExpiry[]
            calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) external;

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateNodes(uint256[] calldata nodeIds) external;

    /// @notice Gets the staked asset balance for all nodes
    /// @param asset The asset to check the balance for
    /// @return The total staked balance of the asset across all nodes
    function getStakedAssetBalance(
        IERC20 asset
    ) external view returns (uint256);

    /// @notice Gets the staked asset balance for a specific node
    /// @param asset The asset to check the balance for
    /// @param nodeId The ID of the node
    /// @return The staked balance of the asset for the specific node
    function getStakedAssetBalanceNode(
        IERC20 asset,
        uint256 nodeId
    ) external view returns (uint256);

    /// @notice Updates the volatility threshold for price updates
    /// @param asset The asset to update threshold for
    /// @param newThreshold The new volatility threshold (in 1e18 precision)
    function setVolatilityThreshold(
        IERC20 asset,
        uint256 newThreshold
    ) external;

    /// @notice Allows rebalancing of funds by partially withdrawing assets from nodes and creating a redemption
    /// @dev On completing the redemption, the funds are transferred to `LiquidToken`
    /// @dev Caller should index the `RedemptionCreatedForRebalancing` event to properly complete the redemption
    /// @dev Strategies are always withdrawn into their respective assets, they are never converted
    /// @param nodeIds The ID of the nodes to withdraw from
    /// @param assets The array of assets to withdraw for each node
    /// @param shares The array of shares to withdraw for each asset
    function withdrawNodeAssets(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata shares
    ) external;

    /// @notice Enables settlement of a set withdrawal requests by directing funds from `LiquidToken` and staker nodes into `WithdrawalManager`
    /// @param requestIds The request IDs of the user withdrawal requests to be fulfilled
    /// @param ltAssets The assets that will be drawn from `LiquidToken`
    /// @param ltAmounts The amounts for `ltAssets`
    /// @param nodeIds The node IDs from which funds will be withdrawn
    /// @param elAssets The array of assets to be withdrawn for a given node
    /// @param elShares The array of shares to be withdrawn for the corresponding array of `elAssets`
    function settleUserWithdrawals(
        bytes32[] calldata requestIds,
        IERC20[] calldata ltAssets,
        uint256[] calldata ltAmounts,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elShares
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

    /// @notice Returns the LiquidToken contract
    /// @return The ILiquidToken interface
    function liquidToken() external view returns (ILiquidToken);

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

    /// @notice Returns the TokenRegistryOracle contract
    /// @return The ITokenRegistryOracle interface
    function tokenRegistryOracle() external view returns (ITokenRegistryOracle);

    /// @notice Returns the WithdrawalManager contract
    /// @return The IWithdrawalManager interface
    function withdrawalManager() external view returns (IWithdrawalManager);
}
