// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IWithdrawalRouter {
    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] shareAmounts;
        uint256 requestTime;
        bool fulfilled;
    }

    event WithdrawalRequested(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] shareAmounts
    );
    event WithdrawalFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts
    );

    error InvalidWithdrawalRequest();
    error WithdrawalDelayNotMet();
    error WithdrawalAlreadyFulfilled();
    error AssetNotSupported(IERC20 asset);
    error ArrayLengthMismatch();
    error InsufficientBalance(
        IERC20 asset,
        uint256 required,
        uint256 available
    );
}
