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

contract StakerNode is IStakerNode, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public id;
    IStakerNodeCoordinator public coordinator;

    constructor() {
        _disableInitializers();
    }

    function initialize(Init calldata init) external initializer {
        __ReentrancyGuard_init();

        id = init.id;
        coordinator = IStakerNodeCoordinator(init.coordinator);
    }

    function delegateToOperator(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external {
        IDelegationManager delegationManager = coordinator.delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);

        emit Delegated(operator);
    }

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

    // function withdrawTokens(
    //     address recipient,
    //     uint256 amount
    // ) external {
    //     require(recipient != address(0), "Invalid recipient");
    //     require(
    //         avsToken.balanceOf(address(this)) >= amount,
    //         "Insufficient balance"
    //     );

    //     avsToken.safeTransfer(recipient, amount);
    // }
}
