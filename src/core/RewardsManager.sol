// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IRewardsManager} from "../interfaces/IRewardsManager.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

/// @title RewardsManager
contract RewardsManager is
    IRewardsManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Role identifier for pausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice EigenLayer contracts
    IRewardsCoordinator public rewardsCoordinator;

    /// @notice LAT contracts
    ILiquidToken public liquidToken;
    ILiquidTokenManager public liquidTokenManager;

    /// @notice Unsupported rewards which remain in the contract until swapped out
    mapping(address => uint256) public unsupportedAssetBalances;
    address[] public unsupportedAssets;

    /// @notice Claimer for earners on EL - using EnumerableSet for efficient operations
    mapping(address => bool) public isClaimerFor;
    EnumerableSetUpgradeable.AddressSet private _claimerForSet;

    // ------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IRewardsManager
    function initialize(Init memory init) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        if (
            address(init.initialOwner) == address(0) ||
            address(init.pauser) == address(0) ||
            address(init.liquidToken) == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            address(init.rewardsCoordinator) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);

        liquidToken = init.liquidToken;
        liquidTokenManager = init.liquidTokenManager;
        rewardsCoordinator = init.rewardsCoordinator;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IRewardsManager
    function updateClaimerFor(address earner) external override nonReentrant {
        _verifyAndUpdateClaimerFor(earner);
    }

    /// @inheritdoc IRewardsManager
    function processClaim(
        IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim
    ) external override nonReentrant whenNotPaused {
        _processClaim(claim);
    }

    /// @inheritdoc IRewardsManager
    function processClaims(
        IRewardsCoordinatorTypes.RewardsMerkleClaim[] calldata claims
    ) external override nonReentrant whenNotPaused {
        require(claims.length <= 50, "Too many claims"); // Prevent gas exhaustion

        for (uint256 i = 0; i < claims.length; i++) {
            _processClaim(claims[i]);
        }
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IRewardsManager
    function balanceAssets(IERC20[] calldata assetList) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](assetList.length);
        for (uint256 i = 0; i < assetList.length; i++) {
            balances[i] = _balanceAsset(assetList[i]);
        }
        return balances;
    }

    /// @notice Get all claimers as an array (for backward compatibility)
    function claimerFor() external view returns (address[] memory) {
        return _claimerForSet.values();
    }

    /// @notice Get number of claimers
    function claimerForLength() external view returns (uint256) {
        return _claimerForSet.length();
    }

    // ------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------

    /// @dev Called by `processClaim` and `processClaims` - Fixed for reentrancy and balance calculation
    function _processClaim(IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim) internal {
        address earner = claim.earnerLeaf.earner;
        if (!_verifyAndUpdateClaimerFor(earner)) revert NotClaimerFor(earner);

        // Record balances BEFORE the external call to prevent reentrancy issues
        IERC20[] memory uniqueTokens = _getUniqueTokensFromClaim(claim);

        // Create properly sized arrays instead of using assembly manipulation
        // Fixed: Renamed to avoid shadowing
        IERC20[] memory supportedTokens = new IERC20[](uniqueTokens.length);
        IERC20[] memory unsupportedTokens = new IERC20[](uniqueTokens.length);
        uint256[] memory supportedBalancesBefore = new uint256[](uniqueTokens.length);
        uint256[] memory unsupportedBalancesBefore = new uint256[](uniqueTokens.length);

        uint256 supportedCount = 0;
        uint256 unsupportedCount = 0;

        IERC20[] memory allSupportedAssets = liquidTokenManager.getSupportedTokens();

        // Categorize tokens and record pre-claim balances
        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            IERC20 currentToken = uniqueTokens[i];
            bool isSupported = _isTokenSupported(currentToken, allSupportedAssets);

            if (isSupported) {
                supportedTokens[supportedCount] = currentToken;
                // Only count newly claimable balance, not existing contract balance
                supportedBalancesBefore[supportedCount] =
                    currentToken.balanceOf(address(this)) -
                    unsupportedAssetBalances[address(currentToken)];
                supportedCount++;
            } else {
                unsupportedTokens[unsupportedCount] = currentToken;
                unsupportedBalancesBefore[unsupportedCount] =
                    currentToken.balanceOf(address(this)) -
                    unsupportedAssetBalances[address(currentToken)];
                unsupportedCount++;
            }
        }

        // Resize arrays to actual counts
        supportedTokens = _resizeTokenArray(supportedTokens, supportedCount);
        unsupportedTokens = _resizeTokenArray(unsupportedTokens, unsupportedCount);
        supportedBalancesBefore = _resizeUintArray(supportedBalancesBefore, supportedCount);
        unsupportedBalancesBefore = _resizeUintArray(unsupportedBalancesBefore, unsupportedCount);

        // Make the external call to EigenLayer AFTER recording pre-state
        rewardsCoordinator.processClaim(claim, address(this));

        // Calculate actual received amounts by comparing post-claim balances
        uint256[] memory supportedReceivedAmounts = new uint256[](supportedCount);
        uint256[] memory unsupportedReceivedAmounts = new uint256[](unsupportedCount);

        for (uint256 i = 0; i < supportedCount; i++) {
            uint256 currentBalance = supportedTokens[i].balanceOf(address(this)) -
                unsupportedAssetBalances[address(supportedTokens[i])];
            supportedReceivedAmounts[i] = currentBalance > supportedBalancesBefore[i]
                ? currentBalance - supportedBalancesBefore[i]
                : 0;
        }

        for (uint256 i = 0; i < unsupportedCount; i++) {
            uint256 currentBalance = unsupportedTokens[i].balanceOf(address(this)) -
                unsupportedAssetBalances[address(unsupportedTokens[i])];
            unsupportedReceivedAmounts[i] = currentBalance > unsupportedBalancesBefore[i]
                ? currentBalance - unsupportedBalancesBefore[i]
                : 0;
        }

        // Update balances for unsupported tokens with events
        _setAssetBalances(unsupportedTokens, unsupportedReceivedAmounts);

        // Transfer supported assets to LiquidToken
        uint256[] memory netTransferredAmounts = _transferRewards(supportedTokens, supportedReceivedAmounts);

        emit RewardsClaimed(
            claim.rootIndex,
            earner,
            supportedTokens,
            netTransferredAmounts,
            unsupportedTokens,
            unsupportedReceivedAmounts
        );
    }

    /// @dev Get unique tokens from claim to avoid O(n²) complexity
    function _getUniqueTokensFromClaim(
        IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim
    ) internal view returns (IERC20[] memory) {
        // Fixed: Use arrays instead of mapping for uniqueness check
        IERC20[] memory tempTokens = new IERC20[](claim.tokenLeaves.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < claim.tokenLeaves.length; i++) {
            IERC20 currentToken = claim.tokenLeaves[i].token;
            bool isDuplicate = false;

            // Check if token already exists in our temp array
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempTokens[j] == currentToken) {
                    isDuplicate = true;
                    break;
                }
            }

            if (!isDuplicate) {
                tempTokens[uniqueCount] = currentToken;
                uniqueCount++;
            }
        }

        return _resizeTokenArray(tempTokens, uniqueCount);
    }

    /// @dev Helper to check if token is supported
    function _isTokenSupported(IERC20 token, IERC20[] memory supportedTokens) internal pure returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    /// @dev Resize token array without assembly
    function _resizeTokenArray(IERC20[] memory arr, uint256 newSize) internal pure returns (IERC20[] memory) {
        IERC20[] memory resized = new IERC20[](newSize);
        for (uint256 i = 0; i < newSize; i++) {
            resized[i] = arr[i];
        }
        return resized;
    }

    /// @dev Resize uint array without assembly
    function _resizeUintArray(uint256[] memory arr, uint256 newSize) internal pure returns (uint256[] memory) {
        uint256[] memory resized = new uint256[](newSize);
        for (uint256 i = 0; i < newSize; i++) {
            resized[i] = arr[i];
        }
        return resized;
    }

    /// @dev Called by `setClaimerFor` and `_processClaim` - Fixed with EnumerableSet
    function _verifyAndUpdateClaimerFor(address earner) internal returns (bool) {
        if (address(earner) == address(0)) revert ZeroAddress();

        // Check on EL if this contract is set as a claimer for the earner
        bool isClaimerOnEl = (rewardsCoordinator.claimerFor(earner) == address(this));

        // Update claimer storage vars if required
        if (isClaimerOnEl) {
            if (!isClaimerFor[earner]) {
                isClaimerFor[earner] = true;
                _claimerForSet.add(earner);
                emit ClaimerForAdded(earner);
            }
        } else {
            if (isClaimerFor[earner]) {
                isClaimerFor[earner] = false;
                _claimerForSet.remove(earner);
                emit ClaimerForRemoved(earner);
            }
        }

        return isClaimerOnEl;
    }

    /// @dev Called by `_processClaim` - Fixed with event emissions
    function _setAssetBalances(IERC20[] memory assets, uint256[] memory amounts) internal {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            address assetAddr = address(assets[i]);
            uint256 oldBalance = unsupportedAssetBalances[assetAddr];
            uint256 newBalance = oldBalance + amounts[i];

            if (unsupportedAssetBalances[assetAddr] == 0 && amounts[i] > 0) {
                unsupportedAssets.push(assetAddr);
            }

            unsupportedAssetBalances[assetAddr] = newBalance;

            if (amounts[i] > 0) {
                emit UnsupportedAssetBalanceUpdated(assetAddr, oldBalance, newBalance);
            }
        }
    }

    /// @dev Called by `_processClaim` - Fixed to use actual received amounts
    function _transferRewards(
        IERC20[] memory assets,
        uint256[] memory receivedAmounts
    ) internal returns (uint256[] memory) {
        if (assets.length != receivedAmounts.length) revert ArrayLengthMismatch();

        uint256[] memory netTransferredAmounts = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            if (receivedAmounts[i] > 0) {
                uint256 liquidTokenBalanceBefore = assets[i].balanceOf(address(liquidToken));

                // Transfer the actual received amount, not the stored balance
                assets[i].safeTransfer(address(liquidToken), receivedAmounts[i]);

                uint256 liquidTokenBalanceAfter = assets[i].balanceOf(address(liquidToken));
                netTransferredAmounts[i] = liquidTokenBalanceAfter - liquidTokenBalanceBefore;
            } else {
                netTransferredAmounts[i] = 0;
            }
        }

        // Credit LiquidToken asset balances with the actual net amounts received
        if (assets.length > 0) {
            liquidToken.creditAssetBalances(assets, netTransferredAmounts);
        }

        return netTransferredAmounts;
    }

    /// @dev Called by `balanceAssets`
    function _balanceAsset(IERC20 asset) internal view returns (uint256) {
        return unsupportedAssetBalances[address(asset)];
    }
}