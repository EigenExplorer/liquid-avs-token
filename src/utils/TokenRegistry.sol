// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../interfaces/ITokenRegistry.sol";

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
    mapping(address => TokenInfo) public tokens;

    /// @notice Array of supported token addresses
    address[] public supportedTokens;

    /// @notice Number of decimal places used for price representation
    uint256 public constant PRICE_DECIMALS = 18;

    /// @notice Role identifier for admin operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role identifier for price update operations
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract, setting up initial roles
    /// @param admin Address to be granted the admin role
    /// @param priceUpdater Address to be granted the price updater role
    function initialize(
        address admin,
        address priceUpdater
    ) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PRICE_UPDATER_ROLE, priceUpdater);
    }

    /// @notice Adds a new token to the registry
    /// @param token Address of the token to add
    /// @param decimals Number of decimals for the token
    /// @param initialPrice Initial price for the token
    function addToken(
        IERC20 token,
        uint256 decimals,
        uint256 initialPrice
    ) external onlyRole(ADMIN_ROLE) {
        if (tokens[address(token)].isSupported)
            revert TokenAlreadySupported(token);
        if (initialPrice == 0) revert InvalidPrice();

        tokens[address(token)] = TokenInfo({
            isSupported: true,
            decimals: decimals,
            pricePerUnit: initialPrice
        });
        supportedTokens.push(address(token));

        emit TokenAdded(token, decimals, initialPrice);
    }

    /// @notice Removes a token from the registry
    /// @param token Address of the token to remove
    function removeToken(IERC20 token) external onlyRole(ADMIN_ROLE) {
        if (!tokens[address(token)].isSupported)
            revert TokenNotSupported(token);

        delete tokens[address(token)];
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == address(token)) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /// @notice Updates the price of a token
    /// @param token Address of the token to update
    /// @param newPrice New price for the token
    function updatePrice(
        IERC20 token,
        uint256 newPrice
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        if (!tokens[address(token)].isSupported)
            revert TokenNotSupported(token);
        if (newPrice == 0) revert InvalidPrice();

        tokens[address(token)].pricePerUnit = newPrice;
        emit PriceUpdated(token, newPrice);
    }

    /// @notice Checks if a token is supported
    /// @param token Address of the token to check
    /// @return bool indicating whether the token is supported
    function tokenIsSupported(
        IERC20 token
    ) public view override returns (bool) {
        return tokens[address(token)].isSupported;
    }

    /// @notice Converts a token amount to the unit of account
    /// @param token Address of the token to convert
    /// @param amount Amount of tokens to convert
    /// @return The converted amount in the unit of account
    function convertToUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) public view override returns (uint256) {
        TokenInfo memory info = tokens[address(token)];
        if (!info.isSupported) revert TokenNotSupported(token);

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
        TokenInfo memory info = tokens[address(token)];
        if (!info.isSupported) revert TokenNotSupported(token);

        return amount.mulDiv(10 ** info.decimals, info.pricePerUnit);
    }

    /// @notice Calculates the total assets in the unit of account
    /// @return The total assets value in the unit of account
    function totalAssets() public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IERC20 token = IERC20(supportedTokens[i]);
            uint256 balance = token.balanceOf(address(this));
            total += convertToUnitOfAccount(token, balance);
        }
        return total;
    }

    /// @notice Retrieves the list of supported tokens
    /// @return An array of addresses of supported tokens
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /// @notice Retrieves the information for a specific token
    /// @param token Address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(
        IERC20 token
    ) external view returns (TokenInfo memory) {
        return tokens[address(token)];
    }
}
