// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";
import {LTMValidation} from "../libraries/LTMValidation.sol";
import {LTMBalances} from "../libraries/LTMBalances.sol";
import {LTMWithdrawalProcessor} from "../libraries/LTMWithdrawalProcessor.sol";
import {LTMHelpers} from "../libraries/LTMHelpers.sol";
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
    using LTMValidation for uint256;
    using LTMValidation for address;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Role identifier for staking operations
    bytes32 public constant STRATEGY_CONTROLLER_ROLE =
        keccak256("STRATEGY_CONTROLLER_ROLE");

    /// @notice Role identifier for asset price update operations
    bytes32 public constant PRICE_UPDATER_ROLE =
        keccak256("PRICE_UPDATER_ROLE");

    /// @notice EigenLayer contracts
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    /// @notice v1 LAT contracts
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

    /// @notice v2 contracts
    IWithdrawalManager public withdrawalManager;

    /// @notice Total redemptions created
    uint256 private _redemptionNonce;

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

        address(init.strategyManager).validateNotZero();
        address(init.delegationManager).validateNotZero();
        address(init.liquidToken).validateNotZero();
        address(init.initialOwner).validateNotZero();
        address(init.priceUpdater).validateNotZero();
        address(init.tokenRegistryOracle).validateNotZero();
        address(init.withdrawalManager).validateNotZero();

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(STRATEGY_CONTROLLER_ROLE, init.strategyController);
        _grantRole(PRICE_UPDATER_ROLE, init.priceUpdater);

        liquidToken = init.liquidToken;
        stakerNodeCoordinator = init.stakerNodeCoordinator;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        tokenRegistryOracle = init.tokenRegistryOracle;
        withdrawalManager = init.withdrawalManager;
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
        if (address(tokenStrategies[token]) != address(0))
            revert LTMValidation.E12(); // TokenExists
        address(token).validateNotZero();
        if (decimals == 0) revert LTMValidation.E04(); // InvalidDecimals
        if (
            volatilityThreshold != 0 &&
            (volatilityThreshold < 1e16 || volatilityThreshold > 1e18)
        ) revert LTMValidation.E05(); // InvalidThreshold
        address(strategy).validateNotZero();
        if (address(strategyTokens[strategy]) != address(0)) {
            revert LTMValidation.E13(); // StrategyAlreadyAssigned
        }

        // Price source validation and configuration
        bool isNative = (primaryType == 0 && primarySource == address(0));
        if (!isNative && (primaryType < 1 || primaryType > 5))
            revert LTMValidation.E14(); // InvalidPriceSource
        if (!isNative && primarySource == address(0))
            revert LTMValidation.E14(); // InvalidPriceSource
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

        try IERC20Metadata(address(token)).decimals() returns (
            uint8 decimalsFromContract
        ) {
            if (decimalsFromContract == 0) revert LTMValidation.E04(); // InvalidDecimals
            if (decimals != decimalsFromContract) revert LTMValidation.E04(); // InvalidDecimals
        } catch {} // Fallback to `decimals` if token contract doesn't implement `decimals()`
        uint256 fetchedPrice;
        if (!isNative) {
            (uint256 price, bool ok) = tokenRegistryOracle
                ._getTokenPrice_getter(address(token));
            if (!ok || price == 0) revert LTMValidation.E15(); // TokenPriceFetchFailed
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

        emit TokenAdded(
            token,
            decimals,
            fetchedPrice,
            volatilityThreshold,
            address(strategy),
            msg.sender
        );
    }

    /// @inheritdoc ILiquidTokenManager
    function removeToken(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert LTMValidation.E07(); // TokenNotSupported

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = token;

        // Check for unstaked balances
        if (liquidToken.balanceAssets(assets)[0] > 0)
            revert LTMValidation.E16(); // TokenInUse

        // Check for pending withdrawal balances
        if (liquidToken.balanceQueuedAssets(assets)[0] > 0)
            revert LTMValidation.E16(); // TokenInUse

        // Check for staked withdrawable balances
        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 len = nodes.length;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                uint256 stakedWithdrawableBalance = getWithdrawableAssetBalanceNode(
                        token,
                        nodes[i].getId(),
                        true
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
    function updatePrice(
        IERC20 token,
        uint256 newPrice
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        if (tokens[token].decimals == 0) revert LTMValidation.E07(); // TokenNotSupported
        if (newPrice == 0) revert LTMValidation.E06(); // InvalidPrice

        uint256 oldPrice = tokens[token].pricePerUnit;
        if (oldPrice == 0) revert LTMValidation.E06(); // InvalidPrice

        // Find the ratio of price change and compare it against the asset's volatility threshold
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

    /// @inheritdoc ILiquidTokenManager
    function setVolatilityThreshold(
        IERC20 asset,
        uint256 newThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    /// @inheritdoc ILiquidTokenManager
    function delegateNodes(
        uint256[] calldata nodeIds,
        address[] calldata operators,
        ISignatureUtilsMixinTypes.SignatureWithExpiry[]
            calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 arrayLength = nodeIds.length;

        operators.length.validateLengths(arrayLength);
        approverSignatureAndExpiries.length.validateLengths(arrayLength);
        approverSalts.length.validateLengths(arrayLength);

        // Call for nodes to delegate themselves (on EigenLayer) to corresponding operators
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
            _stakeAssetsToNode(
                allocation.nodeId,
                allocation.assets,
                allocation.amounts
            );
        }
    }

    /// @dev Called by `stakeAssetsToNode` and `stakeAssetsToNodes`
    function _stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256 assetsLength = assets.length;
        uint256 amountsLength = amounts.length;

        assetsLength.validateLengths(amountsLength);

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        // Find EigenLayer strategies for the given assets
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

        // Bring unstaked assets in from `LiquidToken`
        liquidToken.transferAssets(assets, amounts, address(this));

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        // Transfer assets to node
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

        // Call for node to deposit assets into EigenLayer
        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(
            depositAssets,
            depositAmounts,
            strategiesForNode,
            address(node)
        );
    }

    /// @inheritdoc ILiquidTokenManager
    function undelegateNodes(
        uint256[] calldata nodeIds
    ) external override onlyRole(STRATEGY_CONTROLLER_ROLE) {
        // Fetch and add all asset balances from the node to queued balances
        for (uint256 i = 0; i < nodeIds.length; i++) {
            _createRedemptionNodeUndelegation(nodeIds[i]);
        }
    }

    /// @dev Called by `undelegateNodes`
    function _createRedemptionNodeUndelegation(uint256 nodeId) private {
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(
            address(node)
        );
        address delegatedTo = node.getOperatorDelegation();

        // Find strategies and deposit shares
        (
            IStrategy[] memory redemptionStrategies,
            uint256[] memory redemptionShares
        ) = strategyManager.getDeposits(address(node));

        // Find withdrawable shares
        (uint256[] memory redemptionElWithdrawableShares, ) = delegationManager
            .getWithdrawableShares(address(node), redemptionStrategies);

        // Undelegate node on EL and return withdrawal info
        (
            bytes32[] memory withdrawalRoots,
            IDelegationManagerTypes.Withdrawal[] memory withdrawals,
            IERC20[] memory redemptionAssets
        ) = _processNodeForUndelegation(
                nodeId,
                node,
                delegatedTo,
                redemptionStrategies,
                redemptionShares,
                nonce
            );

        // Credit queued asset shares with total withdrawable shares
        liquidToken.creditQueuedAssetElShares(
            redemptionAssets,
            redemptionElWithdrawableShares
        );

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256(
            abi.encode(
                redemptionAssets,
                redemptionShares,
                block.timestamp,
                _redemptionNonce
            )
        );

        emit RedemptionCreatedForNodeUndelegation(
            _createRedemption(
                requestIds,
                withdrawalRoots,
                redemptionAssets,
                redemptionElWithdrawableShares,
                address(liquidToken)
            ),
            requestIds[0],
            withdrawalRoots,
            withdrawals,
            redemptionAssets,
            nodeId
        );
    }

    /// @dev Called by `_createRedemptionNodeUndelegation`
    function _processNodeForUndelegation(
        uint256 nodeId,
        IStakerNode node,
        address delegatedTo,
        IStrategy[] memory redemptionStrategies,
        uint256[] memory redemptionShares,
        uint256 nonce
    )
        internal
        returns (
            bytes32[] memory withdrawalRoots,
            IDelegationManagerTypes.Withdrawal[] memory withdrawals,
            IERC20[] memory redemptionAssets
        )
    {
        // Undelegate node from EL Operator
        withdrawalRoots = node.undelegate();
        emit NodeUndelegated(nodeId, delegatedTo);

        // Construct withdrawal structs
        withdrawals = new IDelegationManagerTypes.Withdrawal[](
            withdrawalRoots.length
        );
        redemptionAssets = new IERC20[](withdrawalRoots.length); // We can use a 1D array since every withdrawal corresponds to only 1 asset

        // The order of strategies in `withdrawalRoots[]` is the same as that of `redemptionStrategies[]`
        for (uint256 i = 0; i < withdrawalRoots.length; i++) {
            IStrategy[] memory requestStrategies = new IStrategy[](1);
            requestStrategies[0] = redemptionStrategies[i];

            redemptionAssets[i] = strategyTokens[redemptionStrategies[i]];

            uint256[] memory requestScaledShares = new uint256[](1);
            requestScaledShares[0] = _scaleSharesForNodeAsset(
                nodeId,
                redemptionAssets[i],
                redemptionShares[i]
            );

            IDelegationManagerTypes.Withdrawal
                memory withdrawal = IDelegationManagerTypes.Withdrawal({
                    staker: address(node),
                    delegatedTo: node.getOperatorDelegation(),
                    withdrawer: address(node),
                    nonce: nonce++,
                    startBlock: uint32(block.number),
                    strategies: requestStrategies,
                    scaledShares: requestScaledShares
                });

            // Make sure our withdrawal struct is the same as what EL computed
            if (withdrawalRoots[i] != keccak256(abi.encode(withdrawal)))
                revert LTMValidation.E18(); // InvalidWithdrawalRoot

            withdrawals[i] = withdrawal;
        }

        return (withdrawalRoots, withdrawals, redemptionAssets);
    }

    /// @inheritdoc ILiquidTokenManager
    function withdrawNodeAssets(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata elDepositShares
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        assets.length.validateLengths(nodeIds.length);
        elDepositShares.length.validateLengths(nodeIds.length);

        _createRedemptionRebalancing(nodeIds, assets, elDepositShares);
    }

    /// @dev Called by `withdrawNodeAssets`
    function _createRedemptionRebalancing(
        uint256[] calldata nodeIds,
        IERC20[][] calldata nodeAssets,
        uint256[][] calldata nodeElDepositShares
    ) internal {
        bytes32[] memory withdrawalRoots = new bytes32[](nodeIds.length);
        IDelegationManagerTypes.Withdrawal[]
            memory withdrawals = new IDelegationManagerTypes.Withdrawal[](
                nodeIds.length
            );
        bytes32[] memory requestIds = new bytes32[](nodeIds.length);

        IERC20[] memory redemptionAssets = new IERC20[](supportedTokens.length);
        uint256[] memory redemptionElWithdrawableShares = new uint256[](
            supportedTokens.length
        );
        uint256 uniqueTokenCount = 0;

        for (uint256 i = 0; i < nodeIds.length; i++) {
            uniqueTokenCount = _processNodeAssetsForRedemption(
                nodeIds[i],
                nodeAssets[i],
                nodeElDepositShares[i],
                redemptionAssets,
                redemptionElWithdrawableShares,
                uniqueTokenCount
            );

            // Call for EL withdrawals on staker node
            (withdrawalRoots[i], withdrawals[i]) = _createELWithdrawal(
                nodeIds[i],
                nodeAssets[i],
                nodeElDepositShares[i]
            );

            requestIds[i] = keccak256(
                abi.encode(
                    nodeAssets[i],
                    nodeElDepositShares[i],
                    block.timestamp,
                    i,
                    _redemptionNonce
                )
            );
        }

        // Credit queued asset shares with total withdrawable shares
        // Here we specifically factor in any slashing of staked funds in order to maintain accurate values for AUM calc
        // If there is any additional slashing after this (during EL withdrawal queue period), we handle it in redemption completion
        liquidToken.creditQueuedAssetElShares(
            redemptionAssets,
            redemptionElWithdrawableShares
        );

        emit RedemptionCreatedForRebalancing(
            _createRedemption(
                requestIds,
                withdrawalRoots,
                redemptionAssets,
                redemptionElWithdrawableShares,
                address(liquidToken)
            ),
            requestIds,
            withdrawalRoots,
            withdrawals,
            nodeAssets,
            nodeIds
        );
    }

    function _processNodeAssetsForRedemption(
        uint256 nodeId,
        IERC20[] calldata assets,
        uint256[] calldata elDepositShares,
        IERC20[] memory redemptionAssets,
        uint256[] memory redemptionElWithdrawableShares,
        uint256 currentUniqueTokenCount
    ) internal view returns (uint256) {
        uint256 uniqueTokenCount = currentUniqueTokenCount;

        for (uint256 j = 0; j < assets.length; j++) {
            elDepositShares[j].validateAmount();

            uint256 depositShares = getDepositAssetBalanceNode(
                assets[j],
                nodeId,
                true
            );
            // EL deposits for the asset must exist and cannot be less than proposed clawback amount
            if (depositShares == 0 || depositShares < elDepositShares[j]) {
                revert LTMValidation.E19(); // InsufficientBalance
            }

            uint256 withdrawableShares = getWithdrawableAssetBalanceNode(
                assets[j],
                nodeId,
                true
            );

            bool found = false;
            for (uint256 k = 0; k < uniqueTokenCount; k++) {
                if (redemptionAssets[k] == assets[j]) {
                    redemptionElWithdrawableShares[k] +=
                        (elDepositShares[j] * withdrawableShares) /
                        depositShares; // Factor in any slashing
                    found = true;
                    break;
                }
            }
            if (!found) {
                redemptionAssets[uniqueTokenCount] = assets[j];
                redemptionElWithdrawableShares[uniqueTokenCount] =
                    (elDepositShares[j] * withdrawableShares) /
                    depositShares; // Factor in any slashing
                uniqueTokenCount++;
            }
        }

        return uniqueTokenCount;
    }

    /// @inheritdoc ILiquidTokenManager
    function settleUserWithdrawals(
        UserWithdrawalsSettlement calldata settlement
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        settlement.elAssets.length.validateLengths(settlement.nodeIds.length);
        settlement.elDepositShares.length.validateLengths(
            settlement.nodeIds.length
        );

        // Check if all associated withdrawal requests actually get fulfilled from the input amounts
        (
            IERC20[] memory redemptionAssets,
            uint256[] memory redemptionElWithdrawableShares
        ) = _verifyAllRequestsSettle(settlement);

        // Create a redemption for the settlement by withdrawing from staker nodes
        _createRedemptionUserWithdrawals(
            settlement,
            redemptionAssets,
            redemptionElWithdrawableShares
        );
    }

    /// @notice Checks if the cumulative amounts per asset once drawn would actually settle ALL user withdrawal requests
    /// @dev Called by `settleUserWithdrawals`
    function _verifyAllRequestsSettle(
        UserWithdrawalsSettlement calldata settlement
    ) internal returns (IERC20[] memory, uint256[] memory) {
        // Get all associated withdrawal requests (reverts for any invalid request id)
        IWithdrawalManager.WithdrawalRequest[]
            memory withdrawalRequests = withdrawalManager.getWithdrawalRequests(
                settlement.requestIds
            );

        uint256 uniqueTokenCount;
        IERC20[] memory redemptionAssets = new IERC20[](supportedTokens.length);
        uint256[] memory redemptionElDepositShares = new uint256[](
            supportedTokens.length
        );

        // Aggregate cumulative amounts that need to be settled, across all withdrawal requests,
        (
            uniqueTokenCount,
            redemptionAssets,
            redemptionElDepositShares
        ) = _processWithdrawalRequests(withdrawalRequests);

        // Track the proposed amounts to be clawed back from nodes
        uint256[] memory proposedRedemptionElDepositShares = new uint256[](
            uniqueTokenCount
        );

        // Track the withdrawable amounts after slashing, for internal accounting
        // This allows correct AUM calc, where queued balances are checked, slashing is included
        uint256[] memory redemptionElWithdrawableShares = new uint256[](
            uniqueTokenCount
        );

        for (uint256 i = 0; i < settlement.nodeIds.length; i++) {
            for (uint256 j = 0; j < settlement.elAssets[i].length; j++) {
                IERC20 token = settlement.elAssets[i][j];

                settlement.elDepositShares[i][j].validateAmount();

                uint256 depositShares = getDepositAssetBalanceNode(
                    token,
                    settlement.nodeIds[i],
                    true
                );
                // EL deposits for the asset must exist and cannot be less than proposed clawback amount
                if (
                    depositShares == 0 ||
                    depositShares < settlement.elDepositShares[i][j]
                ) {
                    revert LTMValidation.E19(); // InsufficientBalance
                }

                uint256 withdrawableShares = getWithdrawableAssetBalanceNode(
                    token,
                    settlement.nodeIds[i],
                    true
                );

                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (redemptionAssets[k] == token) {
                        proposedRedemptionElDepositShares[k] += settlement
                            .elDepositShares[i][j];
                        redemptionElWithdrawableShares[k] +=
                            (settlement.elDepositShares[i][j] *
                                withdrawableShares) /
                            depositShares; // Factor in any slashing
                        break;
                    }
                }
            }
        }

        // Verify that the cumulative deposit shares required are equal to the proposed values, hence settling all requests
        // We are not concerned with slashing here, hence we use the EL `depositShares` -- slashing loss will be passed on after withdrawal completion
        // We allow 10 bps margin of error for rounding
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            uint256 upperMargin = Math.mulDiv(
                redemptionElDepositShares[i],
                10,
                10000,
                Math.Rounding.Up
            );
            uint256 lowerMargin = Math.mulDiv(
                redemptionElDepositShares[i],
                10,
                10000,
                Math.Rounding.Down
            );

            uint256 maxAllowed = redemptionElDepositShares[i] + upperMargin;
            uint256 minAllowed = redemptionElDepositShares[i] - lowerMargin;

            if (
                proposedRedemptionElDepositShares[i] > maxAllowed ||
                proposedRedemptionElDepositShares[i] < minAllowed
            ) {
                revert LTMValidation.E20(); // RequestsDoNotSettle
            }
        }

        // Trim arrays to actual sizes
        assembly {
            mstore(redemptionAssets, uniqueTokenCount)
            mstore(redemptionElWithdrawableShares, uniqueTokenCount)
        }

        // Credit queued asset shares with total withdrawable amounts, post slashing
        // As noted above, here we specifically factor in any slashing to maintain accurate AUM calc
        // If there is any additional slashing after this (during EL withdrawal queue period), we handle it in redemption completion
        liquidToken.creditQueuedAssetElShares(
            redemptionAssets,
            redemptionElWithdrawableShares
        );

        return (redemptionAssets, redemptionElWithdrawableShares);
    }

    /// @dev Called by `_verifyAllRequestsSettle`
    function _processWithdrawalRequests(
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests
    )
        internal
        view
        returns (
            uint256 uniqueTokenCount,
            IERC20[] memory redemptionAssets,
            uint256[] memory redemptionElDepositShares
        )
    {
        return
            LTMWithdrawalProcessor.processWithdrawalRequests(
                withdrawalRequests,
                supportedTokens
            );
    }

    /// @notice Creates a redemption for the unstaked funds portion of a user withdrawals settlement
    /// @dev Called by `settleUserWithdrawals`
    function _createRedemptionUserWithdrawals(
        UserWithdrawalsSettlement calldata settlement,
        IERC20[] memory redemptionAssets,
        uint256[] memory redemptionElWithdrawableShares
    ) internal {
        bytes32[] memory withdrawalRoots = new bytes32[](
            settlement.nodeIds.length
        );
        IDelegationManagerTypes.Withdrawal[]
            memory withdrawals = new IDelegationManagerTypes.Withdrawal[](
                settlement.nodeIds.length
            );

        // Call for EL withdrawals on staker nodes with the unscaled deposit shares
        for (uint256 i = 0; i < settlement.nodeIds.length; i++) {
            (withdrawalRoots[i], withdrawals[i]) = _createELWithdrawal(
                settlement.nodeIds[i],
                settlement.elAssets[i],
                settlement.elDepositShares[i]
            );
        }

        emit RedemptionCreatedForUserWithdrawals(
            _createRedemption(
                settlement.requestIds,
                withdrawalRoots,
                redemptionAssets,
                redemptionElWithdrawableShares,
                address(withdrawalManager)
            ),
            settlement.requestIds,
            withdrawalRoots,
            withdrawals,
            settlement.elAssets,
            settlement.nodeIds
        );
    }

    /// @dev Called by `_createRedemptionRebalancing` & `_createRedemptionUserWithdrawals`
    /// @dev When EL withdrawal is to be completed, the `withdrawal` and `assets` need to be provided, hence we store this data
    function _createELWithdrawal(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares
    ) private returns (bytes32, IDelegationManagerTypes.Withdrawal memory) {
        assets.length.validateLengths(shares.length);

        // Build the Withdrawal struct
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        IStrategy[] memory strategies = getTokensStrategies(assets);
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        uint256[] memory scaledShares = _scaleSharesForNode(
            nodeId,
            assets,
            shares
        );

        IDelegationManagerTypes.Withdrawal
            memory withdrawal = IDelegationManagerTypes.Withdrawal({
                staker: staker,
                delegatedTo: delegatedTo,
                withdrawer: staker,
                nonce: nonce,
                startBlock: uint32(block.number),
                strategies: strategies,
                scaledShares: scaledShares
            });

        // Request withdrawal on EL
        bytes32 withdrawalRoot = node.withdrawAssets(strategies, shares);

        // Make sure our withdrawal struct is the same as what EL computed
        if (withdrawalRoot != keccak256(abi.encode(withdrawal)))
            revert LTMValidation.E18(); // InvalidWithdrawalRoot

        return (withdrawalRoot, withdrawal);
    }

    /// @dev Called by `_createRedemptionNodeUndelegation`, `_createRedemptionRebalancing` & `_createRedemptionUserWithdrawals`
    function _createRedemption(
        bytes32[] memory requestIds,
        bytes32[] memory withdrawalRoots,
        IERC20[] memory assets,
        uint256[] memory elWithdrawableShares,
        address receiver
    ) private returns (bytes32) {
        bytes32 redemptionId = keccak256(
            abi.encode(
                requestIds,
                withdrawalRoots,
                block.timestamp,
                _redemptionNonce
            )
        );
        _redemptionNonce += 1;

        Redemption memory redemption = Redemption({
            requestIds: requestIds,
            withdrawalRoots: withdrawalRoots,
            assets: assets,
            elWithdrawableShares: elWithdrawableShares,
            receiver: receiver
        });

        // Update `WithdrawalManager` with the new redemption
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        return redemptionId;
    }

    /// @inheritdoc ILiquidTokenManager
    function completeRedemption(
        bytes32 redemptionId,
        uint256[] calldata nodeIds,
        IDelegationManagerTypes.Withdrawal[][] calldata withdrawals,
        IERC20[][][] calldata assets
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        withdrawals.length.validateLengths(nodeIds.length);
        assets.length.validateLengths(nodeIds.length);

        // Reverts for invalid `redemptionId`
        Redemption memory redemption = withdrawalManager.getRedemption(
            redemptionId
        );

        address receiver = redemption.receiver;
        if (
            receiver != address(withdrawalManager) &&
            receiver != address(liquidToken)
        ) revert LTMValidation.E11(); // InvalidReceiver

        // Check if the exact set of withdrawals concerned the redemption have been provided
        // Partial completion of a redemption is not accepted
        // Withdrawals that weren't part of the original redemption are not accepted
        LTMValidation.validateRedemption(
            redemption.withdrawalRoots,
            withdrawals
        );

        // Track unique tokens received from completion of all withdrawals across all nodes
        IERC20[] memory receivedTokens = new IERC20[](supportedTokens.length);
        uint256 uniqueTokenCount = 0;

        for (uint256 k = 0; k < nodeIds.length; k++) {
            uniqueTokenCount = _completeELWithdrawals(
                nodeIds[k],
                withdrawals[k],
                assets[k],
                receivedTokens,
                uniqueTokenCount
            );
        }

        // Keep track of the actual amounts received
        // This may differ from the original requested shares in the `Withdrawal` struct due to slashing
        uint256[] memory receivedAmounts = new uint256[](
            supportedTokens.length
        );
        uint256[] memory receivedElShares = new uint256[](
            supportedTokens.length
        );

        // Transfer all withdrawn assets to `receiver`, either `LiquidToken` or `WithdrawalManager`
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            IERC20 token = receivedTokens[i];
            uint256 balanceBefore = token.balanceOf(address(this));

            if (balanceBefore > 0) {
                uint256 receiverBalanceBefore = token.balanceOf(receiver);
                token.safeTransfer(receiver, balanceBefore);
                uint256 receiverBalanceAfter = token.balanceOf(receiver);

                // Calculate actual net amount transferred
                uint256 netTransferredAmount = receiverBalanceAfter -
                    receiverBalanceBefore;
                receivedAmounts[i] = netTransferredAmount;
                receivedElShares[i] = tokenStrategies[token]
                    .underlyingToSharesView(netTransferredAmount);
            } else {
                receivedAmounts[i] = 0;
                receivedElShares[i] = 0;
            }
        }

        // Update Withdrawal Manager and retrieve the original requested shares
        uint256[] memory requestedElShares = withdrawalManager
            .recordRedemptionCompleted(
                // Accounting for any slashing during withdrawal queue period handled here
                redemptionId,
                receivedTokens,
                receivedElShares
            );

        // If receiver is `LiquidToken`, we follow the debit done in `recordRedemptionCreated` with a corresponding credit to asset balances
        if (receiver == address(liquidToken)) {
            liquidToken.creditAssetBalances(receivedTokens, receivedAmounts);
        }

        emit RedemptionCompleted(
            redemptionId,
            receivedTokens,
            requestedElShares,
            receivedAmounts
        );
    }

    /// @dev Called by `completeRedemption`
    function _completeELWithdrawals(
        uint256 nodeId,
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata assets,
        IERC20[] memory uniqueTokens,
        uint256 uniqueTokenCount
    ) private returns (uint256) {
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        return
            LTMWithdrawalProcessor.completeELWithdrawals(
                nodeId,
                withdrawals,
                assets,
                uniqueTokens,
                uniqueTokenCount,
                node
            );
    }

    /// @dev Called by `_createELWithdrawal`
    function _scaleSharesForNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares
    ) internal view returns (uint256[] memory) {
        return
            LTMHelpers.scaleSharesForNode(
                nodeId,
                assets,
                shares,
                tokenStrategies,
                delegationManager,
                stakerNodeCoordinator
            );
    }

    /// @dev Called by `_createRedemptionNodeUndelegation`,
    function _scaleSharesForNodeAsset(
        uint256 nodeId,
        IERC20 asset,
        uint256 shares
    ) internal view returns (uint256) {
        return
            LTMHelpers.scaleSharesForNodeAsset(
                nodeId,
                asset,
                shares,
                tokenStrategies,
                delegationManager,
                stakerNodeCoordinator
            );
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ILiquidTokenManager
    function getSupportedTokens() external view returns (IERC20[] memory) {
        return supportedTokens;
    }

    /// @inheritdoc ILiquidTokenManager
    function getTokenInfo(
        IERC20 token
    ) external view returns (TokenInfo memory) {
        address(token).validateNotZero();

        TokenInfo memory tokenInfo = tokens[token];

        if (tokenInfo.decimals == 0) {
            revert LTMValidation.E07(); // TokenNotSupported
        }

        return tokenInfo;
    }

    /// @inheritdoc ILiquidTokenManager
    function getTokenStrategy(IERC20 asset) external view returns (IStrategy) {
        address(asset).validateNotZero();

        IStrategy strategy = tokenStrategies[asset];

        address(strategy).validateStrategy();

        return strategy;
    }

    /// @inheritdoc ILiquidTokenManager
    function getTokensStrategies(
        IERC20[] memory assets
    ) public view returns (IStrategy[] memory) {
        IStrategy[] memory strategies = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            address(asset).validateNotZero();

            IStrategy strategy = tokenStrategies[asset];
            address(strategy).validateStrategy();

            strategies[i] = strategy;
        }

        return strategies;
    }

    /// @inheritdoc ILiquidTokenManager
    function getStrategyToken(
        IStrategy strategy
    ) external view returns (IERC20) {
        address(strategy).validateNotZero();

        IERC20 token = strategyTokens[strategy];

        if (address(token) == address(0)) {
            revert LTMValidation.E21(); // TokenForStrategyNotFound
        }

        return token;
    }

    /// @inheritdoc ILiquidTokenManager
    function getDepositAssetBalance(
        IERC20 asset,
        bool inElShares
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += LTMBalances.getDepositBalance(
                strategy,
                address(nodes[i]),
                inElShares
            );
        }

        return totalBalance;
    }

    /// @inheritdoc ILiquidTokenManager
    function getDepositAssetBalanceNode(
        IERC20 asset,
        uint256 nodeId,
        bool inElShares
    ) public view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        return
            LTMBalances.getDepositBalance(strategy, address(node), inElShares);
    }

    /// @inheritdoc ILiquidTokenManager
    function getWithdrawableAssetBalance(
        IERC20 asset,
        bool inElShares
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += LTMBalances.getWithdrawableBalance(
                strategy,
                address(nodes[i]),
                inElShares,
                delegationManager
            );
        }

        return totalBalance;
    }

    /// @inheritdoc ILiquidTokenManager
    function getWithdrawableAssetBalanceNode(
        IERC20 asset,
        uint256 nodeId,
        bool inElShares
    ) public view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        return
            LTMBalances.getWithdrawableBalance(
                strategy,
                address(node),
                inElShares,
                delegationManager
            );
    }

    /// @inheritdoc ILiquidTokenManager
    function getWithdrawableAssetAmount(
        IERC20 asset,
        uint256 amount,
        bool inElShares
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();

        uint256 totalDepositBalance = 0;
        uint256 totalWithdrawableBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalDepositBalance += LTMBalances.getDepositBalance(
                strategy,
                address(nodes[i]),
                inElShares
            );
            totalWithdrawableBalance += LTMBalances.getWithdrawableBalance(
                strategy,
                address(nodes[i]),
                inElShares,
                delegationManager
            );
        }

        if (totalDepositBalance == 0 || totalWithdrawableBalance == 0) return 0;

        return amount.mulDiv(totalWithdrawableBalance, totalDepositBalance); // Withdrawable portion after any slashing
    }

    /// @inheritdoc ILiquidTokenManager
    function tokenIsSupported(IERC20 token) external view returns (bool) {
        return tokens[token].decimals != 0;
    }

    /// @inheritdoc ILiquidTokenManager
    function convertToUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) external view returns (uint256) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert LTMValidation.E07(); // TokenNotSupported

        return amount.mulDiv(info.pricePerUnit, 10 ** info.decimals);
    }

    /// @inheritdoc ILiquidTokenManager
    function convertFromUnitOfAccount(
        IERC20 token,
        uint256 amount
    ) external view returns (uint256) {
        TokenInfo memory info = tokens[token];
        if (info.decimals == 0) revert LTMValidation.E07(); // TokenNotSupported

        return amount.mulDiv(10 ** info.decimals, info.pricePerUnit);
    }

    /// @inheritdoc ILiquidTokenManager
    function isStrategySupported(
        IStrategy strategy
    ) external view returns (bool) {
        if (address(strategy) == address(0)) return false;
        return address(strategyTokens[strategy]) != address(0);
    }

    /// @inheritdoc ILiquidTokenManager
    function assetSharesToUnderlying(
        IERC20 asset,
        uint256 amount
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        return strategy.sharesToUnderlyingView(amount);
    }

    /// @inheritdoc ILiquidTokenManager
    function assetUnderlyingToShares(
        IERC20 asset,
        uint256 amount
    ) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        address(strategy).validateStrategy();

        return strategy.underlyingToSharesView(amount);
    }
}