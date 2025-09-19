// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IDelegationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

library LTMWithdrawalProcessor {
    function processWithdrawalRequests(
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests,
        IERC20[] memory supportedTokens
    )
        internal
        pure
        returns (
            uint256 uniqueTokenCount,
            IERC20[] memory redemptionAssets,
            uint256[] memory redemptionElDepositShares
        )
    {
        redemptionAssets = new IERC20[](supportedTokens.length);
        redemptionElDepositShares = new uint256[](supportedTokens.length);

        for (uint256 i = 0; i < withdrawalRequests.length; i++) {
            IWithdrawalManager.WithdrawalRequest
                memory request = withdrawalRequests[i];
            for (uint256 j = 0; j < request.assets.length; j++) {
                IERC20 token = request.assets[j];
                bool found = false;
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (redemptionAssets[k] == token) {
                        redemptionElDepositShares[k] += request
                            .elWithdrawableShares[j];
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    redemptionAssets[uniqueTokenCount] = token;
                    redemptionElDepositShares[uniqueTokenCount] = request
                        .elWithdrawableShares[j];
                    uniqueTokenCount++;
                }
            }
        }
    }

    function completeELWithdrawals(
        uint256 nodeId,
        IDelegationManagerTypes.Withdrawal[] memory withdrawals,
        IERC20[][] memory assets,
        IERC20[] memory uniqueTokens,
        uint256 uniqueTokenCount,
        IStakerNode node
    ) internal returns (uint256) {
        IERC20[] memory receivedTokens = node.completeWithdrawals(
            withdrawals,
            assets
        );

        for (uint256 j = 0; j < receivedTokens.length; j++) {
            IERC20 token = receivedTokens[j];
            bool found = false;
            for (uint256 k = 0; k < uniqueTokenCount; k++) {
                if (uniqueTokens[k] == token) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                uniqueTokens[uniqueTokenCount++] = token;
            }
        }

        return uniqueTokenCount;
    }
}