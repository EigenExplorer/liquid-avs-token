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

        // Check for pending withdrawals of this token
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = token;
        if (liquidToken.balanceAssets(assets)[0] > 0) revert TokenInUse(token);

        // Additional check for any nodes with outstanding shares of this token
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

    /// @notice Internal function to stake assets to a node
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

        liquidToken.transferAssets(assets, amounts, address(this));

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        for (uint256 i = 0; i < assetsLength; i++) {
            depositAssets[i] = assets[i];
            depositAmounts[i] = amounts[i];
            assets[i].safeTransfer(address(node), amounts[i]);
        }

        emit AssetsStakedToNode(nodeId, assets, amounts, msg.sender);

        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(
            depositAssets,
            depositAmounts,
            strategiesForNode,
            address(node)
        );
    }

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateNodes(
        uint256[] calldata nodeIds
    ) external override onlyRole(STRATEGY_CONTROLLER_ROLE) {
        for (uint256 i = 0; i < nodeIds.length; i++) {
            _createRedemptionForNodeUndelegation(nodeIds[i]);
        }
    }

    function _createRedemptionForNodeUndelegation(uint256 nodeId) private {
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        (IStrategy[] memory strategies, uint256[] memory shares) = strategyManager.getDeposits(staker);
        bytes32[] memory withdrawalRoots = node.undelegate();

        emit NodeUndelegated(nodeId, delegatedTo);

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
                nonce: nonce,
                startBlock: uint32(block.number),
                strategies: requestStrategies,
                shares: requestShares
            });

            if (withdrawalRoots[i] != keccak256(abi.encode(withdrawal)))
                revert InvalidWithdrawalRoot();

            IERC20[] memory requestAssets = new IERC20[](1);
            requestAssets[0] = strategyTokens[strategies[i]];

            liquidToken.creditQueuedAssetBalances(requestAssets, requestShares);

            withdrawals[i] = withdrawal;
            assets[i] = requestAssets;
        }

        // Update `WithdrawalManager` with the new redemption 
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0]  = keccak256(abi.encode(withdrawalRoots));

        bytes32 redemptionId = keccak256(
            abi.encodePacked(
                requestIds,
                withdrawalRoots,
                _redemptionNonce++
            )
        );
        
        withdrawalManager.recordRedemptionCreated(redemptionId, requestIds, withdrawalRoots, withdrawals, assets);
        emit RedemptionCreatedForNodeUndelegation(redemptionId, requestIds[0], withdrawalRoots, nodeId);
    }

    /// @notice Enables settlement of a set of withdrawal requests by directing funds from `LiquidToken` and staker nodes into `WithdrawalManager`
    /// @dev A redemption is an intent to make a certain amount of funds available to be withdrawn from `WithdrawalManager`
    /// @dev This function accepts a redemption only if it will actually retrieve enough funds per token to settle ALL user withdrawal requests
    function createRedemptionForUserWithdrawals(
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

        // Check if all provided requests can be fulfilled if once the redemption is successful
        _checkRedemptionSettlesRequests(requestIds, ltAssets, ltAmounts, nodeIds, elAssets, elShares);

        // Direct unstaked funds from `LiquidToken` to `WithdrawalManager`
        liquidToken.transferAssets(ltAssets, ltAmounts, address(withdrawalManager));

        // Call for EL withdrawals on staker nodes
        bytes32[] memory withdrawalRoots = new bytes32[](elActions);
        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](elActions);
        IERC20[][] memory assets = new IERC20[][](elActions);

        for (uint256 i = 0; i < elActions; i++) {
            (withdrawalRoots[i], withdrawals[i], assets[i]) = _createELWithdrawal(
                nodeIds[i],
                elAssets[i],
                elShares[i]
            );
        }

        // Update `WithdrawalManager` with the new redemption 
        bytes32 redemptionId = keccak256(
            abi.encodePacked(
                requestIds,
                withdrawalRoots,
                _redemptionNonce++
            )
        );

        withdrawalManager.recordRedemptionCreated(redemptionId, requestIds, withdrawalRoots, withdrawals, assets);
        emit RedemptionCreatedForUserWithdrawals(redemptionId, requestIds, withdrawalRoots, nodeIds);
    }

    function _checkRedemptionSettlesRequests(
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

        for(uint256 i = 0; i < withdrawalRequests.length; i++) {
            IWithdrawalManager.WithdrawalRequest memory request = withdrawalRequests[i];
            for (uint256 j = 0; j < request.assets.length; j++) {
                IERC20 token = request.assets[j];
                
                bool found = false;
                for(uint256 k = 0; k < uniqueTokenCount; k++) {
                    if(requestTokens[k] == token) {
                        requestAmounts[k] += request.shareAmounts[j];
                        found = true;
                        break;
                    }
                }
                
                if(!found) {
                    requestTokens[uniqueTokenCount] = token;
                    requestAmounts[uniqueTokenCount++] = request.shareAmounts[j];
                }
            }
        }

        // Gather the cumulative expected amounts per token from the redemption
        uint256[] memory expectedRedemptionAmounts = new uint256[](uniqueTokenCount);

        // From `LiquidToken` unstaked funds
        for (uint256 i = 0; i < ltAssets.length; i++) {
            IERC20 token = ltAssets[i];
            uint256 amount = ltAmounts[i];
            
            if (token.balanceOf(address(liquidToken)) < amount)
                revert InsufficientBalance(
                    token,
                    amount,
                    token.balanceOf(address(liquidToken))
            );

            for (uint256 j = 0; j < uniqueTokenCount; j++) {
                if (requestTokens[j] == token) {
                    expectedRedemptionAmounts[j] += amount;
                    break;
                }
            }
        }

        // From staker node withdrawals
        for (uint256 i = 0; i < nodeIds.length; i++) {
            IERC20[] memory nodeAssets = elAssets[i];
            uint256[] memory nodeShares = elShares[i];
            
            if (nodeShares.length != nodeAssets.length) {
                revert LengthMismatch(nodeShares.length, nodeAssets.length);
            }
            
            for (uint256 j = 0; j < nodeAssets.length; j++) {
                IERC20 token = nodeAssets[j];
                uint256 amount = nodeShares[j];

                uint256 assetBalanceNode = getStakedAssetBalanceNode(token, nodeIds[i]);
                if (assetBalanceNode < amount) {
                    revert InsufficientBalance(
                        token,
                        amount,
                        assetBalanceNode
                    );
                }
                
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (requestTokens[k] == token) {
                        expectedRedemptionAmounts[k] += amount;
                        break;
                    }
                }
            }
        }

        // Verify that the redemption will actually settle all requests
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            if (expectedRedemptionAmounts[i] != requestAmounts[i]) {
                revert RedemptionDoesNotSettleRequests(
                    address(requestTokens[i]),
                    expectedRedemptionAmounts[i],
                    requestAmounts[i]
                );
            }
        }

        // Credit queued asset balances as these amounts would be removed from liquid token & staker nodes
        liquidToken.creditQueuedAssetBalances(requestTokens, requestAmounts);
    }

    function _createELWithdrawal(
        uint256 nodeId,
        IERC20[] calldata assets,
        uint256[] calldata shares
    ) private returns (bytes32, IDelegationManager.Withdrawal memory, IERC20[] memory) {
        IStrategy[] memory strategies = _getTokensStrategies(assets);
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        bytes32 withdrawalRoot = node.withdraw(strategies, shares);

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: staker,
            delegatedTo: delegatedTo,
            withdrawer: staker,
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            shares: shares
        });

        if (withdrawalRoot != keccak256(abi.encode(withdrawal))) 
            revert InvalidWithdrawalRoot();
        
        return (withdrawalRoot, withdrawal, assets);
    }

    function completeRedemption(
        bytes32 redemptionId,
        uint256[] calldata nodeIds,
        bytes32[][] calldata withdrawalRoots,
        address receiver
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        if (receiver != address(withdrawalManager) || receiver != address(liquidToken))
            revert InvalidReceiver(receiver);

        uint256 elActions = nodeIds.length;

        if (withdrawalRoots.length != elActions) 
            revert LengthMismatch(withdrawalRoots.length, elActions);

        Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        bytes32[] memory redemptionWithdrawalRoots = redemption.withdrawalRoots;

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

        // Track expected tokens & balances from completing all withdrawals
        IERC20[] memory uniqueTokens = new IERC20[](supportedTokens.length);
        uint256[] memory expectedAmounts = new uint256[](supportedTokens.length);
        uint256 uniqueTokenCount = 0;

        for (uint256 k = 0; k < elActions; k++) {
            _completeELWithdrawals(
                nodeIds[k], 
                withdrawalRoots[k],
                uniqueTokens,
                expectedAmounts,
                uniqueTokenCount
            );
        }

        // Verify receipt of all withdrawn assets, transfer them to `WithdrawalManager` and update its state
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            IERC20 token = uniqueTokens[i];
            uint256 expectedAmount = expectedAmounts[i];
            uint256 actualBalance = token.balanceOf(address(this));
            
            if (actualBalance < expectedAmount) {
                revert RedemptionDoesNotSettleRequests(
                    address(token),
                    expectedAmount,
                    actualBalance
                );
            }
            
            token.safeTransfer(receiver, expectedAmount);
        }

        // If funds are sent to `LiquidToken` the redemption is from node undelegation; fulfillment is complete & no shares to be burnt
        if (receiver == address(liquidToken)) {
            liquidToken.debitQueuedAssetBalances(uniqueTokens, expectedAmounts, 0);
        }

        withdrawalManager.recordRedemptionCompleted(redemptionId, redemption.requestIds);
        emit RedemptionCompleted(redemptionId);
    }

    function _completeELWithdrawals(
        uint256 nodeId,
        bytes32[] calldata withdrawalRoots,
        IERC20[] memory uniqueTokens,
        uint256[] memory expectedAmounts,
        uint256 uniqueTokenCount
    ) private {
        uint256 arrayLength = withdrawalRoots.length;

        IDelegationManager.Withdrawal[] memory nodeWithdrawals = 
            new IDelegationManager.Withdrawal[](arrayLength);
        IERC20[][] memory nodeTokens = new IERC20[][](arrayLength);
        
        IWithdrawalManager.ELWithdrawalRequest[] memory elRequests = 
            withdrawalManager.getELWithdrawalRequests(withdrawalRoots);

        for (uint256 i = 0; i < arrayLength; i++) {
            nodeWithdrawals[i] = elRequests[i].withdrawal;
            nodeTokens[i] = elRequests[i].assets;
            
            // Track expected amounts for each token
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

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        node.completeWithdrawals(nodeWithdrawals, nodeTokens);
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
        IERC20[] calldata assets
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

    /// @notice Gets the staked balance of all assets for a specific node
    /// @param node The node to get the staked balance for
    /// @return The staked balances of all assets for the node
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
