// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

library LTMRedemption {
    using SafeERC20 for IERC20;

    function createRedemption(
        bytes32[] memory requestIds,
        bytes32[] memory withdrawalRoots,
        IERC20[] memory assets,
        uint256[] memory elWithdrawableShares,
        address receiver,
        uint256 redemptionNonce,
        IWithdrawalManager withdrawalManager
    ) external returns (bytes32 redemptionId) {
        redemptionId = keccak256(
            abi.encode(
                requestIds,
                withdrawalRoots,
                block.timestamp,
                redemptionNonce
            )
        );

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: withdrawalRoots,
                assets: assets,
                elWithdrawableShares: elWithdrawableShares,
                receiver: receiver
            });

        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);
    }

    function validateRedemption(
        bytes32[] memory redemptionWithdrawalRoots,
        bytes32[][] calldata withdrawalHashes
    ) external pure {
        uint256 totalWithdrawals = 0;
        for (uint256 j = 0; j < withdrawalHashes.length; j++) {
            totalWithdrawals += withdrawalHashes[j].length;
        }

        bytes32[] memory allWithdrawalHashes = new bytes32[](totalWithdrawals);
        uint256 index = 0;
        for (uint256 j = 0; j < withdrawalHashes.length; j++) {
            for (uint256 k = 0; k < withdrawalHashes[j].length; k++) {
                allWithdrawalHashes[index++] = withdrawalHashes[j][k];
            }
        }

        for (uint256 i = 0; i < redemptionWithdrawalRoots.length; i++) {
            bool found = false;
            for (uint256 h = 0; h < allWithdrawalHashes.length; h++) {
                if (allWithdrawalHashes[h] == redemptionWithdrawalRoots[i]) {
                    found = true;
                    break;
                }
            }
            require(found, "WithdrawalMissing");
        }
    }

    function processAssetTransfers(
        IERC20[] memory tokens,
        address receiver,
        mapping(IERC20 => IStrategy) storage tokenStrategies
    )
        external
        returns (
            uint256[] memory receivedAmounts,
            uint256[] memory receivedElShares
        )
    {
        uint256 length = tokens.length;
        receivedAmounts = new uint256[](length);
        receivedElShares = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            IERC20 token = tokens[i];
            uint256 balance = token.balanceOf(address(this));

            if (balance > 0) {
                uint256 receiverBalanceBefore = token.balanceOf(receiver);
                token.safeTransfer(receiver, balance);
                uint256 receiverBalanceAfter = token.balanceOf(receiver);

                receivedAmounts[i] =
                    receiverBalanceAfter -
                    receiverBalanceBefore;
                receivedElShares[i] = tokenStrategies[token]
                    .underlyingToSharesView(receivedAmounts[i]);
            }
        }
    }
}