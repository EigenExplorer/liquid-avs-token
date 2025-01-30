// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {IWithdrawalManager} from "../interfaces/IWithdrawalManager.sol";

/**
 * @title StakerNode
 * @notice Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management
 * @dev Interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards
 */
contract StakerNode is IStakerNode, Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IStakerNodeCoordinator public coordinator;
    uint256 public id;
    address public operatorDelegation;

    bytes32 public constant LIQUID_TOKEN_MANAGER_ROLE =
        keccak256("LIQUID_TOKEN_MANAGER_ROLE");
    bytes32 public constant STAKER_NODES_DELEGATOR_ROLE =
        keccak256("STAKER_NODES_DELEGATOR_ROLE");
    bytes32 public constant STAKER_NODES_WITHDRAWER_ROLE =
        keccak256("STAKER_NODES_WITHDRAWER_ROLE");

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the StakerNode contract
    /// @param init Initialization parameters including coordinator address and node ID
    function initialize(
        Init memory init
    ) public notZeroAddress(address(init.coordinator)) initializer {
        __ReentrancyGuard_init();
        coordinator = IStakerNodeCoordinator(init.coordinator);
        id = init.id;
        operatorDelegation = address(0);
    }

    /// @notice Deposits assets into Eigenlayer strategies
    /// @param assets Array of ERC20 token addresses to deposit
    /// @param amounts Array of amounts to deposit for each asset
    /// @param strategies Array of Eigenlayer strategies to deposit into
    function depositAssets(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external override nonReentrant onlyRole(LIQUID_TOKEN_MANAGER_ROLE) {
        IStrategyManager strategyManager = coordinator.strategyManager();

        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = strategies[i];

            asset.forceApprove(address(strategyManager), amount);

            uint256 eigenShares = strategyManager.depositIntoStrategy(
                strategy,
                asset,
                amount
            );

            emit AssetDepositedToStrategy(asset, strategy, amount, eigenShares);
        }
    }

    /// @notice Delegates the StakerNode's assets to an operator
    /// @param operator Address of the operator to delegate to
    /// @param signature Signature authorizing the delegation
    /// @param approverSalt Salt used in the signature
    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external override onlyRole(STAKER_NODES_DELEGATOR_ROLE) {
        if (operatorDelegation != address(0)) revert NodeIsDelegated(operatorDelegation);

        IDelegationManager delegationManager = coordinator.delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);
        operatorDelegation = operator;

        emit NodeDelegated(operator, id, msg.sender);
    }

    /// @notice Undelegates the StakerNode's assets from the current operator
    function undelegate()
        external
        override
        onlyRole(STAKER_NODES_WITHDRAWER_ROLE)
        returns (bytes32[] memory)
    {
        if (operatorDelegation == address(0)) revert NodeIsNotDelegated();

        IDelegationManager delegationManager = coordinator.delegationManager();
        bytes32[] memory withdrawalRoots = delegationManager.undelegate(
            address(this)
        );
        operatorDelegation = address(0);
        emit NodeUndelegated(withdrawalRoots, id, msg.sender);
        return withdrawalRoots;
    }

    function withdraw(IStrategy[] calldata strategies, uint256[] calldata shareAmounts)   
        external
        override
        onlyRole(STAKER_NODES_WITHDRAWER_ROLE)
        returns (bytes32)
    {
        IDelegationManager.QueuedWithdrawalParams[] memory requestParams = 
            new IDelegationManager.QueuedWithdrawalParams[](1);
        
        requestParams[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: shareAmounts,
            withdrawer: coordinator.withdrawerAddress()
        });

        IDelegationManager delegationManager = coordinator.delegationManager();
        return delegationManager.queueWithdrawals(requestParams)[0];
    }

    function completeUndelegationWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool receiveAsTokens
    )   external override onlyRole(STAKER_NODES_WITHDRAWER_ROLE) returns (IERC20[] memory) {
        uint256 arrayLength = withdrawals.length;
        bool[] memory receiveAsTokensArray = new bool[](arrayLength);

        if (receiveAsTokens == true) {
            for (uint256 i = 0; i < arrayLength; i++) {
                receiveAsTokensArray[i] = true;
            }
        } else {
            for (uint256 i = 0; i < arrayLength; i++) {
                receiveAsTokensArray[i] = false;
            }
        }

        IDelegationManager delegationManager = coordinator.delegationManager();
        delegationManager.completeQueuedWithdrawals(
            withdrawals,
            tokens,
            middlewareTimesIndexes,
            receiveAsTokensArray
        );

        IERC20[] memory receivedTokens;
        if (receiveAsTokens) {
            uint256 totalTokenCount = 0;
            for (uint256 i = 0; i < tokens.length; i++) {
                totalTokenCount += tokens[i].length;
            }

            IERC20[] memory tempTokens = new IERC20[](totalTokenCount);
            uint256 uniqueCount = 0;

            for (uint256 i = 0; i < tokens.length; i++) {
                for (uint256 j = 0; j < tokens[i].length; j++) {
                    IERC20 token = tokens[i][j];
                    uint256 balance = token.balanceOf(address(this));
                    if (balance > 0) {
                        token.safeTransfer(msg.sender, balance);
                        tempTokens[uniqueCount++] = token;
                    }
                }
            }

            receivedTokens = new IERC20[](uniqueCount);
            for (uint256 k = 0; k < uniqueCount; k++) {
                receivedTokens[k] = tempTokens[k];
            }
        }

        return receivedTokens;
    }

    /// @notice Returns the address of the current implementation contract
    /// @return The address of the implementation contract
    function implementation() public view override returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }

    /// @notice Returns the version of the contract that was last initialized
    /// @return The initialized version as a uint64
    function getInitializedVersion() external view override returns (uint64) {
        return _getInitializedVersion();
    }

    /// @notice Returns the id of the StakerNode
    /// @return id The StakerNode's id as uint256
    function getId() external view override returns (uint256) {
        return id;
    }

    /// Returns the address of the operator the node is delegate to
    /// @return The address of the delegated operator or zero address if not delegated
    function getOperatorDelegation() external view override returns (address) {
        return operatorDelegation;
    }

    /// @dev Reverts if the caller doesn't have the required role
    /// @param role The role to check for
    modifier onlyRole(bytes32 role) {
        if (role == LIQUID_TOKEN_MANAGER_ROLE) {
            if (!coordinator.hasLiquidTokenManagerRole(msg.sender)) {
                revert UnauthorizedAccess(msg.sender, role);
            }
        } else if (role == STAKER_NODES_DELEGATOR_ROLE) {
            if (!coordinator.hasStakerNodeDelegatorRole(msg.sender)) {
                revert UnauthorizedAccess(msg.sender, role);
            }
        } else if (role == STAKER_NODES_WITHDRAWER_ROLE) {
            if (!coordinator.hasStakerNodeWithdrawerRole(msg.sender)) {
                revert UnauthorizedAccess(msg.sender, role);
            }
        } else {
            revert("Unknown role");
        }
        _;
    }

    /// @dev Reverts if the address is zero
    /// @param _address The address to check
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
