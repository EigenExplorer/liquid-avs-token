// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

/// @title IStakerNode Interface
/// @notice Interface for the StakerNode contract
interface IStakerNode {
    /// @notice Initialization parameters for StakerNode
    struct Init {
        IStakerNodeCoordinator coordinator;
        uint256 id;
    }

    /// @notice Emitted when the StakerNode is delegated to an operator
    event NodeDelegated(address indexed operator, uint256 nodeId, address indexed delegator);

    /// @notice Emitted when the StakerNode is undelegated from the current operator
    event NodeUndelegated(bytes32[] withdrawalRoots, uint256 nodeId, address indexed undelegator);

    /// @notice Emitted when assets are deposited into an Eigenlayer strategy
    event AssetDepositedToStrategy(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 shares
    );

    /// @notice Error for zero address
    error ZeroAddress();

    /// @notice Error for unauthorized access by non-StakerNode operator
    error NotStakerNodeOperator();

    /// @notice Error for unauthorized access by non-StakerNode delegator
    error NotStakerNodeDelegator();

    /// @notice Error for unauthorized access by non-LiquidTokenManager
    error NotLiquidTokenManager();

    /// @notice Error for unauthorized access
    error UnauthorizedAccess(address caller, bytes32 requiredRole);

    /// @notice Error for delegating node when already delegated
    error NodeIsDelegated(address operatorDelegation);

    /// @notice Error for undelegating node when not delegated
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
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external;

    function withdraw(IStrategy[] calldata strategies, uint256[] calldata shareAmounts) external returns (bytes32); 

    /// @notice Undelegates the StakerNode's assets from the current operator
    function undelegate() external returns (bytes32[] memory);

    function completeUndelegationWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool receiveAsTokens
    ) external returns (IERC20[] memory);

    /// @notice Returns the address of the current implementation contract
    /// @return The address of the implementation contract
    function implementation() external view returns (address);

    /// @notice Returns the version of the contract that was last initialized
    /// @return The initialized version as a uint64
    function getInitializedVersion() external view returns (uint64);

    /// @notice Returns the id of the StakerNode
    /// @return The StakerNode's id as uint256
    function getId() external view returns (uint256);

    /// Returns the address of the operator the node is delegate to
    /// @return The address of the delegated operator or zero address if not delegated
    function getOperatorDelegation() external view returns (address);
}