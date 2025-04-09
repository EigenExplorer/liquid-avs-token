// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPriceSource
 * @notice Base interface for token price sources
 * @dev Minimal interface for maximum gas efficiency
 */
interface IPriceSource {
    /**
     * @notice Get the price of a token in ETH
     * @param token The token address
     * @return price The price in ETH (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function getPrice(
        address token
    ) external view returns (uint256 price, bool success);
}