// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/// @title ILiquidToken Interface
/// @notice Interface for the LiquidToken contract
interface ILiquidToken is IERC20Upgradeable {
    /// @notice Initialization parameters for LiquidToken
    struct Init {
        string name;
        string symbol;
        ILiquidTokenManager liquidTokenManager;
        ITokenRegistryOracle tokenRegistryOracle;
        IWithdrawalManager withdrawalManager;
        address initialOwner;
        address pauser;
    }

    /// @notice Custom errors for price update failures
    error PriceUpdateFailed(); // Generic price update failure
    error PriceUpdateRejected(); // Update returned false
    error PricesRemainStale(); // Prices still stale after update
    error AssetPriceInvalid(address token); // Specific token has invalid price

    /// @notice Emitted when prices are updated during a deposit
    event PricesUpdatedBeforeDeposit(address indexed depositor);

    /// @notice Emitted when a price update fails during deposit
    event PriceUpdateFailedDuringDeposit(address indexed depositor);

    /// @notice Emitted when an asset is deposited
    event AssetDeposited(
        address indexed sender,
        address indexed receiver,
        IERC20Upgradeable indexed asset,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted when an asset is transferred
    event AssetTransferred(
        IERC20Upgradeable indexed asset,
        uint256 amount,
        address indexed destination,
        address indexed initiator
    );

    /// @notice Error for unsupported asset
    error UnsupportedAsset(IERC20Upgradeable asset);

    /// @notice Error for zero amount
    error ZeroAmount();

    /// @notice Error for zero shares
    error ZeroShares();

    /// @notice Error for unauthorized access by non-LiquidTokenManager
    error NotLiquidTokenManager(address sender);

    /// @notice Error for invalid funds recepient
    error InvalidReceiver(address receiver);

    /// @notice Error for unauthorized access
    error UnauthorizedAccess(address sender);

    /// @notice Error for mismatched array lengths
    error ArrayLengthMismatch();

    /// @notice Error for invalid withdrawal request
    error InvalidWithdrawalRequest();

    /// @notice Error for insufficient balance
    error InsufficientBalance(
        IERC20Upgradeable asset,
        uint256 required,
        uint256 available
    );

    /// @notice Error when contract token balance is not in sync with accounting balance
    error AssetBalanceOutOfSync(
        IERC20Upgradeable asset,
        uint256 accountingBalance,
        uint256 actualBalance
    );

    /// @notice Deposits multiple assets and mints shares
    /// @param assets The array of assets to deposit
    /// @param amounts The array of amounts to deposit for each asset
    /// @param receiver The address to receive the minted shares
    function deposit(
        IERC20Upgradeable[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external returns (uint256[] memory);

    /// @notice Allows users to initiate a withdrawal request against their shares
    /// @param assets The ERC20 assets to withdraw
    /// @param amounts The amount of tokens to withdraw for each asset
    function initiateWithdrawal(
        IERC20Upgradeable[] memory assets,
        uint256[] memory amounts
    ) external returns (bytes32);

    /// @notice Previews a withdrawal request and returns whether or not it would be successful
    /// @param assets The ERC20 assets to withdraw
    /// @param amounts The amount of tokens to withdraw for each asset
    function previewWithdrawal(
        IERC20Upgradeable[] memory assets,
        uint256[] memory amounts
    ) external view returns (bool);

    /// @notice Credits queued balances for a given set of assets
    /// @param assets The assets to credit
    /// @param amounts The credit amounts expressed in native token
    function creditQueuedAssetBalances(
        IERC20Upgradeable[] calldata assets,
        uint256[] calldata amounts
    ) external;

    /// @notice Debits queued balances for a given set of assets & burns the corresponding shares
    /// @param assets The assets to debit
    /// @param amounts The debit amounts expressed in native token
    /// @param sharesToBurn Amount of shares to burn
    function debitQueuedAssetBalances(
        IERC20Upgradeable[] calldata assets,
        uint256[] calldata amounts,
        uint256 sharesToBurn
    ) external;

    /// @notice Credits asset balances for a given set of assets
    /// @param assets The assets to debit
    /// @param amounts The credit amounts expressed in native token
    function creditAssetBalances(
        IERC20Upgradeable[] calldata assets,
        uint256[] calldata amounts
    ) external;

    /// @notice Transfers assets to the LiquidTokenManager
    /// @param assetsToRetrieve The assets to transfer
    /// @param amounts The amounts to transfer
    /// @param receiver The receiver of the funds, either `LiquidTokenManager` or `WithdrawalManager`
    function transferAssets(
        IERC20Upgradeable[] calldata assetsToRetrieve,
        uint256[] calldata amounts,
        address receiver
    ) external;

    /// @notice Calculates the number of shares for a given asset amount
    /// @param asset The asset to calculate shares for
    /// @param amount The amount of the asset
    /// @return The number of shares
    function calculateShares(
        IERC20Upgradeable asset,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Calculates the amount of an asset for a given number of shares
    /// @param asset The asset to calculate the amount for
    /// @param shares The number of shares
    /// @return The amount of the asset
    function calculateAmount(
        IERC20Upgradeable asset,
        uint256 shares
    ) external view returns (uint256);

    /// @notice Returns the total value of assets managed by the contract
    /// @return The total value of assets in the unit of account
    function totalAssets() external view returns (uint256);

    /// @notice Returns the balances of multiple assets
    /// @param assetList The list of assets to get balances for
    /// @return An array of asset balances
    function balanceAssets(
        IERC20Upgradeable[] calldata assetList
    ) external view returns (uint256[] memory);

    /// @notice Returns the queued balances of multiple assets
    /// @param assetList The list of assets to get queued balances for
    /// @return An array of queued asset balances
    function balanceQueuedAssets(
        IERC20Upgradeable[] calldata assetList
    ) external view returns (uint256[] memory);

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}