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
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

/// @title WithdrawalManager
/// @notice Manages withdrawals between staker nodes and users
/// @dev Implements IWithdrawalManager and uses OpenZeppelin's upgradeable contracts
contract WithdrawalManager is IWithdrawalManager, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------

    /// @notice Maximum number of assets allowed in a single withdrawal request
    uint256 public constant MAX_WITHDRAWAL_ASSETS = 32;

    /// @notice Lock to prevent concurrent redemption completions
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice EigenLayer contracts
    IDelegationManager public delegationManager;

    /// @notice LAT contracts
    ILiquidToken public liquidToken;
    ILiquidTokenManager public liquidTokenManager;
    IStakerNodeCoordinator public stakerNodeCoordinator;

    /// @notice User Withdrawals
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

    /// @notice Redemptions
    mapping(bytes32 => ILiquidTokenManager.Redemption) public redemptions;

    /// @notice The delay between user withdrawal request and ability to withdraw from this contract
    uint256 public withdrawalDelay;

    /// @notice Reentrancy guard for redemption completion
    uint256 private _redemptionCompletionStatus;

    /// @notice Tracks if a withdrawal request is currently being processed
    mapping(bytes32 => bool) private _processingRequest;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IWithdrawalManager
    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (
            address(init.initialOwner) == address(0) ||
            address(init.liquidToken) == address(0) ||
            address(init.delegationManager) == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            address(init.stakerNodeCoordinator) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);

        delegationManager = init.delegationManager;
        liquidToken = init.liquidToken;
        liquidTokenManager = init.liquidTokenManager;
        stakerNodeCoordinator = init.stakerNodeCoordinator;

        withdrawalDelay = 14 days;
        _redemptionCompletionStatus = NOT_ENTERED;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IWithdrawalManager
    function createWithdrawalRequest(
        IERC20[] memory assets,
        uint256[] memory amounts,
        uint256 sharesDeposited,
        address user,
        bytes32 requestId
    ) external override nonReentrant {
        if (msg.sender != address(liquidToken)) revert NotLiquidToken(msg.sender);
        if (sharesDeposited == 0) revert ZeroAmount();
        if (assets.length != amounts.length) revert LengthMismatch();
        if (assets.length == 0) revert ZeroAmount();
        if (assets.length > MAX_WITHDRAWAL_ASSETS) revert ExceedsMaxAssets();
        if (user == address(0)) revert ZeroAddress();
        if (withdrawalRequests[requestId].user != address(0)) revert RequestAlreadyExists();

        uint256[] memory elWithdrawableShares = new uint256[](assets.length);

        // Check for duplicate assets and validate each asset
        for (uint256 i = 0; i < assets.length; i++) {
            if (address(assets[i]) == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();

            // Check for duplicates
            for (uint256 j = 0; j < i; j++) {
                if (assets[i] == assets[j]) revert DuplicateAsset(address(assets[i]));
            }

            // Validate asset is supported
            if (!liquidTokenManager.tokenIsSupported(assets[i])) {
                revert UnsupportedAsset(assets[i]);
            }

            elWithdrawableShares[i] = liquidTokenManager.assetUnderlyingToShares(assets[i], amounts[i]);
            if (elWithdrawableShares[i] == 0) revert ZeroAmount();
        }

        WithdrawalRequest memory request = WithdrawalRequest({
            user: user,
            assets: assets,
            requestedAmounts: amounts,
            elWithdrawableShares: elWithdrawableShares,
            sharesDeposited: sharesDeposited,
            requestTime: block.timestamp,
            canFulfill: false
        });

        withdrawalRequests[requestId] = request;
        userWithdrawalRequests[user].push(requestId);

        emit WithdrawalInitiated(
            requestId,
            user,
            assets,
            amounts,
            elWithdrawableShares,
            sharesDeposited,
            block.timestamp
        );
    }

    /// @inheritdoc IWithdrawalManager
    function fulfillWithdrawal(bytes32 requestId) external override nonReentrant {
        WithdrawalRequest memory request = withdrawalRequests[requestId];

        if (request.user == address(0)) revert InvalidWithdrawalRequest();
        if (request.user != msg.sender) revert UnauthorizedAccess(msg.sender);
        if (block.timestamp <= request.requestTime + withdrawalDelay) revert WithdrawalDelayNotMet();
        if (request.canFulfill == false) revert WithdrawalNotReadyToFulfill();

        // Prevent concurrent processing
        if (_processingRequest[requestId]) revert RequestBeingProcessed();
        _processingRequest[requestId] = true;

        // Build the amounts array from the user's withdrawable shares
        uint256[] memory amounts = new uint256[](request.assets.length);
        for (uint256 i = 0; i < request.assets.length; i++) {
            IERC20 asset = request.assets[i];
            uint256 requestedAmount = liquidTokenManager.assetSharesToUnderlying(
                asset,
                request.elWithdrawableShares[i]
            );
            uint256 availableBalance = asset.balanceOf(address(this));

            if (availableBalance < requestedAmount) {
                // Minor shortfalls shouldn't block withdrawals
                // Allow for 10bps tolerance to handle rounding differences
                uint256 tolerance = Math.mulDiv(requestedAmount, 10, 10000, Math.Rounding.Up);
                uint256 minAcceptableAmount = requestedAmount > tolerance ? requestedAmount - tolerance : 0;

                if (availableBalance < minAcceptableAmount) {
                    revert InsufficientBalance(asset, requestedAmount, availableBalance);
                }

                // Use available balance if within tolerance
                amounts[i] = availableBalance;
            } else {
                amounts[i] = requestedAmount;
            }
        }

        address user = request.user;
        IERC20[] memory assets = request.assets;

        // Delete withdrawal request first to prevent reentrancy
        delete withdrawalRequests[requestId];
        delete _processingRequest[requestId];

        // Remove from user's request list
        bytes32[] storage userRequests = userWithdrawalRequests[user];
        uint256 requestsLength = userRequests.length;
        for (uint256 i = 0; i < requestsLength; i++) {
            if (userRequests[i] == requestId) {
                userRequests[i] = userRequests[requestsLength - 1];
                userRequests.pop();
                break;
            }
        }

        // Transfer assets to user
        for (uint256 i = 0; i < assets.length; i++) {
            if (amounts[i] > 0) {
                assets[i].safeTransfer(user, amounts[i]);
            }
        }

        emit WithdrawalFulfilled(requestId, user, assets, amounts, block.timestamp);
    }

    /// @inheritdoc IWithdrawalManager
    function recordRedemptionCreated(
        bytes32 redemptionId,
        ILiquidTokenManager.Redemption calldata redemption
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);
        if (redemptions[redemptionId].requestIds.length > 0) revert RedemptionAlreadyExists();

        // Record the redemption
        redemptions[redemptionId] = redemption;
    }

    /// @inheritdoc IWithdrawalManager
    function recordRedemptionCompleted(
        bytes32 redemptionId,
        IERC20[] calldata receivedAssets,
        uint256[] calldata receivedElShares
    ) external override returns (uint256[] memory) {
        // Prevent concurrent redemption completions
        if (_redemptionCompletionStatus == ENTERED) revert ReentrantCall();
        _redemptionCompletionStatus = ENTERED;

        if (msg.sender != address(liquidTokenManager)) {
            _redemptionCompletionStatus = NOT_ENTERED;
            revert NotLiquidTokenManager(msg.sender);
        }
        if (receivedElShares.length != receivedAssets.length) {
            _redemptionCompletionStatus = NOT_ENTERED;
            revert LengthMismatch();
        }

        ILiquidTokenManager.Redemption memory redemption = redemptions[redemptionId];
        if (redemption.requestIds.length == 0) {
            _redemptionCompletionStatus = NOT_ENTERED;
            revert RedemptionNotFound(redemptionId);
        }

        // Check if this is a user withdrawal by checking if the first requestId corresponds to a user withdrawal request
        bool isUserWithdrawal = redemption.requestIds.length > 0 &&
            withdrawalRequests[redemption.requestIds[0]].user != address(0);

        uint256[] memory redemptionRequestedElShares = new uint256[](receivedAssets.length);
        uint256 latEscrowShares = 0;

        // Aggregate the total requested shares across all assets
        // For user withdrawals, we also aggregate the total escrow shares so that we can burn them
        if (isUserWithdrawal) {
            // First pass: calculate total LAT escrow shares
            for (uint256 i = 0; i < redemption.requestIds.length; i++) {
                bytes32 requestId = redemption.requestIds[i];
                WithdrawalRequest storage request = withdrawalRequests[requestId];
                if (request.user != address(0)) {
                    latEscrowShares += request.sharesDeposited;
                }
            }

            // Second pass: aggregate shares per asset
            for (uint256 i = 0; i < redemption.requestIds.length; i++) {
                bytes32 requestId = redemption.requestIds[i];
                WithdrawalRequest storage request = withdrawalRequests[requestId];

                for (uint256 j = 0; j < request.assets.length; j++) {
                    bool assetFound = false;
                    for (uint256 k = 0; k < receivedAssets.length; k++) {
                        if (address(request.assets[j]) == address(receivedAssets[k])) {
                            uint256 originalShares = request.elWithdrawableShares[j];
                            redemptionRequestedElShares[k] += originalShares;
                            assetFound = true;
                            break;
                        }
                    }
                    // Track if any assets were not found in receivedAssets
                    if (!assetFound && request.elWithdrawableShares[j] > 0) {
                        emit AssetNotReceived(requestId, request.assets[j], request.elWithdrawableShares[j]);
                    }
                }
            }
        } else {
            for (uint256 i = 0; i < redemption.assets.length; i++) {
                for (uint256 k = 0; k < receivedAssets.length; k++) {
                    if (address(redemption.assets[i]) == address(receivedAssets[k])) {
                        redemptionRequestedElShares[k] = redemption.elWithdrawableShares[i];
                        break;
                    }
                }
            }
        }

        // For user withdrawals, we apply any slashing that may have occurred during the withdrawal queue period
        if (isUserWithdrawal) {
            // Track distributed shares per asset to handle rounding and prevent any shares being "missed"
            uint256[] memory distributedShares = new uint256[](receivedAssets.length);

            for (uint256 i = 0; i < redemption.requestIds.length; i++) {
                bytes32 requestId = redemption.requestIds[i];
                WithdrawalRequest storage request = withdrawalRequests[requestId];
                if (request.user == address(0)) continue; // Skip if request was already fulfilled

                bool isLastRequest = (i == redemption.requestIds.length - 1);

                for (uint256 j = 0; j < request.assets.length; j++) {
                    for (uint256 k = 0; k < receivedAssets.length; k++) {
                        if (address(request.assets[j]) == address(receivedAssets[k])) {
                            uint256 originalShares = request.elWithdrawableShares[j];
                            uint256 totalOriginalShares = redemptionRequestedElShares[k];
                            uint256 totalReceivedShares = receivedElShares[k];

                            uint256 newShares;
                            if (totalOriginalShares > 0) {
                                if (isLastRequest && j == request.assets.length - 1) {
                                    // For the last asset of the last request, assign remaining shares to ensure exact accounting
                                    newShares = totalReceivedShares > distributedShares[k]
                                        ? totalReceivedShares - distributedShares[k]
                                        : 0;
                                } else {
                                    // Calculate proportional share: (originalShares * totalReceived) / totalOriginal
                                    newShares = Math.mulDiv(originalShares, totalReceivedShares, totalOriginalShares);
                                    distributedShares[k] += newShares;
                                }
                            } else {
                                newShares = 0;
                            }

                            request.elWithdrawableShares[j] = newShares;

                            if (newShares < originalShares) {
                                emit UserSlashed(requestId, request.user, request.assets[j], originalShares, newShares);
                            }
                            break;
                        }
                    }
                }

                // Mark withdrawal as ready to fulfill
                request.canFulfill = true;
            }
        }

        // Delete the redemption
        delete redemptions[redemptionId];

        // Clear the queued shares accounting -- here we don't apply the latest slashing as it was not part of the original credit
        // If the redemption is for rebalancing or undelegation, a corresponding credit to asset balances will be done in `completeRedemption`
        // If the redemption is for user withdrawals, we burn the escrow shares deposited by the user
        if (isUserWithdrawal) {
            liquidToken.debitQueuedAssetElShares(receivedAssets, redemptionRequestedElShares, latEscrowShares);
        } else {
            liquidToken.debitQueuedAssetElShares(receivedAssets, redemptionRequestedElShares, 0);
        }

        _redemptionCompletionStatus = NOT_ENTERED;
        return redemptionRequestedElShares;
    }

    /// @inheritdoc IWithdrawalManager
    function setWithdrawalDelay(uint256 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay < 7 days || newDelay > 30 days) {
            revert InvalidWithdrawalDelay(newDelay);
        }

        uint256 oldDelay = withdrawalDelay;
        withdrawalDelay = newDelay;

        emit WithdrawalDelayUpdated(oldDelay, newDelay);
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IWithdrawalManager
    function getUserWithdrawalRequests(address user) external view override returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

    /// @inheritdoc IWithdrawalManager
    function getWithdrawalRequests(
        bytes32[] calldata requestIds
    ) external view override returns (WithdrawalRequest[] memory) {
        uint256 arrayLength = requestIds.length;
        WithdrawalRequest[] memory requests = new WithdrawalRequest[](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            WithdrawalRequest memory request = withdrawalRequests[requestIds[i]];
            if (request.user == address(0)) revert WithdrawalRequestNotFound(requestIds[i]);
            requests[i] = request;
        }

        return requests;
    }

    /// @inheritdoc IWithdrawalManager
    function getRedemption(
        bytes32 redemptionId
    ) external view override returns (ILiquidTokenManager.Redemption memory) {
        ILiquidTokenManager.Redemption memory redemption = redemptions[redemptionId];
        if (redemption.requestIds.length == 0) revert RedemptionNotFound(redemptionId);

        return redemption;
    }
}