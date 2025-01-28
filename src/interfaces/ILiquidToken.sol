// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

/// @title ILiquidToken Interface
/// @notice Interface for the LiquidToken contract
interface ILiquidToken is IERC20 {
    /// @notice Initialization parameters for LiquidToken
    struct Init {
        string name;
        string symbol;
        ILiquidTokenManager liquidTokenManager;
        address initialOwner;
        address pauser;
    }

    /// @notice Represents a withdrawal request
    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] shareAmounts;
        uint256 requestTime;
        bool fulfilled;
    }

    /// @notice Emitted when an asset is deposited
    event AssetDeposited(
        address indexed sender,
        address indexed receiver,
        IERC20 indexed asset,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted when a withdrawal is requested
    event WithdrawalRequested(
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

    /// @notice Emitted when an asset is transferred
    event AssetTransferred(
        IERC20 indexed asset,
        uint256 amount,
        address indexed destination,
        address indexed initiator
    );

    /// @notice Error for unsupported asset
    error UnsupportedAsset(IERC20 asset);

    /// @notice Error for zero amount
    error ZeroAmount();

    /// @notice Error for zero shares
    error ZeroShares();

    /// @notice Error for unauthorized access by non-LiquidTokenManager
    error NotLiquidTokenManager(address sender);

    /// @notice Error for invalid withdrawal request
    error InvalidWithdrawalRequest();

    /// @notice Error when withdrawal delay is not met
    error WithdrawalDelayNotMet();

    /// @notice Error when withdrawal is already fulfilled
    error WithdrawalAlreadyFulfilled();

    /// @notice Error for unsupported asset
    error AssetNotSupported(IERC20 asset);

    /// @notice Error for mismatched array lengths
    error ArrayLengthMismatch();

    /// @notice Error for insufficient balance
    error InsufficientBalance(
        IERC20 asset,
        uint256 required,
        uint256 available
    );

    /// @notice Error when contract token balance is not in sync with accounting balance
    error AssetBalanceOutOfSync(
        IERC20 asset,
        uint256 accountingBalance,
        uint256 actualBalance
    );

    /// @notice Deposits multiple assets and mints shares
    /// @param assets The array of assets to deposit
    /// @param amounts The array of amounts to deposit for each asset
    /// @param receiver The address to receive the minted shares
    function deposit(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external returns (uint256[] memory);


    /// @notice Allows users to request a withdrawal of their shares
    /// @param withdrawAssets The ERC20 assets to withdraw
    /// @param shareAmounts The number of shares to withdraw for each asset
    function requestWithdrawal(
        IERC20[] memory withdrawAssets,
        uint256[] memory shareAmounts
    ) external;

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(bytes32 requestId) external;

    /// @notice Transfers assets to the LiquidTokenManager
    /// @param assetsToRetrieve The assets to transfer
    /// @param amounts The amounts to transfer
    function transferAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external;

    /// @notice Credits queued balances for a given set of asset
    /// @param assets The assets to credit
    /// @param amounts The credit amounts expressed in native token
    function addQueuedAssetBalances(
        IERC20[] calldata assets,
        uint256[] calldata amounts
    ) external;

    /// @notice Calculates the number of shares for a given asset amount
    /// @param asset The asset to calculate shares for
    /// @param amount The amount of the asset
    /// @return The number of shares
    function calculateShares(
        IERC20 asset,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Calculates the amount of an asset for a given number of shares
    /// @param asset The asset to calculate the amount for
    /// @param shares The number of shares
    /// @return The amount of the asset
    function calculateAmount(
        IERC20 asset,
        uint256 shares
    ) external view returns (uint256);

    /// @notice Returns the total value of assets held by the contract
    /// @return The total value of assets
    function totalAssets() external view returns (uint256);

    /// @notice Returns the withdrawal requests for a user
    /// @param user The address of the user
    /// @return An array of withdrawal request IDs
    function getUserWithdrawalRequests(address user) external view returns (bytes32[] memory);

    /// @notice Returns the details of a withdrawal request
    /// @param requestId The ID of the withdrawal request
    /// @return The withdrawal request details
    function getWithdrawalRequest(bytes32 requestId) external view returns (WithdrawalRequest memory);

    /// @notice Returns the balances of multiple assets
    /// @param assetList The list of assets to get balances for
    /// @return An array of asset balances
    function balanceAssets(IERC20[] calldata assetList) external view returns (uint256[] memory);

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}
