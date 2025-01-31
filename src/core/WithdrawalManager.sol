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
    
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(bytes32 => mapping(uint256 => bytes32)) public requestNodeRoots;
    mapping(bytes32 => uint256[]) public requestNodes;
    mapping(bytes32 => ELWithdrawalRequest) public elWithdrawalRequests;
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
            requestTime: block.timestamp
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

    function createELWithdrawalsforRequest(
        bytes32 requestId,
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata shareAmounts
    ) external override nonReentrant onlyRole(WITHDRAWAL_CONTROLLER_ROLE) {
        uint256 arrayLength = nodeIds.length;
        if (assets.length != arrayLength || shareAmounts.length != arrayLength) 
            revert LengthMismatch();
            
        for (uint256 i = 0; i < arrayLength; i++) {
            if (assets[i].length != shareAmounts[i].length)
                revert LengthMismatch();
        }
        
        bytes32[] memory withdrawalRoots = _createELWithdrawals(
            requestId,
            nodeIds,
            assets,
            shareAmounts
        );
        
        emit ELWithdrawalsCreated(requestId, withdrawalRoots);
    }

    function _createELWithdrawals(
        bytes32 requestId,
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata shareAmounts
    ) private returns (bytes32[] memory) {
        uint256 arrayLength = nodeIds.length;
        bytes32[] memory withdrawalRoots = new bytes32[](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            withdrawalRoots[i] = _createELWithdrawal(
                requestId,
                nodeIds[i],
                assets[i],
                shareAmounts[i]
            );
        }

        return withdrawalRoots;
    }

    function _createELWithdrawal(
        bytes32 requestId,
        uint256 nodeId,
        IERC20[] memory assetsArray,
        uint256[] memory sharesArray
    ) private returns (bytes32) {
        IStrategy[] memory strategies = liquidTokenManager.getTokensStrategies(assetsArray);
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        
        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();
        
        bytes32 withdrawalRoot = node.withdraw(strategies, sharesArray);

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: staker,
            delegatedTo: delegatedTo,
            withdrawer: staker,
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            shares: sharesArray
        });

        if (withdrawalRoot != keccak256(abi.encode(withdrawal))) 
            revert InvalidWithdrawalRoot();

        ELWithdrawalRequest memory elRequest = ELWithdrawalRequest({
            withdrawal: withdrawal,
            assets: assetsArray
        });
        
        requestNodeRoots[requestId][nodeId] = withdrawalRoot;
        requestNodes[requestId].push(nodeId);
        elWithdrawalRequests[withdrawalRoot] = elRequest;

        liquidToken.creditQueuedAssetBalances(assetsArray, sharesArray);
        
        return withdrawalRoot;
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

    /// @notice For a given request ID, complete all corresponding withdrawals on EigenLayer and receive funds into the contract
    function _completeELWithdrawals(
        bytes32 withdrawalRoot,
        uint256 nodeId
    ) private {
        IDelegationManager.Withdrawal[] memory nodeWithdrawals = 
            new IDelegationManager.Withdrawal[](1);
        IERC20[][] memory nodeTokens = new IERC20[][](1);
        
        ELWithdrawalRequest memory elRequest = elWithdrawalRequests[withdrawalRoot];
        nodeWithdrawals[0] = elRequest.withdrawal;
        nodeTokens[0] = elRequest.assets;
        
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        node.completeWithdrawals(nodeWithdrawals, nodeTokens);

        delete elWithdrawalRequests[withdrawalRoot];
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

            for (uint256 j = 0; j < withdrawalRoots.length; j++) {
                undelegationRequests[nodeId].push(withdrawalRoots[j]);
            }
        }
    }

    /// @notice Complete a set withdrawals related to undelegation on EigenLayer for a specific node 
    /// @dev Use `receieveAsTokens` to instruct whether the undelegation should trigger assets to be pulled out of EigenLayer
    /// @dev With undelegation tokens/shares can only be received by the node. In case tokens are received, we transfer them to `LiquidToken`
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
        
        _handleReceivedAssets(receivedAssets);
        
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

    function _handleReceivedAssets(IERC20[] memory receivedAssets) private {
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
    }

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