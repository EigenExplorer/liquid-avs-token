// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/**
 * @title LiquidToken
 * @notice Implements a liquid staking token with deposit, withdrawal, and asset management functionalities
 */
contract LiquidToken is
    ILiquidToken,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Role identifier for pausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice v1 LAT contracts
    ILiquidTokenManager public liquidTokenManager;
    ITokenRegistryOracle public tokenRegistryOracle;

    /// @notice Mapping of assets to their corresponding unstaked balances (held in this contract)
    mapping(address => uint256) public assetBalances;

    /// @notice Mapping of tokens to their corresponding queued balances
    mapping(address => uint256) public queuedAssetBalances;

    /// @notice Mapping of user addresses to their corresponding withdrawal nonces
    mapping(address => uint256) private _withdrawalNonce;

    /// @notice v2 LAT contracts
    IWithdrawalManager public withdrawalManager;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ILiquidToken
    function initialize(Init calldata init) external initializer {
        __ERC20_init(init.name, init.symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();

        if (
            address(init.initialOwner) == address(0) ||
            address(init.pauser) == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            address(init.tokenRegistryOracle) == address(0) ||
            address(init.withdrawalManager) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        liquidTokenManager = init.liquidTokenManager;
        tokenRegistryOracle = init.tokenRegistryOracle;
        withdrawalManager = init.withdrawalManager;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ILiquidToken
    function deposit(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        address receiver
    ) external nonReentrant whenNotPaused returns (uint256[] memory) {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        // Check if prices need update
        if (tokenRegistryOracle.arePricesStale()) {
            // Attempt price update with minimal try/catch
            bool updated;
            try tokenRegistryOracle.updateAllPricesIfNeeded() returns (bool result) {
                updated = result;
            } catch {
                revert PriceUpdateFailed();
            }
            // Check update result
            if (!updated) revert PriceUpdateRejected();

            // Verify prices are no longer stale
            if (tokenRegistryOracle.arePricesStale()) revert PricesRemainStale();

            emit PricesUpdatedBeforeDeposit(msg.sender);
        }

        // Always check token prices regardless of staleness
        for (uint256 i = 0; i < assets.length; i++) {
            address assetAddr = address(assets[i]);
            if (liquidTokenManager.tokenIsSupported(assets[i])) {
                if (tokenRegistryOracle.getTokenPrice(assetAddr) == 0) {
                    revert AssetPriceInvalid(assetAddr);
                }
            }
        }

        uint256 len = assets.length;
        uint256[] memory sharesArray = new uint256[](len);

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                IERC20 asset = assets[i];
                uint256 amount = amounts[i];

                if (amount == 0) revert ZeroAmount();
                if (!liquidTokenManager.tokenIsSupported(asset)) revert UnsupportedAsset(assets[i]);

                // True amount received may differ from `amount` for certain LSTs
                uint256 balanceBefore = asset.balanceOf(address(this));
                asset.safeTransferFrom(msg.sender, address(this), amount);
                uint256 balanceAfter = asset.balanceOf(address(this));

                uint256 trueAmount = balanceAfter - balanceBefore;

                uint256 shares = calculateShares(assets[i], trueAmount);
                if (shares == 0) revert ZeroShares();

                // Credit asset balances
                assetBalances[address(asset)] += trueAmount;

                if (assetBalances[address(asset)] > asset.balanceOf(address(this)))
                    revert AssetBalanceOutOfSync(
                        assets[i],
                        assetBalances[address(asset)],
                        asset.balanceOf(address(this))
                    );

                _mint(receiver, shares);
                sharesArray[i] = shares;

                emit AssetDeposited(msg.sender, receiver, assets[i], trueAmount, shares);
            }
        }

        return sharesArray;
    }

    /// @inheritdoc ILiquidToken
    function initiateWithdrawal(
        IERC20[] memory assets,
        uint256[] memory amounts
    ) external nonReentrant whenNotPaused returns (bytes32) {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        // Check if we have enough funds from staked and unstaked balances
        if (!_previewWithdrawal(assets, amounts)) revert InvalidWithdrawalRequest();

        // Calculate the amount of LAT shares to receive from the user in exchange for the
        // withdrawal request with the right to fulfill after a period delay
        uint256 totalShares = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            if (!liquidTokenManager.tokenIsSupported(assets[i])) revert UnsupportedAsset(assets[i]);
            if (amounts[i] == 0) revert ZeroAmount();
            totalShares += calculateShares(assets[i], amounts[i]);
        }

        if (totalShares == 0) revert ZeroAmount();

        if (balanceOf(msg.sender) < totalShares)
            revert InsufficientBalance(IERC20(address(this)), totalShares, balanceOf(msg.sender));

        // Receive LAT shares
        _transfer(msg.sender, address(this), totalShares);

        // Burn shares since there is no cancelling the withdrawal request
        _burn(address(this), totalShares);

        // Create a withdrawal request for the user
        bytes32 requestId = keccak256(
            abi.encodePacked(msg.sender, assets, amounts, block.timestamp, _withdrawalNonce[msg.sender])
        );
        withdrawalManager.createWithdrawalRequest(assets, amounts, msg.sender, requestId);
        _withdrawalNonce[msg.sender] += 1;

        return requestId;
    }

    /// @inheritdoc ILiquidToken
    function previewWithdrawal(IERC20[] memory assets, uint256[] memory amounts) external view override returns (bool) {
        return _previewWithdrawal(assets, amounts);
    }

    /// @inheritdoc ILiquidToken
    function creditQueuedAssetBalances(IERC20[] calldata assets, uint256[] calldata amounts) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager) && msg.sender != address(withdrawalManager))
            revert UnauthorizedAccess(msg.sender);

        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            queuedAssetBalances[address(assets[i])] += amounts[i];
        }
    }

    /// @inheritdoc ILiquidToken
    function debitQueuedAssetBalances(IERC20[] calldata assets, uint256[] calldata amounts) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager) && msg.sender != address(withdrawalManager))
            revert UnauthorizedAccess(msg.sender);

        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            queuedAssetBalances[address(assets[i])] -= amounts[i];
        }
    }

    /// @inheritdoc ILiquidToken
    function creditAssetBalances(IERC20[] calldata assets, uint256[] calldata amounts) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager)) revert UnauthorizedAccess(msg.sender);

        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            assetBalances[address(assets[i])] += amounts[i];
        }
    }

    /// @inheritdoc ILiquidToken
    function transferAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts,
        address receiver
    ) external whenNotPaused {
        if (msg.sender != address(liquidTokenManager)) revert NotLiquidTokenManager(msg.sender);

        if (assetsToRetrieve.length != amounts.length) revert ArrayLengthMismatch();

        // Only `LiquidTokenManager` and `WithdrawalManager` can receive funds from this contract
        if (receiver != address(liquidTokenManager) && receiver != address(withdrawalManager))
            revert InvalidReceiver(receiver);

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = assetsToRetrieve[i];
            uint256 amount = amounts[i];

            if (!liquidTokenManager.tokenIsSupported(asset)) revert UnsupportedAsset(assetsToRetrieve[i]);

            if (amount > assetBalances[address(asset)])
                revert InsufficientBalance(asset, assetBalances[address(asset)], amount);

            assetBalances[address(asset)] -= amount;
            asset.safeTransfer(receiver, amount);

            if (assetBalances[address(asset)] > asset.balanceOf(address(this)))
                revert AssetBalanceOutOfSync(
                    assetsToRetrieve[i],
                    assetBalances[address(asset)],
                    asset.balanceOf(address(this))
                );

            emit AssetTransferred(assetsToRetrieve[i], amount, address(liquidTokenManager), msg.sender);
        }
    }

    /// @inheritdoc ILiquidToken
    function calculateShares(IERC20 asset, uint256 amount) public view returns (uint256) {
        uint256 assetAmountInUnitOfAccount = liquidTokenManager.convertToUnitOfAccount(asset, amount);
        return _convertToShares(assetAmountInUnitOfAccount);
    }

    /// @inheritdoc ILiquidToken
    function calculateAmount(IERC20 asset, uint256 shares) public view returns (uint256) {
        uint256 amountInUnitOfAccount = _convertToAssets(shares);
        return liquidTokenManager.convertFromUnitOfAccount(asset, amountInUnitOfAccount);
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ILiquidToken
    function totalAssets() public view returns (uint256) {
        IERC20[] memory supportedTokens = liquidTokenManager.getSupportedTokens();

        uint256 total = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            // Unstaked asset balances
            total += liquidTokenManager.convertToUnitOfAccount(supportedTokens[i], _balanceAsset(supportedTokens[i]));

            // Queued asset balances
            total += liquidTokenManager.convertToUnitOfAccount(
                supportedTokens[i],
                _balanceQueuedAsset(supportedTokens[i])
            );

            // Staked withdrawable asset balances
            total += liquidTokenManager.getWithdrawableAssetBalance(supportedTokens[i]);
        }

        return total;
    }

    /// @inheritdoc ILiquidToken
    function balanceAssets(IERC20[] calldata assetList) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assetList.length);
        for (uint256 i = 0; i < assetList.length; i++) {
            balances[i] = _balanceAsset(assetList[i]);
        }
        return balances;
    }

    /// @inheritdoc ILiquidToken
    function balanceQueuedAssets(IERC20[] calldata assetList) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assetList.length);
        for (uint256 i = 0; i < assetList.length; i++) {
            balances[i] = _balanceQueuedAsset(assetList[i]);
        }
        return balances;
    }

    // ------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------

    /// @dev Called by `calculateShares`
    function _convertToShares(uint256 amount) internal view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAsset = totalAssets();

        // Check for totalAssets being 0 to avoid division by zero
        if (supply == 0 || totalAsset == 0) {
            return amount;
        }

        return (amount * supply) / totalAsset;
    }

    /// @dev Called by `calculateAmount`
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 totalAsset = totalAssets();

        // Check for totalSupply being 0 to avoid division by zero
        if (supply == 0 || totalAsset == 0) {
            return shares;
        }

        return (shares * totalAsset) / supply;
    }

    /// @dev Called by `balanceAssets` and `totalAssets`
    function _balanceAsset(IERC20 asset) internal view returns (uint256) {
        return assetBalances[address(asset)];
    }

    /// @dev Called by `balanceQueuedAssets` and `totalAssets`
    function _balanceQueuedAsset(IERC20 asset) internal view returns (uint256) {
        return queuedAssetBalances[address(asset)];
    }

    /// @dev Called by `initiateWithdrawal` and `previewWithdrawal`
    function _previewWithdrawal(IERC20[] memory assets, uint256[] memory amounts) internal view returns (bool) {
        bool isPossible = true;
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            if (
                (assetBalances[address(asset)] + liquidTokenManager.getDepositAssetBalance(asset)) < amounts[i] // Preview with pre-slashing balances
            ) {
                isPossible = false;
                break;
            }
        }
        return isPossible;
    }

    // ------------------------------------------------------------------------------
    // Misc
    // ------------------------------------------------------------------------------

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
