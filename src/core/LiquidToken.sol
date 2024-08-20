// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";
import {IOrchestrator} from "../interfaces/IOrchestrator.sol";

contract LiquidToken is
    ILiquidToken,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    ITokenRegistry public tokenRegistry;
    IOrchestrator public orchestrator;
    uint256 public constant WITHDRAWAL_DELAY = 14 days;

    mapping(address => Asset) public assets;
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize(Init calldata init) external initializer {
        __ERC20_init(init.name, init.symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();

        _grantRole(ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        tokenRegistry = init.tokenRegistry;
        orchestrator = init.orchestrator;
    }

    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) external nonReentrant whenNotPaused returns (uint256) {
        if (amount == 0) revert ZeroAmount();
        if (!tokenRegistry.tokenIsSupported(asset))
            revert UnsupportedAsset(asset);

        uint256 shares = calculateShares(asset, amount);
        if (shares == 0) revert ZeroShares();

        asset.safeTransferFrom(msg.sender, address(this), amount);
        assets[address(asset)].balance += amount;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, asset, amount, shares);
        return shares;
    }

    function requestWithdrawal(
        IERC20[] memory assets,
        uint256[] memory shareAmounts
    ) external whenNotPaused {
        if (assets.length != shareAmounts.length) revert ArrayLengthMismatch();

        uint256 totalShares = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (!tokenRegistry.tokenIsSupported(assets[i]))
                revert UnsupportedAsset(assets[i]);
            if (shareAmounts[i] == 0)
                revert("Share amount must be greater than 0");
            totalShares += shareAmounts[i];
        }

        if (balanceOf(msg.sender) < totalShares)
            revert InsufficientBalance(
                IERC20(address(this)),
                totalShares,
                balanceOf(msg.sender)
            );

        bytes32 requestId = keccak256(
            abi.encodePacked(msg.sender, assets, shareAmounts, block.timestamp)
        );
        WithdrawalRequest memory request = WithdrawalRequest({
            user: msg.sender,
            assets: assets,
            shareAmounts: shareAmounts,
            requestTime: block.timestamp,
            fulfilled: false
        });

        withdrawalRequests[requestId] = request;
        userWithdrawalRequests[msg.sender].push(requestId);

        transferFrom(msg.sender, address(this), totalShares);

        emit WithdrawalRequested(requestId, msg.sender, assets, shareAmounts);
    }

    function fulfillWithdrawal(bytes32 requestId) external whenNotPaused {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY)
            revert WithdrawalDelayNotMet();
        if (request.fulfilled) revert WithdrawalAlreadyFulfilled();

        request.fulfilled = true;
        uint256[] memory amounts = new uint256[](request.assets.length);

        for (uint256 i = 0; i < request.assets.length; i++) {
            amounts[i] = calculateAmount(
                request.assets[i],
                request.shareAmounts[i]
            );
            request.assets[i].safeTransfer(msg.sender, amounts[i]);
        }

        emit WithdrawalFulfilled(
            requestId,
            msg.sender,
            request.assets,
            amounts
        );
    }

    function getUserWithdrawalRequests(
        address user
    ) external view returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }

    function getWithdrawalRequest(
        bytes32 requestId
    ) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[requestId];
    }

    function transferAssetsToOrchestrator(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external whenNotPaused {
        if (msg.sender != address(orchestrator))
            revert NotOrchestrator(msg.sender);

        if (assetsToRetrieve.length != amounts.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = assetsToRetrieve[i];
            uint256 amount = amounts[i];

            if (amount > assets[address(asset)].balance)
                revert InsufficientBalance(
                    IERC20(address(asset)),
                    assets[address(asset)].balance,
                    amount
                );

            assets[address(asset)].balance -= amount;
            asset.safeTransfer(address(orchestrator), amount);

            emit AssetTransferred(asset, amount, address(orchestrator));
        }
    }

    function calculateShares(
        IERC20 asset,
        uint256 amount
    ) public view returns (uint256) {
        uint256 assetAmountInUnitOfAccount = tokenRegistry
            .convertToUnitOfAccount(asset, amount);
        return _convertToShares(assetAmountInUnitOfAccount);
    }

    function calculateAmount(
        IERC20 asset,
        uint256 shares
    ) public view returns (uint256) {
        uint256 amountInUnitOfAccount = _convertToAssets(shares);
        return
            tokenRegistry.convertFromUnitOfAccount(
                asset,
                amountInUnitOfAccount
            );
    }

    function _convertToShares(uint256 amount) internal view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAsset = totalAssets();

        // Check for totalAssets being 0 to avoid division by zero
        if (supply == 0 || totalAsset == 0) {
            return amount;
        }

        return (amount * supply) / totalAsset;
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAsset = totalAssets();

        // Check for totalSupply being 0 to avoid division by zero
        if (supply == 0 || totalAsset == 0) {
            return shares;
        }

        return (shares * totalAsset) / supply;
    }

    function totalAssets() public view returns (uint256) {
        return tokenRegistry.totalAssets();
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
