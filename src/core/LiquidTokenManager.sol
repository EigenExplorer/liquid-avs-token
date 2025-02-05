// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

/// @title LiquidTokenManager
/// @notice Manages liquid tokens and their staking to EigenLayer strategies
/// @dev Implements ILiquidTokenManager and uses OpenZeppelin's upgradeable contracts
contract LiquidTokenManager is
    ILiquidTokenManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Role identifier for price update operations
    bytes32 public constant STRATEGY_CONTROLLER_ROLE =
        keccak256("STRATEGY_CONTROLLER_ROLE");

    /// @notice Role identifier for price update operations
    bytes32 public constant PRICE_UPDATER_ROLE =
        keccak256("PRICE_UPDATER_ROLE");

    /// @notice The EigenLayer StrategyManager contract
    IStrategyManager public strategyManager;
    /// @notice The EigenLayer DelegationManager contract
    IDelegationManager public delegationManager;
    /// @notice The StakerNodeCoordinator contract
    IStakerNodeCoordinator public stakerNodeCoordinator;
    /// @notice The LiquidToken contract
    ILiquidToken public liquidToken;
    /// @notice The WithdrawalManager contract
    IWithdrawalManager public withdrawalManager;

    /// @notice Mapping of tokens to their corresponding token info
    mapping(IERC20 => TokenInfo) public tokens;

    /// @notice Mapping of tokens to their corresponding strategies
    mapping(IERC20 => IStrategy) public tokenStrategies;

    /// @notice Mapping of strategies to their corresponding token
    mapping(IStrategy => IERC20) public strategyTokens;

    /// @notice Array of supported token addresses
    IERC20[] public supportedTokens;

    /// @notice Number of decimal places used for price representation
    uint256 public constant PRICE_DECIMALS = 18;

    /// @notice Number of redemptions created
    uint256 private _redemptionNonce;

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param init Initialization parameters
    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(STRATEGY_CONTROLLER_ROLE, init.strategyController);
        _grantRole(PRICE_UPDATER_ROLE, init.priceUpdater);

        if (
            address(init.strategyManager) == address(0) ||
            address(init.delegationManager) == address(0) ||
            address(init.liquidToken) == address(0) ||
            address(init.withdrawalManager) == address(0) ||
            address(init.initialOwner) == address(0) ||
            address(init.priceUpdater) == address(0)
        ) {
            revert ZeroAddress();
        }

        if (init.assets.length != init.tokenInfo.length) {
            revert LengthMismatch(init.assets.length, init.tokenInfo.length);
        }

        if (init.assets.length != init.strategies.length) {
            revert LengthMismatch(init.assets.length, init.strategies.length);
        }

        liquidToken = init.liquidToken;
        withdrawalManager = init.withdrawalManager;
        stakerNodeCoordinator = init.stakerNodeCoordinator;
        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;

        // Initialize strategies for each asset
        for (uint256 i = 0; i < init.assets.length; i++) {
            if (
                address(init.assets[i]) == address(0) ||
                address(init.strategies[i]) == address(0)
            ) {
                revert ZeroAddress();
            }

            if (init.tokenInfo[i].decimals == 0) {
                revert InvalidDecimals();
            }

            if (
                init.tokenInfo[i].volatilityThreshold != 0 &&
                (
                    init.tokenInfo[i].volatilityThreshold < 1e16 || 
                    init.tokenInfo[i].volatilityThreshold > 1e18
                )
            ) {
                revert InvalidThreshold();
            }

            if (tokens[init.assets[i]].decimals != 0) {
                revert TokenExists(address(init.assets[i]));
            }

            tokens[init.assets[i]] = init.tokenInfo[i];
            tokenStrategies[init.assets[i]] = init.strategies[i];
            strategyTokens[init.strategies[i]] = init.assets[i];
            supportedTokens.push(init.assets[i]);

            emit TokenSet(
                init.assets[i],
                init.tokenInfo[i].decimals,
                init.tokenInfo[i].pricePerUnit,
                init.tokenInfo[i].volatilityThreshold,
                address(init.strategies[i]),
                msg.sender
            );
        }
    }

    /// @notice Adds a new token to the registry
    /// @param token Address of the token to add
    /// @param decimals Number of decimals for the token
    /// @param initialPrice Initial price for the token
    /// @param strategy Strategy corresponding to the token
    function addToken(
        IERC20 token,
        uint8 decimals,
        uint256 initialPrice,
        uint256 volatilityThreshold,
        IStrategy strategy
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(tokenStrategies[token]) != address(0)) revert TokenExists(address(token));
        if (address(token) == address(0)) revert ZeroAddress();
        if (decimals == 0) revert InvalidDecimals();
        if (initialPrice == 0) revert InvalidPrice();
        if (volatilityThreshold != 0 && (volatilityThreshold < 1e16 || volatilityThreshold > 1e18)) revert InvalidThreshold();
        if (address(strategy) == address(0)) revert ZeroAddress();

        try IERC20Metadata(address(token)).decimals() returns (uint8 decimalsFromContract) {
            if (decimalsFromContract == 0) revert InvalidDecimals();
            if (decimals != decimalsFromContract) revert InvalidDecimals();
        } catch {} // Fallback to `decimals` if token contract doesn't implement `decimals()`

        tokens[token] = TokenInfo({
            decimals: decimals,
            pricePerUnit: initialPrice,
            volatilityThreshold: volatilityThreshold 
        });
        tokenStrategies[token] = strategy;
        strategyTokens[strategy] = token;

        supportedTokens.push(token);

        emit TokenSet(token, decimals, initialPrice, volatilityThreshold, address(strategy), msg.sender);
    }

    /// @notice Removes a token from the registry
    /// @param token Address of the token to remove
    function removeToken(IERC20 token) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokens[token].decimals == 0) revert TokenNotSupported(token);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = token;

        // Check for unstaked balances
        if (liquidToken.balanceAssets(assets)[0] > 0) revert TokenInUse(token);

        // Check for pending withdrawal balances
        if (liquidToken.balanceQueuedAssets(assets)[0] > 0) revert TokenInUse(token);

        // Check for staked node balances
        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            uint256 stakedBalance = getStakedAssetBalanceNode(
                token,
                nodes[i].getId()
            );
            if (stakedBalance > 0) {
                revert TokenInUse(token);
            }
        }

        delete strategyTokens[tokenStrategies[token]];
        delete tokenStrategies[token];
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

    /// @notice Delegate a set of staker nodes to a corresponding set of operators
    /// @param nodeIds The IDs of the staker nodes
    /// @param operators The addresses of the operators
    /// @param approverSignatureAndExpiries The signatures authorizing the delegations
    /// @param approverSalts The salts used in the signatures
    function delegateNodes(
        uint256[] memory nodeIds,
        address[] memory operators,
        ISignatureUtils.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) external override onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 arrayLength = nodeIds.length;

        if (operators.length != arrayLength) revert LengthMismatch(operators.length, arrayLength);
        if (approverSignatureAndExpiries.length != arrayLength) revert LengthMismatch(approverSignatureAndExpiries.length, arrayLength);
        if (approverSalts.length != arrayLength) revert LengthMismatch(approverSalts.length, arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            IStakerNode node = stakerNodeCoordinator.getNodeById((nodeIds[i]));
            node.delegate(operators[i], approverSignatureAndExpiries[i], approverSalts[i]);
            emit NodeDelegated(nodeIds[i], operators[i]);
        }
    }

    /// @notice Undelegate a set of staker nodes from their operators and creates a set of redemptions
    /// @dev A separate redemption is created for each node since undelegating a node on EL creates one `withdrawalRoot` per strategy
    /// @dev On completing a redemption created from undelegation, the funds are transferred to `LiquidToken`
    /// @dev Caller should index the `RedemptionCreatedForNodeUndelegation` event to properly complete the redemption
    /// @param nodeIds The IDs of the staker nodes
    function undelegateNodes(
        uint256[] calldata nodeIds
    ) external override onlyRole(STRATEGY_CONTROLLER_ROLE) {
        for (uint256 i = 0; i < nodeIds.length; i++) {
            _createRedemptionNodeUndelegation(nodeIds[i]);
        }
    }

    /// @notice Creates a redemption for a node undelegation
    /// @param nodeId The ID of the staker nodes
    function _createRedemptionNodeUndelegation(uint256 nodeId) private {
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        (IStrategy[] memory strategies, uint256[] memory shares) = strategyManager.getDeposits(staker);
        bytes32[] memory withdrawalRoots = node.undelegate();

        emit NodeUndelegated(nodeId, delegatedTo);

        if (strategies.length > 0 ) {
            IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](withdrawalRoots.length);
            IERC20[][] memory assets = new IERC20[][](withdrawalRoots.length);

            for (uint256 i = 0; i < withdrawalRoots.length; i++) {
                IStrategy[] memory requestStrategies = new IStrategy[](1);
                requestStrategies[0] = strategies[i];
                
                uint256[] memory requestShares = new uint256[](1);
                requestShares[0] = shares[i];

                IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
                    staker: staker,
                    delegatedTo: delegatedTo,
                    withdrawer: staker,
                    nonce: nonce++,
                    startBlock: uint32(block.number),
                    strategies: requestStrategies,
                    shares: requestShares
                });

                if (withdrawalRoots[i] != keccak256(abi.encode(withdrawal)))
                    revert InvalidWithdrawalRoot();

                IERC20[] memory requestAssets = new IERC20[](1);
                requestAssets[0] = strategyTokens[strategies[i]];

                // Credit queued asset balances as these amounts would be removed from staker node shares
                liquidToken.creditQueuedAssetBalances(requestAssets, requestShares);

                withdrawals[i] = withdrawal;
                assets[i] = requestAssets;
            }

            bytes32[] memory requestIds = new bytes32[](1);
            requestIds[0]  = keccak256(abi.encode(
                assets,
                shares,
                block.timestamp,
                _redemptionNonce
            ));

            emit RedemptionCreatedForNodeUndelegation(
                _createRedemption(requestIds, withdrawalRoots, withdrawals, assets, address(liquidToken)),
                requestIds[0],
                withdrawalRoots,
                nodeId
            );
        }
    }

    /// @notice Stakes assets to multiple nodes
    /// @param allocations Array of NodeAllocation structs containing staking information
    function stakeAssetsToNodes(
        NodeAllocation[] calldata allocations
    ) external override onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        for (uint256 i = 0; i < allocations.length; i++) {
            NodeAllocation memory allocation = allocations[i];
            _stakeAssetsToNode(
                allocation.nodeId,
                allocation.assets,
                allocation.amounts
            );
        }
    }

    /// @notice Stakes assets to a specific node
    /// @param nodeId The ID of the node to stake to
    /// @param assets Array of asset addresses to stake
    /// @param amounts Array of amounts to stake for each asset
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external override onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        _stakeAssetsToNode(nodeId, assets, amounts);
    }

    /// @notice Internal function to stake assets to a node
    /// @dev Node is funded with assets from `LiquidToken` since nodes cannot have unstaked assets
    /// @dev Assets are always deposited into their respective strategies, they are never converted
    /// @param nodeId The ID of the node to stake to
    /// @param assets Array of asset addresses to stake
    /// @param amounts Array of amounts to stake for each asset
    function _stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256 assetsLength = assets.length;
        uint256 amountsLength = amounts.length;

        if (assetsLength != amountsLength) {
            revert LengthMismatch(assetsLength, amountsLength);
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        if (node.getOperatorDelegation() == address(0)) revert NodeIsNotDelegated();

        // Each asset is deposited into its corresponding strategy ie, we never convert assets
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

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        // Fund the staker node with assets from `LiquidToken`
        liquidToken.transferAssets(assets, amounts, address(this));

        for (uint256 i = 0; i < assetsLength; i++) {
            depositAssets[i] = assets[i];
            depositAmounts[i] = amounts[i];
            assets[i].safeTransfer(address(node), amounts[i]);
        }

        emit AssetsDepositedToNode(nodeId, assets, amounts, msg.sender);    

        // Stake on EL
        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(
            depositAssets,
            depositAmounts,
            strategiesForNode,
            address(node)
        );
    }

    /// @notice Allows rebalancing of funds by partially withdrawing assets from nodes and creating a redemption
    /// @dev On completing the redemption, the funds are transferred to `LiquidToken`
    /// @dev Caller should index the `RedemptionCreatedForRebalancing` event to properly complete the redemption
    /// @dev Strategies are always withdrawn into their respective assets, they are never converted
    /// @param nodeIds The ID of the nodes to withdraw from
    /// @param assets The array of assets to withdraw for each node
    /// @param shares The array of shares to withdraw for each asset
    function withdrawNodeAssets(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata shares
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 arrayLength = nodeIds.length;

        if (assets.length != arrayLength) revert LengthMismatch(assets.length, arrayLength);
        if (shares.length != arrayLength) revert LengthMismatch(shares.length, arrayLength);

        _createRedemptionRebalancing(nodeIds, assets, shares);
    }

    /// @notice Creates a redemption for rebalancing
    /// @param nodeIds The ID of the nodes to withdraw from
    /// @param elAssets The array of assets to withdraw for each node
    /// @param elShares The array of shares to withdraw for each asset
    function _createRedemptionRebalancing(
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elShares
    ) internal {
        uint256 elActions = nodeIds.length;
        bytes32[] memory withdrawalRoots = new bytes32[](elActions);
        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](elActions);
        IERC20[][] memory assets = new IERC20[][](elActions);
        bytes32[] memory requestIds = new bytes32[](elActions);

        // Call for EL withdrawals on staker nodes
        for (uint256 i = 0; i < elActions; i++) {
            IERC20[] memory requestAssets = elAssets[i];
            uint256[] memory requestShares = elShares[i];

            (withdrawalRoots[i], withdrawals[i], assets[i]) = _createELWithdrawal(
                nodeIds[i],
                requestAssets,
                requestShares
            );

            requestIds[i]  = keccak256(abi.encode(
                requestAssets,
                requestShares,
                block.timestamp,
                i,
                _redemptionNonce
            ));

            // Credit queued asset balances as these amounts would be removed from staker node shares
            liquidToken.creditQueuedAssetBalances(requestAssets, requestShares);
        }

        emit RedemptionCreatedForRebalancing(
            _createRedemption(requestIds, withdrawalRoots, withdrawals, assets, address(liquidToken)),
            requestIds,
            withdrawalRoots,
            nodeIds
        );
    }

    /// @notice Enables a set of user withdrawal requests to be fulfillable after 14 days by the respective users
    /// @dev The caller can draw from both, unstaked and staked in the proportion it deems fit
    /// @dev This function accepts a settlement only if it will actually retrieve enough funds per token to settle ALL user withdrawal requests
    /// @dev If drawing from staked funds, a redemption is created on completion of which, funds are transferred to `WithdrawalManager`
    /// @dev Caller should index the `RedemptionCreatedForUserWithdrawals` event to properly complete the redemption
    /// @param requestIds The request IDs of the user withdrawal requests to be fulfilled
    /// @param ltAssets The assets that will be drawn from `LiquidToken`
    /// @param ltAmounts The amounts for `ltAssets`
    /// @param nodeIds The node IDs from which funds will be withdrawn
    /// @param elAssets The array of assets to be withdrawn for a given node
    /// @param elShares The array of shares to be withdrawn for the corresponding array of `elAssets`
    function settleUserWithdrawals(
        bytes32[] calldata requestIds,
        IERC20[] calldata ltAssets,
        uint256[] calldata ltAmounts,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elShares
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 ltActions = ltAssets.length;
        uint256 elActions = nodeIds.length;

        if (ltAmounts.length != ltActions) revert LengthMismatch(ltAmounts.length, ltActions);
        if (elAssets.length != elActions) revert LengthMismatch(elAssets.length, elActions);
        if (elShares.length != elActions) revert LengthMismatch(elShares.length, elActions);

        // Check if all provided requests can be fulfilled once the redemption is successful
        _verifyAllRequestsSettle(requestIds, ltAssets, ltAmounts, nodeIds, elAssets, elShares);

        // Direct unstaked funds from `LiquidToken` to `WithdrawalManager`
        liquidToken.transferAssets(ltAssets, ltAmounts, address(withdrawalManager));

        // Create a redemption for the rest of the settlement by withdrawing from staker nodes
        _createRedemptionUserWithdrawals(requestIds, nodeIds, elAssets, elShares);
    }

    /// @notice Checks if the cumulative amounts per asset once drawn would actually settle ALL user withdrawal requests
    /// @param requestIds The request IDs of the user withdrawal requests to be fulfilled
    /// @param ltAssets The assets that will be drawn from `LiquidToken`
    /// @param ltAmounts The amounts for `ltAssets`
    /// @param nodeIds The node IDs from which funds will be withdrawn
    /// @param elAssets The array of assets to be withdrawn for a given node
    /// @param elShares The array of shares to be withdrawn for the corresponding array of `elAssets`
    function _verifyAllRequestsSettle(
        bytes32[] calldata requestIds,
        IERC20[] calldata ltAssets,
        uint256[] calldata ltAmounts,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elShares
    ) internal {
        // Get the cumulative amounts per token from all requests 
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests =
            withdrawalManager.getWithdrawalRequests(requestIds);

        uint256 uniqueTokenCount;
        IERC20[] memory requestTokens = new IERC20[](supportedTokens.length);
        uint256[] memory requestAmounts = new uint256[](supportedTokens.length);

        // Gather the cumulative expected amounts per token from the redemption
        (uniqueTokenCount, requestTokens, requestAmounts) = _processWithdrawalRequests(withdrawalRequests);
        uint256[] memory expectedRedemptionAmounts = new uint256[](uniqueTokenCount);

        // Process amounts from LiquidToken and Staker Nodes
        _processLtAmounts(ltAssets, ltAmounts, requestTokens, expectedRedemptionAmounts, uniqueTokenCount);
        _processElAmounts(nodeIds, elAssets, elShares, requestTokens, expectedRedemptionAmounts, uniqueTokenCount);

        // Verify that the cumulative amounts are exactly equal to the amount to settle all requests
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            if (expectedRedemptionAmounts[i] != requestAmounts[i]) {
                revert RequestsDoNotSettle(
                    address(requestTokens[i]),
                    expectedRedemptionAmounts[i],
                    requestAmounts[i]
                );
            }
        }

        // Credit queued asset balances as these amounts would be removed from liquid token & staker nodes
        liquidToken.creditQueuedAssetBalances(requestTokens, requestAmounts);
    }

    function _processWithdrawalRequests(
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests
    ) internal view returns (uint256 uniqueTokenCount, IERC20[] memory requestTokens, uint256[] memory requestAmounts) {
        requestTokens = new IERC20[](supportedTokens.length);
        requestAmounts = new uint256[](supportedTokens.length);
        uniqueTokenCount = 0;

        for (uint256 i = 0; i < withdrawalRequests.length; i++) {
            IWithdrawalManager.WithdrawalRequest memory request = withdrawalRequests[i];
            for (uint256 j = 0; j < request.assets.length; j++) {
                IERC20 token = request.assets[j];
                bool found = false;
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (requestTokens[k] == token) {
                        requestAmounts[k] += request.shareAmounts[j];
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    requestTokens[uniqueTokenCount] = token;
                    requestAmounts[uniqueTokenCount] = request.shareAmounts[j];
                    uniqueTokenCount++;
                }
            }
        }
    }

    function _processLtAmounts(
        IERC20[] calldata ltAssets,
        uint256[] calldata ltAmounts,
        IERC20[] memory requestTokens,
        uint256[] memory expectedRedemptionAmounts,
        uint256 uniqueTokenCount
    ) internal view {
        for (uint256 i = 0; i < ltAssets.length; i++) {
            IERC20 asset = ltAssets[i];
            uint256 amount = ltAmounts[i];
            if (asset.balanceOf(address(liquidToken)) < amount) {
                revert InsufficientBalance(
                    asset,
                    amount,
                    asset.balanceOf(address(liquidToken))
                );
            }
            for (uint256 j = 0; j < uniqueTokenCount; j++) {
                if (requestTokens[j] == asset) {
                    expectedRedemptionAmounts[j] += amount;
                    break;
                }
            }
        }
    }

    function _processElAmounts(
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elShares,
        IERC20[] memory requestTokens,
        uint256[] memory expectedRedemptionAmounts,
        uint256 uniqueTokenCount
    ) internal view {
        for (uint256 i = 0; i < nodeIds.length; i++) {
            if (elShares[i].length != elAssets[i].length) {
                revert LengthMismatch(elShares[i].length, elAssets[i].length);
            }
            for (uint256 j = 0; j < elAssets[i].length; j++) {
                IERC20 token = elAssets[i][j];
                uint256 amount = elShares[i][j];
                uint256 assetBalanceNode = getStakedAssetBalanceNode(token, nodeIds[i]);
                if (assetBalanceNode < amount) {
                    revert InsufficientBalance(token, amount, assetBalanceNode);
                }
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (requestTokens[k] == token) {
                        expectedRedemptionAmounts[k] += amount;
                        break;
                    }
                }
            }
        }
    }

    /// @notice Creates a redemption for the unstaked funds portion of a user withdrawals settlement
    /// @param requestIds The request IDs of the user withdrawal requests to be fulfilled
    /// @param nodeIds The node IDs from which funds will be withdrawn
    /// @param elAssets The array of assets to be withdrawn for a given node
    /// @param elShares The array of shares to be withdrawn for the corresponding array of `elAssets`
    function _createRedemptionUserWithdrawals(
        bytes32[] calldata requestIds,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elShares
    ) internal {
        bytes32[] memory withdrawalRoots = new bytes32[](nodeIds.length);
        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](nodeIds.length);
        IERC20[][] memory assets = new IERC20[][](nodeIds.length);

        // Call for EL withdrawals on staker nodes
        for (uint256 i = 0; i < nodeIds.length; i++) {
            (withdrawalRoots[i], withdrawals[i], assets[i]) = _createELWithdrawal(
                nodeIds[i],
                elAssets[i],
                elShares[i]
            );
        }

        emit RedemptionCreatedForUserWithdrawals(
            _createRedemption(requestIds, withdrawalRoots, withdrawals, assets, address(withdrawalManager)),
            requestIds,
            withdrawalRoots,
            nodeIds
        );
    }

    /// @notice For a given node, creates a withdrawal request on EL
    /// @dev When EL withdrawal is to be completed, the `withdrawal` and `assets` need to be provided, hence we store this data
    /// @param nodeId The ID of the node to create a withdrawal request for
    /// @param assets The array of assets to be withdrawn
    /// @param shares Shares to be withdrawn for each asset
    function _createELWithdrawal(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares
    ) private returns (bytes32, IDelegationManager.Withdrawal memory, IERC20[] memory) {
        IStrategy[] memory strategies = _getTokensStrategies(assets);
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        
        // Setup withdrawal
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: staker,
            delegatedTo: delegatedTo,
            withdrawer: staker,
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            shares: shares
        });
        
        // Request withdrawal on EL
        bytes32 withdrawalRoot = node.withdrawAssets(strategies, shares);

        if (withdrawalRoot != keccak256(abi.encode(withdrawal))) 
            revert InvalidWithdrawalRoot();
        
        return (withdrawalRoot, withdrawal, assets);
    }

    function _createRedemption(
        bytes32[] memory requestIds,
        bytes32[] memory withdrawalRoots,
        IDelegationManager.Withdrawal[] memory withdrawals,
        IERC20[][] memory assets,
        address receiver
    ) private returns (bytes32) {
        bytes32 redemptionId = keccak256(
            abi.encode(
                requestIds,
                withdrawalRoots,
                block.timestamp,
                _redemptionNonce++
            )
        );

        Redemption memory redemption = Redemption({
            requestIds: requestIds,
            withdrawalRoots: withdrawalRoots,
            receiver: receiver
        });

        // Update `WithdrawalManager` with the new redemption 
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption, withdrawals, assets);
        
        return redemptionId;
    }

    /// @notice Completes withdrawals on EigenLayer for a given redemption and transfers funds to the `receiver` of the redemption
    /// @dev The caller must make sure every i-th element of `withdrawalRoots[][]` aligns with the corresponding `nodeIds[i]`
    /// @dev The burden is on the caller to keep track of (node, withdrawal roots) pairs via corresponding events emitted during redemption creation
    /// @dev A redemption can never be partially completed, ie. if any withdrawal roots are missing from the input, the fn will revert
    /// @param redemptionId The ID of the redemption to complete
    /// @param nodeIds The set of all node IDs concerned with the redemption
    /// @param withdrawalRoots The set of all withdrawal roots concerned with the redemption per node ID
    function completeRedemption(
        bytes32 redemptionId,
        uint256[] calldata nodeIds,
        bytes32[][] calldata withdrawalRoots
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 elActions = nodeIds.length;

        if (withdrawalRoots.length != elActions) 
            revert LengthMismatch(withdrawalRoots.length, elActions);
        
        Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        bytes32[] memory redemptionWithdrawalRoots = redemption.withdrawalRoots;
        address receiver = redemption.receiver;

        if (
            receiver != address(withdrawalManager) && 
            receiver != address(liquidToken)
        )
            revert InvalidReceiver(receiver);

        // Check if all withdrawal roots for the redemption have been provided
        for (uint256 i = 0; i < redemptionWithdrawalRoots.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < elActions; j++) {
                for (uint256 k = 0; k < withdrawalRoots[j].length; k++) {
                    if (withdrawalRoots[j][k] == redemptionWithdrawalRoots[i]) {
                        found = true;
                        break;
                    }
                }
                if (found) break;
            }
            if (!found) revert WithdrawalRootMissing(redemptionWithdrawalRoots[i]);
        }

        // Track cumulative expected token balances from completion of all withdrawals across all nodes
        IERC20[] memory uniqueTokens = new IERC20[](supportedTokens.length);
        uint256[] memory expectedAmounts = new uint256[](supportedTokens.length);
        uint256 uniqueTokenCount = 0;

        for (uint256 k = 0; k < elActions; k++) {
            uniqueTokenCount = _completeELWithdrawals(
                nodeIds[k], 
                withdrawalRoots[k],
                uniqueTokens,
                expectedAmounts,
                uniqueTokenCount
            );
        }

        // Verify receipt of all withdrawn assets, transfer them to `receiver` and update `WithdrawalManager`
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            IERC20 token = uniqueTokens[i];
            uint256 expectedAmount = expectedAmounts[i];
            uint256 actualBalance = token.balanceOf(address(this));
            
            if (actualBalance < expectedAmount) {
                revert RequestsDoNotSettle(
                    address(token),
                    expectedAmount,
                    actualBalance
                );
            }
            
            token.safeTransfer(receiver, expectedAmount);
        }

        withdrawalManager.recordRedemptionCompleted(redemptionId);
        emit RedemptionCompleted(redemptionId);

        // If receiver is `LiquidToken`, fulfillment is complete & no shares to be burnt
        if (receiver == address(liquidToken)) {
            liquidToken.debitQueuedAssetBalances(uniqueTokens, expectedAmounts, 0);
            liquidToken.creditAssetBalances(uniqueTokens, expectedAmounts);
        }
    }

    /// @notice For a given node ID, completes a set of withdrawals and keeps tracks of corresponding funds entering this contract
    /// @param nodeId The ID of the node to complete a set of EL withdrawals on
    /// @param withdrawalRoots The withdrawal roots of the EL withdrawals to complete
    /// @param uniqueTokens The set of all expected assets from all withdrawal completions across all nodes concerned with the redemption
    /// @param expectedAmounts The set of all expected amounts for all expected assets across all nodes concerned with the redemption
    /// @param uniqueTokenCount The length of `uniqueTokens`
    function _completeELWithdrawals(
        uint256 nodeId,
        bytes32[] calldata withdrawalRoots,
        IERC20[] memory uniqueTokens,
        uint256[] memory expectedAmounts,
        uint256 uniqueTokenCount
    ) private returns (uint256) {
        uint256 arrayLength = withdrawalRoots.length;

        IDelegationManager.Withdrawal[] memory nodeWithdrawals = 
            new IDelegationManager.Withdrawal[](arrayLength);
        IERC20[][] memory nodeTokens = new IERC20[][](arrayLength);
        
        IWithdrawalManager.ELWithdrawalRequest[] memory elRequests = 
            withdrawalManager.getELWithdrawalRequests(withdrawalRoots);

        // Track expected amounts for each token across all withdrawals
        for (uint256 i = 0; i < arrayLength; i++) {
            nodeWithdrawals[i] = elRequests[i].withdrawal;
            nodeTokens[i] = elRequests[i].assets;
            
            for (uint256 j = 0; j < elRequests[i].assets.length; j++) {
                IERC20 token = elRequests[i].assets[j];
                IStrategy strategy = tokenStrategies[token];
                uint256 amount = strategy.sharesToUnderlying(elRequests[i].withdrawal.shares[j]);
                
                bool found = false;
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (uniqueTokens[k] == token) {
                        expectedAmounts[k] += amount;
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    uniqueTokens[uniqueTokenCount] = token;
                    expectedAmounts[uniqueTokenCount++] = amount;
                }
            }
        }

        // Complete withdrawals on EL
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        node.completeWithdrawals(nodeWithdrawals, nodeTokens);

        return uniqueTokenCount;
    }

    /// @notice Updates the price of a token
    /// @param token Address of the token to update
    /// @param newPrice New price for the token
    function updatePrice(
        IERC20 token,
        uint256 newPrice
    ) external override onlyRole(PRICE_UPDATER_ROLE) {
        if (tokens[token].decimals == 0) revert TokenNotSupported(token);
        if (newPrice == 0) revert InvalidPrice();

        uint256 oldPrice = tokens[token].pricePerUnit;
        if (oldPrice == 0) revert InvalidPrice();

        if (tokens[token].volatilityThreshold != 0) {
            uint256 absPriceDiff = (newPrice > oldPrice)
                ? newPrice - oldPrice
                : oldPrice - newPrice;
            uint256 changeRatio = (absPriceDiff * 1e18) / oldPrice;
            
            if (changeRatio > tokens[token].volatilityThreshold) {
                emit VolatilityCheckFailed(token, oldPrice, newPrice, changeRatio);
                revert VolatilityThresholdHit(token, changeRatio);
            }
        }

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
    function getSupportedTokens() external view override returns (IERC20[] memory) {
        return supportedTokens;
    }

    /// @notice Retrieves the information for a specific token
    /// @param token Address of the token to get information for
    /// @return TokenInfo struct containing the token's information
    function getTokenInfo(
        IERC20 token
    ) external view override returns (TokenInfo memory) {
        if (address(token) == address(0)) revert ZeroAddress();

        TokenInfo memory tokenInfo = tokens[token];

        if (tokenInfo.decimals == 0) {
            revert TokenNotSupported(token);
        }

        return tokenInfo;
    }

    /// @notice Returns the strategy for a given asset
    /// @param asset Asset to get the strategy for
    /// @return IStrategy Interface for the corresponding strategy
    function getTokenStrategy(
        IERC20 asset
    ) external view override returns (IStrategy) {
        if (address(asset) == address(0)) revert ZeroAddress();

        IStrategy strategy = tokenStrategies[asset];

        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        return strategy;
    }

    /// @notice Returns the set of strategies for a given set of assets
    /// @param assets Set of assets to get the strategies for
    /// @return IStrategy Interfaces for the corresponding set of strategies
    function _getTokensStrategies(
        IERC20[] memory assets
    ) internal view returns (IStrategy[] memory) {
        IStrategy[] memory strategies = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            if (address(asset) == address(0)) revert ZeroAddress();

            IStrategy strategy = tokenStrategies[asset];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(asset));
            }

            strategies[i] = strategy;
        }
        
        return strategies;
    }

    /// @notice Gets the staked balance of an asset for all nodes
    /// @param asset The asset token address
    /// @return The staked balance of the asset for all nodes
    function getStakedAssetBalance(IERC20 asset) public view override returns (uint256) {
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

    /// @notice Gets the staked balance of an asset for a specific node
    /// @param asset The asset token address
    /// @param nodeId The ID of the node
    /// @return The staked balance of the asset for the node
    function getStakedAssetBalanceNode(
        IERC20 asset,
        uint256 nodeId
    ) public view override returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        return _getStakedAssetBalanceNode(asset, node);
    }

    /// @notice Gets the staked balance of an asset for a specific node
    /// @param asset The asset token address
    /// @param node The node to get the staked balance for
    /// @return The staked balance of the asset for the node
    function _getStakedAssetBalanceNode(
        IERC20 asset,
        IStakerNode node
    ) internal view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }
        return strategy.userUnderlyingView(address(node));
    }

    /// @notice Sets the volatility threshold for a given asset
    /// @param asset The asset token address
    /// @param newThreshold The new volatility threshold value to update to
    function setVolatilityThreshold(IERC20 asset, uint256 newThreshold) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(asset) == address(0)) revert ZeroAddress();
        if (tokens[asset].decimals == 0) revert TokenNotSupported(asset);
        if (newThreshold != 0 && (newThreshold < 1e16 || newThreshold > 1e18)) revert InvalidThreshold();

        emit VolatilityThresholdUpdated(asset, tokens[asset].volatilityThreshold, newThreshold, msg.sender);

        tokens[asset].volatilityThreshold = newThreshold;
    }
}
