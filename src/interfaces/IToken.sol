// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IToken {
    struct Init {
        string name;
        string symbol;
        address initialOwner;
        address pauser;
        address unpauser;
    }

    event Deposit(
        address indexed sender,
        address indexed receiver,
        IERC20 indexed asset,
        uint256 amount,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        IERC20 indexed asset,
        uint256 amount,
        uint256 shares
    );
    event AssetRetrieved(
        IERC20 indexed asset,
        uint256 amount,
        address destination
    );
    event DepositsPausedUpdated(bool paused);

    error UnsupportedAsset(IERC20 asset);
    error Paused();
    error ZeroAmount();
    error ZeroShares();
    error InsufficientBalance(uint256 available, uint256 required);
    error NotStrategyManager(address sender);
}
