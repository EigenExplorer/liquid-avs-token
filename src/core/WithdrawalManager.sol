// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
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
	
    /// @notice Role identifier for price update operations
    bytes32 public constant WITHDRAWAL_CONTROLLER_ROLE =
        keccak256("WITHDRAWAL_CONTROLLER_ROLE");

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
    
    /// @notice EigenLayer Withdrawals
    mapping(bytes32 => ELWithdrawalRequest) public elWithdrawalRequests;

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
    /// @param user The requsting user's address
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
            shareAmounts: amounts,
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

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY)
            revert WithdrawalDelayNotMet();
        if (request.canFulfill != false) revert WithdrawalNotReadyToFulfill();

        uint256[] memory amounts = new uint256[](request.assets.length);
        uint256 totalShares = 0;

        // Calculate amounts for each asset and transfer them to the user
        for (uint256 i = 0; i < request.assets.length; i++) {
            amounts[i] = liquidToken.calculateAmount(
                request.assets[i],
                request.shareAmounts[i]
            );
            totalShares += request.shareAmounts[i];
        }

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            IERC20 asset = request.assets[i];

            if (asset.balanceOf(address(this)) < amount ) {
                revert InsufficientBalance(
                    asset,
                    amount,
                    asset.balanceOf(address(this))
                );
            }

            asset.safeTransfer(msg.sender, amount);
        }

        // Fulfillment is complete and escrow shares to be burnt
        liquidToken.debitQueuedAssetBalances(request.assets, amounts, totalShares);

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
    /// @param withdrawals The withdrawal structs associated with the redemption, needed to complete withdrawal on EL
    /// @param assets The array assets associated with each withdrawal, needed to complete withdrawal on EL
    function recordRedemptionCreated(
        bytes32 redemptionId,
        ILiquidTokenManager.Redemption calldata redemption,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata assets
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);
        uint256 arrayLength = redemption.withdrawalRoots.length;

        if (
            withdrawals.length != arrayLength ||
            assets.length != arrayLength
        )
            revert LengthMismatch();

        // Record all EL withdrawals for the redemption
        for (uint256 i = 0; i < arrayLength; i++) {
            ELWithdrawalRequest memory elRequest = ELWithdrawalRequest({
                withdrawal: withdrawals[i],
                assets: assets[i]
            });
            elWithdrawalRequests[redemption.withdrawalRoots[i]] = elRequest;  
        }

        // Record the redemption
        redemptions[redemptionId] = redemption;
    }

    /// @notice Called by `LiquidTokenManger` when a redemption is completed
    /// @param redemptionId The ID of the redemption
    function recordRedemptionCompleted(
        bytes32 redemptionId
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);
        ILiquidTokenManager.Redemption memory redemption = redemptions[redemptionId];

        // Delete all EL withdrawals for the redemption
        for (uint256 i = 0; i < redemption.requestIds.length; i++) {
            withdrawalRequests[redemption.requestIds[i]].canFulfill = true;
            delete elWithdrawalRequests[redemption.withdrawalRoots[i]];
        }

        // Delete the redemption
        delete redemptions[redemptionId];
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
        WithdrawalRequest[] memory requests = new WithdrawalRequest[](arrayLength);

        for(uint256 i = 0; i < arrayLength; i++) {
            WithdrawalRequest memory request = withdrawalRequests[requestIds[i]];
            if (request.user == address(0)) revert WithdrawalRequestNotFound(requestIds[i]);
            requests[i] = request;
        }

        return requests;
    }

    /// @notice Returns all EL withdrawal request details for a set of withdrawal roots
    /// @param withdrawalRoots The EL withdrawal roots
    function getELWithdrawalRequests(
        bytes32[] calldata withdrawalRoots
    ) external view override returns (ELWithdrawalRequest[] memory) {
        uint256 arrayLength = withdrawalRoots.length;
        ELWithdrawalRequest[] memory elRequests = new ELWithdrawalRequest[](arrayLength);

        for(uint256 i = 0; i < arrayLength; i++) {
            ELWithdrawalRequest memory elRequest = elWithdrawalRequests[withdrawalRoots[i]];
            if (elRequest.assets.length == 0) revert ELWithdrawalRequestNotFound(withdrawalRoots[i]);
            elRequests[i] = elRequest;
        }

        return elRequests;
    }

    /// @notice Returns all redemption details for a given redemption ID
    /// @param redemptionId The ID of the redemption
    function getRedemption(
        bytes32 redemptionId
    ) external view override returns (ILiquidTokenManager.Redemption memory) {
        ILiquidTokenManager.Redemption memory redemption = redemptions[redemptionId];
        if (redemption.requestIds.length == 0) revert RedemptionNotFound(redemptionId);

        return redemption;
    }
}