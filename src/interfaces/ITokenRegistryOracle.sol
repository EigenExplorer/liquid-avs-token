// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidTokenManager} from "./ILiquidTokenManager.sol";

/// @title ITokenRegistryOracle Interface
/// @notice Interface for the TokenRegistryOracle contract
/// @dev Provides price oracle functionality with primary and fallback sources
interface ITokenRegistryOracle {
    /// @notice Struct to hold initialization parameters
    /// @param initialOwner The initial owner of the contract
    /// @param priceUpdater The address of the price updater
    /// @param liquidtoken The LiquidToken contract
    /// @param liquidTokenManager The LiquidTokenManager contract
    struct Init {
        address initialOwner;
        address priceUpdater;
        address liquidToken; // <-- Add this for proper role mngmnt now
        ILiquidTokenManager liquidTokenManager;
    }

    /// @notice Emitted when a token's rate is updated
    event TokenRateUpdated(
        IERC20 indexed token,
        uint256 oldRate,
        uint256 newRate,
        address indexed updater
    );

    /// @notice Emitted when a token's source is set
    event TokenSourceSet(address indexed token, address indexed source);

    /// @notice Emitted when update interval is changed
    event UpdateIntervalChanged(uint256 oldInterval, uint256 newInterval);

    /// @notice Emitted when all prices are updated
    event GlobalPricesUpdated(address indexed updater, uint256 timestamp);

    /**
     * @notice Emitted when a token is removed from configuration
     * @param token Address of the removed token
     */
    event TokenRemoved(address token);

    /// @notice Error thrown when no valid prices fetched by primary&fallbacks sources
    error NoFreshPrice(address token);
    /// @notice Error thrown when an unauthorized address attempts to update prices
    error InvalidUpdater(address sender);

    /// @notice Initializes the TokenRegistryOracle contract
    /// @param init Struct containing initialization parameters
    function initialize(Init memory init) external;

    /// @notice Configure a token with its primary and fallback sources
    /// @param token Token address
    /// @param primaryType Source type (1=Chainlink, 2=Curve, 3=BTC-chained, 4=Protocol)
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

    /// @notice Updates the rate for a single token
    /// @param token The address of the token to update
    /// @param newRate The new rate for the token
    function updateRate(IERC20 token, uint256 newRate) external;
    /**
     * @notice Remove a token configuration from the registry
     * @param token Address of the token to remove
     */
    function removeToken(address token) external;
    /// @notice Updates rates for multiple tokens in a single transaction
    /// @param tokens An array of token addresses to update
    /// @param newRates An array of new rates corresponding to the tokens
    function batchUpdateRates(
        IERC20[] calldata tokens,
        uint256[] calldata newRates
    ) external;

    /// @notice Retrieves the current rate for a given token
    /// @param token The address of the token to query
    /// @return The current rate of the token
    function getRate(IERC20 token) external view returns (uint256);

    /// @notice Checks if prices are stale and need updating
    /// @return Whether prices need updating
    function arePricesStale() external view returns (bool);

    /// @notice Updates all token prices if they are stale
    /// @return Whether prices were updated
    function updateAllPricesIfNeeded() external returns (bool);

    /// @notice Sets price update interval
    /// @param interval New interval in seconds
    function setPriceUpdateInterval(uint256 interval) external;

    /// @notice Get the current price of a token in ETH terms
    /// @param token Token address to get price for
    /// @return The current price with 18 decimals precision
    function getTokenPrice(address token) external view returns (uint256);

    /// @notice Gets configured update interval
    /// @return Interval in seconds
    function priceUpdateInterval() external view returns (uint256);

    /// @notice Get last price update timestamp
    /// @return Timestamp of last price update
    function lastPriceUpdate() external view returns (uint256);
    
    /// @notice Get price for a token
    /// @return price of a token and success/failure of this
    function _getTokenPrice_getter(
        address token
    ) external view returns (uint256 price, bool success);
}