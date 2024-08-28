// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITokenRegistry} from "./ITokenRegistry.sol";

/// @title ITokenRegistryOracle Interface
/// @notice Interface for the TokenRegistryOracle contract
/// @dev This interface defines the functions for managing token rates
interface ITokenRegistryOracle {
    /// @notice Struct to hold initialization parameters
    /// @param initialOwner The initial owner of the contract
    /// @param priceUpdater The address of the price updater
    struct Init {
        address initialOwner;
        address priceUpdater;
        ITokenRegistry tokenRegistry;
    }

    /// @notice Emitted when a token's rate is updated
    /// @param token The address of the token whose rate was updated
    /// @param newRate The new rate for the token
    event RateUpdated(IERC20 indexed token, uint256 newRate);

    /// @notice Initializes the TokenRegistryOracle contract
    /// @param init Struct containing initial owner and price updater addresses
    function initialize(Init memory init) external;

    /// @notice Updates the rate for a single token
    /// @param token The address of the token to update
    /// @param newRate The new rate for the token
    function updateRate(IERC20 token, uint256 newRate) external;

    /// @notice Updates rates for multiple tokens in a single transaction
    /// @param tokens An array of token addresses to update
    /// @param newRates An array of new rates corresponding to the tokens
    function batchUpdateRates(IERC20[] calldata tokens, uint256[] calldata newRates) external;

    /// @notice Retrieves the current rate for a given token
    /// @param token The address of the token to query
    /// @return The current rate of the token
    function getRate(IERC20 token) external view returns (uint256);

    /// @notice Returns the address of the associated TokenRegistry contract
    /// @return The address of the TokenRegistry contract
    function tokenRegistry() external view returns (ITokenRegistry);
}