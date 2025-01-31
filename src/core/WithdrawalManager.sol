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
    
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests; // requestId -> WR
    mapping(bytes32 => Redemption) public redemptions; // redemptionId -> redemption
    mapping(bytes32 => ELWithdrawalRequest) public elWithdrawalRequests; // root -> elER
    mapping(address => bytes32[]) public userWithdrawalRequests;
    mapping(uint256 => bytes32[]) public undelegationRequests;

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

    /*
    TODO: Allow a user to withdraw if corresponding requestId is ready for fulfilment

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(
        // uint256[] callback nodeIds
        // bytes32[][] callback withdrawalRoots
        bytes32 requestId
    ) external override nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY)
            revert WithdrawalDelayNotMet();

        uint256[] memory amounts = new uint256[](request.assets.length);
        uint256 totalShares = 0;

        uint256[] memory nodeIds = requestNodes[requestId];
        bytes32[] memory withdrawalRoots = new bytes32[](nodeIds.length);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            uint256 nodeId = nodeIds[i];
            bytes32 withdrawalRoot = requestNodeRoots[requestId][nodeId];
            withdrawalRoots[i] = withdrawalRoot;
            _completeELWithdrawals(withdrawalRoot, nodeId);
            delete requestNodeRoots[requestId][nodeId];
        }

        emit ELWithdrawalsCompleted(requestId, withdrawalRoots);

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
        delete requestNodes[requestId];
    }
    */

    function recordELWithdrawalCreated(
        bytes32 withdrawalRoot,
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata assets
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        ELWithdrawalRequest memory elRequest = new ELWithdrawalRequest({
            withdrawal: withdrawal,
            assets: assets
        });

        elWithdrawalRequests[withdrawalRoot] = elRequest;
    }

    function recordRedemptionCreated(
        bytes32 redemptionId,
        bytes32[] calldata requestIds,
        bytes32[] calldata withdrawalRoots
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        Redemption memory redemption = new Redemption({
            requestIds: requestIds,
            withdrawalRoots: withdrawalRoots
        });

        redemptions[redemptionId] = redemption;
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

        delete redemptions[redemptionId];
    }

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateStakerNodes(
        uint256[] calldata nodeIds
    ) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            uint256 nodeId = nodeIds[i];
            IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

            bytes32[] memory withdrawalRoots = node.undelegate();

            // TODO: IStrategyManager.getDeposits() gives the list of strategies and shares of the node

            for (uint256 j = 0; j < withdrawalRoots.length; j++) {
                undelegationRequests[nodeId].push(withdrawalRoots[j]);
            }
        }
    }

    /// @notice Complete a set withdrawals related to undelegation on EigenLayer for a specific node 
    /// @dev Tokens received by staker node are transferred to `LiquidToken`
    function completeELWithdrawalsForUndelegation(
        uint256 nodeId,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bytes32[] calldata withdrawalRoots
    ) external nonReentrant onlyRole(WITHDRAWAL_CONTROLLER_ROLE) {
        uint256 arrayLength = withdrawals.length;
        bytes32[] storage existingRoots = undelegationRequests[nodeId];
        if (existingRoots.length == 0) revert InvalidWithdrawalRequest();

        if (
            tokens.length != arrayLength || 
            withdrawalRoots.length != arrayLength
        ) 
            revert LengthMismatch();

        // Validate then delete withdrawal roots
        for (uint256 i = 0; i < withdrawalRoots.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < existingRoots.length; j++) {
                if (existingRoots[j] == withdrawalRoots[i]) {
                    found = true;
                    existingRoots[j] = existingRoots[existingRoots.length - 1];
                    existingRoots.pop();
                    break;
                }
            }
            if (!found) revert WithdrawalRootNotFound(withdrawalRoots[i]);
        }
        
        IERC20[] memory receivedAssets = _completeELUndelegationWithdrawals(
            nodeId,
            withdrawals,
            tokens
        );
        
        uint256 receivedAssetsLength = receivedAssets.length;
        uint256[] memory receivedAmounts = new uint256[](receivedAssetsLength);
        
        for (uint256 i = 0; i < receivedAssetsLength; i++) {
            IERC20 asset = receivedAssets[i];
            uint256 balance = asset.balanceOf(address(this));
            asset.safeTransfer(address(liquidToken), balance);
            receivedAmounts[i] = balance;
        }
        
        // Reduce queued balances but no shares to burn since `LiquidToken` holds the assets
        liquidToken.debitQueuedAssetBalances(receivedAssets, receivedAmounts, 0);
        
        emit ELWithdrawalsForUndelegationCompleted(nodeId, withdrawalRoots);
    }

    function _completeELUndelegationWithdrawals(
        uint256 nodeId,
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens
    ) private returns (IERC20[] memory) {
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        return node.completeWithdrawals(
            withdrawals,
            tokens
        );
    }

    function getUserWithdrawalRequests(
        address user
    ) external view returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

    function getWithdrawalRequests(
        bytes32[] calldata requestIds
    ) external view returns (WithdrawalRequest[] memory) {
        uint256 arrayLength = requestIds.length;
        WithdrawalRequest[] memory requests = new WithdrawalRequest[](arrayLength);

        for(uint256 i = 0; i < arrayLength; i++) {
            bytes32 request = requests[requestIds[i]];
            if (request.user = address(0)) revert WithdrawalRequestNotFound(requestIds[i]);
            requests.push(request);
        }

        return requests;
    }

    function getELWithdrawalRequests(
        bytes32[] calldata withdrawalRoots
    ) external view returns (ELWithdrawalRequest[] memory) {
        uint256 arrayLength = withdrawalRoots.length;
        ELWithdrawalRequest[] memory elRequests = new ELWithdrawalRequest[](arrayLength);

        for(uint256 i = 0; i < arrayLength; i++) {
            bytes32 withdrawalRoot = elWithdrawalRequests[withdrawalRoots[i]];
            if (withdrawalRoot = bytes32(0)) revert ELWithdrawalRequestNotFound(withdrawalRoot);
            elRequests.push(withdrawalRoot);
        }

        return elRequests;
    }

    function getRedemption(
        bytes32 redemptionId
    ) external view returns (Redemption memory) {
        Redemption memory redemption = redemptions[redemptionId];
        if (redemption.requestIds.length == 0) revert RedemptionNotFound(redemptionId);

        return redemption;
    }
}