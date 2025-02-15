// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStakerNode} from "../../src/interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../../src/interfaces/IStakerNodeCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

contract MockStakerNode is IStakerNode {
    IStakerNodeCoordinator public coordinator;
    uint256 public id;
    address public operatorDelegation;
    uint64 public version;

    function initialize(Init calldata params) external {
        coordinator = params.coordinator;
        id = params.id;
        version = 1;
    }

    function delegate(
        address operatorAddr,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external {
        operatorDelegation = operatorAddr;
        emit DelegatedToOperator(operatorAddr);
    }

    function undelegate() external {
        if (operatorDelegation == address(0)) revert NodeNotDelegated();
        address oldOperator = operatorDelegation;
        operatorDelegation = address(0);
        emit UndelegatedFromOperator(oldOperator);
    }

    function isUndelegated() external view returns (bool) {
        return operatorDelegation == address(0);
    }

    function depositAssets(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            emit AssetDepositedToStrategy(tokens[i], strategies[i], amounts[i], amounts[i]);
        }
    }

    function implementation() external view returns (address) {
        return address(this);
    }

    function getId() external view returns (uint256) {
        return id;
    }

    function getInitializedVersion() external view returns (uint64) {
        return version;
    }

    function getOperatorDelegation() external view returns (address) {
        return operatorDelegation;
    }
}
