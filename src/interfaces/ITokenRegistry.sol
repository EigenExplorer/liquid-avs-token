// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ITokenRegistry {
    struct TokenInfo {
        bool isSupported;
        uint256 decimals;
        uint256 pricePerUnit;
    }

    event TokenAdded(
        IERC20 indexed token,
        uint256 decimals,
        uint256 initialPrice
    );
    event TokenRemoved(IERC20 indexed token);
    event PriceUpdated(IERC20 indexed token, uint256 newPrice);

    error TokenNotSupported(IERC20 token);
    error TokenAlreadySupported(IERC20 token);
    error InvalidPrice();

    function tokenIsSupported(IERC20 token) external view returns (bool);
    function convertToUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) external view returns (uint256);
    function convertFromUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) external view returns (uint256);
    function totalAssets() external view returns (uint256);
}
