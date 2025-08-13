// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IRewardsManager} from "../interfaces/IRewardsManager.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

/// @title RewardsManager
contract RewardsManager is IRewardsManager, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice EigenLayer contracts
    IRewardsCoordinator public rewardsCoordinator;

    /// @notice LAT contracts
    ILiquidToken public liquidToken;
    ILiquidTokenManager public liquidTokenManager;

    /// @notice Unsupported rewards which remain in the contract until swapped out
    mapping(address => uint256) public unsupportedAssetBalances;
    address[] public unsupportedAssets;

    /// @notice Claimer for earners on EL
    mapping(address => bool) public isClaimerFor;
    address[] public claimerFor;

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

        if (
            address(init.initialOwner) == address(0) ||
            address(init.liquidToken) == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            address(init.rewardsCoordinator) == address(0)
        ) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);

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
    ) external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        _processClaim(claim);
    }

    /// @inheritdoc IRewardsManager
    function processClaims(
        IRewardsCoordinatorTypes.RewardsMerkleClaim[] calldata claims
    ) external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < claims.length; i++) {
            _processClaim(claims[i]);
        }
    }

    /// @notice For rewards that are in unsupported assets, swaps into supported assets and transfers over to LT
    /// @dev OUT OF SCOPE FOR V2
    /// function swapAndTransferRewards() external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {}

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

    // ------------------------------------------------------------------------------
    // Internal functions
    // ------------------------------------------------------------------------------

    /// @dev Called by `processClaim` and `processClaims`
    function _processClaim(IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim) internal {
        address earner = claim.earnerLeaf.earner;
        if (!_verifyAndUpdateClaimerFor(earner)) revert NotClaimerFor(earner);

        // Call for claim on EL
        rewardsCoordinator.processClaim(claim, address(this));

        // Record current balances of all expected assets from this claim
        IERC20[] memory expectedSupportedAssets = new IERC20[](claim.tokenLeaves.length);
        IERC20[] memory expectedUnsupportedAssets = new IERC20[](claim.tokenLeaves.length);
        uint256[] memory supportedAssetBalances = new uint256[](claim.tokenLeaves.length);
        uint256[] memory unsupportedAssetBalances = new uint256[](claim.tokenLeaves.length);

        IERC20[] allSupportedAssets = liquidTokenManager.getSupportedTokens();
        uint256 supportedCount = 0;
        uint256 unsupportedCount = 0;

        for (uint256 i = 0; i < claim.tokenLeaves.length; i++) {
            IERC20 currentToken = claim.tokenLeaves[i].token;
            bool tokenAlreadyProcessed = false;

            for (uint256 k = 0; k < supportedCount; k++) {
                if (expectedSupportedAssets[k] == currentToken) {
                    tokenAlreadyProcessed = true;
                    break;
                }
            }

            if (!tokenAlreadyProcessed) {
                for (uint256 k = 0; k < unsupportedCount; k++) {
                    if (expectedUnsupportedAssets[k] == currentToken) {
                        tokenAlreadyProcessed = true;
                        break;
                    }
                }
            }

            if (!tokenAlreadyProcessed) {
                bool isSupported = false;

                for (uint256 j = 0; j < allSupportedAssets.length; j++) {
                    if (allSupportedAssets[j] == currentToken) {
                        isSupported = true;
                        break;
                    }
                }

                if (isSupported) {
                    expectedSupportedAssets[supportedCount] = currentToken;
                    supportedAssetBalances[supportedCount] = currentToken.balanceOf(address(this));
                    supportedCount++;
                } else {
                    expectedUnsupportedAssets[unsupportedCount] = currentToken;
                    unsupportedAssetBalances[unsupportedCount] = currentToken.balanceOf(address(this));
                    unsupportedCount++;
                }
            }
        }

        // Trim arrays to actual sizes
        assembly {
            mstore(expectedSupportedAssets, supportedCount)
            mstore(expectedUnsupportedAssets, unsupportedCount)
            mstore(supportedAssetBalances, supportedCount)
            mstore(unsupportedAssetBalances, unsupportedCount)
        }

        // Update balances for unsupported tokens
        // These tokens will stay in the contract until `swapAndTransferRewards` is called
        _setAssetBalances(expectedUnsupportedAssets, unsupportedAssetBalances);

        // Transfer all supported assets to `LiquidToken`
        _transferRewards(expectedSupportedAssets, supportedAssetBalances);

        emit RewardsClaimed(
            claim.rootIndex,
            earner,
            expectedSupportedAssets,
            supportedAssetBalances,
            expectedUnsupportedAssets,
            unsupportedAssetBalances
        );
    }

    /// @dev Called by `setClaimerFor` and `_processClaim`
    function _verifyAndUpdateClaimerFor(address earner) internal returns (bool) {
        if (address(earner) == address(0)) revert ZeroAddress();

        // Check on EL if this contract is set as a claimer for the earner
        bool isClaimerOnEl = (rewardsCoordinator.claimerFor(earner) == address(this));

        // Update claimer storage vars if required
        if (isClaimerOnEl) {
            if (!isClaimerFor[earner]) {
                isClaimerFor[earner] = true;
                claimerFor.push(earner);

                emit ClaimerForAdded(earner);
            }
        } else {
            if (isClaimerFor[earner]) {
                isClaimerFor[earner] = false;
                _removeClaimerFor(earner);
            }
        }

        return isClaimerOnEl;
    }

    /// @dev Called by `_verifyAndUpdateClaimerFor`
    function _removeClaimerFor(address earner) private {
        for (uint i = 0; i < claimerFor.length; i++) {
            if (claimerFor[i] == earner) {
                claimerFor[i] = claimerFor[claimerFor.length - 1];
                claimerFor.pop();
                emit ClaimerForRemoved(earner);
                break;
            }
        }
    }

    /// @dev Called by `_processClaim`
    function _setAssetBalances(IERC20[] memory assets, uint256[] memory amounts) internal {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < assets.length; i++) {
            if (unsupportedAssetBalances[address(assets[i])] == 0 && amounts[i] > 0) {
                unsupportedAssets.push(address(assets[i]));
            }
            unsupportedAssetBalances[address(assets[i])] = amounts[i];
        }
    }

    /// @dev Called by `_processClaim`
    function _transferRewards(IERC20[] memory assets, uint256[] memory amounts) internal {
        if (assets.length != amounts.length) revert ArrayLengthMismatch();

        // Transfer to `LiquidToken` and calculate actual net amounts received
        uint256[] memory netTransferredAmounts = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            uint256 liquidTokenBalanceBefore = assets[i].balanceOf(address(liquidToken));
            uint256 rewardsManagerBalanceBefore = amounts[i];

            if (rewardsManagerBalanceBefore > 0) {
                assets[i].safeTransfer(address(liquidToken), rewardsManagerBalanceBefore);
                uint256 liquidTokenBalanceAfter = assets[i].balanceOf(address(liquidToken));
                netTransferredAmounts[i] = liquidTokenBalanceAfter - liquidTokenBalanceBefore;
            } else {
                netTransferredAmounts[i] = 0;
            }
        }

        // Credit `LiquidToken` asset balances with the actual net amounts recieved
        liquidToken.creditAssetBalances(assets, netTransferredAmounts);
    }

    /// @dev Called by `balanceAssets`
    function _balanceAsset(IERC20 asset) internal view returns (uint256) {
        return unsupportedAssetBalances[address(asset)];
    }
}
