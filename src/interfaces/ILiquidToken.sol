// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/// @title ILiquidToken Interface
/// @notice Interface for the LiquidToken contract
interface ILiquidToken {
    // ============================================================================
    // STRUCTS
    // ============================================================================

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

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when prices are updated during a deposit
    event PricesUpdatedBeforeDeposit(address indexed depositor);

    /// @notice Emitted when an asset is deposited
    event AssetDeposited(
        address indexed sender,
        address indexed receiver,
        IERC20 indexed asset,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted when an asset is transferred
    event AssetTransferred(
        IERC20 indexed asset,
        uint256 amount,
        address indexed destination,
        address indexed initiator
    );

    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================

    /// @notice Error for unsupported asset
    error UnsupportedAsset(IERC20 asset);

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error for zero amount
    error ZeroAmount();

    /// @notice Error for zero shares
    error ZeroShares();

    /// @notice Error for unauthorized access by non-LiquidTokenManager
    error NotLiquidTokenManager(address sender);

    /// @notice Error for unauthorized access
    error UnauthorizedAccess(address sender);

    /// @notice Error for mismatched array lengths
    error ArrayLengthMismatch();

    /// @notice Error for insufficient balance
    error InsufficientBalance(IERC20 asset, uint256 required, uint256 available);

    /// @notice Error when contract token balance is not in sync with accounting balance
    error AssetBalanceOutOfSync(IERC20 asset, uint256 accountingBalance, uint256 actualBalance);

    /// @notice Generic price update failure
    error PriceUpdateFailed();

    /// @notice Price update returned false
    error PriceUpdateRejected();

    /// @notice Prices still stale after update
    error PricesRemainStale();

    /// @notice Specific token has invalid price
    error AssetPriceInvalid(address token);

    /// @notice Error for invalid funds recepient
    error InvalidReceiver(address receiver);

    /// @notice Error for invalid withdrawal request
    error InvalidWithdrawalRequest();

    // ============================================================================
    //  FUNCTIONS
    // ============================================================================

    /// @notice Initializes the LiquidTokenManager contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Allows users to deposit multiple assets and receive shares
    /// @param assets The ERC20 assets to deposit
    /// @param amounts The amounts of the respective assets to deposit
    /// @param receiver The address to receive the minted shares
    function deposit(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external returns (uint256[] memory);

    /// @notice Allows users to initiate a withdrawal request against their shares
    /// @param assets The ERC20 assets to withdraw
    /// @param amounts The amount of tokens to withdraw for each asset
    function initiateWithdrawal(IERC20[] memory assets, uint256[] memory amounts) external returns (bytes32);

    /// @notice Previews a withdrawal request and returns whether or not it would be successful
    /// @param assets The ERC20 assets to withdraw
    /// @param amounts The amount of tokens to withdraw for each asset
    function previewWithdrawal(IERC20[] memory assets, uint256[] memory amounts) external view returns (bool);

    /// @notice Credits queued balances for a given set of assets
    /// @param assets The assets to credit
    /// @param amounts The credit amounts expressed in native token
    function creditQueuedAssetBalances(IERC20[] calldata assets, uint256[] calldata amounts) external;

    /// @notice Debits queued balances for a given set of assets
    /// @param assets The assets to debit
    /// @param amounts The debit amounts expressed in native token
    /// @param sharesToBurn Escrow LAT shares to burn along with this debit (is non-zero only for user withdrawal fulfilment)
    function debitQueuedAssetBalances(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        uint256 sharesToBurn
    ) external;

    /// @notice Credits asset balances for a given set of assets
    /// @param assets The assets to credit
    /// @param amounts The credit amounts expressed in native token
    function creditAssetBalances(IERC20[] calldata assets, uint256[] calldata amounts) external;

    /// @notice Allows the LiquidTokenManager to transfer assets from this contract
    /// @param assetsToRetrieve The ERC20 assets to transfer
    /// @param amounts The amounts of each asset to transfer
    /// @param receiver The receiver of the funds, either `LiquidTokenManager` or `WithdrawalManager`
    function transferAssets(IERC20[] calldata assetsToRetrieve, uint256[] calldata amounts, address receiver) external;

    /// @notice Calculates the number of shares that correspond to a given amount of an asset
    /// @param asset The ERC20 asset
    /// @param amount The amount of the asset
    /// @return The number of shares
    function calculateShares(IERC20 asset, uint256 amount) external view returns (uint256);

    /// @notice Calculates the amount of an asset that corresponds to a given number of shares
    /// @param asset The ERC20 asset
    /// @param shares The number of shares
    /// @return The amount of the asset
    function calculateAmount(IERC20 asset, uint256 shares) external view returns (uint256);

    /// @notice Returns the total value of assets (staked, queued and unstaked) managed by the contract
    /// @return The total value of assets in the unit of account
    function totalAssets() external view returns (uint256);

    /// @notice Returns the unstaked balances for a set of assets
    /// @param assetList The list of assets to get balances for
    /// @return An array of asset balances
    function balanceAssets(IERC20[] calldata assetList) external view returns (uint256[] memory);

    /// @notice Returns the queued balances for a set of assets
    /// @param assetList The list of assets to get queued balances for
    /// @return An array of queued asset balances
    function balanceQueuedAssets(IERC20[] calldata assetList) external view returns (uint256[] memory);

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}
