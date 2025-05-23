// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

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
    ITokenRegistryOracle public tokenRegistryOracle;

    /**
    * @dev Withdrawal delay constant used for request/fulfill withdrawal flow
    * @dev OUT OF SCOPE FOR V1
    uint256 public constant WITHDRAWAL_DELAY = 14 days;
    */

    mapping(address => uint256) public assetBalances;
    mapping(address => uint256) public queuedAssetBalances;
    /**
     * @dev Withdrawal request structure
     * @dev OUT OF SCOPE FOR V1
    mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => bytes32[]) public userWithdrawalRequests;
    mapping(address => uint256) private _withdrawalNonce;
    */

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
        if (address(init.tokenRegistryOracle) == address(0)) {
            revert("TokenRegistryOracle cannot be the zero address");
        }
        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        liquidTokenManager = init.liquidTokenManager;
        tokenRegistryOracle = init.tokenRegistryOracle;
    }

    /// @notice Allows users to deposit multiple assets and receive shares
    /// @param assets The ERC20 assets to deposit
    /// @param amounts The amounts of the respective assets to deposit
    /// @param receiver The address to receive the minted shares
    /// @return sharesArray The array of shares minted for each asset
    function deposit(
        IERC20Upgradeable[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external nonReentrant whenNotPaused returns (uint256[] memory) {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        // Check if prices need update
        if (tokenRegistryOracle.arePricesStale()) {
            // Attempt price update with minimal try/catch
            bool updated;
            try tokenRegistryOracle.updateAllPricesIfNeeded() returns (
                bool result
            ) {
                updated = result;
            } catch {
                revert PriceUpdateFailed();
            }

            // Check update result - most gas efficient check first
            if (!updated) revert PriceUpdateRejected();

            // Verify prices are no longer stale
            if (tokenRegistryOracle.arePricesStale())
                revert PricesRemainStale();

            emit PricesUpdatedBeforeDeposit(msg.sender);
        }

        // Always check token prices regardless of staleness (enhanced security)
        for (uint256 i = 0; i < assets.length; i++) {
            address assetAddr = address(assets[i]);
            if (liquidTokenManager.tokenIsSupported(IERC20(assetAddr))) {
                if (tokenRegistryOracle.getTokenPrice(assetAddr) == 0) {
                    revert AssetPriceInvalid(assetAddr);
                }
            }
        }

        uint256 len = assets.length;
        uint256[] memory sharesArray = new uint256[](len);

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                IERC20 asset = IERC20(address(assets[i]));
                uint256 amount = amounts[i];

                if (amount == 0) revert ZeroAmount();
                if (!liquidTokenManager.tokenIsSupported(asset))
                    revert UnsupportedAsset(assets[i]);

                // True amount received may differ from `amount` for rebasing tokens
                uint256 balanceBefore = asset.balanceOf(address(this));
                asset.safeTransferFrom(msg.sender, address(this), amount);
                uint256 balanceAfter = asset.balanceOf(address(this));

                uint256 trueAmount = balanceAfter - balanceBefore;

                uint256 shares = calculateShares(assets[i], trueAmount);
                if (shares == 0) revert ZeroShares();

                assetBalances[address(asset)] += trueAmount;

                if (
                    assetBalances[address(asset)] >
                    asset.balanceOf(address(this))
                )
                    revert AssetBalanceOutOfSync(
                        assets[i],
                        assetBalances[address(asset)],
                        asset.balanceOf(address(this))
                    );

                _mint(receiver, shares);
                sharesArray[i] = shares;

                emit AssetDeposited(
                    msg.sender,
                    receiver,
                    assets[i],
                    trueAmount,
                    shares
                );
            }
        }

        return sharesArray;
    }
    /// @notice Allows users to request a withdrawal of their shares
    /// @param withdrawAssets The ERC20 assets to withdraw
    /// @param shareAmounts The number of shares to withdraw for each asset
    /// @dev OUT OF SCOPE FOR V1
    /** 
    function requestWithdrawal(
        IERC20Upgradeable[] memory withdrawAssets,
        uint256[] memory shareAmounts
    ) external nonReentrant whenNotPaused {
        if (withdrawAssets.length != shareAmounts.length)
            revert ArrayLengthMismatch();

        uint256 len = withdrawAssets.length;
        address sender = msg.sender;
        uint256 totalShares;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                if (
                    !liquidTokenManager.tokenIsSupported(
                        IERC20(address(withdrawAssets[i]))
                    )
                ) revert UnsupportedAsset(withdrawAssets[i]);
                if (shareAmounts[i] == 0) revert ZeroAmount();
                totalShares += shareAmounts[i];
            }
        }

        if (balanceOf(sender) < totalShares)
            revert InsufficientBalance(
                IERC20Upgradeable(address(this)),
                totalShares,
                balanceOf(sender)
            );

        bytes32 requestId = keccak256(
            abi.encodePacked(
                sender,
                withdrawAssets,
                shareAmounts,
                block.timestamp,
                block.number,
                tx.gasprice,
                address(this),
                _withdrawalNonce[sender]++
            )
        );

        if (withdrawalRequests[requestId].user != address(0)) {
            revert DuplicateRequestId(requestId);
        }

        WithdrawalRequest memory request = WithdrawalRequest({
            user: sender,
            assets: withdrawAssets,
            shareAmounts: shareAmounts,
            requestTime: block.timestamp,
            fulfilled: false
        });

        withdrawalRequests[requestId] = request;
        userWithdrawalRequests[sender].push(requestId);

        _transfer(sender, address(this), totalShares);

        emit WithdrawalRequested(
            requestId,
            sender,
            withdrawAssets,
            shareAmounts,
            block.timestamp
        );
    }
    */

    /// @notice Allows users to fulfill a withdrawal request after the delay period
    /// @param requestId The unique identifier of the withdrawal request
    /// @dev OUT OF SCOPE FOR V1
    /**
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
            totalShares += request.shareAmounts[i];
        }

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            IERC20 asset = IERC20(address(request.assets[i]));

            // Check the contract's actual token balance
            if (asset.balanceOf(address(this)) < amount) {
                revert InsufficientBalance(
                    request.assets[i],
                    asset.balanceOf(address(this)),
                    amount
                );
            }

            // Transfer the amount back to the user
            asset.safeTransfer(msg.sender, amount);

            // Reduce the asset balances for the asset
            // Note: Make sure that whenever this contract receives funds from EL withdrawal, `queuedAssetBalances` is debited and `assetBalances` is credited
            assetBalances[address(asset)] -= amount;

            if (assetBalances[address(asset)] > asset.balanceOf(address(this)))
                revert AssetBalanceOutOfSync(
                    request.assets[i],
                    assetBalances[address(asset)],
                    asset.balanceOf(address(this))
                );
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
    */

    /// @notice Credits queued balances for a given set of asset
    /// @param assets The assets to credit
    /// @param amounts The credit amounts expressed in native token
    function creditQueuedAssetBalances(
        IERC20Upgradeable[] calldata assets,
        uint256[] calldata amounts
    ) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);

        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            queuedAssetBalances[address(assets[i])] += amounts[i];
        }
    }

    /// @notice Allows the LiquidTokenManager to transfer assets from this contract
    /// @param assetsToRetrieve The ERC20 assets to transfer
    /// @param amounts The amounts of each asset to transfer
    function transferAssets(
        IERC20Upgradeable[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager))
            revert NotLiquidTokenManager(msg.sender);

        if (assetsToRetrieve.length != amounts.length)
            revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = IERC20(address(assetsToRetrieve[i]));
            uint256 amount = amounts[i];

            if (!liquidTokenManager.tokenIsSupported(asset))
                revert UnsupportedAsset(assetsToRetrieve[i]);

            if (amount > assetBalances[address(asset)])
                revert InsufficientBalance(
                    IERC20Upgradeable(address(asset)),
                    assetBalances[address(asset)],
                    amount
                );

            assetBalances[address(asset)] -= amount;
            asset.safeTransfer(address(liquidTokenManager), amount);

            if (assetBalances[address(asset)] > asset.balanceOf(address(this)))
                revert AssetBalanceOutOfSync(
                    assetsToRetrieve[i],
                    assetBalances[address(asset)],
                    asset.balanceOf(address(this))
                );

            emit AssetTransferred(
                assetsToRetrieve[i],
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
        IERC20Upgradeable asset,
        uint256 amount
    ) public view returns (uint256) {
        uint256 assetAmountInUnitOfAccount = liquidTokenManager
            .convertToUnitOfAccount(IERC20(address(asset)), amount);
        return _convertToShares(assetAmountInUnitOfAccount);
    }

    /// @notice Calculates the amount of an asset that corresponds to a given number of shares
    /// @param asset The ERC20 asset
    /// @param shares The number of shares
    /// @return The amount of the asset
    function calculateAmount(
        IERC20Upgradeable asset,
        uint256 shares
    ) public view returns (uint256) {
        uint256 amountInUnitOfAccount = _convertToAssets(shares);
        return
            liquidTokenManager.convertFromUnitOfAccount(
                IERC20(address(asset)),
                amountInUnitOfAccount
            );
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /**
     * @dev Gets withdrawal requests for a user
     * @dev OUT OF SCOPE FOR V1
     */
    /**
    function getUserWithdrawalRequests(
        address user
    ) external view returns (bytes32[] memory) {
        return userWithdrawalRequests[user];
    }
    */

    /**
     * @dev Gets details of a specific withdrawal request
     * @dev OUT OF SCOPE FOR V1
     */
    /**
    function getWithdrawalRequest(
        bytes32 requestId
    ) external view returns (WithdrawalRequest memory) {
        return withdrawalRequests[requestId];
    }
    */

    /// @notice Returns the total value of assets managed by the contract
    /// @return The total value of assets in the unit of account
    function totalAssets() public view returns (uint256) {
        IERC20[] memory supportedTokens = liquidTokenManager
            .getSupportedTokens();

        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            // Unstaked Asset Balances
            total += liquidTokenManager.convertToUnitOfAccount(
                supportedTokens[i],
                _balanceAsset(IERC20Upgradeable(address(supportedTokens[i])))
            );

            // Queued Asset Balances
            total += liquidTokenManager.convertToUnitOfAccount(
                supportedTokens[i],
                _balanceQueuedAsset(
                    IERC20Upgradeable(address(supportedTokens[i]))
                )
            );

            // Staked Withdrawable Asset Balances
            total += liquidTokenManager.getWithdrawableAssetBalance(
                supportedTokens[i]
            );
        }

        return total;
    }

    function balanceAssets(
        IERC20Upgradeable[] calldata assetList
    ) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assetList.length);
        for (uint256 i = 0; i < assetList.length; i++) {
            balances[i] = _balanceAsset(assetList[i]);
        }
        return balances;
    }

    /// @notice Returns the queued balances of multiple assets
    /// @param assetList The list of assets to get queued balances for
    /// @return An array of queued asset balances
    function balanceQueuedAssets(
        IERC20Upgradeable[] calldata assetList
    ) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assetList.length);
        for (uint256 i = 0; i < assetList.length; i++) {
            balances[i] = _balanceQueuedAsset(assetList[i]);
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

    function _balanceAsset(
        IERC20Upgradeable asset
    ) internal view returns (uint256) {
        return assetBalances[address(asset)];
    }

    function _balanceQueuedAsset(
        IERC20Upgradeable asset
    ) internal view returns (uint256) {
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
