// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

library LTMGetters {
    using Math for uint256;

    function getSupportedTokens(
        IERC20[] storage supportedTokens
    ) internal pure returns (IERC20[] memory) {
        return supportedTokens;
    }

    function getTokenInfo(
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens,
        IERC20 token
    ) internal view returns (ILiquidTokenManager.TokenInfo memory) {
        if (address(token) == address(0)) revert("Zero address");

        ILiquidTokenManager.TokenInfo memory tokenInfo = tokens[token];

        if (tokenInfo.decimals == 0) {
            revert("Token not supported");
        }

        return tokenInfo;
    }

    function getTokenStrategy(
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IERC20 asset
    ) internal view returns (IStrategy) {
        if (address(asset) == address(0)) revert("Zero address");

        IStrategy strategy = tokenStrategies[asset];

        if (address(strategy) == address(0)) revert("Strategy not found");

        return strategy;
    }

    function getStrategyToken(
        mapping(IStrategy => IERC20) storage strategyTokens,
        IStrategy strategy
    ) internal view returns (IERC20) {
        if (address(strategy) == address(0)) revert("Zero address");

        IERC20 token = strategyTokens[strategy];

        if (address(token) == address(0)) {
            revert("Token for strategy not found");
        }

        return token;
    }

    function tokenIsSupported(
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens,
        IERC20 token
    ) internal view returns (bool) {
        return tokens[token].decimals != 0;
    }

    function convertToUnitOfAccount(
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens,
        IERC20 token,
        uint256 amount
    ) internal view returns (uint256) {
        ILiquidTokenManager.TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert("Token not supported");

        return amount.mulDiv(info.pricePerUnit, 10 ** info.decimals);
    }

    function convertFromUnitOfAccount(
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens,
        IERC20 token,
        uint256 amount
    ) internal view returns (uint256) {
        ILiquidTokenManager.TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert("Token not supported");

        return amount.mulDiv(10 ** info.decimals, info.pricePerUnit);
    }

    function isStrategySupported(
        mapping(IStrategy => IERC20) storage strategyTokens,
        IStrategy strategy
    ) internal view returns (bool) {
        if (address(strategy) == address(0)) return false;
        return address(strategyTokens[strategy]) != address(0);
    }

    function assetSharesToUnderlying(
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IERC20 asset,
        uint256 amount
    ) internal view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) revert("Strategy not found");

        return strategy.sharesToUnderlyingView(amount);
    }

    function assetUnderlyingToShares(
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IERC20 asset,
        uint256 amount
    ) internal view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) revert("Strategy not found");

        return strategy.underlyingToSharesView(amount);
    }
}