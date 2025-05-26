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
contract WithdrawalManager is
    IWithdrawalManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    IDelegationManager public delegationManager;
    ILiquidToken public liquidToken;
    ILiquidTokenManager public liquidTokenManager;
    IStakerNodeCoordinator public stakerNodeCoordinator;

    uint256 public withdrawalDelay;

    /// @notice User Withdrawals
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

    /// @notice Redemptions
    mapping(bytes32 => ILiquidTokenManager.Redemption) public redemptions;

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param init Initialization parameters
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

    /// @notice Creates a withdrawal request for a user when they initate one via `LiquidToken`
    /// @param assets The final assets the the user wants to end up with
    /// @param amounts The withdrawal amounts per asset
    /// @param user The requesting user's address
    /// @param requestId The unique identifier of the withdrawal request
    function createWithdrawalRequest(
        IERC20[] memory assets,
        uint256[] memory amounts,
        address user,
        bytes32 requestId
    ) external override nonReentrant {
        if (msg.sender != address(liquidToken))
            revert NotLiquidToken(msg.sender);

        WithdrawalRequest memory request = WithdrawalRequest({
            user: user,
            assets: assets,
            requestedAmounts: amounts,
            withdrawableAmounts: amounts,
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
            block.timestamp
        );
    }

    /// @notice Allows users to fulfill a withdrawal request after the delay period and receive all corresponding funds
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(
        bytes32 requestId
    ) external override nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user == address(0)) revert InvalidWithdrawalRequest();
        if (request.user != msg.sender) revert UnauthorizedAccess(msg.sender);
        if (block.timestamp <= request.requestTime + withdrawalDelay)
            revert WithdrawalDelayNotMet();
        if (request.canFulfill == false) revert WithdrawalNotReadyToFulfill();

        for (uint256 i = 0; i < request.assets.length; i++) {
            IERC20 asset = request.assets[i];
            uint256 amount = request.withdrawableAmounts[i];

            if (asset.balanceOf(address(this)) < amount) {
                revert InsufficientBalance(
                    asset,
                    amount,
                    asset.balanceOf(address(this))
                );
            }
        }

        address user = request.user;
        IERC20[] memory assets = request.assets;
        uint256[] memory amounts = request.withdrawableAmounts;

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
        liquidToken.debitQueuedAssetBalances(assets, amounts);

        for (uint256 i = 0; i < assets.length; i++) {
            assets[i].safeTransfer(msg.sender, amounts[i]);
        }

        emit WithdrawalFulfilled(
            requestId,
            user,
            assets,
            amounts,
            block.timestamp
        );
    }

    /// @notice Called by `LiquidTokenManger` when a new redemption is created
    /// @param redemptionId The unique identifier of the redemption
    /// @param redemption The details of the redemption
    function recordRedemptionCreated(
        bytes32 redemptionId,
        ILiquidTokenManager.Redemption calldata redemption
    ) external override {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);

        // Record the redemption
        redemptions[redemptionId] = redemption;
    }

    /// @notice Called by `LiquidTokenManger` when a redemption is completed
    /// @dev If there was any slashing during the withdrawal queue period, its accounting is handled here
    /// @param redemptionId The ID of the redemption
    /// @param receivedAssets The set of assets that received from all EL withdrawals
    /// @param receivedAmounts Total amounts per for `receivedAssets` (after any slashing)
    function recordRedemptionCompleted(
        bytes32 redemptionId,
        IERC20[] calldata receivedAssets,
        uint256[] calldata receivedAmounts
    ) external override returns (uint256[] memory) {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);
        if (receivedAmounts.length != receivedAssets.length)
            revert LengthMismatch();

        ILiquidTokenManager.Redemption memory redemption = redemptions[
            redemptionId
        ];

        // We have already accounted for slashing up until the point of creating the withdrawal request on EL
        // Now we compare the received amounts with the original withdrawable amounts (recorded during withdrawal request creation)
        // to check for any slashing during the withdrawal queue period
        uint256[] memory slashedFactors = new uint256[](receivedAssets.length);
        uint256[] memory slashedAmounts = new uint256[](receivedAssets.length);

        for (uint256 i = 0; i < receivedAssets.length; i++) {
            uint256 originalWithdrawableAmount = 0;
            bool assetFound = false;

            for (uint256 j = 0; j < redemption.assets.length; j++) {
                if (
                    address(receivedAssets[i]) == address(redemption.assets[j])
                ) {
                    originalWithdrawableAmount = redemption.withdrawableAmounts[
                        j
                    ];
                    assetFound = true;
                    break;
                }
            }

            if (
                receivedAmounts[i] < originalWithdrawableAmount &&
                originalWithdrawableAmount != 0
            ) {
                slashedFactors[i] =
                    (receivedAmounts[i] * 1e18) /
                    originalWithdrawableAmount;

                slashedAmounts[i] =
                    originalWithdrawableAmount -
                    receivedAmounts[i];
            } else {
                slashedFactors[i] = 1e18;
                slashedAmounts[i] = 0;
            }
        }

        // Track the aggregated requested amounts per asset
        uint256[] memory redemptionRequestedAmounts = new uint256[](
            receivedAssets.length
        );

        // If the redemption is for user withdrawasl, slash their withdrawable amounts by the slashing factor
        if (
            redemption.requestIds.length > 0 &&
            withdrawalRequests[redemption.requestIds[0]].user != address(0) // If one user withdrawal is found, all requests are for user withdrawals
        ) {
            for (uint256 i = 0; i < redemption.requestIds.length; i++) {
                bytes32 requestId = redemption.requestIds[i];
                WithdrawalRequest storage request = withdrawalRequests[
                    requestId
                ];

                for (uint256 j = 0; j < request.assets.length; j++) {
                    for (uint256 k = 0; k < receivedAssets.length; k++) {
                        if (
                            address(request.assets[j]) ==
                            address(receivedAssets[k])
                        ) {
                            uint256 originalAmount = request.requestedAmounts[
                                j
                            ];
                            redemptionRequestedAmounts[k] += originalAmount;

                            // Slash the user's withdrawable amount by applying the slashed factor
                            request.withdrawableAmounts[j] = Math.mulDiv(
                                originalAmount,
                                slashedFactors[k],
                                1e18
                            );

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
        // If the redemption is for rebalancing or undelegation, all internal accounting will now be complete
        // If the redemption is for user withdrawals, the queued balances will still contain the withdrawable amounts
        liquidToken.debitQueuedAssetBalances(receivedAssets, slashedAmounts);

        return redemptionRequestedAmounts;
    }

    /// @notice Returns all withdrawal request IDs for a given user
    /// @param user The address of the user
    function getUserWithdrawalRequests(
        address user
    ) external view override returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

    /// @notice Returns all withdrawal request details for a set of request IDs
    /// @param requestIds The IDs of the withdrawal requests
    function getWithdrawalRequests(
        bytes32[] calldata requestIds
    ) external view override returns (WithdrawalRequest[] memory) {
        uint256 arrayLength = requestIds.length;
        WithdrawalRequest[] memory requests = new WithdrawalRequest[](
            arrayLength
        );

        for (uint256 i = 0; i < arrayLength; i++) {
            WithdrawalRequest memory request = withdrawalRequests[
                requestIds[i]
            ];
            if (request.user == address(0))
                revert WithdrawalRequestNotFound(requestIds[i]);
            requests[i] = request;
        }

        return requests;
    }

    /// @notice Returns all redemption details for a given redemption ID
    /// @param redemptionId The ID of the redemption
    function getRedemption(
        bytes32 redemptionId
    ) external view override returns (ILiquidTokenManager.Redemption memory) {
        ILiquidTokenManager.Redemption memory redemption = redemptions[
            redemptionId
        ];
        if (redemption.requestIds.length == 0)
            revert RedemptionNotFound(redemptionId);

        return redemption;
    }

    /// @notice Updates the withdrawal delay period
    /// @dev Only callable by admin role
    /// @param newDelay The new withdrawal delay in seconds
    function setWithdrawalDelay(
        uint256 newDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay < 7 days || newDelay > 30 days) {
            revert InvalidWithdrawalDelay(newDelay);
        }

        uint256 oldDelay = withdrawalDelay;
        withdrawalDelay = newDelay;

        emit WithdrawalDelayUpdated(oldDelay, newDelay);
    }
}
