// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

library LTMWithdrawal {
    using Math for uint256;

    function validateWithdrawalInputs(
        uint256[] calldata nodeIds,
        IERC20[][] calldata assets,
        uint256[][] calldata elDepositShares
    ) external pure {
        require(assets.length == nodeIds.length, "LengthMismatch");
        require(elDepositShares.length == nodeIds.length, "LengthMismatch");
    }

    function processNodeForWithdrawal(
        uint256 nodeId,
        IERC20[] calldata assets,
        uint256[] calldata elDepositShares,
        IERC20[] memory redemptionAssets,
        uint256[] memory redemptionElWithdrawableShares,
        uint256 currentUniqueTokenCount,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IStakerNodeCoordinator stakerNodeCoordinator,
        IDelegationManager delegationManager
    ) external view returns (uint256 newUniqueTokenCount) {
        uint256 uniqueTokenCount = currentUniqueTokenCount;
        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);

        for (uint256 j = 0; j < assets.length; j++) {
            require(elDepositShares[j] != 0, "ZeroAmount");

            IStrategy strategy = tokenStrategies[assets[j]];
            uint256 depositShares = strategy.shares(address(node));
            require(
                depositShares != 0 && depositShares >= elDepositShares[j],
                "InsufficientBalance"
            );

            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = strategy;
            (uint256[] memory withdrawableShares, ) = delegationManager
                .getWithdrawableShares(address(node), strategies);

            bool found = false;
            for (uint256 k = 0; k < uniqueTokenCount; k++) {
                if (redemptionAssets[k] == assets[j]) {
                    redemptionElWithdrawableShares[k] +=
                        (elDepositShares[j] * withdrawableShares[0]) /
                        depositShares;
                    found = true;
                    break;
                }
            }
            if (!found) {
                redemptionAssets[uniqueTokenCount] = assets[j];
                redemptionElWithdrawableShares[uniqueTokenCount] =
                    (elDepositShares[j] * withdrawableShares[0]) /
                    depositShares;
                uniqueTokenCount++;
            }
        }

        return uniqueTokenCount;
    }

    function createELWithdrawal(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IStakerNodeCoordinator stakerNodeCoordinator,
        IDelegationManager delegationManager
    )
        external
        returns (
            bytes32 withdrawalRoot,
            IDelegationManagerTypes.Withdrawal memory withdrawal
        )
    {
        require(assets.length == shares.length, "LengthMismatch");

        IStakerNode node = stakerNodeCoordinator.getNodeById(nodeId);
        IStrategy[] memory strategies = new IStrategy[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = tokenStrategies[assets[i]];
        }

        address staker = address(node);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = node.getOperatorDelegation();

        uint256[] memory scaledShares = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            scaledShares[i] = shares[i].mulDiv(
                delegationManager.depositScalingFactor(staker, strategies[i]),
                1e18
            );
        }

        withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: staker,
            delegatedTo: delegatedTo,
            withdrawer: staker,
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            scaledShares: scaledShares
        });

        withdrawalRoot = node.withdrawAssets(strategies, shares);
        require(
            withdrawalRoot == keccak256(abi.encode(withdrawal)),
            "InvalidWithdrawalRoot"
        );
    }

    function trimArrays(
        IERC20[] memory assets,
        uint256[] memory shares,
        uint256 actualLength
    ) external pure {
        assembly {
            mstore(assets, actualLength)
            mstore(shares, actualLength)
        }
    }
}