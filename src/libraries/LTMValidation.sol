// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

library LTMValidation {
    // Shortened error messages
    error E01(); // LengthMismatch
    error E02(); // ZeroAddress
    error E03(); // ZeroAmount
    error E04(); // InvalidDecimals
    error E05(); // InvalidThreshold
    error E06(); // InvalidPrice
    error E07(); // TokenNotSupported
    error E08(); // InvalidStakingAmount
    error E09(); // StrategyNotFound
    error E10(); // WithdrawalMissing
    error E11(); // InvalidReceiver
    error E12(); // TokenExists
    error E13(); // StrategyAlreadyAssigned
    error E14(); // InvalidPriceSource
    error E15(); // TokenPriceFetchFailed
    error E16(); // TokenInUse
    error E17(); // VolatilityThresholdHit
    error E18(); // InvalidWithdrawalRoot
    error E19(); // InsufficientBalance
    error E20(); // RequestsDoNotSettle
    error E21(); // TokenForStrategyNotFound

    function validateLengths(uint256 len1, uint256 len2) internal pure {
        if (len1 != len2) revert E01();
    }

    function validateNotZero(address addr) internal pure {
        if (addr == address(0)) revert E02();
    }

    function validateAmount(uint256 amount) internal pure {
        if (amount == 0) revert E03();
    }

    function validateStrategy(address strategy) internal pure {
        if (strategy == address(0)) revert E09();
    }

    function validateRedemption(
        bytes32[] memory redemptionWithdrawalRoots,
        IDelegationManagerTypes.Withdrawal[][] calldata withdrawals
    ) internal pure {
        uint256 totalWithdrawals;
        for (uint256 j = 0; j < withdrawals.length; j++) {
            totalWithdrawals += withdrawals[j].length;
        }

        bytes32[] memory allWithdrawalHashes = new bytes32[](totalWithdrawals);
        uint256 index;
        for (uint256 j = 0; j < withdrawals.length; j++) {
            for (uint256 k = 0; k < withdrawals[j].length; k++) {
                allWithdrawalHashes[index++] = keccak256(
                    abi.encode(withdrawals[j][k])
                );
            }
        }

        for (uint256 i = 0; i < redemptionWithdrawalRoots.length; i++) {
            bool found;
            for (uint256 h = 0; h < allWithdrawalHashes.length; h++) {
                if (allWithdrawalHashes[h] == redemptionWithdrawalRoots[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) revert E10();
        }
    }
}