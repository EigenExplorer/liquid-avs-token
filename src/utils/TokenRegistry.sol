// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../interfaces/ITokenRegistry.sol";

contract TokenRegistry is
    ITokenRegistry,
    Initializable,
    AccessControlUpgradeable
{
    using Math for uint256;

    mapping(address => TokenInfo) public tokens;
    address[] public supportedTokens;

    uint256 public constant PRICE_DECIMALS = 18;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE =
        keccak256("PRICE_UPDATER_ROLE");

    function initialize(
        address admin,
        address priceUpdater
    ) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PRICE_UPDATER_ROLE, priceUpdater);
    }

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

    function tokenIsSupported(
        IERC20 token
    ) public view override returns (bool) {
        return tokens[address(token)].isSupported;
    }

    function convertToUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) public view override returns (uint256) {
        TokenInfo memory info = tokens[address(token)];
        if (!info.isSupported) revert TokenNotSupported(token);

        return amount.mulDiv(info.pricePerUnit, 10 ** info.decimals);
    }

    function convertFromUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) public view override returns (uint256) {
        TokenInfo memory info = tokens[address(token)];
        if (!info.isSupported) revert TokenNotSupported(token);

        return amount.mulDiv(10 ** info.decimals, info.pricePerUnit);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IERC20 token = IERC20(supportedTokens[i]);
            uint256 balance = token.balanceOf(address(this));
            total += convertToUnitOfAccount(token, balance);
        }
        return total;
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    function getTokenInfo(
        IERC20 token
    ) external view returns (TokenInfo memory) {
        return tokens[address(token)];
    }
}
