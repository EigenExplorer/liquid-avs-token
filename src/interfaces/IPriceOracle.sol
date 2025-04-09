// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPriceOracle
 * @notice Interface for token price oracle with primary/fallback sources
 */
interface IPriceOracle {
    /**
     * @notice Updates token prices if stale
     * @return Whether prices were updated
     */
    function updateAllPricesIfNeeded() external returns (bool);

    /**
     * @notice Returns the current price of a token in ETH
     * @param token Token address
     * @return Price in ETH (18 decimals)
     */
    function getTokenPrice(address token) external view returns (uint256);

    /**
     * @notice Checks if prices need updating
     * @return True if prices are stale and need update
     */
    function arePricesStale() external view returns (bool);

    /**
     * @notice Gets timestamp of last price update
     * @return Timestamp of the last update
     */
    function lastPriceUpdate() external view returns (uint256);

    /**
     * @notice Gets configured update interval
     * @return Interval in seconds
     */
    function priceUpdateInterval() external view returns (uint256);

    /**
     * @notice Emitted when a token price is updated
     */
    event TokenPriceUpdated(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice
    );

    /**
     * @notice Emitted when all prices are updated
     */
    event AllPricesUpdated(address indexed updater, uint256 timestamp);
}