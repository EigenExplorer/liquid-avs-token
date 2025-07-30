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

        WithdrawalRequest memory request = WithdrawalRequest({
            user: user,
            assets: assets,
            requestedAmounts: amounts,
            withdrawableAmounts: amounts,
            sharesDeposited: sharesDeposited,
            requestTime: block.timestamp,
            canFulfill: false
        });

        withdrawalRequests[requestId] = request;
        userWithdrawalRequests[user].push(requestId);

        emit WithdrawalInitiated(requestId, user, assets, amounts, sharesDeposited, block.timestamp);
    }

    /// @inheritdoc IWithdrawalManager
    function fulfillWithdrawal(bytes32 requestId) external override nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user == address(0)) revert InvalidWithdrawalRequest();
        if (request.user != msg.sender) revert UnauthorizedAccess(msg.sender);
        if (block.timestamp <= request.requestTime + withdrawalDelay) revert WithdrawalDelayNotMet();
        if (request.canFulfill == false) revert WithdrawalNotReadyToFulfill();

        for (uint256 i = 0; i < request.assets.length; i++) {
            IERC20 asset = request.assets[i];
            uint256 amount = request.withdrawableAmounts[i];

            if (asset.balanceOf(address(this)) < amount) {
                revert InsufficientBalance(asset, amount, asset.balanceOf(address(this)));
            }
        }

        address user = request.user;
        IERC20[] memory assets = request.assets;
        uint256[] memory amounts = request.withdrawableAmounts;
        uint256 sharesDeposited = request.sharesDeposited;

        delete withdrawalRequests[requestId];
        bytes32[] storage userRequests = userWithdrawalRequests[user];
        for (uint256 i = 0; i < userRequests.length; i++) {
            if (userRequests[i] == requestId) {
                userRequests[i] = userRequests[userRequests.length - 1];
                userRequests.pop();
                break;
            }
        }

        // Fulfillment is complete
        liquidToken.debitQueuedAssetBalances(assets, amounts, sharesDeposited);

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
        uint256[] calldata receivedAmounts
    ) external override returns (uint256[] memory) {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);
        if (receivedAmounts.length != receivedAssets.length) revert LengthMismatch();

        ILiquidTokenManager.Redemption memory redemption = redemptions[redemptionId];

        // We have already accounted for slashing up until the point of creating the withdrawal request on EL
        // Now we compare the received amounts with the original withdrawable amounts (recorded during withdrawal request creation)
        // to check for any slashing during the withdrawal queue period
        uint256[] memory slashedFactors = new uint256[](receivedAssets.length);
        uint256[] memory slashedAmounts = new uint256[](receivedAssets.length);

        for (uint256 i = 0; i < receivedAssets.length; i++) {
            uint256 originalWithdrawableAmount = 0;
            bool assetFound = false;

            for (uint256 j = 0; j < redemption.assets.length; j++) {
                if (address(receivedAssets[i]) == address(redemption.assets[j])) {
                    originalWithdrawableAmount = redemption.withdrawableAmounts[j];
                    assetFound = true;
                    break;
                }
            }

            if (receivedAmounts[i] < originalWithdrawableAmount && originalWithdrawableAmount != 0) {
                slashedFactors[i] = (receivedAmounts[i] * 1e18) / originalWithdrawableAmount;

                slashedAmounts[i] = originalWithdrawableAmount - receivedAmounts[i];
            } else {
                slashedFactors[i] = 1e18;
                slashedAmounts[i] = 0;
            }
        }

        // Track the aggregated requested amounts per asset
        uint256[] memory redemptionRequestedAmounts = new uint256[](receivedAssets.length);

        // If the redemption is for user withdrawal, slash their withdrawable amounts by the slashing factor
        if (
            redemption.requestIds.length > 0 && withdrawalRequests[redemption.requestIds[0]].user != address(0) // If one user withdrawal is found, all requests are for user withdrawals
        ) {
            for (uint256 i = 0; i < redemption.requestIds.length; i++) {
                bytes32 requestId = redemption.requestIds[i];
                WithdrawalRequest storage request = withdrawalRequests[requestId];

                for (uint256 j = 0; j < request.assets.length; j++) {
                    for (uint256 k = 0; k < receivedAssets.length; k++) {
                        if (address(request.assets[j]) == address(receivedAssets[k])) {
                            uint256 originalAmount = request.requestedAmounts[j];
                            redemptionRequestedAmounts[k] += originalAmount;

                            // Slash the user's withdrawable amount by applying the slashed factor
                            request.withdrawableAmounts[j] = Math.mulDiv(originalAmount, slashedFactors[k], 1e18);

                            // Emit slashing event if amount was actually slashed
                            if (slashedFactors[k] < 1e18) {
                                emit UserSlashed(
                                    requestId,
                                    request.user,
                                    request.assets[j],
                                    originalAmount,
                                    request.withdrawableAmounts[j]
                                );
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

        // Account for withdrawal period slashing in queued withdrawal balances
        // If the redemption is for rebalancing or undelegation, all internal accounting will now be complete after this
        // If the redemption is for user withdrawals,
        //  - the queued balances will still contain the withdrawable amounts
        //  - the deposited escrow LAT shares are still to be burnt
        liquidToken.debitQueuedAssetBalances(receivedAssets, slashedAmounts, 0);

        return redemptionRequestedAmounts;
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
