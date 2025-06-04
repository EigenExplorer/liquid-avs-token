// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidTokenManager} from "./ILiquidTokenManager.sol";

/// @title ITokenRegistryOracle Interface
/// @notice Interface for the TokenRegistryOracle contract
/// @dev Provides price oracle functionality with primary and fallback sources
interface ITokenRegistryOracle {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Initialization parameters for TokenRegistryOracle
    struct Init {
        address initialOwner;
        address priceUpdater;
        address liquidToken;
        ILiquidTokenManager liquidTokenManager;
    }

    struct TokenConfig {
        uint8 primaryType; // 1=Chainlink, 2=Curve, 3=Protocol,
        uint8 needsArg; // 0=No arg, 1=Needs arg
        uint16 reserved; // For future use
        address primarySource; // Primary price source address
        address fallbackSource; // Fallback source contract address
        bytes4 fallbackFn; // Function selector for fallback
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when a token's rate is updated
    event TokenRateUpdated(IERC20 indexed token, uint256 oldRate, uint256 newRate, address indexed updater);

    /// @notice Emitted when the emergency interval is disabled
    event EmergencyIntervalDisabled();

    /// @notice Emitted when a token's source is set
    event TokenSourceSet(address indexed token, address indexed source);

    /// @notice Emitted when update interval is changed
    event UpdateIntervalChanged(uint256 oldInterval, uint256 newInterval);

    /// @notice Emitted when all prices are updated
    event GlobalPricesUpdated(address indexed updater, uint256 timestamp);

    /// @notice Emitted when a token is removed from configuration
    event TokenRemoved(address token);

    /// @notice Emitted when multiple pool safety settings are updated
    event BatchPoolsConfigured(address[] pools, bool[] settings);

    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================

    /// @notice Error zero address
    error ZeroAddress();

    /// @notice Error thrown when no valid prices fetched by both primary & fallbacks sources
    error NoFreshPrice(address token);

    /// @notice Error thrown when an unauthorized address attempts to update prices
    error InvalidUpdater(address sender);

    /// @notice Error for mismatched array lengths
    error ArrayLengthMismatch();

    /// @notice Error when trying to configure native tokens in oracle
    error NativeTokensNotConfigurable();

    /// @notice Error when fallback source required but not provided
    error FallbackSourceRequired();

    /// @notice Error when interval input is zero
    error IntervalCannotBeZero();

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Initializes the TokenRegistryOracle contract
    /// @param init Struct containing initialization parameters
    function initialize(Init memory init, uint256 stalenessSalt) external;

    /// @notice Configure a token with its primary and fallback sources
    /// @param token Token address
    /// @param primaryType Source type (1=Chainlink, 2=Curve, 3=Protocol)
    /// @param primarySource Primary source address
    /// @param needsArg Whether fallback fn needs args
    /// @param fallbackSource Address of the fallback source contract
    /// @param fallbackFn Function selector for fallback
    function configureToken(
        address token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn
    ) external;

    /// @notice Remove a token configuration from the registry
    /// @param token Address of the token to remove
    function removeToken(address token) external;

    /// @notice Updates the rate for a single token
    /// @param token Address of the token to update
    /// @param newRate New rate for the token
    function updateRate(IERC20 token, uint256 newRate) external;

    /// @notice Updates rates for multiple tokens in a single transaction
    /// @param tokens Array of token addresses to update
    /// @param newRates Array of new rates corresponding to the tokens
    function batchUpdateRates(IERC20[] calldata tokens, uint256[] calldata newRates) external;

    /// @notice Updates all token prices if they are stale
    /// @return Whether prices were updated
    function updateAllPricesIfNeeded() external returns (bool);

    /// @notice Sets price update interval
    /// @param interval New interval in seconds
    function setPriceUpdateInterval(uint256 interval) external;

    /// @notice Disables emergency interval mode and returns to dynamic intervals
    function disableEmergencyInterval() external;

    /// @notice Set reentrancy lock requirements for multiple pools in one transaction
    /// @param pools Array of Curve pool addresses
    /// @param settings Array of boolean values indicating if each pool requires the lock
    function batchSetRequiresLock(address[] calldata pools, bool[] calldata settings) external;

    /// @notice Retrieves the current rate for a given token
    /// @param token Address of the token to query
    /// @return Current rate of the token
    function getRate(IERC20 token) external view returns (uint256);

    /// @notice Checks if prices are stale and need updating
    /// @return Whether prices need updating
    function arePricesStale() external view returns (bool);

    /// @notice Get last price update timestamp
    /// @return Timestamp of last price update
    function lastPriceUpdate() external view returns (uint256);

    /// @notice Get the current price of a token in ETH
    /// @param token Token address to get price for
    /// @return The current price with 18 decimals precision
    function getTokenPrice(address token) external returns (uint256);

    /// @notice Get token price from primary source
    /// @dev Helper function for `ILiquidTokenManger.addToken`
    /// @dev This function exposes the internal `_getTokenPrice` for testing/setting purposes
    /// @param token The token address to get the price for
    /// @return price The price of the asset in 18 decimals
    /// @return success Whether the price fetch was successful
    function _getTokenPrice_getter(address token) external returns (uint256 price, bool success);
}
