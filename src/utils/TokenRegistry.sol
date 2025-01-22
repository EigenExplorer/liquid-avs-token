// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";

/// @title TokenRegistry
/// @notice A contract for managing token information and prices
/// @dev Implements ITokenRegistry interface and uses AccessControl for role-based permissions
contract TokenRegistry is
    ITokenRegistry,
    Initializable,
    AccessControlUpgradeable
{
    using Math for uint256;

    /// @notice Mapping of token addresses to their TokenInfo
    mapping(IERC20 => TokenInfo) public tokens;

    /// @notice Array of supported token addresses
    IERC20[] public supportedTokens;

    /// @notice Number of decimal places used for price representation
    uint256 public constant PRICE_DECIMALS = 18;

    /// @notice Role identifier for price update operations
    bytes32 public constant PRICE_UPDATER_ROLE =
        keccak256("PRICE_UPDATER_ROLE");

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract, setting up initial roles
    /// @param init Struct containing initial owner and price updater addresses
    function initialize(Init memory init) public initializer {
        __AccessControl_init();

        // Zero address checks
        if (init.initialOwner == address(0)) {
            revert("Initial owner cannot be the zero address");
        }
        if (init.priceUpdater == address(0)) {
            revert("Price updater cannot be the zero address");
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(PRICE_UPDATER_ROLE, init.priceUpdater);
    }

    /// @notice Adds a new token to the registry
    /// @param token Address of the token to add
    /// @param decimals Number of decimals for the token
    /// @param initialPrice Initial price for the token
    function addToken(
        IERC20 token,
        uint256 decimals,
        uint256 initialPrice
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokens[token].decimals != 0) revert TokenAlreadySupported(token);
        if (decimals == 0) revert InvalidDecimals();
        if (initialPrice == 0) revert InvalidPrice();

        tokens[token] = TokenInfo({
            decimals: decimals,
            pricePerUnit: initialPrice
        });
        supportedTokens.push(token);

        emit TokenAdded(token, decimals, initialPrice, msg.sender);
    }

    /// @notice Removes a token from the registry
    /// @param token Address of the token to remove
    function removeToken(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokens[token].decimals == 0) revert TokenNotSupported(token);

        delete tokens[token];
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(token, msg.sender);
    }

    /// @notice Updates the price of a token
    /// @param token Address of the token to update
    /// @param newPrice New price for the token
    function updatePrice(
        IERC20 token,
        uint256 newPrice
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        if (tokens[token].decimals == 0) revert TokenNotSupported(token);
        if (newPrice == 0) revert InvalidPrice();

        uint256 oldPrice = tokens[token].pricePerUnit;
        tokens[token].pricePerUnit = newPrice;
        emit TokenPriceUpdated(token, oldPrice, newPrice, msg.sender);
    }

    /// @notice Checks if a token is supported
    /// @param token Address of the token to check
    /// @return bool indicating whether the token is supported
    function tokenIsSupported(
        IERC20 token
    ) public view override returns (bool) {
        return tokens[token].decimals != 0;
    }

    /// @notice Converts a token amount to the unit of account
    /// @param token Address of the token to convert
    /// @param amount Amount of tokens to convert
    /// @return The converted amount in the unit of account
    function convertToUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) public view override returns (uint256) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert TokenNotSupported(token);

        return amount.mulDiv(info.pricePerUnit, 10 ** info.decimals);
    }

    /// @notice Converts an amount in the unit of account to a token amount
    /// @param token Address of the token to convert to
    /// @param amount Amount in the unit of account to convert
    /// @return The converted amount in the specified token
    function convertFromUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) public view override returns (uint256) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert TokenNotSupported(token);

        return amount.mulDiv(10 ** info.decimals, info.pricePerUnit);
    }

    /// @notice Retrieves the list of supported tokens
    /// @return An array of addresses of supported tokens
    function getSupportedTokens() external view returns (IERC20[] memory) {
        return supportedTokens;
    }

    /// @notice Retrieves the information for a specific token
    /// @param token Address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(
        IERC20 token
    ) external view returns (TokenInfo memory) {
        return tokens[token];
    }
}
