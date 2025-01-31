// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "./common/BaseTest.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockERC20, MockERC20NoDecimals} from "./mocks/MockERC20.sol";

import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

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
            address(liquidTokenManager.getTokenStrategy(IERC20(address(testToken)))),
            address(mockStrategy)
        );
        assertEq(
            address(liquidTokenManager.getTokenStrategy(IERC20(address(testToken2)))),
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

    function testAddTokenSuccess() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        liquidTokenManager.addToken(newToken, decimals, initialPrice, volatilityThreshold, newStrategy);

        // Verify that the token was successfully added
        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(
            newToken
        );
        IStrategy strategy = liquidTokenManager.getTokenStrategy(newToken);
        assertEq(tokenInfo.decimals, decimals, "Incorrect decimals");
        assertEq(
              tokenInfo.decimals,
              IERC20Metadata(address(newToken)).decimals(),
              "Incorrect decimals"
        );
        assertEq(
            tokenInfo.pricePerUnit,
            initialPrice,
            "Incorrect initial price"
        );
        assertEq(
            address(strategy),
            address(newStrategy),
            "Incorrect strategy"
        );

        // Verify that the token is now supported
        assertTrue(
            liquidTokenManager.tokenIsSupported(newToken),
            "Token should be supported"
        );

        // Verify that the token is included in the supportedTokens array
        IERC20[] memory supportedTokens = liquidTokenManager.getSupportedTokens();
        bool isTokenInArray = false;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == newToken) {
                isTokenInArray = true;
                break;
            }
        }
        assertTrue(
            isTokenInArray,
            "Token should be in the supportedTokens array"
        );
    }

    function testAddTokenUnauthorized() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(user1);
        vm.expectRevert(); 
        liquidTokenManager.addToken(newToken, decimals, initialPrice, volatilityThreshold, newStrategy);
    }

    function testAddTokenZeroAddress() public {
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, IERC20(address(0)));

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.ZeroAddress.selector);
        liquidTokenManager.addToken(IERC20(address(0)), decimals, initialPrice, volatilityThreshold, newStrategy);
    }

    function testAddTokenStrategyZeroAddress() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.ZeroAddress.selector);
        liquidTokenManager.addToken(newToken, decimals, initialPrice, volatilityThreshold, IStrategy(address(0)));
    }

    function testAddTokenFailsIfAlreadySupported() public {
        // Try to add testToken which was already added in setUp()
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy duplicateStrategy = new MockStrategy(strategyManager, testToken);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.TokenExists.selector,
            address(testToken)
        ));
        liquidTokenManager.addToken(testToken, decimals, initialPrice, volatilityThreshold, duplicateStrategy);
    }

    function testAddTokenFailsForZeroDecimals() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidDecimals.selector);
        liquidTokenManager.addToken(newToken, 0, initialPrice, volatilityThreshold, newStrategy);
    }

    function testAddTokenFailsForMismatchedDecimals() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 6; // Actual decimals value is 18
        uint256 price = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.expectRevert(ILiquidTokenManager.InvalidDecimals.selector);
        liquidTokenManager.addToken(newToken, decimals, price, volatilityThreshold, newStrategy);
    }

    function testAddTokenSuccessForNoDecimalsFunction() public {
        IERC20 newToken = IERC20(address(new MockERC20NoDecimals())); // Doesn't have a `decimals()` function
        uint8 decimals = 6;
        uint256 price = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        liquidTokenManager.addToken(newToken, decimals, price, volatilityThreshold, newStrategy);

        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(
            newToken
        );
        assertEq(tokenInfo.decimals, decimals, "Incorrect decimals");
    }

    function testAddTokenFailsForZeroInitialPrice() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidPrice.selector);
        liquidTokenManager.addToken(newToken, decimals, 0, volatilityThreshold, newStrategy);
    }

    function testAddTokenFailsForInvalidThreshold() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 price = 1e18;
        uint256 volatilityThreshold = 50;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidThreshold.selector);
        liquidTokenManager.addToken(newToken, decimals, price, volatilityThreshold, newStrategy);
    }

    function testRemoveTokenSuccess() public {
        // First add a new token that we'll remove
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        liquidTokenManager.addToken(newToken, decimals, initialPrice, volatilityThreshold, newStrategy);

        // Verify token was added
        assertTrue(liquidTokenManager.tokenIsSupported(newToken));

        // Remove the token
        vm.prank(admin);
        liquidTokenManager.removeToken(newToken);

        // Verify token was removed
        assertFalse(liquidTokenManager.tokenIsSupported(newToken));

        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.TokenNotSupported.selector,
            newToken
        ));
        liquidTokenManager.getTokenInfo(newToken);

        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.StrategyNotFound.selector,
            newToken
        ));
        liquidTokenManager.getTokenStrategy(newToken);

        // Verify token is not in supported tokens array
        IERC20[] memory supportedTokens = liquidTokenManager.getSupportedTokens();
        bool isTokenInArray = false;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == newToken) {
                isTokenInArray = true;
                break;
            }
        }
        assertFalse(isTokenInArray, "Token should not be in the supportedTokens array");
    }

    function testRemoveTokenFailsForUnsupportedToken() public {
        IERC20 unsupportedToken = IERC20(address(new MockERC20("Unsupported", "UNS")));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.TokenNotSupported.selector,
            unsupportedToken
        ));
        liquidTokenManager.removeToken(unsupportedToken);
    }

    function testRemoveTokenFailsForNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        liquidTokenManager.removeToken(testToken);
    }

    function testRemoveTokenFailsIfNonZeroBalance() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        vm.prank(user1);
        liquidToken.deposit(assets, amounts, user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(testToken)
            )
        );
        liquidTokenManager.removeToken(testToken);
    }

    function testRemoveTokenFailsIfNodeHasShares() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        vm.prank(user1);
        liquidToken.deposit(assets, amounts, user1);

        uint256 nodeId = 0;
        uint256[] memory strategyAmounts = new uint256[](1);
        strategyAmounts[0] = 1 ether;
        IStrategy[] memory strategiesForNode = new IStrategy[](1);
        strategiesForNode[0] = mockStrategy;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, strategyAmounts);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(testToken)
            )
        );
        liquidTokenManager.removeToken(testToken);
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

    function testStakeAssetsToMultipleNodesLengthMismatch() public {
        uint256 nodeId = 0;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidTokenManager.LengthMismatch.selector, 1, 2));
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
    }

    function testInvalidStakingAmount() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0 ether;
    
        uint256 nodeId = 0;
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidTokenManager.InvalidStakingAmount.selector, 0)); // Expect InvalidStakingAmount with 0 value
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
    }

    function testGetStakedAssetBalanceInvalidNodeId() public {
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

        uint256 invalidNodeId = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakerNodeCoordinator.NodeIdOutOfRange.selector,
                invalidNodeId
            )
        );
        liquidTokenManager.getStakedAssetBalanceNode(
            testToken,
            invalidNodeId
        );
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
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        liquidTokenManager.setVolatilityThreshold(IERC20(address(testToken)), 0);  // Disable volatility check
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 2e18); // 1 testToken = 2 units
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 unit
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
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        liquidTokenManager.setVolatilityThreshold(IERC20(address(testToken)), 0);  // Disable volatility check
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 2e18); // 1 testToken = 2 units
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 unit
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
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 3e18); // 1 testToken = 3 units (increase in value)
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

    function testPriceUpdateUpdateFailsVolatilityCheck() public {
        vm.prank(admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.VolatilityThresholdHit.selector,
            testToken,
            1e18
        ));
        liquidTokenManager.updatePrice(testToken, 2e18); // 100% increase but only 10% is allowed
    }

    function testSetVolatilityThresholdSuccess() public {
        vm.prank(admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        vm.prank(admin);
        liquidTokenManager.setVolatilityThreshold(testToken, 0);
        liquidTokenManager.updatePrice(testToken, 10e18); // 10x increase should pass
    }

    function testSetVolatilityThresholdFailsForInvalidValue() public {
        vm.prank(admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidThreshold.selector);
        liquidTokenManager.setVolatilityThreshold(testToken, 20);
    }

    /*
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

    function testQueuedAssetBalancesUpdateAfterWithdrawalRequest() public {
        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );

        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(stakerNodeCoordinator)
        );

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50 ether;        
        
        vm.prank(user1);
        liquidToken.deposit(assets, amounts, user1);

        uint256 initialQueuedBalance = liquidToken.queuedAssetBalances(address(testToken));
        assertEq(initialQueuedBalance, 0, "Initial queued balance should be 0");

        uint256 nodeId = 0;
        uint256[] memory strategyAmounts = new uint256[](1);
        strategyAmounts[0] = 50 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, strategyAmounts);

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        liquidTokenManager.undelegateNodesFromOperators(nodeIds);

        uint256 finalQueuedBalance = liquidToken.queuedAssetBalances(address(testToken));
        assertEq(
            finalQueuedBalance, 
            50 ether, 
            "Queued assets balance should match original staked amount"
        );
    }

    function testQueuedWithdrawalsDoNotInflateShares() public {
        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );

        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(stakerNodeCoordinator)
        );

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50 ether;        
        
        vm.prank(user1);
        liquidToken.deposit(assets, amounts, user1);

        uint256 nodeId = 0;
        uint256[] memory strategyAmounts = new uint256[](1);
        strategyAmounts[0] = 50 ether;
        IStrategy[] memory strategiesForNode = new IStrategy[](1);
        strategiesForNode[0] = mockStrategy;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, strategyAmounts);

        uint256 sharesBeforeWithdrawalQueued = liquidToken.calculateShares(testToken, 1 ether);

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        liquidTokenManager.undelegateNodesFromOperators(nodeIds);

        uint256 expectedTotal = 50 ether;
        assertEq(liquidToken.totalAssets(), expectedTotal, "Total assets should include queued withdrawals");

        uint256 sharesAfterWithdrawalQueued = liquidToken.calculateShares(testToken, 1 ether);
        assertEq(sharesBeforeWithdrawalQueued, sharesAfterWithdrawalQueued, "Token is mispriced due to inflated shares");
    }
    */

    function testCannotDelegateDelegatedNode() public {
        address testOperator = address(uint160(uint256(keccak256(abi.encodePacked(
            block.timestamp + 1,  // Different from setUp() operator
            block.prevrandao
        )))));

        vm.prank(testOperator);
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: testOperator,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }),
            "ipfs://"
        );

        address currentOperator = stakerNode.getOperatorDelegation();
        assertTrue(currentOperator != address(0), "Node should be delegated in setUp");

        vm.prank(admin);
        ISignatureUtils.SignatureWithExpiry memory signature;
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakerNode.NodeIsDelegated.selector,
                currentOperator
            )
        );
        stakerNode.delegate(testOperator, signature, bytes32(0));
    }

    function testCannotUndelegateUndelegatedNode() public {
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_WITHDRAWER_ROLE(),
            admin
        );
        vm.prank(admin);
        stakerNode.undelegate();

        address operator = stakerNode.getOperatorDelegation();
        assertEq(operator, address(0), "Node should be undelegated");

        vm.prank(admin);
        vm.expectRevert(IStakerNode.NodeIsNotDelegated.selector);
        stakerNode.undelegate();
    }
}
