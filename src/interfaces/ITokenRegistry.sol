// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ITokenRegistry Interface
/// @notice Interface for the TokenRegistry contract
/// @dev This interface defines the functions and events for managing token information and prices
interface ITokenRegistry {
    /// @notice Struct to hold initialization parameters
    /// @param initialOwner The initial owner of the contract
    /// @param priceUpdater The address of the price updater
    struct Init {
        address initialOwner;
        address priceUpdater;
    }

    /// @notice Struct to hold token information
    /// @param decimals The number of decimals for the token
    /// @param pricePerUnit The price per unit of the token
    struct TokenInfo {
        uint256 decimals;
        uint256 pricePerUnit;
    }

    /// @notice Emitted when a new token is added to the registry
    /// @param token The address of the added token
    /// @param decimals The number of decimals for the token
    /// @param initialPrice The initial price set for the token
    /// @param adder The address of the user who added the token
    event TokenAdded(
        IERC20 indexed token,
        uint256 decimals,
        uint256 initialPrice,
        address indexed adder
    );

    /// @notice Emitted when a token is removed from the registry
    /// @param token The address of the removed token
    /// @param remover The address of the user who removed the token
    event TokenRemoved(IERC20 indexed token, address indexed remover);

    /// @notice Emitted when a token's price is updated
    /// @param token The address of the token whose price was updated
    /// @param oldPrice The old price for the token
    /// @param newPrice The new price for the token
    /// @param updater The address of the user who updated the price
    event TokenPriceUpdated(IERC20 indexed token, uint256 oldPrice, uint256 newPrice, address indexed updater);

    /// @notice Error thrown when an operation is attempted on an unsupported token
    /// @param token The address of the unsupported token
    error TokenNotSupported(IERC20 token);

    /// @notice Error thrown when attempting to add a token that is already supported
    /// @param token The address of the token that is already supported
    error TokenAlreadySupported(IERC20 token);

    /// @notice Error thrown when an invalid decimals value is provided
    error InvalidDecimals();

    /// @notice Error thrown when an invalid price is provided
    error InvalidPrice();

    /// @notice Adds a new token to the registry
    /// @param token The address of the token to add
    /// @param decimals The number of decimals for the token
    /// @param initialPrice The initial price for the token
    function addToken(IERC20 token, uint8 decimals, uint256 initialPrice) external;

    /// @notice Removes a token from the registry
    /// @param token The address of the token to remove
    function removeToken(IERC20 token) external;

    /// @notice Updates the price of a token
    /// @param token The address of the token to update
    /// @param newPrice The new price for the token
    function updatePrice(IERC20 token, uint256 newPrice) external;

    /// @notice Checks if a token is supported
    /// @param token The address of the token to check
    /// @return bool indicating whether the token is supported
    function tokenIsSupported(IERC20 token) external view returns (bool);

    /// @notice Converts a token amount to the unit of account
    /// @param token The address of the token to convert
    /// @param amount The amount of tokens to convert
    /// @return The converted amount in the unit of account
    function convertToUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);

    /// @notice Converts an amount in the unit of account to a token amount
    /// @param token The address of the token to convert to
    /// @param amount The amount in the unit of account to convert
    /// @return The converted amount in the specified token
    function convertFromUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);

    /// @notice Retrieves the list of supported tokens
    /// @return An array of addresses of supported tokens
    function getSupportedTokens() external view returns (IERC20[] memory);

    /// @notice Retrieves the information for a specific token
    /// @param token The address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(IERC20 token) external view returns (TokenInfo memory);
}
