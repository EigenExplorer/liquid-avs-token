// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

/**
 * @title StakerNode
 * @notice Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management
 * @dev Interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards
 */
contract StakerNode is IStakerNode, Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Role identifier for `LiquidTokenManager` operations
    bytes32 public constant LIQUID_TOKEN_MANAGER_ROLE = keccak256("LIQUID_TOKEN_MANAGER_ROLE");

    /// @notice Role identifier for delegation operations
    bytes32 public constant STAKER_NODES_DELEGATOR_ROLE = keccak256("STAKER_NODES_DELEGATOR_ROLE");

    /// @notice v1 LAT contracts
    IStakerNodeCoordinator public coordinator;

    uint256 public id;
    address public operatorDelegation;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IStakerNode
    function initialize(Init memory init) public notZeroAddress(address(init.coordinator)) initializer {
        __ReentrancyGuard_init();
        coordinator = IStakerNodeCoordinator(init.coordinator);
        id = init.id;
        operatorDelegation = address(0);
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IStakerNode
    function delegate(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) public override onlyRole(STAKER_NODES_DELEGATOR_ROLE) {
        if (operatorDelegation != address(0)) revert NodeIsDelegated(operatorDelegation);

        IDelegationManager delegationManager = coordinator.delegationManager();

        // Call EigenLayer contract to delegate stake
        delegationManager.delegateTo(operator, signature, approverSalt);
        operatorDelegation = operator;

        emit DelegatedToOperator(operator);
    }

    /// @inheritdoc IStakerNode
    function depositAssets(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external override nonReentrant onlyRole(LIQUID_TOKEN_MANAGER_ROLE) {
        if (operatorDelegation == address(0)) revert NodeIsNotDelegated();

        IStrategyManager strategyManager = coordinator.strategyManager();
        uint256 assetsLength = assets.length;

        unchecked {
            for (uint256 i = 0; i < assetsLength; i++) {
                IERC20 asset = assets[i];
                uint256 amount = amounts[i];
                IStrategy strategy = strategies[i];

                asset.forceApprove(address(strategyManager), amount);

                // Call EigenLayer contract to deposit asset
                uint256 eigenShares = strategyManager.depositIntoStrategy(strategy, asset, amount);

                emit AssetDepositedToStrategy(asset, strategy, amount, eigenShares);
            }
        }
    }

    /// @inheritdoc IStakerNode
    function withdrawAssets(
        IStrategy[] calldata strategies,
        uint256[] calldata shareAmounts
    ) external override onlyRole(LIQUID_TOKEN_MANAGER_ROLE) returns (bytes32) {
        if (operatorDelegation == address(0)) revert NodeIsNotDelegated();
        if (strategies.length != shareAmounts.length) revert LengthMismatch(strategies.length, shareAmounts.length);

        IDelegationManagerTypes.QueuedWithdrawalParams[]
            memory requestParams = new IDelegationManagerTypes.QueuedWithdrawalParams[](1);

        requestParams[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: strategies,
            depositShares: shareAmounts,
            __deprecated_withdrawer: address(this)
        });

        IDelegationManager delegationManager = coordinator.delegationManager();
        return delegationManager.queueWithdrawals(requestParams)[0];
    }

    /// @inheritdoc IStakerNode
    function completeWithdrawals(
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens
    ) external override onlyRole(LIQUID_TOKEN_MANAGER_ROLE) returns (IERC20[] memory) {
        uint256 arrayLength = withdrawals.length;
        bool[] memory receiveAsTokensArray = new bool[](arrayLength);

        for (uint256 i = 0; i < arrayLength; i++) {
            receiveAsTokensArray[i] = true;
        }

        IDelegationManager delegationManager = coordinator.delegationManager();
        delegationManager.completeQueuedWithdrawals(withdrawals, tokens, receiveAsTokensArray);

        uint256 totalTokenCount = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            totalTokenCount += tokens[i].length;
        }

        IERC20[] memory receivedTokens = new IERC20[](totalTokenCount);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokens[i].length; j++) {
                IERC20 token = tokens[i][j];
                uint256 balance = token.balanceOf(address(this));
                if (balance > 0) {
                    token.safeTransfer(msg.sender, balance);
                    receivedTokens[uniqueCount++] = token;
                }
            }
        }

        return receivedTokens;
    }

    /// @inheritdoc IStakerNode
    function undelegate() external override onlyRole(STAKER_NODES_DELEGATOR_ROLE) returns (bytes32[] memory) {
        if (operatorDelegation == address(0)) revert NodeIsNotDelegated();

        IDelegationManager delegationManager = coordinator.delegationManager();
        bytes32[] memory withdrawalRoots = delegationManager.undelegate(address(this));

        emit UndelegatedFromOperator(operatorDelegation);

        operatorDelegation = address(0);
        return withdrawalRoots;
    }

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc IStakerNode
    function implementation() public view override returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }

    /// @inheritdoc IStakerNode
    function getInitializedVersion() external view override returns (uint64) {
        return _getInitializedVersion();
    }

    /// @inheritdoc IStakerNode
    function getId() external view override returns (uint256) {
        return id;
    }

    /// @inheritdoc IStakerNode
    function getOperatorDelegation() external view override returns (address) {
        return operatorDelegation;
    }

    // ------------------------------------------------------------------------------
    // Misc
    // ------------------------------------------------------------------------------

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
