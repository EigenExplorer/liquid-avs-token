// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

interface ILiquidToken is IERC20 {
    struct Init {
        string name;
        string symbol;
        ITokenRegistry tokenRegistry;
        ILiquidTokenManager liquidTokenManager;
        address initialOwner;
        address pauser;
    }

    struct Asset {
        uint256 balance;
    }

    struct WithdrawalRequest {
        address user;
        IERC20[] assets;
        uint256[] shareAmounts;
        uint256 requestTime;
        bool fulfilled;
    }

    event Deposit(
        address indexed sender,
        address indexed receiver,
        IERC20 indexed asset,
        uint256 amount,
        uint256 shares
    );
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
    event AssetTransferred(
        IERC20 indexed asset,
        uint256 amount,
        address destination
    );

    error UnsupportedAsset(IERC20 asset);
    error ZeroAmount();
    error ZeroShares();
    error NotLiquidTokenManager(address sender);
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

    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) external returns (uint256);

    function transferAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external;

    function calculateShares(
        IERC20 asset,
        uint256 amount
    ) external view returns (uint256);

    function calculateAmount(
        IERC20 asset,
        uint256 shares
    ) external view returns (uint256);

    function totalAssets() external view returns (uint256);
}
