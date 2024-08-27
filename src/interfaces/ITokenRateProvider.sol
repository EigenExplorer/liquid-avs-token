// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./ITokenRegistry.sol";

/// @title ITokenRateProvider Interface
/// @notice Interface for the TokenRateProvider contract
/// @dev This interface defines the functions for managing token rates
interface ITokenRateProvider {
    /// @notice Emitted when a token's rate is updated
    /// @param token The address of the token whose rate was updated
    /// @param newRate The new rate for the token
    event RateUpdated(IERC20 indexed token, uint256 newRate);

    /// @notice Initializes the TokenRateProvider contract
    /// @param admin The address to be granted admin rights
    /// @param _tokenRegistry The address of the TokenRegistry contract
    function initialize(address admin, ITokenRegistry _tokenRegistry) external;

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