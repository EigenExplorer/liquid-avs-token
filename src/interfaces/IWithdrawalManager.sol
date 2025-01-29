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
        ILiquidToken liquidToken;
        ILiquidTokenManager liquidTokenManager;
        IStakerNodeCoordinator stakerNodeCoordinator;
    }

    /// @notice Represents a withdrawal request
    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] shareAmounts;
        uint256 requestTime;
        bool fulfilled;
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

    event WithdrawalRequested(bytes32 indexed requestId, bytes32[] indexed withdrawalRoots);

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

    /// @notice Error when withdrawal is already fulfilled
    error WithdrawalAlreadyFulfilled();

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

    function requestWithdrawal(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata shareAmounts,
        bytes32 requestId
    ) external;

    function fulfillWithdrawalEigenLayer(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bytes32 requestId
    ) external;

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawalUser(bytes32 requestId) external;

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateStakerNodes(uint256[] calldata nodeIds) external;

    /// @notice Returns the withdrawal requests for a user
    /// @param user The address of the user
    /// @return An array of withdrawal request IDs
    function getUserWithdrawalRequests(address user) external view returns (bytes32[] memory);

    /// @notice Returns the details of a withdrawal request
    /// @param requestId The ID of the withdrawal request
    /// @return The withdrawal request details
    function getWithdrawalRequest(bytes32 requestId) external view returns (WithdrawalRequest memory);
}