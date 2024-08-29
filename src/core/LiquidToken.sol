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
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistry} from "../interfaces/ITokenRegistry.sol";

/**
 * @title LiquidToken
 * @notice Implements a liquid staking token with deposit, withdrawal, and asset management functionalities
 * @dev Interacts with TokenRegistry and LiquidTokenManager to manage assets and handle user requests
 */
contract LiquidToken is
    ILiquidToken,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    ITokenRegistry public tokenRegistry;
    ILiquidTokenManager public liquidTokenManager;
    uint256 public constant WITHDRAWAL_DELAY = 14 days;

    mapping(address => Asset) public assets;
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the LiquidToken contract
    /// @param init The initialization parameters
    function initialize(Init calldata init) external initializer {
        __ERC20_init(init.name, init.symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        tokenRegistry = init.tokenRegistry;
        liquidTokenManager = init.liquidTokenManager;
    }

    /// @notice Allows users to deposit an asset and receive shares
    /// @param asset The ERC20 asset to deposit
    /// @param amount The amount of the asset to deposit
    /// @param receiver The address to receive the minted shares
    /// @return shares The number of shares minted
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

        emit AssetDeposited(msg.sender, receiver, asset, amount, shares);
        return shares;
    }

    /// @notice Allows users to request a withdrawal of their shares
    /// @param withdrawAssets The ERC20 assets to withdraw
    /// @param shareAmounts The number of shares to withdraw for each asset
    function requestWithdrawal(
        IERC20[] memory withdrawAssets,
        uint256[] memory shareAmounts
    ) external nonReentrant whenNotPaused {
        if (withdrawAssets.length != shareAmounts.length)
            revert ArrayLengthMismatch();

        uint256 totalShares = 0;
        for (uint256 i = 0; i < withdrawAssets.length; i++) {
            if (!tokenRegistry.tokenIsSupported(withdrawAssets[i]))
                revert UnsupportedAsset(withdrawAssets[i]);
            if (shareAmounts[i] == 0) revert ZeroAmount();
            totalShares += shareAmounts[i];
        }

        if (balanceOf(msg.sender) < totalShares)
            revert InsufficientBalance(
                IERC20(address(this)),
                totalShares,
                balanceOf(msg.sender)
            );

        bytes32 requestId = keccak256(
            abi.encodePacked(
                msg.sender,
                withdrawAssets,
                shareAmounts,
                block.timestamp
            )
        );
        WithdrawalRequest memory request = WithdrawalRequest({
            user: msg.sender,
            assets: withdrawAssets,
            shareAmounts: shareAmounts,
            requestTime: block.timestamp,
            fulfilled: false
        });

        withdrawalRequests[requestId] = request;
        userWithdrawalRequests[msg.sender].push(requestId);

        _transfer(msg.sender, address(this), totalShares);

        emit WithdrawalRequested(
            requestId,
            msg.sender,
            withdrawAssets,
            shareAmounts,
            block.timestamp
        );
    }

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    function fulfillWithdrawal(bytes32 requestId) external nonReentrant {
        WithdrawalRequest storage request = withdrawalRequests[requestId];

        if (request.user != msg.sender) revert InvalidWithdrawalRequest();
        if (block.timestamp < request.requestTime + WITHDRAWAL_DELAY)
            revert WithdrawalDelayNotMet();
        if (request.fulfilled) revert WithdrawalAlreadyFulfilled();

        request.fulfilled = true;
        uint256[] memory amounts = new uint256[](request.assets.length);
        uint256 totalShares = 0;

        for (uint256 i = 0; i < request.assets.length; i++) {
            amounts[i] = calculateAmount(
                request.assets[i],
                request.shareAmounts[i]
            );
            request.assets[i].safeTransfer(msg.sender, amounts[i]);
            totalShares += request.shareAmounts[i];
        }

        // Burn the shares that were transferred to the contract during the withdrawal request
        _burn(address(this), totalShares);

        emit WithdrawalFulfilled(
            requestId,
            msg.sender,
            request.assets,
            amounts,
            block.timestamp
        );
    }

    /// @notice Allows the LiquidTokenManager to transfer assets from this contract
    /// @param assetsToRetrieve The ERC20 assets to transfer
    /// @param amounts The amounts of each asset to transfer
    function transferAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);

        if (assetsToRetrieve.length != amounts.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = assetsToRetrieve[i];
            uint256 amount = amounts[i];

            if (!tokenRegistry.tokenIsSupported(asset))
                revert UnsupportedAsset(asset);

            if (amount > assets[address(asset)].balance)
                revert InsufficientBalance(
                    IERC20(address(asset)),
                    assets[address(asset)].balance,
                    amount
                );

            assets[address(asset)].balance -= amount;
            asset.safeTransfer(address(liquidTokenManager), amount);

            emit AssetTransferred(
                asset,
                amount,
                address(liquidTokenManager),
                msg.sender
            );
        }
    }

    /// @notice Calculates the number of shares that correspond to a given amount of an asset
    /// @param asset The ERC20 asset
    /// @param amount The amount of the asset
    /// @return The number of shares
    function calculateShares(
        IERC20 asset,
        uint256 amount
    ) public view returns (uint256) {
        uint256 assetAmountInUnitOfAccount = tokenRegistry
            .convertToUnitOfAccount(asset, amount);
        return _convertToShares(assetAmountInUnitOfAccount);
    }

    /// @notice Calculates the amount of an asset that corresponds to a given number of shares
    /// @param asset The ERC20 asset
    /// @param shares The number of shares
    /// @return The amount of the asset
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

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

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

    /// @notice Returns the total value of assets managed by the contract
    /// @return The total value of assets in the unit of account
    function totalAssets() public view returns (uint256) {
        IERC20[] memory supportedTokens = tokenRegistry.getSupportedTokens();

        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            total += tokenRegistry.convertToUnitOfAccount(
                supportedTokens[i],
                _balanceAsset(supportedTokens[i])
            );
        }

        return total;
    }

    function balanceAssets(
        IERC20[] calldata assets
    ) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            balances[i] = _balanceAsset(assets[i]);
        }
        return balances;
    }

    // ------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------

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

    function _balanceAsset(IERC20 asset) internal view returns (uint256) {
        return assets[address(asset)].balance;
    }

    // ------------------------------------------------------------------------------
    // Misc
    // ------------------------------------------------------------------------------

    /// @notice Pauses the contract
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
