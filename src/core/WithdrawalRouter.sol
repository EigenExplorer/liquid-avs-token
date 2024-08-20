// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IWithdrawalRouter.sol";
import "../interfaces/IToken.sol";
import "../interfaces/ITokenRegistry.sol";

contract WithdrawalRouter is IWithdrawalRouter, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    IToken public token;
    ITokenRegistry public tokenRegistry;
    uint256 public constant WITHDRAWAL_DELAY = 14 days;

    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function initialize(IToken _token, ITokenRegistry _tokenRegistry, address admin, address pauser) public initializer {
        __AccessControl_init();
        __Pausable_init();

        token = _token;
        tokenRegistry = _tokenRegistry;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
    }

    function requestWithdrawal(IERC20[] memory assets, uint256[] memory shareAmounts) external whenNotPaused {
        if (assets.length != shareAmounts.length) revert ArrayLengthMismatch();

        uint256 totalShares = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (!tokenRegistry.tokenIsSupported(assets[i])) revert AssetNotSupported(assets[i]);
            if (shareAmounts[i] == 0) revert("Share amount must be greater than 0");
            totalShares += shareAmounts[i];
        }

        if (token.balanceOf(msg.sender) < totalShares) revert InsufficientBalance(IERC20(address(token)), totalShares, token.balanceOf(msg.sender));

        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, assets, shareAmounts, block.timestamp));
        WithdrawalRequest memory request = WithdrawalRequest({
            user: msg.sender,
            assets: assets,
            shareAmounts: shareAmounts,
            requestTime: block.timestamp,
            fulfilled: false
        });

        withdrawalRequests[requestId] = request;
        userWithdrawalRequests[msg.sender].push(requestId);

        token.transferFrom(msg.sender, address(this), totalShares);

        emit WithdrawalRequested(requestId, msg.sender, assets, shareAmounts);
    }

    function fulfillWithdrawal(bytes32 requestId) external whenNotPaused {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY) revert WithdrawalDelayNotMet();
        if (request.fulfilled) revert WithdrawalAlreadyFulfilled();

        request.fulfilled = true;
        uint256[] memory amounts = new uint256[](request.assets.length);

        for (uint256 i = 0; i < request.assets.length; i++) {
            amounts[i] = token.calculateAmount(request.assets[i], request.shareAmounts[i]);
            token.withdraw(request.assets[i], request.shareAmounts[i]);
            request.assets[i].safeTransfer(msg.sender, amounts[i]);
        }

        emit WithdrawalFulfilled(requestId, msg.sender, request.assets, amounts);
    }

    function getUserWithdrawalRequests(address user) external view returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

    function getWithdrawalRequest(bytes32 requestId) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[requestId];
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}