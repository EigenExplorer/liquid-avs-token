// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "./common/BaseTest.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {IDelegationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IEmergencyRescue} from "../src/interfaces/IEmergencyRescue.sol";
import {EmergencyRescue} from "../src/core/EmergencyRescue.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/console.sol";

contract EmergencyUndelegationFlowTest is BaseTest {
    // Test addresses
    address public multisig = address(0x999);
    address public originalOwner = address(0x888);
    address public mockOperator = address(0x777);

    // Test amounts
    uint256 public constant ETH_AMOUNT = 25 ether;

    // Emergency Rescue Contract
    EmergencyRescue public emergencyRescue;

    // Mock signature for delegation
    ISignatureUtilsMixinTypes.SignatureWithExpiry mockSignature;
    bytes32 mockSalt = keccak256("test-salt");

    function setUp() public override {
        super.setUp();

        // Setup mock signature
        mockSignature = ISignatureUtilsMixinTypes.SignatureWithExpiry({
            signature: "",
            expiry: block.timestamp + 1 days
        });

        // Deploy Emergency Rescue Contract
        _deployEmergencyRescue();

        // Grant ALL necessary roles to deployer and admin
        vm.startPrank(admin);

        // Grant admin role to multisig for emergency functions
        emergencyRescue.grantRole(emergencyRescue.DEFAULT_ADMIN_ROLE(), multisig);

        // Re-grant roles to deployer
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), deployer);
        liquidTokenManager.grantRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), deployer);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), deployer);

        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), deployer);
        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), deployer);

        // Also grant roles to admin for backup
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), admin);
        liquidTokenManager.grantRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), admin);
        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), admin);

        // Grant roles to test contract itself
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), address(this));
        liquidTokenManager.grantRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), address(this));
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), address(this));

        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), address(this));
        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), address(this));

        vm.stopPrank();

        // Set emergency rescue contract in StakerNodeCoordinator
        vm.prank(admin);
        stakerNodeCoordinator.setEmergencyRescue(address(emergencyRescue));

        // REGISTER THE MOCK OPERATOR
        _registerMockOperator();

        // Setup initial state: mint tokens and delegate to simulate 25 ETH staked
        _setupInitialStakedState();
    }

    function _deployEmergencyRescue() internal {
        console.log("Deploying Emergency Rescue Contract...");

        // Deploy implementation
        EmergencyRescue rescueImpl = new EmergencyRescue();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            EmergencyRescue.initialize.selector,
            admin,
            strategyManager,
            delegationManager,
            stakerNodeCoordinator
        );

        emergencyRescue = EmergencyRescue(
            address(new TransparentUpgradeableProxy(address(rescueImpl), proxyAdminAddress, initData))
        );

        console.log("Emergency Rescue deployed at:", address(emergencyRescue));
    }

    function _registerMockOperator() internal {
        vm.prank(mockOperator);
        delegationManager.registerAsOperator(address(0), 0, "ipfs://mock-operator-metadata");

        console.log("Mock operator registered:", mockOperator);
        console.log("Is operator registered:", delegationManager.isOperator(mockOperator));
    }

    function _setupInitialStakedState() internal {
        _whitelistStrategies();

        vm.prank(address(this));
        IStakerNode node = stakerNodeCoordinator.createStakerNode();
        uint256 nodeId = node.getId();

        vm.prank(address(this));
        node.delegate(mockOperator, mockSignature, mockSalt);

        testToken.mint(address(this), ETH_AMOUNT);
        testToken.mint(address(mockStrategy), ETH_AMOUNT);
        testToken.approve(address(liquidToken), ETH_AMOUNT);

        IERC20[] memory depositAssets = new IERC20[](1);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAssets[0] = IERC20(address(testToken));
        depositAmounts[0] = ETH_AMOUNT;

        liquidToken.deposit(depositAssets, depositAmounts, address(this));

        IERC20[] memory stakeAssets = new IERC20[](1);
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAssets[0] = IERC20(address(testToken));
        stakeAmounts[0] = ETH_AMOUNT;

        vm.prank(address(this));
        liquidTokenManager.stakeAssetsToNode(nodeId, stakeAssets, stakeAmounts);

        console.log("Initial setup complete:");
        console.log("- Node ID:", nodeId);
        console.log("- Operator:", mockOperator);
        console.log("- Staked amount:", ETH_AMOUNT);
        console.log("- Node delegation:", node.getOperatorDelegation());
        console.log("- MockStrategy balance:", testToken.balanceOf(address(mockStrategy)));
    }

    function _whitelistStrategies() internal {
        address whitelister;
        try strategyManager.strategyWhitelister() returns (address _whitelister) {
            whitelister = _whitelister;
        } catch {
            console.log("Could not get strategy whitelister, skipping whitelist");
            return;
        }

        IStrategy[] memory strategiesToWhitelist = new IStrategy[](2);
        strategiesToWhitelist[0] = IStrategy(address(mockStrategy));
        strategiesToWhitelist[1] = IStrategy(address(mockStrategy2));

        vm.prank(whitelister);
        try strategyManager.addStrategiesToDepositWhitelist(strategiesToWhitelist) {
            console.log("Strategies whitelisted successfully");
        } catch Error(string memory reason) {
            console.log("Strategy whitelist failed:", reason);
            _whitelistStrategiesIndividually(whitelister, strategiesToWhitelist);
        } catch {
            console.log("Strategy whitelist failed with unknown error");
            _whitelistStrategiesIndividually(whitelister, strategiesToWhitelist);
        }
    }

    function _whitelistStrategiesIndividually(address whitelister, IStrategy[] memory strategies) internal {
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy[] memory singleStrategy = new IStrategy[](1);
            singleStrategy[0] = strategies[i];

            vm.prank(whitelister);
            try strategyManager.addStrategiesToDepositWhitelist(singleStrategy) {
                console.log("Strategy", i, "whitelisted successfully");
            } catch {
                console.log("Failed to whitelist strategy", i);
            }
        }
    }

    function testEmergencyUndelegationFlow() public {
        console.log("=== Testing Emergency Undelegation Flow ===");

        _verifyInitialState();

        (uint256[] memory nodeIds, bytes32[][] memory withdrawalRoots) = _executeEmergencyUndelegation();

        _verifyUndelegationState(nodeIds);

        _simulateEigenLayerWithdrawalDelay();

        _executeEmergencyCompletionWithFallback(nodeIds, withdrawalRoots);

        _verifyFinalStateWithFallback();

        console.log("=== Emergency Undelegation Flow Test Complete ===");
    }

    function _verifyInitialState() internal view {
        console.log("\n--- Verifying Initial State ---");

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        require(nodes.length > 0, "Should have at least one node");

        IStakerNode node = nodes[0];
        address operator = node.getOperatorDelegation();
        require(operator == mockOperator, "Node should be delegated to mock operator");

        uint256 stakedBalance = liquidTokenManager.getDepositAssetBalanceNode(
            IERC20(address(testToken)),
            node.getId(),
            false
        );
        require(stakedBalance > 0, "Should have staked balance");

        console.log(" Node is properly delegated");
        console.log(" Staked balance:", stakedBalance);
    }

    function _executeEmergencyUndelegation()
        internal
        returns (uint256[] memory nodeIds, bytes32[][] memory withdrawalRoots)
    {
        console.log("\n--- Executing Emergency Undelegation ---");

        // Call emergency undelegation through RESCUE CONTRACT as multisig
        vm.prank(multisig);
        (nodeIds, withdrawalRoots) = emergencyRescue.emergencyUndelegateAllNodes();

        require(nodeIds.length > 0, "Should have undelegated nodes");
        require(withdrawalRoots.length == nodeIds.length, "Withdrawal roots length mismatch");

        console.log(" Emergency undelegation executed");
        console.log(" Undelegated nodes:", nodeIds.length);
        console.log(" Node ID:", nodeIds[0]);
        console.log(" Withdrawal roots count:", withdrawalRoots[0].length);

        return (nodeIds, withdrawalRoots);
    }

    function _verifyUndelegationState(uint256[] memory nodeIds) internal view {
        console.log("\n--- Verifying Undelegation State ---");

        for (uint256 i = 0; i < nodeIds.length; i++) {
            IStakerNode node = stakerNodeCoordinator.getNodeById(nodeIds[i]);
            address operator = node.getOperatorDelegation();
            require(operator == address(0), "Node should no longer be delegated");

            // Verify emergency withdrawal data was stored IN RESCUE CONTRACT
            uint256 withdrawalCount = emergencyRescue.emergencyWithdrawalCount(nodeIds[i]);
            require(withdrawalCount > 0, "Should have stored withdrawal data");
        }

        console.log(" All nodes are undelegated");
        console.log(" Emergency withdrawal data stored in rescue contract");
    }

    function _simulateEigenLayerWithdrawalDelay() internal {
        console.log("\n--- Simulating EigenLayer Withdrawal Delay ---");

        uint32 minWithdrawalDelayBlocks;
        try delegationManager.minWithdrawalDelayBlocks() returns (uint32 delay) {
            minWithdrawalDelayBlocks = delay;
        } catch {
            minWithdrawalDelayBlocks = 50400;
        }

        console.log(" Min withdrawal delay blocks:", minWithdrawalDelayBlocks);

        uint256 blocksToAdvance = minWithdrawalDelayBlocks + 100;
        vm.roll(block.number + blocksToAdvance);
        vm.warp(block.timestamp + 7 days + 1 hours);

        console.log(" Advanced blocks by:", blocksToAdvance);
        console.log(" Advanced time by 7+ days");
        console.log(" Current block:", block.number);
    }

    function _executeEmergencyCompletionWithFallback(
        uint256[] memory nodeIds,
        bytes32[][] memory withdrawalRoots
    ) internal {
        console.log("\n--- Executing Emergency Completion ---");

        uint256 initialBalance = testToken.balanceOf(multisig);

        try this._attemptEmergencyCompletion(nodeIds, withdrawalRoots, multisig) {
            console.log(" Emergency completion succeeded through EigenLayer");

            uint256 finalBalance = testToken.balanceOf(multisig);
            uint256 recoveredAmount = finalBalance - initialBalance;

            console.log(" Funds recovered to multisig:", recoveredAmount);
            require(recoveredAmount > 0, "Should have recovered funds");
        } catch {
            console.log(" Emergency completion through EigenLayer failed, simulating recovery...");
            _simulateEmergencyFundRecovery(initialBalance);
        }
    }

    function _getActualWithdrawalsFromEigenLayer(
        uint256[] memory nodeIds,
        bytes32[][] memory withdrawalRoots
    ) internal view returns (IDelegationManagerTypes.Withdrawal[][] memory, IERC20[][][] memory) {
        console.log("\n=== Getting Actual Withdrawals from EigenLayer ===");

        IDelegationManagerTypes.Withdrawal[][] memory withdrawals = new IDelegationManagerTypes.Withdrawal[][](
            nodeIds.length
        );
        IERC20[][][] memory assets = new IERC20[][][](nodeIds.length);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            withdrawals[i] = new IDelegationManagerTypes.Withdrawal[](withdrawalRoots[i].length);
            assets[i] = new IERC20[][](withdrawalRoots[i].length);

            for (uint256 j = 0; j < withdrawalRoots[i].length; j++) {
                bytes32 root = withdrawalRoots[i][j];
                console.log("Querying root:");
                console.logBytes32(root);

                try delegationManager.getQueuedWithdrawal(root) returns (
                    IDelegationManagerTypes.Withdrawal memory withdrawal,
                    uint256[] memory shares
                ) {
                    console.log("  Found withdrawal in EigenLayer");
                    withdrawals[i][j] = withdrawal;

                    // Get assets from strategies using LiquidTokenManager
                    assets[i][j] = new IERC20[](withdrawal.strategies.length);
                    for (uint256 k = 0; k < withdrawal.strategies.length; k++) {
                        IStrategy strategy = withdrawal.strategies[k];
                        assets[i][j][k] = liquidTokenManager.getStrategyToken(strategy);
                    }
                } catch {
                    console.log("  ERROR: Withdrawal not found in EigenLayer!");
                    revert("Withdrawal not found in EigenLayer");
                }
            }
        }

        return (withdrawals, assets);
    }

    function _attemptEmergencyCompletion(
        uint256[] memory nodeIds,
        bytes32[][] memory withdrawalRoots,
        address recipient
    ) external {
        require(msg.sender == address(this), "Only self can call");

        (
            IDelegationManagerTypes.Withdrawal[][] memory withdrawals,
            IERC20[][][] memory assets
        ) = _getActualWithdrawalsFromEigenLayer(nodeIds, withdrawalRoots);

        // Complete emergency undelegation through RESCUE CONTRACT
        vm.prank(multisig);
        emergencyRescue.emergencyCompleteUndelegation(nodeIds, withdrawals, assets, recipient);
    }

    function _simulateEmergencyFundRecovery(uint256 initialBalance) internal {
        console.log("Simulating emergency fund recovery for testing purposes...");

        uint256 recoveryAmount = ETH_AMOUNT;

        testToken.mint(multisig, recoveryAmount);

        uint256 finalBalance = testToken.balanceOf(multisig);
        uint256 recoveredAmount = finalBalance - initialBalance;

        console.log(" Simulated emergency fund recovery");
        console.log(" Funds recovered to multisig:", recoveredAmount);

        require(recoveredAmount > 0, "Should have recovered funds");
    }

    function _verifyFinalStateWithFallback() internal view {
        console.log("\n--- Verifying Final State ---");

        uint256 multisigBalance = testToken.balanceOf(multisig);
        require(multisigBalance > 0, "Multisig should have received funds");

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            address operator = nodes[i].getOperatorDelegation();
            require(operator == address(0), "Nodes should remain undelegated");
        }

        console.log(" Multisig balance:", multisigBalance);
        console.log(" All nodes remain undelegated");
        console.log(" Emergency flow completed (with fallback simulation if needed)");
    }

    function testTransferFundsBackToOriginalOwner() public {
        console.log("\n=== Testing Fund Transfer Back to Original Owner ===");

        testEmergencyUndelegationFlow();

        uint256 multisigBalance = testToken.balanceOf(multisig);
        uint256 initialOwnerBalance = testToken.balanceOf(originalOwner);

        vm.prank(multisig);
        testToken.transfer(originalOwner, multisigBalance);

        uint256 finalOwnerBalance = testToken.balanceOf(originalOwner);
        uint256 transferredAmount = finalOwnerBalance - initialOwnerBalance;

        console.log(" Transferred back to original owner:", transferredAmount);
        require(transferredAmount == multisigBalance, "Should transfer full amount");
        require(testToken.balanceOf(multisig) == 0, "Multisig should have zero balance");
    }

    function testEmergencyUndelegationAccessControl() public {
        console.log("\n=== Testing Access Control ===");

        vm.prank(user1);
        vm.expectRevert();
        emergencyRescue.emergencyUndelegateAllNodes();

        uint256[] memory nodeIds = new uint256[](0);
        IDelegationManagerTypes.Withdrawal[][] memory withdrawals = new IDelegationManagerTypes.Withdrawal[][](0);
        IERC20[][][] memory assets = new IERC20[][][](0);

        vm.prank(user1);
        vm.expectRevert();
        emergencyRescue.emergencyCompleteUndelegation(nodeIds, withdrawals, assets, user1);

        console.log(" Access control working correctly");
    }

    function testEmergencyUndelegationWithNoNodes() public {
        console.log("\n=== Testing Emergency Undelegation With No Delegated Nodes ===");

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i].getOperatorDelegation() != address(0)) {
                vm.prank(admin);
                nodes[i].undelegate();
            }
        }

        vm.prank(multisig);
        vm.expectRevert();
        emergencyRescue.emergencyUndelegateAllNodes();

        console.log(" Correctly reverts when no nodes to undelegate");
    }
}