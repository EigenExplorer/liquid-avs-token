// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

/**
 * @title StakerNode
 * @dev
 */
contract StakerNode is IStakerNode, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public id;
    IStakerNodeCoordinator public coordinator;

    /**
     * @dev Initializes the StakerNode contract.
     * @param init The initialization parameters, including the node ID and the coordinator address.
     */
    function initialize(Init calldata init) external initializer {
        __ReentrancyGuard_init();
        id = init.id;
        coordinator = IStakerNodeCoordinator(init.coordinator);
    }

    /**
     * @dev Delegates the staker node to an operator.
     * @param operator The address of the operator to delegate to.
     * @param signature The signature with expiry for the delegation.
     * @param approverSalt The salt for the approver's signature.
     */
    function delegateToOperator(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external {
        IDelegationManager delegationManager = coordinator.delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);
        emit Delegated(operator);
    }

    /**
     * @dev Deposits assets into strategies.
     * @param assets The list of ERC20 tokens to be deposited.
     * @param amounts The list of amounts for each asset to be deposited.
     * @param strategies The list of strategies to deposit the assets into.
     */
    function depositToStrategy(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external {
        IStrategyManager strategyManager = coordinator.strategyManager();
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = strategies[i];
            asset.forceApprove(address(strategyManager), amount);
            uint256 shares = strategyManager.depositIntoStrategy(
                IStrategy(strategy),
                asset,
                amount
            );
            emit DepositedToStrategy(asset, strategy, amount, shares);
        }
    }
}
