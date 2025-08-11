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
import {ILSTSwapRouter} from "../interfaces/ILSTSwapRouter.sol";

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
    bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256("STRATEGY_CONTROLLER_ROLE");

    /// @notice Role identifier for asset price update operations
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");

    /// @notice Number of decimal places used for price representation
    uint256 public constant PRICE_DECIMALS = 18;

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
    ILSTSwapRouter public lstSwapRouter;

    /// @notice Constant for ETH address representation
    address private constant _ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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

        if (
            address(init.strategyManager) == address(0) ||
            address(init.delegationManager) == address(0) ||
            address(init.liquidToken) == address(0) ||
            address(init.initialOwner) == address(0) ||
            address(init.priceUpdater) == address(0) ||
            address(init.tokenRegistryOracle) == address(0) ||
            address(init.withdrawalManager) == address(0) ||
            address(init.lstSwapRouter) == address(0)
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
        withdrawalManager = init.withdrawalManager;
        lstSwapRouter = init.lstSwapRouter;
    }

    // ------------------------------------------------------------------------------
    // Admin functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ILiquidTokenManager
    function updateLSTSwapRouter(address newLstSwapRouter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newLstSwapRouter == address(0)) revert ZeroAddress();

        address oldLsr = address(lstSwapRouter);
        lstSwapRouter = ILSTSwapRouter(newLstSwapRouter);

        emit LSTSwapRouterUpdated(oldLsr, newLstSwapRouter, msg.sender);
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

        // Check for staked withdrawable balances
        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 len = nodes.length;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                uint256 stakedWithdrawableBalance = getWithdrawableAssetBalanceNode(token, nodes[i].getId(), true);
                if (stakedWithdrawableBalance > 0) {
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
        liquidToken.transferAssets(assets, amounts, address(this));

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

    /// @inheritdoc ILiquidTokenManager
    function swapAndStakeAssetsToNodes(
        NodeAllocationWithSwap[] calldata allocationsWithSwaps
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        for (uint256 i = 0; i < allocationsWithSwaps.length; i++) {
            NodeAllocationWithSwap memory allocationWithSwap = allocationsWithSwaps[i];
            _swapAndStakeAssetsToNode(
                allocationWithSwap.nodeId,
                allocationWithSwap.assetsToSwap,
                allocationWithSwap.amountsToSwap,
                allocationWithSwap.assetsToStake
            );
        }
    }

    /// @inheritdoc ILiquidTokenManager
    function swapAndStakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assetsToSwap,
        uint256[] memory amountsToSwap,
        IERC20[] memory assetsToStake
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        _swapAndStakeAssetsToNode(nodeId, assetsToSwap, amountsToSwap, assetsToStake);
    }

    /// @dev Called by `swapAndStakeAssetsToNode` and `swapAndStakeAssetsToNodes`
    /// @dev Flow: LTM >> DEX >> LTM (using LSR for routing data)
    function _swapAndStakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assetsToSwap,
        uint256[] memory amountsToSwap,
        IERC20[] memory assetsToStake
    ) internal {
        uint256 assetsLength = assetsToStake.length;

        if (assetsLength != assetsToSwap.length) {
            revert LengthMismatch(assetsLength, assetsToSwap.length);
        }
        if (assetsLength != amountsToSwap.length) {
            revert LengthMismatch(assetsLength, amountsToSwap.length);
        }

        // Validate that ETH is not used as direct tokenIn or tokenOut (only as bridge asset)
        for (uint256 i = 0; i < assetsLength; i++) {
            if (address(assetsToSwap[i]) == _ETH_ADDRESS) {
                revert ETHNotSupportedAsDirectToken(address(assetsToSwap[i]));
            }
            if (address(assetsToStake[i]) == _ETH_ADDRESS) {
                revert ETHNotSupportedAsDirectToken(address(assetsToStake[i]));
            }
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        // Find EigenLayer strategies for the given assets
        IStrategy[] memory strategiesForNode = new IStrategy[](assetsLength);
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assetsToStake[i]; // using `assetsToStake` not `assetsToSwap`
            if (amountsToSwap[i] == 0) {
                revert InvalidStakingAmount(amountsToSwap[i]);
            }
            IStrategy strategy = tokenStrategies[asset];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(asset));
            }
            strategiesForNode[i] = strategy;
        }

        // Bring unstaked assets in from `LiquidToken`
        liquidToken.transferAssets(assetsToSwap, amountsToSwap, address(this));

        uint256[] memory amountsToStake = new uint256[](assetsLength);

        // Swap using LSR - for every `tokenIn`, swap to corresponding `tokenOut`
        for (uint256 i = 0; i < assetsLength; i++) {
            address tokenIn = address(assetsToSwap[i]);
            address tokenOut = address(assetsToStake[i]);
            uint256 amountIn = amountsToSwap[i];

            if (tokenIn == tokenOut) {
                // No swap needed, direct stake
                amountsToStake[i] = amountIn;
            } else {
                // Get swap plan from LSR
                (, ILSTSwapRouter.MultiStepExecutionPlan memory plan) = lstSwapRouter.getCompleteMultiStepPlan(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    address(this) // LTM is the recipient
                );

                // Execute the swap plan step by step
                uint256 actualAmountOut = _executeLsrSwapPlan(tokenOut, plan);
                amountsToStake[i] = actualAmountOut;

                emit SwapExecuted(tokenIn, tokenOut, amountIn, actualAmountOut, nodeId);
            }
        }

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](assetsLength);

        // Transfer assets to node
        for (uint256 i = 0; i < assetsLength; i++) {
            depositAssets[i] = assetsToStake[i];
            depositAmounts[i] = amountsToStake[i];
            assetsToStake[i].safeTransfer(address(node), amountsToStake[i]);
        }

        emit AssetsSwappedAndStakedToNode(
            nodeId,
            assetsToSwap,
            amountsToSwap,
            assetsToStake,
            amountsToStake,
            msg.sender
        );

        // Call for node to deposit assets into EigenLayer
        node.depositAssets(depositAssets, depositAmounts, strategiesForNode);

        emit AssetsDepositedToEigenlayer(depositAssets, depositAmounts, strategiesForNode, address(node));
    }

    /// @dev Executes a swap plan from LSR following LTM >> DEX >> LTM flow
    /// @param tokenOut Output token address
    /// @param plan Execution plan from LSR
    /// @return actualAmountOut The actual amount received from the swap
    function _executeLsrSwapPlan(
        address tokenOut,
        ILSTSwapRouter.MultiStepExecutionPlan memory plan
    ) internal returns (uint256 actualAmountOut) {
        require(plan.steps.length > 0, "Empty swap plan");
        require(address(lstSwapRouter) != address(0), "LSR not configured");

        // Track balances before and after
        uint256 initialBalance = tokenOut == _ETH_ADDRESS
            ? address(this).balance
            : IERC20(tokenOut).balanceOf(address(this));

        // Execute each step in the plan
        for (uint256 i = 0; i < plan.steps.length; i++) {
            ILSTSwapRouter.SwapStep memory step = plan.steps[i];

            // Approve the target DEX to spend our tokens
            if (step.tokenIn != _ETH_ADDRESS) {
                IERC20(step.tokenIn).safeApprove(step.target, 0);
                IERC20(step.tokenIn).safeApprove(step.target, step.amountIn);
            }

            // Execute the swap on the DEX
            (bool success, bytes memory returnData) = step.target.call{value: step.value}(step.data);

            if (!success) {
                // Decode revert reason if possible
                if (returnData.length > 0) {
                    assembly {
                        let returnDataSize := mload(returnData)
                        revert(add(32, returnData), returnDataSize)
                    }
                } else {
                    revert("Swap execution failed");
                }
            }

            // Reset approval
            if (step.tokenIn != _ETH_ADDRESS) {
                IERC20(step.tokenIn).safeApprove(step.target, 0);
            }
        }

        // Calculate actual output amount
        uint256 finalBalance = tokenOut == _ETH_ADDRESS
            ? address(this).balance
            : IERC20(tokenOut).balanceOf(address(this));

        actualAmountOut = finalBalance - initialBalance;

        // Validate we received at least the minimum expected
        ILSTSwapRouter.SwapStep memory lastStep = plan.steps[plan.steps.length - 1];
        require(actualAmountOut >= lastStep.minAmountOut, "Insufficient output amount");

        return actualAmountOut;
    }

    /// @inheritdoc ILiquidTokenManager
    function undelegateNodes(uint256[] calldata nodeIds) external override onlyRole(STRATEGY_CONTROLLER_ROLE) {
        // Fetch and add all asset balances from the node to queued balances
        for (uint256 i = 0; i < nodeIds.length; i++) {
            _createRedemptionNodeUndelegation(nodeIds[i]);
        }
    }

    /// @dev Called by `undelegateNodes`
    function _createRedemptionNodeUndelegation(uint256 nodeId) private {
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(address(node));
        address delegatedTo = node.getOperatorDelegation();

        // Find strategies and deposit shares
        (IStrategy[] memory redemptionStrategies, uint256[] memory redemptionShares) = strategyManager.getDeposits(
            address(node)
        );

        // Find withdrawable shares
        (uint256[] memory redemptionElWithdrawableShares, ) = delegationManager.getWithdrawableShares(
            address(node),
            redemptionStrategies
        );

        // Undelegate node from EL Operator
        bytes32[] memory withdrawalRoots = node.undelegate();
        emit NodeUndelegated(nodeId, delegatedTo);

        // Construct withdrawal structs
        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](
            withdrawalRoots.length
        );
        IERC20[] memory redemptionAssets = new IERC20[](withdrawalRoots.length); // We can use a 1D array since every withdrawal corresponds to only 1 asset

        // The order of strategies in `withdrawalRoots[]` is the same as that of `redemptionStrategies[]`
        for (uint256 i = 0; i < withdrawalRoots.length; i++) {
            IStrategy[] memory requestStrategies = new IStrategy[](1);
            requestStrategies[0] = redemptionStrategies[i];

            redemptionAssets[i] = strategyTokens[redemptionStrategies[i]];

            uint256[] memory requestScaledShares = new uint256[](1);
            requestScaledShares[0] = _scaleSharesForNodeAsset(nodeId, redemptionAssets[i], redemptionShares[i]);

            IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
                staker: address(node),
                delegatedTo: node.getOperatorDelegation(),
                withdrawer: address(node),
                nonce: nonce++,
                startBlock: uint32(block.number),
                strategies: requestStrategies,
                scaledShares: requestScaledShares
            });

            // Make sure our withdrawal struct is the same as what EL computed
            if (withdrawalRoots[i] != keccak256(abi.encode(withdrawal))) revert InvalidWithdrawalRoot();

            withdrawals[i] = withdrawal;
        }

        // Credit queued asset shares with total withdrawable shares
        liquidToken.creditQueuedAssetElShares(redemptionAssets, redemptionElWithdrawableShares);

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256(abi.encode(redemptionAssets, redemptionShares, block.timestamp, _redemptionNonce));

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

    /// @inheritdoc ILiquidTokenManager
    function withdrawNodeAssets(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata elDepositShares
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 arrayLength = nodeIds.length;

        if (assets.length != arrayLength) revert LengthMismatch(assets.length, arrayLength);
        if (elDepositShares.length != arrayLength) revert LengthMismatch(elDepositShares.length, arrayLength);

        _createRedemptionRebalancing(nodeIds, assets, elDepositShares);
    }

    /// @dev Called by `withdrawNodeAssets`
    function _createRedemptionRebalancing(
        uint256[] calldata nodeIds,
        IERC20[][] calldata nodeAssets,
        uint256[][] calldata nodeElDepositShares
    ) internal {
        uint256 elActions = nodeIds.length;

        bytes32[] memory withdrawalRoots = new bytes32[](elActions);
        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](elActions);
        bytes32[] memory requestIds = new bytes32[](elActions);

        IERC20[] memory redemptionAssets = new IERC20[](supportedTokens.length);
        uint256[] memory redemptionElWithdrawableShares = new uint256[](supportedTokens.length);
        uint256 uniqueTokenCount = 0;

        for (uint256 i = 0; i < elActions; i++) {
            for (uint256 j = 0; j < nodeAssets[i].length; j++) {
                IERC20 asset = nodeAssets[i][j];
                uint256 proposedDepositShares = nodeElDepositShares[i][j];

                if (proposedDepositShares == 0) {
                    revert ZeroAmount();
                }

                uint256 depositShares = getDepositAssetBalanceNode(asset, nodeIds[i], true);
                // EL deposits for the asset must exist and cannot be less than proposed clawback amount
                if (depositShares == 0 || depositShares < proposedDepositShares) {
                    revert InsufficientBalance(asset, proposedDepositShares, depositShares);
                }

                uint256 withdrawableShares = getWithdrawableAssetBalanceNode(asset, nodeIds[i], true);

                bool found = false;
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (redemptionAssets[k] == asset) {
                        redemptionElWithdrawableShares[k] +=
                            (proposedDepositShares * withdrawableShares) /
                            depositShares; // Factor in any slashing
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    redemptionAssets[uniqueTokenCount] = asset;
                    redemptionElWithdrawableShares[uniqueTokenCount] =
                        (proposedDepositShares * withdrawableShares) /
                        depositShares; // Factor in any slashing
                    uniqueTokenCount++;
                }
            }

            // Call for EL withdrawals on staker node
            (withdrawalRoots[i], withdrawals[i]) = _createELWithdrawal(
                nodeIds[i],
                nodeAssets[i],
                nodeElDepositShares[i]
            );

            requestIds[i] = keccak256(
                abi.encode(nodeAssets[i], nodeElDepositShares[i], block.timestamp, i, _redemptionNonce)
            );
        }

        // Credit queued asset shares with total withdrawable shares
        // Here we specifically factor in any slashing of staked funds in order to maintain accurate values for AUM calc
        // If there is any additional slashing after this (during EL withdrawal queue period), we handle it in redemption completion
        liquidToken.creditQueuedAssetElShares(redemptionAssets, redemptionElWithdrawableShares);

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

    /// @inheritdoc ILiquidTokenManager
    function settleUserWithdrawals(
        bytes32[] calldata requestIds,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elDepositShares
    ) external override nonReentrant onlyRole(STRATEGY_CONTROLLER_ROLE) {
        uint256 elActions = nodeIds.length;

        if (elAssets.length != elActions) revert LengthMismatch(elAssets.length, elActions);
        if (elDepositShares.length != elActions) revert LengthMismatch(elDepositShares.length, elActions);

        // Check if all associated withdrawal requests actually get fulfilled from the input amounts
        (IERC20[] memory redemptionAssets, uint256[] memory redemptionElWithdrawableShares) = _verifyAllRequestsSettle(
            requestIds,
            nodeIds,
            elAssets,
            elDepositShares
        );

        // Create a redemption for the settlement by withdrawing from staker nodes
        _createRedemptionUserWithdrawals(
            requestIds,
            nodeIds,
            elAssets,
            elDepositShares,
            redemptionAssets,
            redemptionElWithdrawableShares
        );
    }

    /// @notice Checks if the cumulative amounts per asset once drawn would actually settle ALL user withdrawal requests
    /// @dev Called by `settleUserWithdrawals`
    function _verifyAllRequestsSettle(
        bytes32[] calldata requestIds,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elDepositShares
    ) internal returns (IERC20[] memory, uint256[] memory) {
        // Get all associated withdrawal requests (reverts for any invalid request id)
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests = withdrawalManager.getWithdrawalRequests(
            requestIds
        );

        uint256 uniqueTokenCount;
        IERC20[] memory redemptionAssets = new IERC20[](supportedTokens.length);
        uint256[] memory redemptionElDepositShares = new uint256[](supportedTokens.length);

        // Aggregate cumulative amounts that need to be settled, across all withdrawal requests,
        (uniqueTokenCount, redemptionAssets, redemptionElDepositShares) = _processWithdrawalRequests(
            withdrawalRequests
        );

        // Track the proposed amounts to be clawed back from nodes
        uint256[] memory proposedRedemptionElDepositShares = new uint256[](uniqueTokenCount);

        // Track the withdrawable amounts after slashing, for internal accounting
        // This allows correct AUM calc, where queued balances are checked, slashing is included
        uint256[] memory redemptionElWithdrawableShares = new uint256[](uniqueTokenCount);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            for (uint256 j = 0; j < elAssets[i].length; j++) {
                IERC20 token = elAssets[i][j];
                uint256 proposedDepositShares = elDepositShares[i][j];

                if (proposedDepositShares == 0) {
                    revert ZeroAmount();
                }

                uint256 depositShares = getDepositAssetBalanceNode(token, nodeIds[i], true);
                // EL deposits for the asset must exist and cannot be less than proposed clawback amount
                if (depositShares == 0 || depositShares < proposedDepositShares) {
                    revert InsufficientBalance(token, proposedDepositShares, depositShares);
                }

                uint256 withdrawableShares = getWithdrawableAssetBalanceNode(token, nodeIds[i], true);

                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (redemptionAssets[k] == token) {
                        proposedRedemptionElDepositShares[k] += proposedDepositShares;
                        redemptionElWithdrawableShares[k] +=
                            (proposedDepositShares * withdrawableShares) /
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
            uint256 upperMargin = Math.mulDiv(redemptionElDepositShares[i], 10, 10000, Math.Rounding.Up);
            uint256 lowerMargin = Math.mulDiv(redemptionElDepositShares[i], 10, 10000, Math.Rounding.Down);

            uint256 maxAllowed = redemptionElDepositShares[i] + upperMargin;
            uint256 minAllowed = redemptionElDepositShares[i] - lowerMargin;

            if (
                proposedRedemptionElDepositShares[i] > maxAllowed || proposedRedemptionElDepositShares[i] < minAllowed
            ) {
                revert RequestsDoNotSettle(
                    address(redemptionAssets[i]),
                    proposedRedemptionElDepositShares[i],
                    redemptionElDepositShares[i]
                );
            }
        }

        // Credit queued asset shares with total withdrawable amounts, post slashing
        // As noted above, here we specifically factor in any slashing to maintain accurate AUM calc
        // If there is any additional slashing after this (during EL withdrawal queue period), we handle it in redemption completion
        liquidToken.creditQueuedAssetElShares(redemptionAssets, redemptionElWithdrawableShares);

        return (redemptionAssets, redemptionElWithdrawableShares);
    }

    /// @dev Called by `_verifyAllRequestsSettle`
    function _processWithdrawalRequests(
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests
    )
        internal
        view
        returns (uint256 uniqueTokenCount, IERC20[] memory redemptionAssets, uint256[] memory redemptionElDepositShares)
    {
        redemptionAssets = new IERC20[](supportedTokens.length);
        redemptionElDepositShares = new uint256[](supportedTokens.length);
        uniqueTokenCount = 0;

        for (uint256 i = 0; i < withdrawalRequests.length; i++) {
            IWithdrawalManager.WithdrawalRequest memory request = withdrawalRequests[i];
            for (uint256 j = 0; j < request.assets.length; j++) {
                IERC20 token = request.assets[j];
                bool found = false;
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (redemptionAssets[k] == token) {
                        redemptionElDepositShares[k] += request.elWithdrawableShares[j]; // These are deposit shares for now, we will slash them on redemption completion
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    redemptionAssets[uniqueTokenCount] = token;
                    redemptionElDepositShares[uniqueTokenCount] = request.elWithdrawableShares[j]; // These are deposit shares for now, we will slash them on redemption completion
                    uniqueTokenCount++;
                }
            }
        }
    }

    /// @notice Creates a redemption for the unstaked funds portion of a user withdrawals settlement
    /// @dev Called by `settleUserWithdrawals`
    function _createRedemptionUserWithdrawals(
        bytes32[] calldata requestIds,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elDepositShares,
        IERC20[] memory redemptionAssets,
        uint256[] memory redemptionElWithdrawableShares
    ) internal {
        bytes32[] memory withdrawalRoots = new bytes32[](nodeIds.length);
        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](
            nodeIds.length
        );

        // Call for EL withdrawals on staker nodes with the unscaled deposit shares
        for (uint256 i = 0; i < nodeIds.length; i++) {
            (withdrawalRoots[i], withdrawals[i]) = _createELWithdrawal(nodeIds[i], elAssets[i], elDepositShares[i]);
        }

        emit RedemptionCreatedForUserWithdrawals(
            _createRedemption(
                requestIds,
                withdrawalRoots,
                redemptionAssets,
                redemptionElWithdrawableShares,
                address(withdrawalManager)
            ),
            requestIds,
            withdrawalRoots,
            withdrawals,
            elAssets,
            nodeIds
        );
    }

    /// @dev Called by `_createRedemptionRebalancing` & `_createRedemptionUserWithdrawals`
    /// @dev When EL withdrawal is to be completed, the `withdrawal` and `assets` need to be provided, hence we store this data
    function _createELWithdrawal(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares
    ) private returns (bytes32, IDelegationManagerTypes.Withdrawal memory) {
        if (assets.length != shares.length) revert LengthMismatch(assets.length, shares.length);

        // Build the Withdrawal struct
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        IStrategy[] memory strategies = getTokensStrategies(assets);
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        uint256[] memory scaledShares = _scaleSharesForNode(nodeId, assets, shares);

        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
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
        if (withdrawalRoot != keccak256(abi.encode(withdrawal))) revert InvalidWithdrawalRoot();

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
        bytes32 redemptionId = keccak256(abi.encode(requestIds, withdrawalRoots, block.timestamp, _redemptionNonce));
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
        uint256 elActions = nodeIds.length;

        if (withdrawals.length != elActions) revert LengthMismatch(withdrawals.length, elActions);
        if (assets.length != elActions) revert LengthMismatch(withdrawals.length, elActions);

        // Reverts for invalid `redemptionId`
        Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);

        address receiver = redemption.receiver;
        if (receiver != address(withdrawalManager) && receiver != address(liquidToken))
            revert InvalidReceiver(receiver);

        // Check if the exact set of withdrawals concerned the redemption have been provided
        // Partial completion of a redemption is not accepted
        // Withdrawals that weren't part of the original redemption are not accepted
        bytes32[] memory redemptionWithdrawalRoots = redemption.withdrawalRoots;
        uint256 totalWithdrawals = 0;
        for (uint256 j = 0; j < elActions; j++) {
            totalWithdrawals += withdrawals[j].length;
        }

        bytes32[] memory allWithdrawalHashes = new bytes32[](totalWithdrawals);
        uint256 index = 0;
        for (uint256 j = 0; j < elActions; j++) {
            for (uint256 k = 0; k < withdrawals[j].length; k++) {
                allWithdrawalHashes[index++] = keccak256(abi.encode(withdrawals[j][k]));
            }
        }

        for (uint256 i = 0; i < redemptionWithdrawalRoots.length; i++) {
            bool found = false;
            for (uint256 h = 0; h < allWithdrawalHashes.length; h++) {
                if (allWithdrawalHashes[h] == redemptionWithdrawalRoots[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert WithdrawalMissing(redemptionWithdrawalRoots[i]);
        }

        // Track unique tokens received from completion of all withdrawals across all nodes
        IERC20[] memory receivedTokens = new IERC20[](supportedTokens.length);
        uint256 uniqueTokenCount = 0;

        for (uint256 k = 0; k < elActions; k++) {
            uniqueTokenCount = _completeELWithdrawals(
                nodeIds[k],
                withdrawals[k],
                assets[k],
                receivedTokens,
                uniqueTokenCount
            );
        }

        // Keep track of the actual amounts received
        // This may differ from the original requested amounts in the `Withdrawal` struct due to slashing
        uint256[] memory receivedAmounts = new uint256[](supportedTokens.length);
        uint256[] memory receivedElShares = new uint256[](supportedTokens.length);

        // Transfer all withdrawn assets to `receiver`, either `LiquidToken` or `WithdrawalManager`
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            IERC20 token = receivedTokens[i];
            uint256 balance = token.balanceOf(address(this));
            receivedAmounts[i] = balance;
            receivedElShares[i] = tokenStrategies[token].underlyingToSharesView(balance);

            if (balance > 0) {
                token.safeTransfer(receiver, balance);
            }
        }

        // Update Withdrawal Manager and retrieve the original requested shares
        uint256[] memory requestedElShares = withdrawalManager.recordRedemptionCompleted(
            // Accounting for any slashing during withdrawal queue period handled here
            redemptionId,
            receivedTokens,
            receivedElShares
        );

        // If receiver is `LiquidToken`, we follow the debit done in `recordRedemptionCreated` with a corresponding credit to asset balances
        if (receiver == address(liquidToken)) {
            liquidToken.creditAssetBalances(receivedTokens, receivedAmounts);
        }

        emit RedemptionCompleted(redemptionId, receivedTokens, requestedElShares, receivedAmounts);
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
        IERC20[] memory receivedTokens = node.completeWithdrawals(withdrawals, assets);

        // Track received tokens
        for (uint256 j = 0; j < receivedTokens.length; j++) {
            IERC20 token = receivedTokens[j];

            bool found = false;
            for (uint256 k = 0; k < uniqueTokenCount; k++) {
                if (uniqueTokens[k] == token) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                uniqueTokens[uniqueTokenCount++] = token;
            }
        }

        return uniqueTokenCount;
    }

    /// @dev Called by `_createELWithdrawal`
    function _scaleSharesForNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares
    ) internal view returns (uint256[] memory) {
        address nodeAddress = address(stakerNodeCoordinator.getNodeById(nodeId));
        uint256[] memory scaledShares = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            scaledShares[i] = shares[i].mulDiv(
                delegationManager.depositScalingFactor(nodeAddress, tokenStrategies[assets[i]]),
                1e18
            );
        }

        return scaledShares;
    }

    /// @dev Called by `_createRedemptionNodeUndelegation`,
    function _scaleSharesForNodeAsset(uint256 nodeId, IERC20 asset, uint256 shares) internal view returns (uint256) {
        address nodeAddress = address(stakerNodeCoordinator.getNodeById(nodeId));

        uint256 scaledSharesAsset = 0;

        scaledSharesAsset = shares.mulDiv(
            delegationManager.depositScalingFactor(nodeAddress, tokenStrategies[asset]),
            1e18
        );

        return scaledSharesAsset;
    }

    /// @notice Fallback to receive ETH from swaps
    receive() external payable {
        // Accept ETH from DEX swaps
    }

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
    function getTokensStrategies(IERC20[] memory assets) public view returns (IStrategy[] memory) {
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
    function getDepositAssetBalance(IERC20 asset, bool inElShares) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += _getDepositAssetBalanceNode(asset, nodes[i], inElShares);
        }

        return totalBalance;
    }

    /// @inheritdoc ILiquidTokenManager
    function getDepositAssetBalanceNode(IERC20 asset, uint256 nodeId, bool inElShares) public view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        return _getDepositAssetBalanceNode(asset, node, inElShares);
    }

    /// @dev Called by `getDepositAssetBalance` and `getDepositAssetBalanceNode`
    function _getDepositAssetBalanceNode(
        IERC20 asset,
        IStakerNode node,
        bool inElShares
    ) internal view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }
        return inElShares ? strategy.shares(address(node)) : strategy.userUnderlyingView(address(node));
    }

    /// @inheritdoc ILiquidTokenManager
    function getWithdrawableAssetBalance(IERC20 asset, bool inElShares) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            totalBalance += _getWithdrawableAssetBalanceNode(asset, nodes[i], inElShares);
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
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        return _getWithdrawableAssetBalanceNode(asset, node, inElShares);
    }

    /// @dev Called by `getWithdrawableAssetBalance` and `getWithdrawableAssetBalanceNode`
    function _getWithdrawableAssetBalanceNode(
        IERC20 asset,
        IStakerNode node,
        bool inElShares
    ) internal view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;

        (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(address(node), strategies);

        if (withdrawableShares[0] == 0) {
            return 0;
        }

        return inElShares ? withdrawableShares[0] : strategy.sharesToUnderlyingView(withdrawableShares[0]);
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

    /// @inheritdoc ILiquidTokenManager
    function assetSharesToUnderlying(IERC20 asset, uint256 amount) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        return strategy.sharesToUnderlyingView(amount);
    }

    /// @inheritdoc ILiquidTokenManager
    function assetUnderlyingToShares(IERC20 asset, uint256 amount) external view returns (uint256) {
        IStrategy strategy = tokenStrategies[asset];
        if (address(strategy) == address(0)) {
            revert StrategyNotFound(address(asset));
        }

        return strategy.underlyingToSharesView(amount);
    }
}
