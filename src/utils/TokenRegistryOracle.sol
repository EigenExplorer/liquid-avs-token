// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";

/// @title TokenRegistryOracle
/// @notice A contract to provide and update rates for given tokens
/// @dev This contract interacts with a TokenRegistry to manage token rates
contract TokenRegistryOracle is ITokenRegistryOracle, Initializable, AccessControlUpgradeable {
    ILiquidTokenManager public liquidTokenManager;

    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");

    /// @notice Initializes the contract
    /// @param init Struct containing initial owner and price updater addresses
    function initialize(Init memory init) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(RATE_UPDATER_ROLE, init.priceUpdater);

        liquidTokenManager = init.liquidTokenManager;
    }

    /// @notice Updates the rate for a single token
    /// @param token The token address
    /// @param newRate The new rate for the token
    function updateRate(IERC20 token, uint256 newRate) external onlyRole(RATE_UPDATER_ROLE) {
        _updateTokenRate(token, newRate);
    }

    /// @notice Updates rates for multiple tokens in a single transaction
    /// @param tokens An array of token addresses
    /// @param newRates An array of new rates corresponding to the tokens
    function batchUpdateRates(IERC20[] calldata tokens, uint256[] calldata newRates) external onlyRole(RATE_UPDATER_ROLE) {
        require(tokens.length == newRates.length, "Mismatched array lengths");

        // Cache array length
        uint256 len = tokens.length;
        
        // Use unchecked for counter increment since i < len
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                _updateTokenRate(tokens[i], newRates[i]);
            }
        }
    }

    /// @notice Retrieves the current rate for a given token
    /// @param token The token address
    /// @return The current rate of the token
    function getRate(IERC20 token) external view returns (uint256) {
        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(token);
        return tokenInfo.pricePerUnit;
    }

    /// @notice Internal function to update the rate of a token
    /// @param token The token address
    /// @param newRate The new rate for the token
    function _updateTokenRate(IERC20 token, uint256 newRate) internal {
        // Cache liquidTokenManager to save gas
        ILiquidTokenManager manager = liquidTokenManager;
        uint256 oldRate = manager.getTokenInfo(token).pricePerUnit;
        manager.updatePrice(token, newRate);
        emit TokenRateUpdated(token, oldRate, newRate, msg.sender);
    }
}
