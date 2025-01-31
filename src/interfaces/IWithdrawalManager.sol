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
/// @notice Interface for the WithdrawalManager contract
interface IWithdrawalManager {
    /// @notice Initialization parameters for WithdrawalManager
    struct Init {
        address initialOwner;
        address withdrawalController;
        IDelegationManager delegationManager;
        ILiquidToken liquidToken;
        ILiquidTokenManager liquidTokenManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
    }

    /// @notice Represents withdrawal request from user
    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] shareAmounts;
        uint256 requestTime;
        bool canFulfill;
    }

    /// @notice Represents withdrawal request from staker node to EL
    struct ELWithdrawalRequest {
        IDelegationManager.Withdrawal withdrawal;
        IERC20[] assets;
    }

    /// @notice Represents a set of request ids and the withdrawal roots they depend upon
    struct Redemption {
        bytes32[] requestIds;
        bytes32[] withdrawalRoots;
    }

    /// @notice Emitted when a withdrawal is requested
    event WithdrawalInitiated(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] shareAmounts,
        uint256 timestamp
    );

    /// @notice Emitted when a withdrawal is fulfilled
    event WithdrawalFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts,
        uint256 timestamp
    );

    /// @notice Emitted when a set of withdrawals are completed on EigenLayer
    event ELWithdrawalsCompleted(bytes32 indexed requestId, bytes32[] indexed withdrawalRoots);

    /// @notice Emitted when a set of withdrawals from node undelegation are completed on EigenLayer
    event ELWithdrawalsForUndelegationCompleted(uint256 nodeId, bytes32[] indexed withdrawalRoots);

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error for zero asset amount
    error ZeroAmount();

    /// @notice Error for unauthorized access by non-LiquidToken
    error NotLiquidToken(address sender);

    /// @notice Error for unauthorized access by non-LiquidTokenManager
    error NotLiquidTokenManager(address sender);

    /// @notice Error for mismatched array lengths
    error LengthMismatch();

    /// @notice Error for invalid withdrawal request
    error InvalidWithdrawalRequest();

    /// @notice Error when withdrawal delay is not met
    error WithdrawalDelayNotMet();

    /// @notice Error when withdrawal root is not found
    error WithdrawalRootNotFound(bytes32 withdrawalRoot);

    /// @notice Error for withdrawal request not found
    error WithdrawalRequestNotFound(bytes32 requestId);

    /// @notice Error for EL withdrawal request not found
    error ELWithdrawalRequestNotFound(bytes32 withdrawalRoot);

    /// @notice Error for redemption not found
    error RedemptionNotFound(bytes32 redemptionId);

    /// @notice Error when withdrawals on EigenLayer haven't been completed
    error ELWithdrawalsNotCompleted(bytes32 requestId);

    /// @notice Error for insufficient balance
    error InsufficientBalance(
        IERC20 asset,
        uint256 required,
        uint256 available
    );

    function createWithdrawalRequest(
        IERC20[] memory assets,
        uint256[] memory amounts,
        address user,
        bytes32 requestId
    ) external;

    function recordELWithdrawalCreated(
        bytes32 withdrawalRoot,
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata assets
    ) external;

    function recordRedemptionCreated(
        bytes32 redemptionId,
        bytes32[] calldata requestIds,
        bytes32[] calldata withdrawalRoots
    ) external;

    function recordRedemptionCompleted(
        bytes32 redemptionId,
        bytes32[] calldata requestIds
    ) external;

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(bytes32 requestId) external;

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateStakerNodes(uint256[] calldata nodeIds) external;

    function completeELWithdrawalsForUndelegation(
        uint256 nodeId,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bytes32[] calldata withdrawalRoots
    ) external;

    /// @notice Returns the withdrawal requests for a user
    /// @param user The address of the user
    /// @return An array of withdrawal request IDs
    function getUserWithdrawalRequests(address user) external view returns (bytes32[] memory);


    function getWithdrawalRequests(bytes32[] calldata requestIds) external view returns (WithdrawalRequest[] memory);

    function getELWithdrawalRequests(bytes32[] calldata withdrawalRoots) external view returns (ELWithdrawalRequest[] memory);

    function getRedemption(bytes32 redemptionId) external view returns (Redemption memory);
}