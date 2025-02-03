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
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/**
 * @title LiquidToken
 * @notice Implements a liquid staking token with deposit, withdrawal, and asset management functionalities
 * @dev Interacts with LiquidTokenManager to manage assets and handle user requests
 */
contract LiquidToken is
    ILiquidToken,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    ILiquidTokenManager public liquidTokenManager;
    IWithdrawalManager public withdrawalManager;

    mapping(address => uint256) public assetBalances;
    mapping(address => uint256) public queuedAssetBalances;
    mapping(address => uint256) private _withdrawalNonce;

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

        // Zero address checks
        if (init.initialOwner == address(0)) {
            revert("Initial owner cannot be the zero address");
        }
        if (init.pauser == address(0)) {
            revert("Pauser cannot be the zero address");
        }
        if (address(init.liquidTokenManager) == address(0)) {
            revert("LiquidTokenManager cannot be the zero address");
        }
        if (address(init.withdrawalManager) == address(0)) {
            revert("WithdrawalManager cannot be the zero address");
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        liquidTokenManager = init.liquidTokenManager;
        withdrawalManager = init.withdrawalManager;
    }

    /// @notice Allows users to deposit multiple assets and receive shares
    /// @param assets The ERC20 assets to deposit
    /// @param amounts The amounts of the respective assets to deposit
    /// @param receiver The address to receive the minted shares
    /// @return sharesArray The array of shares minted for each asset
    function deposit(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external nonReentrant whenNotPaused returns (uint256[] memory) {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        uint256[] memory sharesArray = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];

            if (amount == 0) revert ZeroAmount();
            if (!liquidTokenManager.tokenIsSupported(asset))
                revert UnsupportedAsset(asset);

            uint256 shares = calculateShares(asset, amount);
            if (shares == 0) revert ZeroShares();

            asset.safeTransferFrom(msg.sender, address(this), amount);
            assetBalances[address(asset)] += amount;
            
            if (assetBalances[address(asset)] > asset.balanceOf(address(this))) 
                revert AssetBalanceOutOfSync(
                    asset, 
                    assetBalances[address(asset)], 
                    asset.balanceOf(address(this))
                );

            _mint(receiver, shares);

            sharesArray[i] = shares;

            emit AssetDeposited(
                msg.sender,
                receiver,
                asset,
                amount,
                shares
            );
        }

        return sharesArray;
    }

    /// @notice Allows users to initiate a withdrawal request against their shares
    /// @param assets The ERC20 assets to withdraw
    /// @param amounts The amount of tokens to withdraw for each asset
    function initiateWithdrawal(
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external nonReentrant whenNotPaused returns (bytes32) {
        if (assets.length != amounts.length)
            revert ArrayLengthMismatch();

        if (!_previewWithdrawal(assets, amounts)) revert InvalidWithdrawalRequest();

        uint256 totalShares = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (!liquidTokenManager.tokenIsSupported(assets[i]))
                revert UnsupportedAsset(assets[i]);
            if (amounts[i] == 0) revert ZeroAmount();
            totalShares += amounts[i];
        }

        if (balanceOf(msg.sender) < totalShares)
            revert InsufficientBalance(
                IERC20(address(this)),
                totalShares,
                balanceOf(msg.sender)
            );

        // Receive escrow shares to burn on returning assets to user
        _transfer(msg.sender, address(this), totalShares);
        
        bytes32 requestId = keccak256(
            abi.encodePacked(
                msg.sender,
                assets,
                amounts,
                block.timestamp,
                _withdrawalNonce[msg.sender]
            )
        );
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            msg.sender,
            requestId
        );
        _withdrawalNonce[msg.sender] += 1;

        return requestId;
    }

    function previewWithdrawal(
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external view override returns (bool) {
        return _previewWithdrawal(assets, amounts);
    }

    function _previewWithdrawal(
        IERC20[] memory assets,
        uint256[] memory amounts
    ) internal view returns (bool) {
        bool isPossible = true;
        for(uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            if (
                (assetBalances[address(asset)] + liquidTokenManager.getStakedAssetBalance(assets[i])) < 
                amounts[i]
            ) {
                isPossible = false;
                break;
            }
        }
        return isPossible;
    }

    /// @notice Credits queued balances for a given set of assets
    /// @param assets The assets to credit
    /// @param amounts The credit amounts expressed in native token
    function creditQueuedAssetBalances(
        IERC20[] calldata assets,
        uint256[] calldata amounts
    ) external whenNotPaused {
        if (msg.sender != address(withdrawalManager) && msg.sender != address(liquidTokenManager))
            revert UnauthorizedAccess(msg.sender);

        if (assets.length != amounts.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            queuedAssetBalances[address(assets[i])] += amounts[i];
        }
    }

    function bulkCreditQueuedAssetBalances(
        IERC20[][] calldata assets,
        uint256[][] calldata amounts
    ) external whenNotPaused {
        if (msg.sender != address(withdrawalManager) && msg.sender != address(liquidTokenManager))
            revert UnauthorizedAccess(msg.sender);

        if (assets.length != amounts.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i].length != amounts[i].length)
                revert ArrayLengthMismatch();
            
            for (uint256 j = 0; j < assets[i].length; j++) {
                queuedAssetBalances[address(assets[i][j])] += amounts[i][j];
            }
        }
    }

    /// @notice Debits queued balances for a given set of assets & burns the corresponding shares if taken from user
    /// @param assets The assets to debit
    /// @param amounts The debit amounts expressed in native token
    /// @param sharesToBurn Amount of shares to burn
    function debitQueuedAssetBalances(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        uint256 sharesToBurn
    ) external whenNotPaused {
        if (msg.sender != address(withdrawalManager))
            revert UnauthorizedAccess(msg.sender);

        if (assets.length != amounts.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            queuedAssetBalances[address(assets[i])] -= amounts[i];
        }

        // Burn escrow shares that were transferred to the contract during the withdrawal request
        _burn(address(this), sharesToBurn);
    }

    /// @notice Allows the LiquidTokenManager to transfer assets from this contract
    /// @param assetsToRetrieve The ERC20 assets to transfer
    /// @param amounts The amounts of each asset to transfer
    /// @param receiver The receiver of the funds, either `LiquidTokenManager` or `WithdrawalManager`
    function transferAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts,
        address receiver
    ) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);

        if (assetsToRetrieve.length != amounts.length)
            revert ArrayLengthMismatch();

        if (receiver != address(liquidTokenManager) && receiver != address(withdrawalManager))
            revert InvalidReceiver(receiver);

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = assetsToRetrieve[i];
            uint256 amount = amounts[i];

            if (!liquidTokenManager.tokenIsSupported(asset))
                revert UnsupportedAsset(asset);

            if (amount > assetBalances[address(asset)])
                revert InsufficientBalance(
                    IERC20(address(asset)),
                    assetBalances[address(asset)],
                    amount
                );

            assetBalances[address(asset)] -= amount;
            asset.safeTransfer(receiver, amount);

            if (assetBalances[address(asset)] > asset.balanceOf(address(this))) 
                revert AssetBalanceOutOfSync(
                    asset, 
                    assetBalances[address(asset)], 
                    asset.balanceOf(address(this))
                );

            emit AssetTransferred(
                asset,
                amount,
                receiver,
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
        uint256 assetAmountInUnitOfAccount = liquidTokenManager
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
            liquidTokenManager.convertFromUnitOfAccount(
                asset,
                amountInUnitOfAccount
            );
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @notice Returns the total value of assets managed by the contract
    /// @return The total value of assets in the unit of account
    function totalAssets() public view returns (uint256) {
        IERC20[] memory supportedTokens = liquidTokenManager.getSupportedTokens();

        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            // Unstaked Asset Balances
            total += liquidTokenManager.convertToUnitOfAccount(
                supportedTokens[i],
                _balanceAsset(supportedTokens[i])
            );

            // Queued Asset Balances
            total += liquidTokenManager.convertToUnitOfAccount(
                supportedTokens[i],
                _balanceQueuedAsset(supportedTokens[i])
            );

            // Staked Asset Balances
            total += liquidTokenManager.getStakedAssetBalance(supportedTokens[i]);
        }

        return total;
    }

    function balanceAssets(
        IERC20[] calldata assetList
    ) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assetList.length);
        for (uint256 i = 0; i < assetList.length; i++) {
            balances[i] = _balanceAsset(assetList[i]);
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
        return assetBalances[address(asset)];
    }

    function _balanceQueuedAsset(IERC20 asset) internal view returns (uint256) {
        return queuedAssetBalances[address(asset)];
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
