// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidToken} from "./ILiquidToken.sol";
import {ILiquidTokenManager} from "./ILiquidTokenManager.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";

/// @title IWithdrawalManager Interface
/// @notice Interface for managing withdrawals between staker nodes and users
interface IWithdrawalManager {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Initialization parameters for WithdrawalManager
    /// @param initialOwner Address that will be granted DEFAULT_ADMIN_ROLE
    /// @param delegationManager The EigenLayer DelegationManager contract
    /// @param liquidToken The LiquidToken contract
    /// @param liquidTokenManager The LiquidTokenManager contract
    /// @param stakerNodeCoordinator The StakerNodeCoordinator contract
    struct Init {
        address initialOwner;
        IDelegationManager delegationManager;
        ILiquidToken liquidToken;
        ILiquidTokenManager liquidTokenManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
    }

    /// @notice Represents a user's withdrawal request
    /// @param user Address of the user requesting withdrawal
    /// @param assets Array of token addresses being withdrawn
    /// @param requestedAmounts Array of amounts being withdrawn per asset (in the unit of the asset)
    /// @param withdrawableAmounts Array of amounts withdrawable per asset after any slashing (in the unit of the asset)
    /// @param sharesDeposited The LAT shares deposited by the user, to be burned on withdrawal fulfilment
    /// @param requestTime Timestamp when the withdrawal was requested
    /// @param canFulfill Whether the withdrawal can be fulfilled by the user (set to true after redemption completion)
    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] requestedAmounts;
        uint256[] withdrawableAmounts;
        uint256 sharesDeposited;
        uint256 requestTime;
        bool canFulfill;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a user initiates a withdrawal request
    /// @param requestId Unique identifier for the withdrawal request
    /// @param user Address of the user requesting withdrawal
    /// @param assets Array of token addresses being withdrawn
    /// @param amounts Array of amounts being withdrawn per asset
    /// @param sharesDeposited The LAT shares deposited by the user, to be burned on withdrawal fulfilment
    /// @param timestamp Block timestamp when the request was made
    event WithdrawalInitiated(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts,
        uint256 sharesDeposited,
        uint256 timestamp
    );

    /// @notice Emitted when a user's withdrawal request is fulfilled
    /// @param requestId Unique identifier for the withdrawal request
    /// @param user Address of the user whose withdrawal was fulfilled
    /// @param assets Array of token addresses that were withdrawn
    /// @param amounts Array of token amounts that were withdrawn
    /// @param timestamp Block timestamp when the fulfillment occurred
    event WithdrawalFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts,
        uint256 timestamp
    );

    /// @notice Emitted when a user is slashed and the slashing is applied to the corresponding withdrawable amount on their withdrawal request
    /// @param requestId Unique identifier for the withdrawal request
    /// @param user Address of the user whose withdrawal was fulfilled
    /// @param asset The ERC20 token that was slashed
    /// @param originalAmount The original withdrawal amount requested by the user on creating the withdrawal request
    /// @param withdrawableAmount The final withdrawable amount after slashing
    event UserSlashed(
        bytes32 indexed requestId,
        address indexed user,
        IERC20 indexed asset,
        uint256 originalAmount,
        uint256 withdrawableAmount
    );

    /// @notice Emitted when the withdrawal delay is updated
    /// @param oldDelay Previous withdrawal delay value
    /// @param newDelay Newly updated withdrawal delay value
    event WithdrawalDelayUpdated(uint256 oldDelay, uint256 newDelay);

    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================

    /// @notice Error thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Error for zero amount
    error ZeroAmount();

    /// @notice Error thrown when a function restricted to LiquidToken is called by another address
    /// @param sender Address that attempted the call
    error NotLiquidToken(address sender);

    /// @notice Error thrown when a function restricted to LiquidTokenManager is called by another address
    /// @param sender Address that attempted the call
    error NotLiquidTokenManager(address sender);

    /// @notice Error thrown when array lengths don't match in function parameters
    error LengthMismatch();

    /// @notice Error thrown when a withdrawal request is invalid
    error InvalidWithdrawalRequest();

    /// @notice Error for unauthorized access
    error UnauthorizedAccess(address sender);

    /// @notice Error thrown when a redemption is invalid
    error InvalidRedemption();

    /// @notice Error thrown when attempting to fulfill a withdrawal before the delay period
    error WithdrawalDelayNotMet();

    /// @notice Error thrown when withdrawal cannot be fulfilled yet (redemption not completed)
    error WithdrawalNotReadyToFulfill();

    /// @notice Error when withdrawal delay value was attempted with an invalid delay value
    error InvalidWithdrawalDelay(uint256 delay);

    /// @notice Error thrown when a withdrawal request ID doesn't exist
    /// @param requestId The withdrawal request ID that wasn't found
    error WithdrawalRequestNotFound(bytes32 requestId);

    /// @notice Error thrown when a redemption ID doesn't exist
    /// @param redemptionId The redemption ID that wasn't found
    error RedemptionNotFound(bytes32 redemptionId);

    /// @notice Error thrown when contract has insufficient balance for an operation
    /// @param asset The token address
    /// @param required The amount required
    /// @param available The amount available
    error InsufficientBalance(IERC20 asset, uint256 required, uint256 available);

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Initializes the contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Creates a withdrawal request for a user when they initate one via `LiquidToken`
    /// @param assets The final assets the the user wants to end up with
    /// @param amounts The withdrawal amounts per asset
    /// @param sharesDeposited The LAT shares deposited by the user, to be burned on withdrawal fulfilment
    /// @param user The requesting user's address
    /// @param requestId The unique identifier of the withdrawal request
    function createWithdrawalRequest(
        IERC20[] memory assets,
        uint256[] memory amounts,
        uint256 sharesDeposited,
        address user,
        bytes32 requestId
    ) external;

    /// @notice Allows users to fulfill a withdrawal request after the delay period and receive all corresponding funds
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(bytes32 requestId) external;

    /// @notice Called by `LiquidTokenManger` when a new redemption is created
    /// @param redemptionId The unique identifier of the redemption
    /// @param redemption The details of the redemption
    function recordRedemptionCreated(bytes32 redemptionId, ILiquidTokenManager.Redemption calldata redemption) external;

    /// @notice Called by `LiquidTokenManger` when a redemption is completed
    /// @dev If there was any slashing during the withdrawal queue period, its accounting is handled here
    /// @param redemptionId The ID of the redemption
    /// @param receivedAssets The set of assets that received from all EL withdrawals
    /// @param receivedAmounts Total amounts per for `receivedAssets` (after any slashing)
    function recordRedemptionCompleted(
        bytes32 redemptionId,
        IERC20[] calldata receivedAssets,
        uint256[] calldata receivedAmounts
    ) external returns (uint256[] memory);

    /// @notice Updates the withdrawal delay period
    /// @param newDelay The new withdrawal delay in seconds
    function setWithdrawalDelay(uint256 newDelay) external;

    /// @notice Returns all withdrawal request IDs for a given user
    /// @param user The address of the user
    function getUserWithdrawalRequests(address user) external view returns (bytes32[] memory);

    /// @notice Returns all withdrawal request details for a set of request IDs
    /// @param requestIds The IDs of the withdrawal requests
    function getWithdrawalRequests(bytes32[] calldata requestIds) external view returns (WithdrawalRequest[] memory);

    /// @notice Returns all redemption details for a given redemption ID
    /// @param redemptionId The ID of the redemption
    function getRedemption(bytes32 redemptionId) external view returns (ILiquidTokenManager.Redemption memory);
}
