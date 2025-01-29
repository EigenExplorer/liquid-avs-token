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

    ILiquidToken public liquidToken;
    ILiquidTokenManager public liquidTokenManager;
    IStakerNodeCoordinator public stakerNodeCoordinator;
    uint256 public constant WITHDRAWAL_DELAY = 14 days;

    mapping(uint256 => bytes32[]) public undelegationRequests;
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

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
            address(init.liquidTokenManager) == address(0) ||
            address(init.withdrawalController) == address(0) ||
            address(init.stakerNodeCoordinator) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(WITHDRAWAL_CONTROLLER_ROLE, init.withdrawalController);

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
            fulfilled: false
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

    function requestWithdrawal(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata shareAmounts,
        bytes32 requestId
    ) external override nonReentrant {
        uint256 arrayLength = nodeIds.length;
        bytes32[] memory withdrawalRoots = new bytes32[](arrayLength);

        if (assets.length != arrayLength || shareAmounts.length != arrayLength) 
            revert LengthMismatch();

        for (uint256 i = 0; i < arrayLength; i++) {
            if (assets[i].length != shareAmounts[i].length)
                revert LengthMismatch();

            IStrategy[] memory strategies = liquidTokenManager.getTokensStrategies(assets[i]);
            IStakerNode node = stakerNodeCoordinator.getNodeById(nodeIds[i]);

            // NOTE: This will fail on EigenLayer contracts if the node doesn't have the shares implied by the input parameters
            withdrawalRoots[i] = node.withdraw(strategies, shareAmounts[i]);

            liquidToken.creditQueuedAssetBalances(
                assets[i],
                shareAmounts[i]
            );
        }

        emit WithdrawalRequested(requestId, withdrawalRoots);
    }

    function fulfillWithdrawalEigenLayer(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bytes32 requestId
    ) external nonReentrant {

    }

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawalUser(bytes32 requestId) external nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY)
            revert WithdrawalDelayNotMet();
        if (request.fulfilled) revert WithdrawalAlreadyFulfilled();

        request.fulfilled = true;
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

            // Transfer the amount back to the user
            asset.safeTransfer(msg.sender, amount);
        }

        // Reduce the corresponding queued asset balances
        liquidToken.debitAndBurnQueuedAssetBalances(request.assets, amounts, totalShares);

        emit WithdrawalFulfilled(
            requestId,
            msg.sender,
            request.assets,
            amounts,
            block.timestamp
        );
    }

    /// @notice Undelegate a set of staker nodes from their operators
    /// @param nodeIds The IDs of the staker nodes
    function undelegateStakerNodes(uint256[] calldata nodeIds) external override {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            uint256 nodeId = nodeIds[i];
            IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

            bytes32[] memory withdrawalRoots = node.undelegate();

            for (uint256 j = 0; j < withdrawalRoots.length; j++) {
                undelegationRequests[nodeId].push(withdrawalRoots[j]);
            }
        }
    }

    function fulfillWithdrawalsFromUndelegation(bytes32[] calldata requestId) external nonReentrant { }

    function getUserWithdrawalRequests(
        address user
    ) external view returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

    function getWithdrawalRequest(
        bytes32 requestId
    ) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[requestId];
    }
}