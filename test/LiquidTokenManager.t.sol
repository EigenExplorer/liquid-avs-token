// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "./common/BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";

contract LiquidTokenManagerTest is BaseTest {
    IStakerNode public stakerNode;

    function setUp() public override {
        super.setUp();

        // Create a staker node for testing
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();
        stakerNode = stakerNodeCoordinator.getAllNodes()[0];

        // Register a mock operator to EL
        address operatorAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(block.timestamp, block.prevrandao)
                    )
                )
            )
        );

        vm.prank(operatorAddress);
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: operatorAddress,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }),
            "ipfs://"
        );

        // Strategy whitelist
        ISignatureUtils.SignatureWithExpiry memory signature;
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](1);
        bool[] memory thirdPartyTransfersForbiddenValues = new bool[](1);

        strategiesToWhitelist[0] = IStrategy(address(mockStrategy));
        thirdPartyTransfersForbiddenValues[0] = false;

        vm.prank(strategyManager.strategyWhitelister());
        strategyManager.addStrategiesToDepositWhitelist(
            strategiesToWhitelist,
            thirdPartyTransfersForbiddenValues
        );

        // Delegate the staker node to EL
        stakerNode.delegate(operatorAddress, signature, bytes32(0));
    }

    function testInitialize() public {
        assertEq(
            address(liquidTokenManager.liquidToken()),
            address(liquidToken)
        );
        assertEq(
            address(liquidTokenManager.strategies(IERC20(address(testToken)))),
            address(mockStrategy)
        );
        assertEq(
            address(liquidTokenManager.strategies(IERC20(address(testToken2)))),
            address(mockStrategy2)
        );
        assertTrue(
            liquidTokenManager.hasRole(
                liquidTokenManager.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
        assertTrue(
            liquidTokenManager.hasRole(
                liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
                admin
            )
        );
    }

    function testSetStrategy() public {
        MockStrategy newStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(testToken))
        );
        vm.prank(admin);
        liquidTokenManager.setStrategy(
            IERC20(address(testToken)),
            IStrategy(address(newStrategy))
        );
        assertEq(
            address(liquidTokenManager.strategies(IERC20(address(testToken)))),
            address(newStrategy)
        );
    }

    function testSetStrategyUnauthorized() public {
        MockStrategy newStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(testToken))
        );
        vm.prank(user1);
        vm.expectRevert(); // TODO: Check if this is the correct revert message
        liquidTokenManager.setStrategy(
            IERC20(address(testToken)),
            IStrategy(address(newStrategy))
        );
    }

    function testStakeAssetsToNode() public {
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256 nodeId = 0;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        IStrategy[] memory strategiesForNode = new IStrategy[](1);
        strategiesForNode[0] = mockStrategy;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);

        (
            IStrategy[] memory depositStrategies,
            uint256[] memory depositAmounts
        ) = strategyManager.getDeposits(address(stakerNode));
        assertEq(address(depositStrategies[0]), address(mockStrategy));
        assertEq(depositAmounts[0], 1 ether);
    }

    function testStakeAssetsToNodeUnauthorized() public {
        uint256 nodeId = 1;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(user1);
        vm.expectRevert(); // TODO: Check if this is the correct revert message
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
    }

    function testGetStakedAssetBalanceInvalidStrategy() public {
        uint256 nodeId = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.StrategyNotFound.selector,
                address(0x123)
            )
        );
        liquidTokenManager.getStakedAssetBalanceNode(
            IERC20(address(0x123)),
            nodeId
        );
    }

    function testShareCalculation() public {
        vm.startPrank(admin);
        tokenRegistry.grantRole(tokenRegistry.PRICE_UPDATER_ROLE(), admin);

        tokenRegistry.updatePrice(IERC20(address(testToken)), 2e18); // 1 testToken = 2 units
        tokenRegistry.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 unit
        vm.stopPrank();

        // User1 deposits 10 ether of testToken
        vm.prank(user1);
        IERC20[] memory assetsToDepositUser1 = new IERC20[](1);
        assetsToDepositUser1[0] = IERC20(address(testToken));
        uint256[] memory amountsToDepositUser1 = new uint256[](1);
        amountsToDepositUser1[0] = 10 ether;
        
        liquidToken.deposit(assetsToDepositUser1, amountsToDepositUser1, user1);

        // User2 deposits 20 ether of testToken2
        vm.prank(user2);
        IERC20[] memory assetsToDepositUser2 = new IERC20[](1);
        assetsToDepositUser2[0] = IERC20(address(testToken2));
        uint256[] memory amountsToDepositUser2 = new uint256[](1);
        amountsToDepositUser2[0] = 20 ether;
        liquidToken.deposit(assetsToDepositUser2, amountsToDepositUser2, user2);

        uint256 totalAssets = liquidToken.totalAssets();
        uint256 totalSupply = liquidToken.totalSupply();

        // Validate the total supply and total assets
        assertEq(
            totalSupply,
            40 ether,
            "Total supply after deposits is incorrect"
        );
        assertEq(
            totalAssets,
            40 ether,
            "Total assets after deposits is incorrect"
        );

        // Validate the individual user shares
        uint256 user1Shares = liquidToken.balanceOf(user1);
        uint256 user2Shares = liquidToken.balanceOf(user2);

        assertEq(user1Shares, 20 ether, "User1 shares are incorrect");
        assertEq(user2Shares, 20 ether, "User2 shares are incorrect");
    }

    function testShareCalculationWithAssetValueIncrease() public {
        vm.startPrank(admin);
        tokenRegistry.grantRole(tokenRegistry.PRICE_UPDATER_ROLE(), admin);

        tokenRegistry.updatePrice(IERC20(address(testToken)), 2e18); // 1 testToken = 2 units
        tokenRegistry.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 unit
        vm.stopPrank();

        // User1 deposits 10 ether of testToken
        vm.prank(user1);
        IERC20[] memory assetsToDepositUser1 = new IERC20[](1);
        assetsToDepositUser1[0] = IERC20(address(testToken));
        uint256[] memory amountsToDepositUser1 = new uint256[](1);
        amountsToDepositUser1[0] = 10 ether;
        
        liquidToken.deposit(assetsToDepositUser1, amountsToDepositUser1, user1);

        // User2 deposits 20 ether of testToken2
        vm.prank(user2);
        IERC20[] memory assetsToDepositUser2 = new IERC20[](1);
        assetsToDepositUser2[0] = IERC20(address(testToken2));
        uint256[] memory amountsToDepositUser2 = new uint256[](1);
        amountsToDepositUser2[0] = 20 ether;
        liquidToken.deposit(assetsToDepositUser2, amountsToDepositUser2, user2);

        uint256 initialTotalAssets = liquidToken.totalAssets();
        uint256 initialTotalSupply = liquidToken.totalSupply();

        assertEq(
            initialTotalSupply,
            40 ether,
            "Initial total supply after deposits is incorrect"
        );
        assertEq(
            initialTotalAssets,
            40 ether,
            "Initial total assets after deposits is incorrect"
        );

        // Simulate a value increase
        vm.startPrank(admin);
        tokenRegistry.updatePrice(IERC20(address(testToken)), 3e18); // 1 testToken = 3 units (increase in value)
        vm.stopPrank();

        // Check totalAssets and totalSupply after price change
        uint256 totalAssetsAfterPriceChange = liquidToken.totalAssets();
        uint256 totalSupplyAfterPriceChange = liquidToken.totalSupply();

        assertEq(
            totalSupplyAfterPriceChange,
            initialTotalSupply,
            "Total supply should not change after price increase"
        );
        assertEq(
            totalAssetsAfterPriceChange,
            50 ether,
            "Total assets after price increase are incorrect"
        );

        // Validate the individual user shares remain unchanged
        uint256 user1Shares = liquidToken.balanceOf(user1);
        uint256 user2Shares = liquidToken.balanceOf(user2);

        assertEq(
            user1Shares,
            20 ether,
            "User1 shares are incorrect after price change"
        );
        assertEq(
            user2Shares,
            20 ether,
            "User2 shares are incorrect after price change"
        );
    }

    function testWithdrawalFailureDueToInsufficientBalance() public {
        // User1 deposits 10 ether
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256 nodeId = 0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);

        // User1 tries to request a withdrawal for 9 ether (should eventually fail in fulfillment)
        vm.startPrank(user1);
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 9 ether; // More than available

        liquidToken.requestWithdrawal(assets, withdrawalAmounts);
        vm.warp(block.timestamp + 15 days);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];
        vm.expectRevert(); // TODO: Check if this is the correct revert message

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();
    }

    function testSuccessfulWithdrawal() public {
        // User1 deposits 10 ether
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);
        vm.stopPrank();

        uint256 nodeId = 0;
        uint256[] memory amountsToStake = new uint256[](1);
        amountsToStake[0] = 5 ether;
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amountsToStake);

        uint256 availableBalance = liquidToken.balanceOf(user1);
        assertEq(
            availableBalance,
            10 ether,
            "User1 liquid balance should be 10 ether after staking."
        );

        // User1 requests a withdrawal for the available amount (should pass)
        vm.startPrank(user1);
        uint256[] memory withdrawalAmounts = new uint256[](1);
        withdrawalAmounts[0] = 5 ether; // Exactly the available amount

        liquidToken.requestWithdrawal(assets, withdrawalAmounts);

        vm.warp(block.timestamp + 15 days); // Simulate withdrawal delay

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];
        liquidToken.fulfillWithdrawal(requestId);

        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "User1 remaining balance after withdrawal is incorrect"
        );
        assertEq(
            IERC20(address(testToken)).balanceOf(user1),
            95 ether,
            "User1 token balance after withdrawal is incorrect"
        );

        vm.stopPrank();
    }
}
