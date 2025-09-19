// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

library LTMTokenOps {
    struct TokenInfo {
        uint8 decimals;
        uint256 pricePerUnit;
        uint256 volatilityThreshold;
    }

    function addTokenValidation(
        IERC20 token,
        uint8 decimals,
        uint256 volatilityThreshold,
        IStrategy strategy,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        mapping(IStrategy => IERC20) storage strategyTokens
    ) external view {
        require(address(tokenStrategies[token]) == address(0), "TokenExists");
        require(address(token) != address(0), "ZeroAddress");
        require(decimals != 0, "InvalidDecimals");
        require(
            volatilityThreshold == 0 ||
                (volatilityThreshold >= 1e16 && volatilityThreshold <= 1e18),
            "InvalidThreshold"
        );
        require(address(strategy) != address(0), "ZeroAddress");
        require(
            address(strategyTokens[strategy]) == address(0),
            "StrategyAlreadyAssigned"
        );
    }

    function configurePriceSource(
        IERC20 token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn,
        ITokenRegistryOracle tokenRegistryOracle
    ) external returns (uint256 fetchedPrice) {
        bool isNative = (primaryType == 0 && primarySource == address(0));

        if (!isNative) {
            require(primaryType >= 1 && primaryType <= 3, "InvalidPriceSource");
            require(primarySource != address(0), "InvalidPriceSource");

            tokenRegistryOracle.configureToken(
                address(token),
                primaryType,
                primarySource,
                needsArg,
                fallbackSource,
                fallbackFn
            );

            (uint256 price, bool ok) = tokenRegistryOracle
                ._getTokenPrice_getter(address(token));
            require(ok && price != 0, "TokenPriceFetchFailed");
            fetchedPrice = price;
        } else {
            fetchedPrice = 1e18;
        }
    }

    function validateDecimals(
        IERC20 token,
        uint8 expectedDecimals
    ) external view {
        try IERC20Metadata(address(token)).decimals() returns (
            uint8 decimalsFromContract
        ) {
            require(
                decimalsFromContract != 0 &&
                    decimalsFromContract == expectedDecimals,
                "InvalidDecimals"
            );
        } catch {}
    }

    function executeTokenAddition(
        IERC20 token,
        TokenInfo memory info,
        IStrategy strategy,
        mapping(IERC20 => TokenInfo) storage tokens,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        mapping(IStrategy => IERC20) storage strategyTokens,
        IERC20[] storage supportedTokens
    ) external {
        tokens[token] = info;
        tokenStrategies[token] = strategy;
        strategyTokens[strategy] = token;
        supportedTokens.push(token);
    }

    function validatePriceUpdate(
        IERC20 token,
        uint256 newPrice,
        mapping(IERC20 => TokenInfo) storage tokens
    ) external view returns (uint256 oldPrice, uint256 changeRatio) {
        TokenInfo memory info = tokens[token];
        require(info.decimals != 0, "TokenNotSupported");
        require(newPrice != 0, "InvalidPrice");

        oldPrice = info.pricePerUnit;
        require(oldPrice != 0, "InvalidPrice");

        if (info.volatilityThreshold != 0) {
            uint256 absPriceDiff = (newPrice > oldPrice)
                ? newPrice - oldPrice
                : oldPrice - newPrice;
            changeRatio = (absPriceDiff * 1e18) / oldPrice;
            require(
                changeRatio <= info.volatilityThreshold,
                "VolatilityThresholdHit"
            );
        }
    }
}