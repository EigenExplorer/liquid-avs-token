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

        uint256[] memory elWithdrawableShares = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            elWithdrawableShares[i] = liquidTokenManager.assetUnderlyingToShares(assets[i], amounts[i]);
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
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user == address(0)) revert InvalidWithdrawalRequest();
        if (request.user != msg.sender) revert UnauthorizedAccess(msg.sender);
        if (block.timestamp <= request.requestTime + withdrawalDelay) revert WithdrawalDelayNotMet();
        if (request.canFulfill == false) revert WithdrawalNotReadyToFulfill();

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
                uint256 minAcceptableAmount = requestedAmount - tolerance;

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

        delete withdrawalRequests[requestId];
        bytes32[] storage userRequests = userWithdrawalRequests[user];
        for (uint256 i = 0; i < userRequests.length; i++) {
            if (userRequests[i] == requestId) {
                userRequests[i] = userRequests[userRequests.length - 1];
                userRequests.pop();
                break;
            }
        }

        for (uint256 i = 0; i < assets.length; i++) {
            assets[i].safeTransfer(msg.sender, amounts[i]);
        }

        emit WithdrawalFulfilled(requestId, user, assets, amounts, block.timestamp);
    }

    /// @inheritdoc IWithdrawalManager
    function recordRedemptionCreated(
        bytes32 redemptionId,
        ILiquidTokenManager.Redemption calldata redemption
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        // Record the redemption
        redemptions[redemptionId] = redemption;
    }

    /// @inheritdoc IWithdrawalManager
    function recordRedemptionCompleted(
        bytes32 redemptionId,
        IERC20[] calldata receivedAssets,
        uint256[] calldata receivedElShares
    ) external override returns (uint256[] memory) {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);
        if (receivedElShares.length != receivedAssets.length) revert LengthMismatch();

        ILiquidTokenManager.Redemption memory redemption = redemptions[redemptionId];

        // Check if this is a user withdrawal by checking if the first requestId corresponds to a user withdrawal request
        bool isUserWithdrawal = redemption.requestIds.length > 0 &&
            withdrawalRequests[redemption.requestIds[0]].user != address(0);

        uint256[] memory redemptionRequestedElShares = new uint256[](receivedAssets.length);
        uint256 latEscrowShares = 0;

        // Aggregate the total requested shares across all assets
        // For user withdrawals, we also aggregate the total escrow shares so that we can burn them
        if (isUserWithdrawal) {
            for (uint256 i = 0; i < redemption.requestIds.length; i++) {
                bytes32 requestId = redemption.requestIds[i];
                WithdrawalRequest storage request = withdrawalRequests[requestId];

                for (uint256 j = 0; j < request.assets.length; j++) {
                    for (uint256 k = 0; k < receivedAssets.length; k++) {
                        if (address(request.assets[j]) == address(receivedAssets[k])) {
                            uint256 originalShares = request.elWithdrawableShares[j];
                            redemptionRequestedElShares[k] += originalShares;
                            latEscrowShares += request.sharesDeposited;
                            break;
                        }
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
                bool isLastRequest = (i == redemption.requestIds.length - 1);

                for (uint256 j = 0; j < request.assets.length; j++) {
                    for (uint256 k = 0; k < receivedAssets.length; k++) {
                        if (address(request.assets[j]) == address(receivedAssets[k])) {
                            uint256 originalShares = request.elWithdrawableShares[j];
                            uint256 totalOriginalShares = redemptionRequestedElShares[k];
                            uint256 totalReceivedShares = receivedElShares[k];

                            uint256 newShares;
                            if (totalOriginalShares > 0) {
                                if (isLastRequest) {
                                    // For the last request, assign remaining shares to ensure exact accounting
                                    newShares = totalReceivedShares - distributedShares[k];
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
