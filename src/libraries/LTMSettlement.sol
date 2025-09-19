// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

library LTMSettlement {
    using Math for uint256;

    function validateSettlement(
        bytes32[] calldata requestIds,
        uint256[] calldata nodeIds,
        IERC20[][] calldata elAssets,
        uint256[][] calldata elDepositShares
    ) external pure {
        require(elAssets.length == nodeIds.length, "LengthMismatch");
        require(elDepositShares.length == nodeIds.length, "LengthMismatch");
    }

    function processWithdrawalRequests(
        IWithdrawalManager.WithdrawalRequest[] memory withdrawalRequests,
        uint256 maxTokens
    ) external pure returns (
        uint256 uniqueTokenCount,
        IERC20[] memory redemptionAssets,
        uint256[] memory redemptionElDepositShares
    ) {
        redemptionAssets = new IERC20[](maxTokens);
        redemptionElDepositShares = new uint256[](maxTokens);
        uniqueTokenCount = 0;

        for (uint256 i = 0; i < withdrawalRequests.length; i++) {
            IWithdrawalManager.WithdrawalRequest memory request = withdrawalRequests[i];
            for (uint256 j = 0; j < request.assets.length; j++) {
                IERC20 token = request.assets[j];
                bool found = false;
                for (uint256 k = 0; k < uniqueTokenCount; k++) {
                    if (redemptionAssets[k] == token) {
                        redemptionElDepositShares[k] += request.elWithdrawableShares[j];
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    redemptionAssets[uniqueTokenCount] = token;
                    redemptionElDepositShares[uniqueTokenCount] = request.elWithdrawableShares[j];
                    uniqueTokenCount++;
                }
            }
        }
    }

    function verifySettlementAmounts(
        uint256[] memory redemptionElDepositShares,
        uint256[] memory proposedRedemptionElDepositShares,
        uint256 uniqueTokenCount
    ) external pure {
        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            uint256 upperMargin = Math.mulDiv(redemptionElDepositShares[i], 10, 10000, Math.Rounding.Up);
            uint256 lowerMargin = Math.mulDiv(redemptionElDepositShares[i], 10, 10000, Math.Rounding.Down);

            uint256 maxAllowed = redemptionElDepositShares[i] + upperMargin;
            uint256 minAllowed = redemptionElDepositShares[i] - lowerMargin;

            require(
                proposedRedemptionElDepositShares[i] <= maxAllowed && 
                proposedRedemptionElDepositShares[i] >= minAllowed,
                "RequestsDoNotSettle"
            );
        }
    }
}