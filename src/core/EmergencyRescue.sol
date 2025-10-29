// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {IEmergencyRescue} from "../interfaces/IEmergencyRescue.sol";

/// @title EmergencyRescue
/// @notice Emergency contract to recover funds from staker nodes
contract EmergencyRescue is IEmergencyRescue, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice EigenLayer contracts
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    /// @notice StakerNodeCoordinator
    IStakerNodeCoordinator public stakerNodeCoordinator;

    /// @notice Mapping of nodeId => withdrawal index => withdrawal data
    mapping(uint256 => mapping(uint256 => EmergencyWithdrawalData)) public emergencyWithdrawalData;

    /// @notice Mapping of nodeId => number of withdrawals
    mapping(uint256 => uint256) public emergencyWithdrawalCount;

    // ------------------------------------------------------------------------------
    // Init
    // ------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        IStakerNodeCoordinator _stakerNodeCoordinator
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (_admin == address(0)) revert ZeroAddress();
        if (address(_strategyManager) == address(0)) revert ZeroAddress();
        if (address(_delegationManager) == address(0)) revert ZeroAddress();
        if (address(_stakerNodeCoordinator) == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        strategyManager = _strategyManager;
        delegationManager = _delegationManager;
        stakerNodeCoordinator = _stakerNodeCoordinator;
    }

    // ------------------------------------------------------------------------------
    // Emergency Functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IEmergencyRescue
    function emergencyUndelegateAllNodes()
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256[] memory nodeIds, bytes32[][] memory withdrawalRoots)
    {
        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        uint256 delegatedCount = 0;

        // Count delegated nodes
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i].getOperatorDelegation() != address(0)) {
                delegatedCount++;
            }
        }

        if (delegatedCount == 0) revert NoNodesToUndelegate();

        nodeIds = new uint256[](delegatedCount);
        withdrawalRoots = new bytes32[][](delegatedCount);
        uint256 index = 0;

        // Undelegate each node
        for (uint256 i = 0; i < nodes.length; i++) {
            IStakerNode node = nodes[i];
            address operator = node.getOperatorDelegation();

            if (operator != address(0)) {
                uint256 nodeId = node.getId();
                address nodeAddress = address(node);

                // Get deposits before undelegating
                (IStrategy[] memory strategies, uint256[] memory depositShares) = strategyManager.getDeposits(
                    nodeAddress
                );

                // Get nonce
                uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(nodeAddress);

                // Undelegate
                bytes32[] memory roots = node.emergencyUndelegate();

                // Store withdrawal roots
                _storeEmergencyWithdrawalData(nodeId, strategies, depositShares, nonce, operator, roots);

                nodeIds[index] = nodeId;
                withdrawalRoots[index] = roots;
                index++;

                emit EmergencyNodeUndelegated(nodeId, operator, roots);
            }
        }

        emit EmergencyUndelegationInitiated(nodeIds, msg.sender);
    }

    /// @inheritdoc IEmergencyRescue
    function emergencyCompleteUndelegation(
        uint256[] calldata nodeIds,
        IDelegationManagerTypes.Withdrawal[][] calldata withdrawals,
        IERC20[][][] calldata assets,
        address recipient
    ) external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        if (withdrawals.length != nodeIds.length) revert LengthMismatch(withdrawals.length, nodeIds.length);
        if (assets.length != nodeIds.length) revert LengthMismatch(assets.length, nodeIds.length);

        // Validate withdrawals
        for (uint256 i = 0; i < nodeIds.length; i++) {
            _validateEmergencyWithdrawals(nodeIds[i], withdrawals[i]);
        }

        // Track received tokens
        IERC20[] memory receivedTokens = new IERC20[](10);
        uint256 uniqueTokenCount = 0;

        // Complete withdrawals
        for (uint256 i = 0; i < nodeIds.length; i++) {
            IStakerNode node = stakerNodeCoordinator.getNodeById(nodeIds[i]);

            // Complete withdrawals - funds go to node then to this contract
            IERC20[] memory nodeReceivedTokens = node.emergencyCompleteWithdrawals(
                withdrawals[i],
                assets[i],
                address(this)
            );

            // Track unique tokens
            for (uint256 j = 0; j < nodeReceivedTokens.length; j++) {
                IERC20 token = nodeReceivedTokens[j];
                bool found = false;

                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (receivedTokens[k] == token) {
                        found = true;
                        break;
                    }
                }

                if (!found && uniqueTokenCount < receivedTokens.length) {
                    receivedTokens[uniqueTokenCount++] = token;
                }
            }

            // Clear data
            _clearEmergencyWithdrawalData(nodeIds[i]);
        }

        // Transfer to recipient
        uint256[] memory recoveredAmounts = new uint256[](uniqueTokenCount);

        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            IERC20 token = receivedTokens[i];
            uint256 balance = token.balanceOf(address(this));

            if (balance > 0) {
                recoveredAmounts[i] = balance;
                token.safeTransfer(recipient, balance);
            }
        }

        emit EmergencyUndelegationCompleted(nodeIds, receivedTokens, recoveredAmounts, recipient, msg.sender);
    }

    // ------------------------------------------------------------------------------
    // Internal Functions
    // ------------------------------------------------------------------------------

    function _storeEmergencyWithdrawalData(
        uint256 nodeId,
        IStrategy[] memory strategies,
        uint256[] memory depositShares,
        uint256 nonce,
        address operator,
        bytes32[] memory withdrawalRoots
    ) internal {
        uint256 withdrawalIndex = emergencyWithdrawalCount[nodeId];

        EmergencyWithdrawalData storage data = emergencyWithdrawalData[nodeId][withdrawalIndex];

        data.strategies = new IStrategy[](strategies.length);
        data.depositShares = new uint256[](depositShares.length);
        data.withdrawalRoots = new bytes32[](withdrawalRoots.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            data.strategies[i] = strategies[i];
            data.depositShares[i] = depositShares[i];
        }

        for (uint256 i = 0; i < withdrawalRoots.length; i++) {
            data.withdrawalRoots[i] = withdrawalRoots[i];
        }

        data.nonce = nonce;
        data.operator = operator;
        data.startBlock = block.number;
        data.exists = true;

        emergencyWithdrawalCount[nodeId]++;

        emit EmergencyWithdrawalDataStored(nodeId, strategies, depositShares, nonce, operator);
    }

    function _scaleSharesForNode(
        uint256 nodeId,
        IStrategy[] memory strategies,
        uint256[] memory shares
    ) internal view returns (uint256[] memory) {
        address nodeAddress = address(stakerNodeCoordinator.getNodeById(nodeId));
        uint256[] memory scaledShares = new uint256[](shares.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            scaledShares[i] = shares[i].mulDiv(
                delegationManager.depositScalingFactor(nodeAddress, strategies[i]),
                1e18
            );
        }

        return scaledShares;
    }

    function _validateEmergencyWithdrawals(
        uint256 nodeId,
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals
    ) internal view {
        uint256 storedCount = emergencyWithdrawalCount[nodeId];

        if (withdrawals.length != storedCount) revert InvalidWithdrawalData();

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        address nodeAddress = address(node);

        uint256 minWithdrawalDelay = uint256(delegationManager.minWithdrawalDelayBlocks());

        for (uint256 i = 0; i < withdrawals.length; i++) {
            EmergencyWithdrawalData storage stored = emergencyWithdrawalData[nodeId][i];

            if (!stored.exists) revert InvalidWithdrawalData();

            IDelegationManagerTypes.Withdrawal calldata withdrawal = withdrawals[i];

            if (withdrawal.staker != nodeAddress) revert InvalidWithdrawalData();
            if (withdrawal.delegatedTo != stored.operator) revert InvalidWithdrawalData();
            if (withdrawal.withdrawer != nodeAddress) revert InvalidWithdrawalData();
            if (withdrawal.nonce != stored.nonce) revert InvalidWithdrawalData();
            if (withdrawal.startBlock != uint32(stored.startBlock)) revert InvalidWithdrawalData();

            if (withdrawal.strategies.length != stored.strategies.length) revert InvalidWithdrawalData();

            for (uint256 j = 0; j < withdrawal.strategies.length; j++) {
                if (address(withdrawal.strategies[j]) != address(stored.strategies[j])) {
                    revert InvalidWithdrawalData();
                }
            }

            if (block.number < stored.startBlock + minWithdrawalDelay) {
                revert WithdrawalDelayNotMet();
            }

            // Validate withdrawal root hash
            bytes32 computedRoot = keccak256(abi.encode(withdrawal));
            bool rootFound = false;

            for (uint256 j = 0; j < stored.withdrawalRoots.length; j++) {
                if (stored.withdrawalRoots[j] == computedRoot) {
                    rootFound = true;
                    break;
                }
            }

            if (!rootFound) revert InvalidWithdrawalRoot();
        }
    }

    function _clearEmergencyWithdrawalData(uint256 nodeId) internal {
        uint256 count = emergencyWithdrawalCount[nodeId];

        for (uint256 i = 0; i < count; i++) {
            delete emergencyWithdrawalData[nodeId][i];
        }

        emergencyWithdrawalCount[nodeId] = 0;
    }

    // ------------------------------------------------------------------------------
    // Getter Functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IEmergencyRescue
    function getEmergencyWithdrawalData(
        uint256 nodeId,
        uint256 withdrawalIndex
    ) external view override returns (EmergencyWithdrawalData memory data) {
        data = emergencyWithdrawalData[nodeId][withdrawalIndex];
        if (!data.exists) revert InvalidWithdrawalData();
        return data;
    }

    /// @inheritdoc IEmergencyRescue
    function getAllEmergencyWithdrawalData(
        uint256 nodeId
    ) external view override returns (EmergencyWithdrawalData[] memory allData) {
        uint256 count = emergencyWithdrawalCount[nodeId];
        allData = new EmergencyWithdrawalData[](count);

        for (uint256 i = 0; i < count; i++) {
            allData[i] = emergencyWithdrawalData[nodeId][i];
        }

        return allData;
    }
}