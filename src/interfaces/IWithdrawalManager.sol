// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {ILiquidToken} from "./ILiquidToken.sol";
import {ILiquidTokenManager} from "./ILiquidTokenManager.sol";
import {IStakerNodeCoordinator} from "./IStakerNodeCoordinator.sol";

/// @title IWithdrawalManager Interface
/// @notice Interface for managing withdrawals between staker nodes and users
interface IWithdrawalManager {
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
    /// @param shareAmounts Array of share amounts being withdrawn per asset
    /// @param requestTime Timestamp when the withdrawal was requested
    /// @param canFulfill Whether the withdrawal can be fulfilled by the user (set to true after redemption completion)
    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] shareAmounts;
        uint256 requestTime;
        bool canFulfill;
    }

    /// @notice Represents a withdrawal request from a staker node to EigenLayer
    /// @param withdrawal The EigenLayer withdrawal struct containing delegation details
    /// @param assets Array of token addresses being withdrawn
    struct ELWithdrawalRequest {
        IDelegationManager.Withdrawal withdrawal;
        IERC20[] assets;
    }

    /// @notice Emitted when a user initiates a withdrawal request
    /// @param requestId Unique identifier for the withdrawal request
    /// @param user Address of the user requesting withdrawal
    /// @param assets Array of token addresses being withdrawn
    /// @param shareAmounts Array of share amounts being withdrawn per asset
    /// @param timestamp Block timestamp when the request was made 
    event WithdrawalInitiated(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] shareAmounts,
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

    /// @notice Error thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Error thrown when a function restricted to LiquidToken is called by another address
    /// @param sender Address that attempted the call
    error NotLiquidToken(address sender);

    /// @notice Error thrown when a function restricted to LiquidTokenManager is called by another address
    /// @param sender Address that attempted the call
    error NotLiquidTokenManager(address sender);

    /// @notice Error thrown when array lengths don't match in function parameters
    error LengthMismatch();

    /// @notice Error thrown when a withdrawal request is invalid (e.g., wrong user)
    error InvalidWithdrawalRequest();

    /// @notice Error thrown when a redemption is invalid
    error InvalidRedemption();

    /// @notice Error thrown when attempting to fulfill a withdrawal before the delay period
    error WithdrawalDelayNotMet();

    /// @notice Error thrown when withdrawal cannot be fulfilled yet (redemption not completed)
    error WithdrawalNotReadyToFulfill();

    /// @notice Error thrown when a withdrawal request ID doesn't exist
    /// @param requestId The withdrawal request ID that wasn't found
    error WithdrawalRequestNotFound(bytes32 requestId);

    /// @notice Error thrown when an EigenLayer withdrawal request doesn't exist
    /// @param withdrawalRoot The withdrawal root that wasn't found
    error ELWithdrawalRequestNotFound(bytes32 withdrawalRoot);

    /// @notice Error thrown when a redemption ID doesn't exist
    /// @param redemptionId The redemption ID that wasn't found
    error RedemptionNotFound(bytes32 redemptionId);

    /// @notice Error thrown when contract has insufficient balance for an operation
    /// @param asset The token address
    /// @param required The amount required
    /// @param available The amount available
    error InsufficientBalance(
        IERC20 asset,
        uint256 required,
        uint256 available
    );

    /// @notice Initializes the contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Creates a withdrawal request for a user when they initiate one via LiquidToken
    /// @param assets The final assets the user wants to withdraw
    /// @param amounts The withdrawal amounts per asset
    /// @param user The requesting user's address
    /// @param requestId The unique identifier for the withdrawal request
    function createWithdrawalRequest(
        IERC20[] memory assets,
        uint256[] memory amounts,
        address user,
        bytes32 requestId
    ) external;

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(bytes32 requestId) external;

    /// @notice Records the creation of a new redemption by LiquidTokenManager
    /// @param redemptionId The unique identifier of the redemption
    /// @param redemption The redemption details
    /// @param withdrawals The withdrawal structs needed to complete withdrawal on EigenLayer
    /// @param assets The assets associated with each withdrawal
    function recordRedemptionCreated(
        bytes32 redemptionId,
        ILiquidTokenManager.Redemption calldata redemption,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata assets
    ) external;

    /// @notice Records the completion of a redemption by LiquidTokenManager
    /// @param redemptionId The ID of the completed redemption
    function recordRedemptionCompleted(bytes32 redemptionId) external;

    /// @notice Gets all withdrawal request IDs for a user
    /// @param user The address of the user
    /// @return Array of withdrawal request IDs
    function getUserWithdrawalRequests(
        address user
    ) external view returns (bytes32[] memory);

    /// @notice Gets withdrawal request details for multiple request IDs
    /// @param requestIds Array of withdrawal request IDs
    /// @return Array of withdrawal request details
    function getWithdrawalRequests(
        bytes32[] calldata requestIds
    ) external view returns (WithdrawalRequest[] memory);

    /// @notice Gets EigenLayer withdrawal request details for multiple withdrawal roots
    /// @param withdrawalRoots Array of EigenLayer withdrawal roots
    /// @return Array of EigenLayer withdrawal request details
    function getELWithdrawalRequests(
        bytes32[] calldata withdrawalRoots
    ) external view returns (ELWithdrawalRequest[] memory);

    /// @notice Gets redemption details for a redemption ID
    /// @param redemptionId The ID of the redemption
    /// @return The redemption details
    function getRedemption(
        bytes32 redemptionId
    ) external view returns (ILiquidTokenManager.Redemption memory);
}