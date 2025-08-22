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
    address[] public unsupportedAssets;

    /// @notice Claimer for earners on EL - using EnumerableSet for efficient operations
    mapping(address => bool) public isClaimerFor;
    EnumerableSetUpgradeable.AddressSet private _claimerForSet;

    // ------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------

    // Events inherited from IRewardsManager interface

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

    /// @dev Process a single claim - transfers all token balances to LAT
    /// @dev These values tell us the actual tokens realized by the LAT after a process claim procedure
    /// @dev The values may differ from the corresponding EL event due to rounding/transfer loss or unexpected token transfers to this contract
    /// @dev We are only concerned with actual value accrued to LAT, exact EL data can be found via corresponding EL events
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

        // Transfer ALL balances of supported tokens to LiquidToken
        uint256[] memory supportedAmounts = new uint256[](supportedCount);
        for (uint256 i = 0; i < supportedCount; i++) {
            uint256 fullBalance = supportedTokens[i].balanceOf(address(this));
            if (fullBalance > 0) {
                supportedTokens[i].safeTransfer(address(liquidToken), fullBalance);
                supportedAmounts[i] = fullBalance;
            }
        }

        // Record full balances for unsupported tokens (not additive - we set the full balance)
        uint256[] memory unsupportedAmounts = new uint256[](unsupportedCount);
        for (uint256 i = 0; i < unsupportedCount; i++) {
            address assetAddr = address(unsupportedTokens[i]);
            uint256 fullBalance = unsupportedTokens[i].balanceOf(address(this));
            unsupportedAmounts[i] = fullBalance;
            
            // Update storage
            uint256 oldBalance = unsupportedAssetBalances[assetAddr];
            
            // Add to unsupported assets array if new
            if (oldBalance == 0 && fullBalance > 0) {
                unsupportedAssets.push(assetAddr);
            }
            
            // Set the full balance (not additive)
            unsupportedAssetBalances[assetAddr] = fullBalance;
            
            // Emit event if balance changed
            if (oldBalance != fullBalance) {
                emit UnsupportedAssetBalanceUpdated(assetAddr, oldBalance, fullBalance);
            }
        }

        // Credit LiquidToken with the transferred amounts
        if (supportedCount > 0 && supportedAmounts.length > 0) {
            liquidToken.creditAssetBalances(supportedTokens, supportedAmounts);
        }

        emit RewardsClaimed(
            claim.rootIndex,
            earner,
            supportedTokens,
            supportedAmounts,
            unsupportedTokens,
            unsupportedAmounts
        );
    }

    /// @dev Get unique tokens from claim to avoid processing duplicates
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
    function _isTokenSupported(IERC20 token, IERC20[] memory supportedTokens) internal pure returns (bool) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    /// @dev Resize token array to actual size
    function _resizeTokenArray(IERC20[] memory arr, uint256 newSize) internal pure returns (IERC20[] memory) {
        IERC20[] memory resized = new IERC20[](newSize);
        for (uint256 i = 0; i < newSize; i++) {
            resized[i] = arr[i];
        }
        return resized;
    }

    /// @dev Verify and update claimer status for an earner
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

    /// @dev Get balance of unsupported asset
    function _balanceAsset(IERC20 asset) internal view returns (uint256) {
        return unsupportedAssetBalances[address(asset)];
    }
}