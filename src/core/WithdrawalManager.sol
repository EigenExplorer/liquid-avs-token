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
    
    /// @notice Users
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

    /// @notice Redemptions
    mapping(bytes32 => bytes32[]) public redemptionRequests;
    mapping(bytes32 => bytes32[]) public redemptionRoots;

    /// @notice Undelgations
    mapping(bytes32 => bytes32[]) public undelegationRoots;
    
    /// @notice EigenLayer
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
            address(init.withdrawalController) == address(0) ||
            address(init.stakerNodeCoordinator) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(WITHDRAWAL_CONTROLLER_ROLE, init.withdrawalController);

        delegationManager = init.delegationManager;
        liquidToken = init.liquidToken;
        liquidTokenManager = init.liquidTokenManager;
        stakerNodeCoordinator = init.stakerNodeCoordinator;
    }

    function createWithdrawalRequest(
        IERC20[] memory assets,
        uint256[] memory amounts,
        address user,
        bytes32 requestId
    ) external override nonReentrant {
        if(msg.sender != address(liquidToken))
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

    /// @notice Allows users to fulfill a withdrawal request after the delay period
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

            // Check the contract's actual token balance
            if (asset.balanceOf(address(this)) < amount ) {
                revert InsufficientBalance(
                    asset,
                    amount,
                    asset.balanceOf(address(this))
                );
            }

            // Transfer the amount to the user
            asset.safeTransfer(msg.sender, amount);
        }

        // Reduce the corresponding queued balances and burn escrow shares
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

    function recordRedemptionCreated(
        bytes32 redemptionId,
        bytes32[] calldata requestIds,
        bytes32[] calldata withdrawalRoots,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata assets
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);
        uint256 arrayLength = requestIds.length;

        if (withdrawalRoots.length != arrayLength ||
            withdrawals.length != arrayLength ||
            assets.length != arrayLength
        )
            revert LengthMismatch();

        for (uint256 i = 0; i < arrayLength; i++) {
            _recordELWithdrawalCreated(withdrawalRoots[i], withdrawals[i], assets[i]);
        }

        redemptionRequests[redemptionId] = requestIds;
        redemptionRoots[redemptionId] =  withdrawalRoots;
    }

    function _recordELWithdrawalCreated(
        bytes32 withdrawalRoot,
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata assets
    ) internal {
        ELWithdrawalRequest memory elRequest = ELWithdrawalRequest({
            withdrawal: withdrawal,
            assets: assets
        });

        elWithdrawalRequests[withdrawalRoot] = elRequest;
    }

    function recordRedemptionCompleted(
        bytes32 redemptionId,
        bytes32[] calldata withdrawalRoots
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        for (uint256 i = 0; i < withdrawalRoots.length; i++) {
            bytes32 withdrawalRoot = withdrawalRoots[i];
            withdrawalRequests[withdrawalRoot].canFulfill = true;

            delete elWithdrawalRequests[withdrawalRoot];
        }

        delete redemptionRequests[redemptionId];
        delete redemptionRoots[redemptionId];
    }

    function getUserWithdrawalRequests(
        address user
    ) external view override returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

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

    function getRedemption(
        bytes32 redemptionId
    ) external view override returns (ILiquidTokenManager.Redemption memory) {
        bytes32[] memory requestIds = redemptionRequests[redemptionId];
        bytes32[] memory withdrawalRoots = redemptionRoots[redemptionId];

        if (requestIds.length == 0) revert RedemptionNotFound(redemptionId);

        return ILiquidTokenManager.Redemption({
            requestIds: requestIds,
            withdrawalRoots: withdrawalRoots
        });
    }
}