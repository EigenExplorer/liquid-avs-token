// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IDelegationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEmergencyRescue {
    // ------------------------------------------------------------------------------
    // Structs
    // ------------------------------------------------------------------------------

    struct EmergencyWithdrawalData {
        IStrategy[] strategies;
        uint256[] depositShares;
        uint256 nonce;
        address operator;
        uint256 startBlock;
        bytes32[] withdrawalRoots;
        bool exists;
    }

    // ------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------

    event EmergencyUndelegationInitiated(uint256[] nodeIds, address indexed initiator);

    event EmergencyNodeUndelegated(uint256 indexed nodeId, address indexed operator, bytes32[] withdrawalRoots);

    event EmergencyWithdrawalDataStored(
        uint256 indexed nodeId,
        IStrategy[] strategies,
        uint256[] shares,
        uint256 nonce,
        address operator
    );

    event EmergencyUndelegationCompleted(
        uint256[] nodeIds,
        IERC20[] tokens,
        uint256[] amounts,
        address indexed recipient,
        address indexed initiator
    );

    // ------------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------------

    error ZeroAddress();
    error NoNodesToUndelegate();
    error InvalidWithdrawalData();
    error WithdrawalDelayNotMet();
    error LengthMismatch(uint256 length1, uint256 length2);
    error InvalidWithdrawalRoot();

    // ------------------------------------------------------------------------------
    // Functions
    // ------------------------------------------------------------------------------

    function emergencyUndelegateAllNodes()
        external
        returns (uint256[] memory nodeIds, bytes32[][] memory withdrawalRoots);

    function emergencyCompleteUndelegation(
        uint256[] calldata nodeIds,
        IDelegationManagerTypes.Withdrawal[][] calldata withdrawals,
        IERC20[][][] calldata assets,
        address recipient
    ) external;

    function getEmergencyWithdrawalData(
        uint256 nodeId,
        uint256 withdrawalIndex
    ) external view returns (EmergencyWithdrawalData memory);

    function getAllEmergencyWithdrawalData(uint256 nodeId) external view returns (EmergencyWithdrawalData[] memory);
}