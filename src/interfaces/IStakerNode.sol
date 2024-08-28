// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

interface IStakerNode {
    struct Init {
        IStakerNodeCoordinator coordinator;
        uint256 id;
    }

    event Delegated(address indexed operator);
    event Undelegated(bytes32[] withdrawalRoots);
    event DepositedToStrategy(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 shares
    );

    error ZeroAddress();
    error NotStakerNodeOperator();
    error NotStakerNodeDelegator();
    error NotLiquidTokenManager();
    error UnauthorizedAccess(address caller, bytes32 requiredRole);

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

    /// @notice Undelegates the StakerNode's assets from the current operator
    function undelegate() external;

    /// @notice Returns the address of the current implementation contract
    /// @return The address of the implementation contract
    function implementation() external view returns (address);

    /// @notice Returns the version of the contract that was last initialized
    /// @return The initialized version as a uint64
    function getInitializedVersion() external view returns (uint64);
}