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
/// @notice Manages reward claims from EigenLayer and distributes them to the Liquid Token
/// @dev Handles both supported and unsupported tokens, transferring all value to LAT holders
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
    EnumerableSetUpgradeable.AddressSet private _unsupportedAssets;

    /// @notice Claimer for earners on EL
    mapping(address => bool) public isClaimerFor;
    EnumerableSetUpgradeable.AddressSet private _claimerForSet;

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

    /// @notice For rewards that are in unsupported assets, swaps into supported assets and transfers over to LT
    /// @dev OUT OF SCOPE FOR V2
    /// function swapAndTransferRewards() external override nonReentrant whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc IRewardsManager
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IRewardsManager
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
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

    /// @inheritdoc IRewardsManager
    function claimerFor() external view returns (address[] memory) {
        return _claimerForSet.values();
    }

    /// @inheritdoc IRewardsManager
    function claimerForLength() external view returns (uint256) {
        return _claimerForSet.length();
    }

    /// @inheritdoc IRewardsManager
    function unsupportedAssets() external view returns (address[] memory) {
        return _unsupportedAssets.values();
    }

    function unsupportedAssetsLength() external view returns (uint256) {
        return _unsupportedAssets.length();
    }

    // ------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------

    /// @dev Called by `processClaim` and `processClaims`
    function _processClaim(IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim) internal {
        address earner = claim.earnerLeaf.earner;
        if (!_verifyAndUpdateClaimerFor(earner)) revert NotClaimerFor(earner);

        // Get unique tokens from the claim
        IERC20[] memory uniqueTokens = _getUniqueTokensFromClaim(claim);

        // Categorize tokens into supported and unsupported
        IERC20[] memory allSupportedAssets = liquidTokenManager.getSupportedTokens();

        IERC20[] memory supportedTokens = new IERC20[](uniqueTokens.length);
        IERC20[] memory unsupportedTokens = new IERC20[](uniqueTokens.length);
        uint256 supportedCount = 0;
        uint256 unsupportedCount = 0;

        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            IERC20 currentToken = uniqueTokens[i];
            bool isSupported = _isTokenSupported(currentToken, allSupportedAssets);

            if (isSupported) {
                supportedTokens[supportedCount] = currentToken;
                supportedCount++;
            } else {
                unsupportedTokens[unsupportedCount] = currentToken;
                unsupportedCount++;
            }
        }

        // Resize arrays to actual counts
        supportedTokens = _resizeTokenArray(supportedTokens, supportedCount);
        unsupportedTokens = _resizeTokenArray(unsupportedTokens, unsupportedCount);

        // Process the claim on EigenLayer
        rewardsCoordinator.processClaim(claim, address(this));

        // Update balances for unsupported tokens
        // These tokens will stay in the contract until `swapAndTransferRewards` is called
        uint256[] memory unsupportedAmounts = _setAssetBalances(unsupportedTokens);

        // Transfer all supported assets to `LiquidToken`
        uint256[] memory netTransferredAmounts = _transferRewards(supportedTokens);

        emit RewardsClaimed(
            claim.rootIndex,
            earner,
            supportedTokens,
            netTransferredAmounts,
            unsupportedTokens,
            unsupportedAmounts
        );
    }

    /// @dev Verify and update claimer status for an earner
    /// @dev Called by `_processClaim`
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

    /// @dev Get unique tokens from claim to avoid processing duplicates
    /// @dev Called by `_processClaim`
    function _getUniqueTokensFromClaim(
        IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim
    ) internal pure returns (IERC20[] memory) {
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
    /// @dev Called by `_processClaim`
    function _isTokenSupported(IERC20 token, IERC20[] memory supportedTokens) internal pure returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    /// @dev Resize token array to actual size
    /// @dev Called by `_processClaim`
    function _resizeTokenArray(IERC20[] memory arr, uint256 newSize) internal pure returns (IERC20[] memory) {
        IERC20[] memory resized = new IERC20[](newSize);
        for (uint256 i = 0; i < newSize; i++) {
            resized[i] = arr[i];
        }
        return resized;
    }

    /// @dev Called by `_processClaim`
    function _setAssetBalances(IERC20[] memory assets) internal returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            uint256 oldBalance = unsupportedAssetBalances[address(asset)];
            uint256 newBalance = asset.balanceOf(address(this));

            if (!_unsupportedAssets.contains(address(asset)) && newBalance > 0) {
                // Asset doesn't exist in set yet
                _unsupportedAssets.add(address(asset));
            }
            if (oldBalance != newBalance) {
                unsupportedAssetBalances[address(asset)] = newBalance;
                amounts[i] = newBalance;
                emit UnsupportedAssetBalanceUpdated(address(asset), oldBalance, newBalance);
            }
        }

        return amounts;
    }

    /// @dev Called by `_processClaim`
    function _transferRewards(IERC20[] memory assets) internal returns (uint256[] memory) {
        // Transfer to `LiquidToken` and calculate actual net amounts received
        uint256[] memory netTransferredAmounts = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            uint256 rewardsManagerBalanceBefore = asset.balanceOf(address(this));

            if (rewardsManagerBalanceBefore > 0) {
                uint256 liquidTokenBalanceBefore = asset.balanceOf(address(liquidToken));
                assets[i].safeTransfer(address(liquidToken), rewardsManagerBalanceBefore);
                uint256 liquidTokenBalanceAfter = assets[i].balanceOf(address(liquidToken));
                netTransferredAmounts[i] = liquidTokenBalanceAfter - liquidTokenBalanceBefore;
            } else {
                netTransferredAmounts[i] = 0;
            }
        }

        // Credit `LiquidToken` asset balances with the actual net amounts recieved
        liquidToken.creditAssetBalances(assets, netTransferredAmounts);

        return netTransferredAmounts;
    }

    /// @dev Get balance of unsupported asset
    /// @dev Called by `balanceAssets`
    function _balanceAsset(IERC20 asset) internal view returns (uint256) {
        return unsupportedAssetBalances[address(asset)];
    }
}
