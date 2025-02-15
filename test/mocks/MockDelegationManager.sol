// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockDelegationManager {
    mapping(address => address) public delegatedTo;
    mapping(address => bool) public operators;
    mapping(address => IDelegationManager.OperatorDetails) public operatorDetails_;
    mapping(address => mapping(IStrategy => uint256)) public operatorShares_;
    mapping(address => uint256) public stakerNonce_;
    mapping(address => uint256) public cumulativeWithdrawalsQueued_;

    function registerAsOperator(IDelegationManager.OperatorDetails calldata _operatorDetails, string calldata) external {
        operators[msg.sender] = true;
        operatorDetails_[msg.sender] = _operatorDetails;
    }

    function delegateTo(address operator, ISignatureUtils.SignatureWithExpiry memory, bytes32) external {
        require(operators[operator], "Not an operator");
        require(delegatedTo[operator] == address(0), "Already delegated");
        delegatedTo[operator] = msg.sender;
    }

    function isDelegated(address staker) external view returns (bool) {
        return delegatedTo[staker] != address(0);
    }

    function isOperator(address operator) external view returns (bool) {
        return operators[operator];
    }

    function operatorDetails(address operator) external view returns (IDelegationManager.OperatorDetails memory) {
        return operatorDetails_[operator];
    }

    function DELEGATION_APPROVAL_TYPEHASH() external pure returns (bytes32) {
        return bytes32(0);
    }

    function DOMAIN_TYPEHASH() external pure returns (bytes32) {
        return bytes32(0);
    }

    function STAKER_DELEGATION_TYPEHASH() external pure returns (bytes32) {
        return bytes32(0);
    }

    function beaconChainETHStrategy() external pure returns (IStrategy) {
        return IStrategy(address(0));
    }

    function calculateCurrentStakerDelegationDigestHash(
        address,
        address,
        uint256,
        bytes32
    ) external pure returns (bytes32) {
        return bytes32(0);
    }

    function calculateDelegationApprovalDigestHash(
        address,
        address,
        uint256,
        bytes32
    ) external pure returns (bytes32) {
        return bytes32(0);
    }

    function calculateStakerDelegationDigestHash(
        address,
        address,
        uint256,
        bytes32
    ) external pure returns (bytes32) {
        return bytes32(0);
    }

    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory) external pure returns (bytes32) {
        return bytes32(0);
    }

    function completeQueuedWithdrawal(
        IDelegationManager.Withdrawal calldata,
        IERC20[] calldata,
        uint256[] calldata,
        address,
        bool
    ) external pure returns (bytes32) {
        return bytes32(0);
    }

    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata,
        IERC20[][] calldata,
        uint256[][] calldata,
        address,
        bool[] calldata
    ) external pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function cumulativeWithdrawalsQueued(address staker) external view returns (uint256) {
        return cumulativeWithdrawalsQueued_[staker];
    }

    function decreaseDelegatedShares(address staker, IStrategy strategy, uint256 shares) external {
        operatorShares_[staker][strategy] -= shares;
    }

    function delegateToBySignature(
        address,
        address,
        ISignatureUtils.SignatureWithExpiry calldata,
        bytes32
    ) external pure {}

    function delegationApprover(address) external pure returns (address) {
        return address(0);
    }

    function delegationApproverSaltIsSpent(address, bytes32) external pure returns (bool) {
        return false;
    }

    function domainSeparator() external pure returns (bytes32) {
        return bytes32(0);
    }

    function getOperatorShares(address operator, IStrategy strategy) external view returns (uint256) {
        return operatorShares_[operator][strategy];
    }

    function getWithdrawalDelay(IStrategy[] calldata) external pure returns (uint256) {
        return 0;
    }

    function increaseDelegatedShares(address staker, IStrategy strategy, uint256 shares) external {
        operatorShares_[staker][strategy] += shares;
    }

    function minWithdrawalDelayBlocks() external pure returns (uint256) {
        return 0;
    }

    function modifyOperatorDetails(IDelegationManager.OperatorDetails calldata newOperatorDetails) external {
        operatorDetails_[msg.sender] = newOperatorDetails;
    }

    function operatorShares(address operator, IStrategy strategy) external view returns (uint256) {
        return operatorShares_[operator][strategy];
    }

    function queueWithdrawals(IDelegationManager.QueuedWithdrawalParams[] calldata) external pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function stakerNonce(address staker) external view returns (uint256) {
        return stakerNonce_[staker];
    }

    function stakerOptOutWindowBlocks(address operator) external view returns (uint256) {
        return operatorDetails_[operator].stakerOptOutWindowBlocks;
    }

    function strategyWithdrawalDelayBlocks(IStrategy) external pure returns (uint256) {
        return 0;
    }

    function undelegate(address staker) external pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function updateOperatorMetadataURI(string calldata) external pure {}
}
