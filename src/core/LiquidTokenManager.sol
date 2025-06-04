// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from '@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol';
import {AccessControlUpgradeable} from '@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol';
import {IStrategyManager} from '@eigenlayer/contracts/interfaces/IStrategyManager.sol';
import {IDelegationManager} from '@eigenlayer/contracts/interfaces/IDelegationManager.sol';
import {IStrategy} from '@eigenlayer/contracts/interfaces/IStrategy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ISignatureUtilsMixinTypes} from '@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

import {ILiquidToken} from '../interfaces/ILiquidToken.sol';
import {ILiquidTokenManager} from '../interfaces/ILiquidTokenManager.sol';
import {IStakerNode} from '../interfaces/IStakerNode.sol';
import {IStakerNodeCoordinator} from '../interfaces/IStakerNodeCoordinator.sol';
import {ITokenRegistryOracle} from '../interfaces/ITokenRegistryOracle.sol';

/// @title LiquidTokenManager
/// @notice Manages liquid tokens and their staking to EigenLayer strategies
contract LiquidTokenManager is
    ILiquidTokenManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Role identifier for staking operations
    bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256('STRATEGY_CONTROLLER_ROLE');

    /// @notice Role identifier for asset price update operations
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256('PRICE_UPDATER_ROLE');

    /// @notice Number of decimal places used for price representation
    uint256 public constant PRICE_DECIMALS = 18;

    /// @notice EigenLayer contracts
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    /// @notice LAT contracts
    ILiquidToken public liquidToken;
    IStakerNodeCoordinator public stakerNodeCoordinator;
    ITokenRegistryOracle public tokenRegistryOracle;

    /// @notice Mapping of tokens to their corresponding token info
    mapping(IERC20 => TokenInfo) public tokens;

    /// @notice Mapping of tokens to their corresponding strategies
    mapping(IERC20 => IStrategy) public tokenStrategies;

    /// @notice Mapping of strategies to their corresponding tokens (reverse of `tokenStrategies`)
    mapping(IStrategy => IERC20) public strategyTokens;

    /// @notice Array of supported token addresses
    IERC20[] public supportedTokens;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ILiquidTokenManager
    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (
            address(init.strategyManager) == address(0) ||
            address(init.delegationManager) == address(0) ||
            address(init.liquidToken) == address(0) ||
            address(init.initialOwner) == address(0) ||
            address(init.priceUpdater) == address(0) ||
            address(init.tokenRegistryOracle) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(STRATEGY_CONTROLLER_ROLE, init.strategyController);
        _grantRole(PRICE_UPDATER_ROLE, init.priceUpdater);

        liquidToken = init.liquidToken;
        stakerNodeCoordinator = init.stakerNodeCoordinator;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        tokenRegistryOracle = init.tokenRegistryOracle;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ILiquidTokenManager
    function addToken(
        IERC20 token,
        uint8 decimals,
        uint256 volatilityThreshold,
        IStrategy strategy,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(tokenStrategies[token]) != address(0)) revert TokenExists(address(token));
        if (address(token) == address(0)) revert ZeroAddress();
        if (decimals == 0) revert InvalidDecimals();
        if (volatilityThreshold != 0 && (volatilityThreshold < 1e16 || volatilityThreshold > 1e18))
            revert InvalidThreshold();
        if (address(strategy) == address(0)) revert ZeroAddress();
        if (address(strategyTokens[strategy]) != address(0)) {
            revert StrategyAlreadyAssigned(address(strategy), address(strategyTokens[strategy]));
        }

        // Price source validation and configuration
        bool isNative = (primaryType == 0 && primarySource == address(0));
        if (!isNative && (primaryType < 1 || primaryType > 3)) revert InvalidPriceSource();
        if (!isNative && primarySource == address(0)) revert InvalidPriceSource();
        if (!isNative) {
            tokenRegistryOracle.configureToken(
                address(token),
                primaryType,
                primarySource,
                needsArg,
                fallbackSource,
                fallbackFn
            );
        }

        try IERC20Metadata(address(token)).decimals() returns (uint8 decimalsFromContract) {
            if (decimalsFromContract == 0) revert InvalidDecimals();
            if (decimals != decimalsFromContract) revert InvalidDecimals();
        } catch {} // Fallback to `decimals` if token contract doesn't implement `decimals()`
        uint256 fetchedPrice;
        if (!isNative) {
            (uint256 price, bool ok) = tokenRegistryOracle._getTokenPrice_getter(address(token));
            if (!ok || price == 0) revert TokenPriceFetchFailed();
            fetchedPrice = price;
        } else {
            fetchedPrice = 1e18;
        }

        tokens[token] = TokenInfo({
            decimals: decimals,
            pricePerUnit: fetchedPrice,
            volatilityThreshold: volatilityThreshold
        });
        tokenStrategies[token] = strategy;
        strategyTokens[strategy] = token;
        supportedTokens.push(token);

        emit TokenAdded(token, decimals, fetchedPrice, volatilityThreshold, address(strategy), msg.sender);
    }

    /// @inheritdoc ILiquidTokenManager
    function removeToken(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert TokenNotSupported(token);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = token;

        // Check for unstaked balances
        if (liquidToken.balanceAssets(assets)[0] > 0) revert TokenInUse(token);

        // Check for pending withdrawal balances
        if (liquidToken.balanceQueuedAssets(assets)[0] > 0) revert TokenInUse(token);

        // Check for staked balances
        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 len = nodes.length;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                uint256 stakedBalance = getStakedAssetBalanceNode(token, nodes[i].getId());
                if (stakedBalance > 0) {
                    revert TokenInUse(token);
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

        // Remove token from TRO
        tokenRegistryOracle.removeToken(address(token));

        // Delete token strategy mapping and its reverse mapping
        IStrategy strategy = tokenStrategies[token];
        if (address(strategy) != address(0)) {
            delete strategyTokens[strategy];
        }
        delete tokenStrategies[token];
        delete tokens[token];

        emit TokenRemoved(token, msg.sender);
    }

    /// @inheritdoc ILiquidTokenManager
    function updatePrice(IERC20 token, uint256 newPrice) external onlyRole(PRICE_UPDATER_ROLE) {
        if (tokens[token].decimals == 0) revert TokenNotSupported(token);
        if (newPrice == 0) revert InvalidPrice();

        uint256 oldPrice = tokens[token].pricePerUnit;
        if (oldPrice == 0) revert InvalidPrice();

        // Find the ratio of price change and compare it against the asset's volatility threshold
        if (tokens[token].volatilityThreshold != 0) {
            uint256 absPriceDiff = (newPrice > oldPrice) ? newPrice - oldPrice : oldPrice - newPrice;
            uint256 changeRatio = (absPriceDiff * 1e18) / oldPrice;

            if (changeRatio > tokens[token].volatilityThreshold) {
                emit VolatilityCheckFailed(token, oldPrice, newPrice, changeRatio);
                revert VolatilityThresholdHit(token, changeRatio);
            }
        }

        tokens[token].pricePerUnit = newPrice;
        emit TokenPriceUpdated(token, oldPrice, newPrice, msg.sender);
    }

    /// @inheritdoc ILiquidTokenManager
    function setVolatilityThreshold(IERC20 asset, uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(asset) == address(0)) revert ZeroAddress();
        if (tokens[asset].decimals == 0) revert TokenNotSupported(asset);
        if (newThreshold != 0 && (newThreshold < 1e16 || newThreshold > 1e18)) revert InvalidThreshold();

        emit VolatilityThresholdUpdated(asset, tokens[asset].volatilityThreshold, newThreshold, msg.sender);

        tokens[asset].volatilityThreshold = newThreshold;
    }

    /// @inheritdoc ILiquidTokenManager
    function delegateNodes(
        uint256[] calldata nodeIds,
        address[] calldata operators,
        ISignatureUtilsMixinTypes.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 arrayLength = nodeIds.length;

        if (operators.length != arrayLength) revert LengthMismatch(operators.length, arrayLength);
        if (approverSignatureAndExpiries.length != arrayLength)
            revert LengthMismatch(approverSignatureAndExpiries.length, arrayLength);
        if (approverSalts.length != arrayLength) revert LengthMismatch(approverSalts.length, arrayLength);

        // Call for nodes to delegate themselves (on EigenLayer) to corresponding operators
        for (uint256 i = 0; i < arrayLength; i++) {
            IStakerNode node = stakerNodeCoordinator.getNodeById((nodeIds[i]));
            node.delegate(operators[i], approverSignatureAndExpiries[i], approverSalts[i]);
            emit NodeDelegated(nodeIds[i], operators[i]);
        }
    }

    /// @inheritdoc ILiquidTokenManager
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        _stakeAssetsToNode(nodeId, assets, amounts);
    }

    /// @inheritdoc ILiquidTokenManager
    function stakeAssetsToNodes(
        NodeAllocation[] calldata allocations
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        for (uint256 i = 0; i < allocations.length; i++) {
            NodeAllocation memory allocation = allocations[i];
            _stakeAssetsToNode(allocation.nodeId, allocation.assets, allocation.amounts);
        }
    }

    /// @dev Called by `stakeAssetsToNode` and `stakeAssetsToNodes`
    function _stakeAssetsToNode(uint256 nodeId, IERC20[] memory assets, uint256[] memory amounts) internal {
        uint256 assetsLength = assets.length;
        uint256 amountsLength = amounts.length;

        if (assetsLength != amountsLength) {
            revert LengthMismatch(assetsLength, amountsLength);
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        // Find EigenLayer strategies for the given assets
        IStrategy[] memory strategiesForNode = new IStrategy[](assetsLength);
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            if (amounts[i] == 0) {
                revert InvalidStakingAmount(amounts[i]);
            }
            IStrategy strategy = tokenStrategies[asset];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(asset));
            }
            strategiesForNode[i] = strategy;
        }

        // Bring unstaked assets in from `LiquidToken`
        liquidToken.transferAssets(assets, amounts);

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        // Transfer assets to node
        for (uint256 i = 0; i < assetsLength; i++) {
            depositAssets[i] = assets[i];
            depositAmounts[i] = amounts[i];
            assets[i].safeTransfer(address(node), amounts[i]);
        }

        emit AssetsStakedToNode(nodeId, assets, amounts, msg.sender);

        // Call for node to deposit assets into EigenLayer
        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(depositAssets, depositAmounts, strategiesForNode, address(node));
    }

    /// @dev OUT OF SCOPE FOR V1
    /**
    function undelegateNodes(
        uint256[] calldata nodeIds
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) {
        // Fetch and add all asset balances from the node to queued balances
        for (uint256 i = 0; i < nodeIds.length; i++) {
            IStakerNode node = stakerNodeCoordinator.getNodeById((nodeIds[i]));

            // Convert supportedTokens to IERC20Upgradeable array
            IERC20Upgradeable[]
                memory upgradeableTokens = new IERC20Upgradeable[](
                    supportedTokens.length
                );
            for (uint256 j = 0; j < supportedTokens.length; j++) {
                upgradeableTokens[j] = IERC20Upgradeable(
                    address(supportedTokens[j])
                );
            }

            liquidToken.creditQueuedAssetBalances(
                upgradeableTokens,
                _getAllStakedAssetBalancesNode(node)
            );

            node.undelegate();
        }
    }

    function _getAllStakedAssetBalancesNode(
        IStakerNode node
    ) internal view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](supportedTokens.length);
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            IStrategy strategy = tokenStrategies[supportedTokens[i]];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(supportedTokens[i]));
            }
            balances[i] = strategy.userUnderlyingView(address(node));
        }
        return balances;
    }
    */

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ILiquidTokenManager
    function getSupportedTokens() external view returns (IERC20[] memory) {
        return supportedTokens;
    }

    /// @inheritdoc ILiquidTokenManager
    function getTokenInfo(IERC20 token) external view returns (TokenInfo memory) {
        if (address(token) == address(0)) revert ZeroAddress();

        TokenInfo memory tokenInfo = tokens[token];

        if (tokenInfo.decimals == 0) {
            revert TokenNotSupported(token);
        }

        return tokenInfo;
    }

    /// @inheritdoc ILiquidTokenManager
    function getTokenStrategy(IERC20 asset) external view returns (IStrategy) {
        if (address(asset) == address(0)) revert ZeroAddress();

        IStrategy strategy = tokenStrategies[asset];

        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        return strategy;
    }

    /// @inheritdoc ILiquidTokenManager
    function getStrategyToken(IStrategy strategy) external view returns (IERC20) {
        if (address(strategy) == address(0)) revert ZeroAddress();

        IERC20 token = strategyTokens[strategy];

        if (address(token) == address(0)) {
            revert TokenForStrategyNotFound(address(strategy));
        }

        return token;
    }

    /// @inheritdoc ILiquidTokenManager
    function getStakedAssetBalance(IERC20 asset) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += _getStakedAssetBalanceNode(asset, nodes[i]);
        }

        return totalBalance;
    }

    /// @inheritdoc ILiquidTokenManager
    function getStakedAssetBalanceNode(IERC20 asset, uint256 nodeId) public view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        return _getStakedAssetBalanceNode(asset, node);
    }

    /// @dev Called by `getStakedAssetBalance` and `getStakedAssetBalanceNode`
    function _getStakedAssetBalanceNode(IERC20 asset, IStakerNode node) internal view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }
        return strategy.userUnderlyingView(address(node));
    }

    /// @inheritdoc ILiquidTokenManager
    function tokenIsSupported(IERC20 token) external view returns (bool) {
        return tokens[token].decimals != 0;
    }

    /// @inheritdoc ILiquidTokenManager
    function convertToUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert TokenNotSupported(token);

        return amount.mulDiv(info.pricePerUnit, 10 ** info.decimals);
    }

    /// @inheritdoc ILiquidTokenManager
    function convertFromUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert TokenNotSupported(token);

        return amount.mulDiv(10 ** info.decimals, info.pricePerUnit);
    }

    /// @inheritdoc ILiquidTokenManager
    function isStrategySupported(IStrategy strategy) external view returns (bool) {
        if (address(strategy) == address(0)) return false;
        return address(strategyTokens[strategy]) != address(0);
    }
}
