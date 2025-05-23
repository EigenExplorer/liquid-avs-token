// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    uint256 public constant WITHDRAWAL_DELAY = 14 days;

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
            amounts: amounts,
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

    /// TODO: Account for slashing
    /// @notice Allows users to fulfill a withdrawal request after the delay period and receive all corresponding funds
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(
        bytes32 requestId
    ) external override nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY)
            revert WithdrawalDelayNotMet();
        if (request.canFulfill == false) revert WithdrawalNotReadyToFulfill();

        uint256[] memory amounts = new uint256[](request.assets.length);
        uint256 totalShares = 0;

        // Calculate the amount of shares to be burned on withdrawal
        for (uint256 i = 0; i < request.assets.length; i++) {
            amounts[i] = liquidToken.calculateAmount( // <-- wrong because we are already in native unit of asset
                    request.assets[i],
                    request.amounts[i]
                );
            totalShares += request.amounts[i];
        }

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            IERC20 asset = request.assets[i];

            if (asset.balanceOf(address(this)) < amount) {
                revert InsufficientBalance(
                    asset,
                    amount,
                    asset.balanceOf(address(this))
                );
            }

            asset.safeTransfer(msg.sender, amount);
        }

        // Fulfillment is complete and escrow shares to be burnt
        liquidToken.debitQueuedAssetBalances(
            request.assets,
            amounts,
            totalShares
        );

        emit WithdrawalFulfilled(
            requestId,
            msg.sender,
            request.assets,
            amounts,
            block.timestamp
        );

        delete withdrawalRequests[requestId];
        delete userWithdrawalRequests[msg.sender];
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
    /// @dev Slashing, if any, is accounted for here
    /// @dev The function back-calculates the % of funds slashed with the discrepancy between the
    /// @dev requested withdrawal amounts (recorded in `withdrawalRequests`) and the actual returned amounts
    /// @param redemptionId The ID of the redemption
    /// @param assets The set of assets that received from EL withdrawals
    /// @param receivedAmounts Total share amounts per asset that were received from EL withdrawals
    function recordRedemptionCompleted(
        bytes32 redemptionId,
        IERC20[] calldata assets,
        uint256[] calldata receivedAmounts
    ) external override returns (uint256[] memory) {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);
        if (receivedAmounts.length != assets.length) revert LengthMismatch();

        ILiquidTokenManager.Redemption memory redemption = redemptions[
            redemptionId
        ];

        // Calculate total requested shares per asset across all withdrawal requests
        uint256[] memory requestedAmounts = new uint256[](assets.length);

        for (uint256 i = 0; i < redemption.requestIds.length; i++) {
            bytes32 requestId = redemption.requestIds[i];
            WithdrawalRequest storage request = withdrawalRequests[requestId];

            if (request.user == address(0))
                revert WithdrawalRequestNotFound(requestId);

            for (uint256 j = 0; j < request.assets.length; j++) {
                for (uint256 k = 0; k < assets.length; k++) {
                    if (address(request.assets[j]) == address(assets[k])) {
                        requestedAmounts[k] += request.amounts[j];
                        break;
                    }
                }
            }
        }

        // Calculate slashing factors per asset by looking at the difference between
        // requested and received amounts (1e18 = 100% = nothing slashed)
        uint256[] memory slashingFactors = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            if (requestedAmounts[i] > 0) {
                slashingFactors[i] = Math.mulDiv(
                    receivedAmounts[i],
                    1e18,
                    requestedAmounts[i]
                );
            }
        }

        // Track total slashed amount per asset
        uint256[] memory totalSlashedAmounts = new uint256[](assets.length);

        // Slash requested amounts per asset from all withdrawal requests related to this redemption
        for (uint256 i = 0; i < redemption.requestIds.length; i++) {
            bytes32 requestId = redemption.requestIds[i];
            WithdrawalRequest storage request = withdrawalRequests[requestId];

            for (uint256 j = 0; j < request.assets.length; j++) {
                for (uint256 k = 0; k < assets.length; k++) {
                    if (address(request.assets[j]) == address(assets[k])) {
                        uint256 originalAmount = request.amounts[j];

                        // Apply slashing factor
                        request.amounts[j] = Math.mulDiv(
                            originalAmount,
                            slashingFactors[k],
                            1e18
                        );

                        // Calculate slashed amount and add to total
                        if (slashingFactors[k] < 1e18) {
                            uint256 slashedAmount = originalAmount -
                                request.amounts[j];
                            totalSlashedAmounts[k] += slashedAmount;
                        }
                        break;
                    }
                }
            }

            // Mark withdrawal as ready to fulfill
            request.canFulfill = true;
        }

        // Debit the slashed amounts, if any, from queued asset balances
        uint256 slashedCount = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (totalSlashedAmounts[i] > 0) {
                slashedCount++;
            }
        }

        if (slashedCount > 0) {
            IERC20[] memory slashedAssets = new IERC20[](slashedCount);
            uint256[] memory slashedAmounts = new uint256[](slashedCount);

            uint256 index = 0;
            for (uint256 i = 0; i < assets.length; i++) {
                if (totalSlashedAmounts[i] > 0) {
                    slashedAssets[index] = assets[i];
                    slashedAmounts[index] = totalSlashedAmounts[i];
                    index++;
                }
            }

            // No shares to burn and no corresponding credit, because funds are taken by AVS
            liquidToken.debitQueuedAssetBalances(
                slashedAssets,
                slashedAmounts,
                0
            );
        }

        // Delete the redemption
        delete redemptions[redemptionId];

        return requestedAmounts;
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
}
