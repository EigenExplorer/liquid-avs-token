// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {LTMValidation} from "./LTMValidation.sol";
import {LTMBalances} from "./LTMBalances.sol";

library LTMCore {
    using SafeERC20 for IERC20;
    using LTMValidation for uint256;
    using LTMValidation for address;

    event TokenAdded(
        IERC20 indexed token,
        uint8 decimals,
        uint256 pricePerUnit,
        uint256 volatilityThreshold,
        address strategy,
        address indexed caller
    );

    event TokenRemoved(IERC20 indexed token, address indexed caller);

    event TokenPriceUpdated(
        IERC20 indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        address indexed caller
    );

    event VolatilityCheckFailed(
        IERC20 indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 changeRatio
    );

    event VolatilityThresholdUpdated(
        IERC20 indexed asset,
        uint256 oldThreshold,
        uint256 newThreshold,
        address indexed caller
    );

    event AssetsStakedToNode(
        uint256 indexed nodeId,
        IERC20[] assets,
        uint256[] amounts,
        address indexed caller
    );

    event AssetsDepositedToEigenlayer(
        IERC20[] assets,
        uint256[] amounts,
        IStrategy[] strategies,
        address indexed node
    );

    event NodeDelegated(uint256 indexed nodeId, address indexed operator);

    struct TokenAdditionParams {
        IERC20 token;
        uint8 decimals;
        uint256 volatilityThreshold;
        IStrategy strategy;
        uint8 primaryType;
        address primarySource;
        uint8 needsArg;
        address fallbackSource;
        bytes4 fallbackFn;
    }

    function processTokenAddition(
        TokenAdditionParams calldata params,
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        mapping(IStrategy => IERC20) storage strategyTokens,
        IERC20[] storage supportedTokens,
        ITokenRegistryOracle tokenRegistryOracle
    ) external {
        if (address(tokenStrategies[params.token]) != address(0))
            revert LTMValidation.E12(); // TokenExists
        address(params.token).validateNotZero();
        if (params.decimals == 0) revert LTMValidation.E04(); // InvalidDecimals
        if (
            params.volatilityThreshold != 0 &&
            (params.volatilityThreshold < 1e16 ||
                params.volatilityThreshold > 1e18)
        ) revert LTMValidation.E05(); // InvalidThreshold
        address(params.strategy).validateNotZero();
        if (address(strategyTokens[params.strategy]) != address(0)) {
            revert LTMValidation.E13(); // StrategyAlreadyAssigned
        }

        // Price source validation and configuration
        bool isNative = (params.primaryType == 0 &&
            params.primarySource == address(0));
        if (!isNative && (params.primaryType < 1 || params.primaryType > 5))
            revert LTMValidation.E14(); // InvalidPriceSource
        if (!isNative && params.primarySource == address(0))
            revert LTMValidation.E14(); // InvalidPriceSource
        if (!isNative) {
            tokenRegistryOracle.configureToken(
                address(params.token),
                params.primaryType,
                params.primarySource,
                params.needsArg,
                params.fallbackSource,
                params.fallbackFn
            );
        }

        try IERC20Metadata(address(params.token)).decimals() returns (
            uint8 decimalsFromContract
        ) {
            if (decimalsFromContract == 0) revert LTMValidation.E04(); // InvalidDecimals
            if (params.decimals != decimalsFromContract)
                revert LTMValidation.E04(); // InvalidDecimals
        } catch {} // Fallback to `decimals` if token contract doesn't implement `decimals()`

        uint256 fetchedPrice;
        if (!isNative) {
            (uint256 price, bool ok) = tokenRegistryOracle
                ._getTokenPrice_getter(address(params.token));
            if (!ok || price == 0) revert LTMValidation.E15(); // TokenPriceFetchFailed
            fetchedPrice = price;
        } else {
            fetchedPrice = 1e18;
        }

        tokens[params.token] = ILiquidTokenManager.TokenInfo({
            decimals: params.decimals,
            pricePerUnit: fetchedPrice,
            volatilityThreshold: params.volatilityThreshold
        });
        tokenStrategies[params.token] = params.strategy;
        strategyTokens[params.strategy] = params.token;
        supportedTokens.push(params.token);

        emit TokenAdded(
            params.token,
            params.decimals,
            fetchedPrice,
            params.volatilityThreshold,
            address(params.strategy),
            msg.sender
        );
    }

    function processTokenRemoval(
        IERC20 token,
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        mapping(IStrategy => IERC20) storage strategyTokens,
        IERC20[] storage supportedTokens,
        ILiquidToken liquidToken,
        IStakerNodeCoordinator stakerNodeCoordinator,
        ITokenRegistryOracle tokenRegistryOracle
    ) external {
        ILiquidTokenManager.TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert LTMValidation.E07(); // TokenNotSupported

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = token;

        if (liquidToken.balanceAssets(assets)[0] > 0)
            revert LTMValidation.E16(); // TokenInUse

        if (liquidToken.balanceQueuedAssets(assets)[0] > 0)
            revert LTMValidation.E16(); // TokenInUse

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 len = nodes.length;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                IStrategy strategy = tokenStrategies[token];
                // Fixed: Use delegationManager instead of getDelegationManager()
                uint256 stakedWithdrawableBalance = LTMBalances
                    .getWithdrawableBalance(
                        strategy,
                        address(nodes[i]),
                        true,
                        stakerNodeCoordinator.delegationManager()
                    );
                if (stakedWithdrawableBalance > 0) {
                    revert LTMValidation.E16(); // TokenInUse
                }
            }
        }

        uint256 tokenCount = supportedTokens.length;
        for (uint256 i = 0; i < tokenCount; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[tokenCount - 1];
                supportedTokens.pop();
                break;
            }
        }

        tokenRegistryOracle.removeToken(address(token));

        IStrategy strategy = tokenStrategies[token];
        if (address(strategy) != address(0)) {
            delete strategyTokens[strategy];
        }
        delete tokenStrategies[token];
        delete tokens[token];

        emit TokenRemoved(token, msg.sender);
    }

    function processPriceUpdate(
        IERC20 token,
        uint256 newPrice,
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens
    ) external {
        if (tokens[token].decimals == 0) revert LTMValidation.E07(); // TokenNotSupported
        if (newPrice == 0) revert LTMValidation.E06(); // InvalidPrice

        uint256 oldPrice = tokens[token].pricePerUnit;
        if (oldPrice == 0) revert LTMValidation.E06(); // InvalidPrice

        if (tokens[token].volatilityThreshold != 0) {
            uint256 absPriceDiff = (newPrice > oldPrice)
                ? newPrice - oldPrice
                : oldPrice - newPrice;
            uint256 changeRatio = (absPriceDiff * 1e18) / oldPrice;

            if (changeRatio > tokens[token].volatilityThreshold) {
                emit VolatilityCheckFailed(
                    token,
                    oldPrice,
                    newPrice,
                    changeRatio
                );
                revert LTMValidation.E17(); // VolatilityThresholdHit
            }
        }

        tokens[token].pricePerUnit = newPrice;
        emit TokenPriceUpdated(token, oldPrice, newPrice, msg.sender);
    }

    function processVolatilityThresholdUpdate(
        IERC20 asset,
        uint256 newThreshold,
        mapping(IERC20 => ILiquidTokenManager.TokenInfo) storage tokens
    ) external {
        address(asset).validateNotZero();
        if (tokens[asset].decimals == 0) revert LTMValidation.E07(); // TokenNotSupported
        if (newThreshold != 0 && (newThreshold < 1e16 || newThreshold > 1e18))
            revert LTMValidation.E05(); // InvalidThreshold

        emit VolatilityThresholdUpdated(
            asset,
            tokens[asset].volatilityThreshold,
            newThreshold,
            msg.sender
        );

        tokens[asset].volatilityThreshold = newThreshold;
    }

    function processDelegateNodes(
        uint256[] calldata nodeIds,
        address[] calldata operators,
        ISignatureUtilsMixinTypes.SignatureWithExpiry[]
            calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts,
        IStakerNodeCoordinator stakerNodeCoordinator
    ) external {
        uint256 arrayLength = nodeIds.length;

        operators.length.validateLengths(arrayLength);
        approverSignatureAndExpiries.length.validateLengths(arrayLength);
        approverSalts.length.validateLengths(arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            IStakerNode node = stakerNodeCoordinator.getNodeById((nodeIds[i]));
            node.delegate(
                operators[i],
                approverSignatureAndExpiries[i],
                approverSalts[i]
            );
            emit NodeDelegated(nodeIds[i], operators[i]);
        }
    }

    function processStakingToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        ILiquidToken liquidToken,
        IStakerNodeCoordinator stakerNodeCoordinator
    ) external {
        uint256 assetsLength = assets.length;
        uint256 amountsLength = amounts.length;

        assetsLength.validateLengths(amountsLength);

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        IStrategy[] memory strategiesForNode = new IStrategy[](assetsLength);
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            if (amounts[i] == 0) {
                revert LTMValidation.E08(); // InvalidStakingAmount
            }
            IStrategy strategy = tokenStrategies[asset];
            address(strategy).validateStrategy();
            strategiesForNode[i] = strategy;
        }

        liquidToken.transferAssets(assets, amounts, address(this));

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        for (uint256 i = 0; i < assetsLength; i++) {
            depositAssets[i] = assets[i];
            uint256 balance = assets[i].balanceOf(address(this));
            depositAmounts[i] = balance < amounts[i] ? balance : amounts[i];

            assets[i].safeTransfer(address(node), depositAmounts[i]);
        }

        emit AssetsStakedToNode(
            nodeId,
            depositAssets,
            depositAmounts,
            msg.sender
        );

        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(
            depositAssets,
            depositAmounts,
            strategiesForNode,
            address(node)
        );
    }
}