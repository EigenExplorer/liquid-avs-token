// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";

import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

/// @title IStakerNode Interface
/// @notice Interface for managing staking node functionality for tokens, enabling token staking, delegation, and rewards management
/// @dev Interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards
interface IStakerNode {
    /// @notice Initialization parameters for StakerNode
    /// @param coordinator The StakerNodeCoordinator contract
    /// @param id Unique identifier for this staker node
    struct Init {
        IStakerNodeCoordinator coordinator;
        uint256 id;
    }

    /// @notice Emitted node is delegated to an operator
    /// @param operator Address of the operator delegation
    event DelegatedToOperator(address operator);

    /// @notice Emitted node is undelegated from an operator
    /// @param operator Address of the operator undelegation
    event UndelegatedFromOperator(address operator);

    /// @notice Emitted when assets are successfully deposited into an Eigenlayer strategy
    /// @param asset Address of the token being deposited
    /// @param strategy Address of the Eigenlayer strategy receiving the deposit
    /// @param amount Amount of tokens being deposited
    /// @param shares Number of strategy shares received for the deposit
    event AssetDepositedToStrategy(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 shares
    );

    /// @notice Error thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Error thrown when array lengths don't match in function parameters
    /// @param length1 Length of the first array
    /// @param length2 Length of the second array
    error LengthMismatch(uint256 length1, uint256 length2);

    /// @notice Error thrown when a function restricted to StakerNode operator is called by another address
    error NotStakerNodeOperator();

    /// @notice Error thrown when a function restricted to StakerNode delegator is called by another address
    error NotStakerNodeDelegator();

    /// @notice Error thrown when a function restricted to LiquidTokenManager is called by another address
    error NotLiquidTokenManager();

    /// @notice Error thrown when no tokens are received after completing withdrawals
    error NoTokensReceived();

    /// @notice Error thrown when a caller lacks the required role for an operation
    /// @param caller Address that attempted the call
    /// @param requiredRole The role that was required
    error UnauthorizedAccess(address caller, bytes32 requiredRole);

    /// @notice Error thrown when attempting to delegate a node that is already delegated
    /// @param operatorDelegation The address the node is currently delegated to
    error NodeIsDelegated(address operatorDelegation);

    /// @notice Error thrown when attempting to undelegate a node that is not delegated
    error NodeIsNotDelegated();

    /// @notice Initializes the StakerNode contract
    /// @param init Initialization parameters including coordinator address and node ID
    function initialize(Init memory init) external;

    /// @notice Deposits assets into Eigenlayer strategies
    /// @param assets Array of ERC20 token addresses to deposit
    /// @param amounts Array of amounts to deposit for each asset
    /// @param strategies Array of Eigenlayer strategies to deposit into
    function depositAssets(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external;

    /// @notice Delegates the StakerNode's assets to an operator
    /// @param operator Address of the operator to delegate to
    /// @param signature Signature authorizing the delegation
    /// @param approverSalt Salt used in the signature
    function delegate(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external;

    /// @notice Undelegates the node from the current operator and withdraws all shares from all strategies
    /// @dev EL creates one withdrawal request per strategy in the case of undelegation
    /// @return Array of withdrawal root hashes from Eigenlayer
    function undelegate() external returns (bytes32[] memory);

    /// @notice Creates a withdrawal request of EL for a set of strategies
    /// @dev EL creates one withdrawal request regardless of the number of strategies
    /// @param strategies The set of strategies to withdraw from
    /// @param shareAmounts The amount of shares (unscaled `depositShares`) to withdraw per strategy
    /// @return The withdrawal root hash from Eigenlayer
    function withdrawAssets(
        IStrategy[] calldata strategies,
        uint256[] calldata shareAmounts
    ) external returns (bytes32);

    /// @notice Completes a set of withdrawal requests on EL and retrieves funds
    /// @dev The funds are always withdrawn in tokens and sent to LiquidTokenManager, ie the node never keeps unstaked assets
    /// @param withdrawals The set of EL withdrawals to complete and associated data
    /// @param tokens The set of tokens to receive funds in
    /// @return Array of token addresses that were received from the withdrawal
    function completeWithdrawals(
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens
    ) external returns (IERC20[] memory);

    /// @notice Returns the address of the current implementation contract
    /// @return The address of the implementation contract
    function implementation() external view returns (address);

    /// @notice Returns the version of the contract that was last initialized
    /// @return The initialized version as a uint64
    function getInitializedVersion() external view returns (uint64);

    /// @notice Returns the ID of the StakerNode
    /// @return The StakerNode's ID as uint256
    function getId() external view returns (uint256);

    /// @notice Returns the address of the operator the node is delegated to
    /// @return The address of the delegated operator or zero address if not delegated
    function getOperatorDelegation() external view returns (address);
}
