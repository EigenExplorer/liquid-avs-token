// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRewardsCoordinatorTypes} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {ILiquidToken} from "../interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";

/// @title IRewardsManager Interface
/// @notice Interface for the RewardsManager contract
interface IRewardsManager {
    // ============================================================================
    // STRUCTS
    // ============================================================================

    /// @notice Initialization parameters for RewardsManager
    struct Init {
        IRewardsCoordinator rewardsCoordinator;
        ILiquidToken liquidToken;
        ILiquidTokenManager liquidTokenManager;
        address initialOwner;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    /// @notice Emitted when rewards are claimed
    event RewardsClaimed(
        uint32 indexed rootIndex,
        address indexed earner,
        IERC20[] supportedAssets,
        uint256[] supportedAmounts,
        IERC20[] unsupportedAssets,
        uint256[] unsupportedAmounts
    );

    /// @notice Emitted when a claimer is added for an earner
    event ClaimerForAdded(address indexed earner);

    /// @notice Emitted when a claimer is removed for an earner
    event ClaimerForRemoved(address indexed earner);

    // ============================================================================
    // CUSTOM ERRORS
    // ============================================================================

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error when this contract is not set as claimer for the earner
    error NotClaimerFor(address earner);

    /// @notice Error for mismatched array lengths
    error ArrayLengthMismatch();

    // ============================================================================
    // FUNCTIONS
    // ============================================================================

    /// @notice Initializes the RewardsManager contract
    /// @param init Initialization parameters
    function initialize(Init memory init) external;

    /// @notice Updates the claimer status for an earner
    /// @param earner The earner address to update claimer status for
    function updateClaimerFor(address earner) external;

    /// @notice Processes a single reward claim
    /// @param claim The reward merkle claim to process
    function processClaim(IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim) external;

    /// @notice Processes multiple reward claims
    /// @param claims Array of reward merkle claims to process
    function processClaims(IRewardsCoordinatorTypes.RewardsMerkleClaim[] calldata claims) external;

    /// @notice Returns the balances of unsupported assets for the given asset list
    /// @param assetList The list of assets to get balances for
    /// @return An array of asset balances
    function balanceAssets(IERC20[] calldata assetList) external view returns (uint256[] memory);
}
