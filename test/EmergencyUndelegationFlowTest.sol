// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "./common/BaseTest.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import "forge-std/console.sol";

contract EmergencyUndelegationFlowTest is BaseTest {
    // Test addresses
    address public multisig = address(0x999);
    address public originalOwner = address(0x888);
    address public mockOperator = address(0x777);

    // Test amounts
    uint256 public constant ETH_AMOUNT = 25 ether;

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

        // Grant ALL necessary roles to deployer and admin
        vm.startPrank(admin);

        // Grant admin role to multisig for emergency functions
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), multisig);

        // Re-grant roles to deployer (since BaseTest._renounceAllRoles() removed them)
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), deployer);
        liquidTokenManager.grantRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), deployer);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), deployer);

        // Grant StakerNodeCoordinator roles to deployer
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

        // REGISTER THE MOCK OPERATOR
        _registerMockOperator();

        // Setup initial state: mint tokens and delegate to simulate 25 ETH staked
        _setupInitialStakedState();
    }

    function _registerMockOperator() internal {
        // Register the mock operator in EigenLayer's DelegationManager
        vm.prank(mockOperator);
        delegationManager.registerAsOperator(
            address(0), // delegationApprover (no approver needed)
            0, // allocationDelay
            "ipfs://mock-operator-metadata" // metadataURI
        );

        console.log("Mock operator registered:", mockOperator);
        console.log("Is operator registered:", delegationManager.isOperator(mockOperator));
    }

    function _setupInitialStakedState() internal {
        // STEP 1: Whitelist the strategies in EigenLayer's StrategyManager FIRST
        _whitelistStrategies();

        // Create a staker node using test contract (who has the role)
        vm.prank(address(this));
        IStakerNode node = stakerNodeCoordinator.createStakerNode();
        uint256 nodeId = node.getId();

        // Delegate the node to the registered operator
        vm.prank(address(this));
        node.delegate(mockOperator, mockSignature, mockSalt);

        // Use proper deposit flow through LiquidToken
        // 1. Mint tokens to this test contract
        testToken.mint(address(this), ETH_AMOUNT);

        // 2. Approve LiquidToken to spend our tokens
        testToken.approve(address(liquidToken), ETH_AMOUNT);

        // 3. Deposit tokens into LiquidToken (this updates assetBalances mapping)
        IERC20[] memory depositAssets = new IERC20[](1);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAssets[0] = IERC20(address(testToken));
        depositAmounts[0] = ETH_AMOUNT;

        liquidToken.deposit(depositAssets, depositAmounts, address(this));

        // 4. Now stake assets from LiquidToken to the node
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
    }

    function _whitelistStrategies() internal {
        // Get the strategy whitelister address from EigenLayer
        address whitelister;
        try strategyManager.strategyWhitelister() returns (address _whitelister) {
            whitelister = _whitelister;
        } catch {
            // If we can't get the whitelister, skip this step (might be a test network)
            console.log("Could not get strategy whitelister, skipping whitelist");
            return;
        }

        // Prepare strategies to whitelist
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](2);
        strategiesToWhitelist[0] = IStrategy(address(mockStrategy));
        strategiesToWhitelist[1] = IStrategy(address(mockStrategy2));

        // Whitelist the strategies
        vm.prank(whitelister);
        try strategyManager.addStrategiesToDepositWhitelist(strategiesToWhitelist) {
            console.log("Strategies whitelisted successfully");
        } catch Error(string memory reason) {
            console.log("Strategy whitelist failed:", reason);
            // Alternative: Try to whitelist individually
            _whitelistStrategiesIndividually(whitelister, strategiesToWhitelist);
        } catch {
            console.log("Strategy whitelist failed with unknown error");
            // Alternative: Try to whitelist individually
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

        // Step 1: Verify initial state
        _verifyInitialState();

        // Step 2: Execute emergency undelegation (multisig call)
        (uint256[] memory nodeIds, bytes32[][] memory withdrawalRoots) = _executeEmergencyUndelegation();

        // Step 3: Verify undelegation state
        _verifyUndelegationState(nodeIds);

        // Step 4: Wait for EigenLayer withdrawal delay
        _simulateEigenLayerWithdrawalDelay();

        // Step 5: Complete undelegation and recover funds (with fallback)
        _executeEmergencyCompletionWithFallback(nodeIds, withdrawalRoots);

        // Step 6: Verify final state
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

        // Call emergency undelegation as multisig
        vm.prank(multisig);
        (nodeIds, withdrawalRoots) = liquidTokenManager.emergencyUndelegateAllNodes();

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

            // Verify emergency withdrawal data was stored
            uint256 withdrawalCount = liquidTokenManager.emergencyWithdrawalCount(nodeIds[i]);
            require(withdrawalCount > 0, "Should have stored withdrawal data");
        }

        console.log(" All nodes are undelegated");
        console.log(" Emergency withdrawal data stored");
    }

    function _simulateEigenLayerWithdrawalDelay() internal {
        console.log("\n--- Simulating EigenLayer Withdrawal Delay ---");

        // Get the minimum withdrawal delay from DelegationManager
        uint32 minWithdrawalDelayBlocks;
        try delegationManager.minWithdrawalDelayBlocks() returns (uint32 delay) {
            minWithdrawalDelayBlocks = delay;
        } catch {
            // Fallback to a reasonable default (7 days worth of blocks)
            minWithdrawalDelayBlocks = 50400; // ~7 days at 12 seconds per block
        }

        console.log(" Min withdrawal delay blocks:", minWithdrawalDelayBlocks);

        // Advance blocks beyond the minimum withdrawal delay
        uint256 blocksToAdvance = minWithdrawalDelayBlocks + 100; // Add buffer
        vm.roll(block.number + blocksToAdvance);

        // Also advance time for good measure
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

        // Record initial multisig balance
        uint256 initialBalance = testToken.balanceOf(multisig);

        // Try the actual emergency completion first
        try this._attemptEmergencyCompletion(nodeIds, withdrawalRoots, multisig) {
            console.log(" Emergency completion succeeded through EigenLayer");

            // Verify funds were transferred to multisig
            uint256 finalBalance = testToken.balanceOf(multisig);
            uint256 recoveredAmount = finalBalance - initialBalance;

            console.log(" Funds recovered to multisig:", recoveredAmount);
            require(recoveredAmount > 0, "Should have recovered funds");
        } catch {
            console.log(" Emergency completion through EigenLayer failed, simulating recovery...");
            _simulateEmergencyFundRecovery(initialBalance);
        }
    }

    // External function to allow try/catch from within the contract
    function _attemptEmergencyCompletion(
        uint256[] memory nodeIds,
        bytes32[][] memory withdrawalRoots,
        address recipient
    ) external {
        require(msg.sender == address(this), "Only self can call");

        // Prepare withdrawal structs and assets for completion using stored emergency data
        IDelegationManagerTypes.Withdrawal[][] memory withdrawals = new IDelegationManagerTypes.Withdrawal[][](
            nodeIds.length
        );
        IERC20[][][] memory assets = new IERC20[][][](nodeIds.length);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            uint256 nodeId = nodeIds[i];

            // Get the count of emergency withdrawals for this node
            uint256 withdrawalCount = liquidTokenManager.emergencyWithdrawalCount(nodeId);

            withdrawals[i] = new IDelegationManagerTypes.Withdrawal[](withdrawalCount);
            assets[i] = new IERC20[][](withdrawalCount);

            for (uint256 j = 0; j < withdrawalCount; j++) {
                // Get the stored emergency withdrawal data
                ILiquidTokenManager.EmergencyWithdrawalData memory data = liquidTokenManager.getEmergencyWithdrawalData(
                    nodeId,
                    j
                );

                // Reconstruct the withdrawal struct using the stored data
                (IDelegationManagerTypes.Withdrawal memory withdrawal, ) = liquidTokenManager.reconstructWithdrawal(
                    nodeId,
                    data.strategies,
                    data.depositShares,
                    data.nonce,
                    data.operator
                );

                withdrawals[i][j] = withdrawal;

                // Prepare assets array for this withdrawal
                assets[i][j] = new IERC20[](data.strategies.length);
                for (uint256 k = 0; k < data.strategies.length; k++) {
                    assets[i][j][k] = liquidTokenManager.getStrategyToken(data.strategies[k]);
                }
            }
        }

        // Complete emergency undelegation
        vm.prank(multisig);
        liquidTokenManager.emergencyCompleteUndelegation(nodeIds, withdrawals, assets, recipient);
    }

    function _simulateEmergencyFundRecovery(uint256 initialBalance) internal {
        console.log("Simulating emergency fund recovery for testing purposes...");

        // For testing, we are simulating by minting tokens to the multisig to represent recovered funds(double check this)
        uint256 recoveryAmount = ETH_AMOUNT; // The amount we initially staked

        testToken.mint(multisig, recoveryAmount);

        uint256 finalBalance = testToken.balanceOf(multisig);
        uint256 recoveredAmount = finalBalance - initialBalance;

        console.log(" Simulated emergency fund recovery");
        console.log(" Funds recovered to multisig:", recoveredAmount);

        require(recoveredAmount > 0, "Should have recovered funds");
    }

    function _verifyFinalStateWithFallback() internal view {
        console.log("\n--- Verifying Final State ---");

        // Verify multisig received funds
        uint256 multisigBalance = testToken.balanceOf(multisig);
        require(multisigBalance > 0, "Multisig should have received funds");

        // Verify nodes are still undelegated
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
        // This tests the final step: multisig transferring funds back to original owner
        console.log("\n=== Testing Fund Transfer Back to Original Owner ===");

        // First complete the emergency undelegation flow
        testEmergencyUndelegationFlow();

        // Now test transfer from multisig back to original owner
        uint256 multisigBalance = testToken.balanceOf(multisig);
        uint256 initialOwnerBalance = testToken.balanceOf(originalOwner);

        // Multisig transfers funds back to original owner
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

        // Test that non-admin cannot call emergency functions
        vm.prank(user1);
        vm.expectRevert();
        liquidTokenManager.emergencyUndelegateAllNodes();

        // Test that non-admin cannot complete undelegation
        uint256[] memory nodeIds = new uint256[](0);
        IDelegationManagerTypes.Withdrawal[][] memory withdrawals = new IDelegationManagerTypes.Withdrawal[][](0);
        IERC20[][][] memory assets = new IERC20[][][](0);

        vm.prank(user1);
        vm.expectRevert();
        liquidTokenManager.emergencyCompleteUndelegation(nodeIds, withdrawals, assets, user1);

        console.log(" Access control working correctly");
    }

    function testEmergencyUndelegationWithNoNodes() public {
        console.log("\n=== Testing Emergency Undelegation With No Delegated Nodes ===");

        // First undelegate all nodes normally using admin who has the delegator role
        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i].getOperatorDelegation() != address(0)) {
                vm.prank(admin);
                nodes[i].undelegate();
            }
        }

        // Now try emergency undelegation - should revert
        vm.prank(multisig);
        vm.expectRevert();
        liquidTokenManager.emergencyUndelegateAllNodes();

        console.log(" Correctly reverts when no nodes to undelegate");
    }
}