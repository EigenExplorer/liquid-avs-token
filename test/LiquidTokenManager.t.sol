// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BaseTest} from "./common/BaseTest.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockERC20, MockERC20NoDecimals} from "./mocks/MockERC20.sol";

import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IWithdrawalManager} from "../src/interfaces/IWithdrawalManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

contract LiquidTokenManagerTest is BaseTest {    
    function setUp() public override {
        super.setUp();

        // Delegate staker node
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 0;
        address[] memory operators = new address[](1);
        operators[0] = operatorAddress;
        ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
        bytes32[] memory salts = new bytes32[](1);
        
        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIds, operators, sigs, salts);

        assertEq(
            stakerNode.getOperatorDelegation(),
            operatorAddress,
            "Node not delegated to correct operator"
        );
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
        vm.expectRevert(abi.encodeWithSelector(ILiquidTokenManager.InvalidStakingAmount.selector, 0));
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

        uint256 invalidNodeId = 2;
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

    function testCannotDelegateDelegatedNode() public {
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 0;
        address[] memory operators = new address[](1);
        address newOperator = address(0x123);
        operators[0] = newOperator;
        ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
        bytes32[] memory salts = new bytes32[](1);
        
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakerNode.NodeIsDelegated.selector,
                operatorAddress
            )
        );
        liquidTokenManager.delegateNodes(nodeIds, operators, sigs, salts);
    }

    function testUndelegateNodesWithoutRedemption() public {    
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 0;

        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);
        
        // Verify node is undelegated
        assertEq(
            stakerNode.getOperatorDelegation(),
            address(0),
            "Node still shows delegation after undelegation"
        );
    }

    function testUndelegateNodesWithRedemption() public {
    // Delegate 2nd node
    uint256[] memory nodeIdsToDelegate = new uint256[](1);
    nodeIdsToDelegate[0] = 1;
    address[] memory operators = new address[](1);
    operators[0] = operatorAddress;
    ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
    bytes32[] memory salts = new bytes32[](1);
    
    vm.prank(admin);
    liquidTokenManager.delegateNodes(nodeIdsToDelegate, operators, sigs, salts);

    // Prepare arrays for both nodes (0 and 1)
    uint256[] memory nodeIds = new uint256[](2);
    nodeIds[0] = 0;
    nodeIds[1] = 1;
    
    // Set up assets arrays with both tokens
    IERC20[] memory assets = new IERC20[](2);
    assets[0] = IERC20(address(testToken));
    assets[1] = IERC20(address(testToken2));
    
    // Deposit amounts for user
    uint256[] memory amountsToDeposit = new uint256[](2);
    amountsToDeposit[0] = 10 ether;
    amountsToDeposit[1] = 10 ether;
    
    // Stake amounts for nodes
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 1 ether;
    amounts[1] = 1 ether;

    // User deposits both tokens
    vm.prank(user1);
    liquidToken.deposit(assets, amountsToDeposit, user1);

    // Set up strategies for staking
    IStrategy[] memory strategiesForNode = new IStrategy[](2);
    strategiesForNode[0] = mockStrategy;
    strategiesForNode[1] = mockStrategy2;

    // Stake assets to both nodes
    vm.startPrank(admin);
    liquidTokenManager.stakeAssetsToNode(nodeIds[0], assets, amounts);
    liquidTokenManager.stakeAssetsToNode(nodeIds[1], assets, amounts);
    vm.stopPrank();

    // Get deposits for both nodes before undelegation
    (IStrategy[] memory strategies0, uint256[] memory depositAmounts0) = strategyManager.getDeposits(address(stakerNode));
    (IStrategy[] memory strategies1, uint256[] memory depositAmounts1) = strategyManager.getDeposits(address(stakerNode2));
    
    // Convert strategies to tokens for verification
    IERC20[] memory expectedAssets0 = new IERC20[](strategies0.length);
    IERC20[] memory expectedAssets1 = new IERC20[](strategies1.length);
    for (uint256 i = 0; i < strategies0.length; i++) {
        expectedAssets0[i] = liquidTokenManager.strategyTokens(strategies0[i]);
        expectedAssets1[i] = liquidTokenManager.strategyTokens(strategies1[i]);
    }
    
    // Set up event capture
    vm.recordLogs();
    
    // Undelegate both nodes
    vm.prank(admin);
    liquidTokenManager.undelegateNodes(nodeIds);
    
    // Verify both nodes are undelegated
    assertEq(
        stakerNode.getOperatorDelegation(),
        address(0),
        "Node 0 still shows delegation after undelegation"
    );
    assertEq(
        stakerNode2.getOperatorDelegation(),
        address(0),
        "Node 1 still shows delegation after undelegation"
    );

    // Get the recorded logs
    Vm.Log[] memory entries = vm.getRecordedLogs();
    
    // Find RedemptionCreatedForNodeUndelegation events for both nodes
    bytes32[] memory redemptionIds = new bytes32[](2);
    bytes32[] memory requestIds = new bytes32[](2);
    bytes32[][] memory withdrawalRoots = new bytes32[][](2);
    uint256 foundEvents = 0;
    
    for (uint256 i = 0; i < entries.length; i++) {
        if (entries[i].topics[0] == keccak256("RedemptionCreatedForNodeUndelegation(bytes32,bytes32,bytes32[],uint256)")) {
            (redemptionIds[foundEvents], requestIds[foundEvents], withdrawalRoots[foundEvents],) = abi.decode(
                entries[i].data, 
                (bytes32, bytes32, bytes32[], uint256)
            );
            foundEvents++;
            if (foundEvents == 2) break;
        }
    }
    
    // Verify redemptions for both nodes
    for (uint256 i = 0; i < 2; i++) {
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionIds[i]);
        assertEq(redemption.requestIds.length, 1, string.concat("Incorrect requestIds length for node"));
        assertEq(redemption.requestIds[0], requestIds[i], string.concat("Incorrect requestId for node"));
        assertEq(redemption.withdrawalRoots.length, withdrawalRoots[i].length, string.concat("Incorrect withdrawalRoots length for node"));
        assertEq(redemption.withdrawalRoots[0], withdrawalRoots[i][0], string.concat("Incorrect withdrawalRoot for node"));
        assertEq(redemption.receiver, address(liquidToken), string.concat("Incorrect receiver for node"));
        
        // Get and verify withdrawal requests
        IWithdrawalManager.ELWithdrawalRequest[] memory elRequests = withdrawalManager.getELWithdrawalRequests(withdrawalRoots[i]);
        
        // Verify withdrawal request details using the appropriate node and deposits
        address expectedStaker = i == 0 ? address(stakerNode) : address(stakerNode2);
        uint256[] memory expectedAmounts = i == 0 ? depositAmounts0 : depositAmounts1;
        IERC20[] memory expectedTokens = i == 0 ? expectedAssets0 : expectedAssets1;
        
        assertEq(elRequests[0].withdrawal.staker, expectedStaker, string.concat("Incorrect staker address for node"));
        assertEq(elRequests[0].withdrawal.delegatedTo, operatorAddress, string.concat("Incorrect operator address for node"));
        
        // Verify both token amounts and addresses
        for (uint256 j = 0; j < elRequests.length; j++) {
            for (uint256 k = 0; k < elRequests[k].assets.length; k++) {
                assertEq(elRequests[j].withdrawal.shares[k], expectedAmounts[j], string.concat("Incorrect withdrawal amount"));
                assertEq(address(elRequests[j].assets[k]), address(expectedTokens[j]), string.concat("Incorrect withdrawal asset"));
            }
        }
    }
}

    function testNodeUndelegationsDoNotInflateShares() public {
        // Stake assets to node
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

        // Get initial share calculation
        uint256 sharesBeforeWithdrawalQueued = liquidToken.calculateShares(testToken, 1 ether);

        // Perform undelegation
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 0;

        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);
        
        // Check share calculation after undelegation
        uint256 sharesAfterWithdrawalQueued = liquidToken.calculateShares(testToken, 1 ether);
        
        // Verify shares haven't been inflated
        assertEq(
            sharesBeforeWithdrawalQueued,
            sharesAfterWithdrawalQueued,
            "Token is mispriced due to inflated shares"
        );
    }

    function testCannotUndelegateUndelegatedNode() public {
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 1;
        
        vm.expectRevert(IStakerNode.NodeIsNotDelegated.selector);
        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);
    }

    function testWithdrawNodeAssets() public {
        uint256[] memory nodeIdsToDelegate = new uint256[](1);
        nodeIdsToDelegate[0] = 1;
        address[] memory operators = new address[](1);
        operators[0] = operatorAddress;
        ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
        bytes32[] memory salts = new bytes32[](1);
        
        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIdsToDelegate, operators, sigs, salts);

        // Helper function to set up test state with multiple nodes and assets
        (
            uint256[] memory nodeIds,
            uint256[][] memory initialNodeBalances
        ) = _setupWithdrawNodeAssetsTest();
        
        // Helper function to perform withdrawal and get event data
        (
            bytes32 redemptionId,
            bytes32[] memory requestIds,
            bytes32[] memory withdrawalRoots,
            uint256[] memory eventNodeIds
        ) = _performWithdrawNodeAssets(nodeIds);
        
        // Verify redemption details for multiple nodes and assets
        _verifyWithdrawNodeAssetsRedemption(
            redemptionId,
            requestIds,
            withdrawalRoots,
            eventNodeIds,
            nodeIds,
            initialNodeBalances
        );
    }

    // Helper functions to break down the test
    function _setupWithdrawNodeAssetsTest() internal returns (
        uint256[] memory nodeIds,
        uint256[][] memory initialNodeBalances
    ) {
        // Setup: Create nodes array
        nodeIds = new uint256[](2);
        nodeIds[0] = 0;
        nodeIds[1] = 1;
        
        // Setup: Create assets array
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        
        // Setup: Deposit assets from user1
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 20 ether; // More tokens to split across nodes
        amountsToDeposit[1] = 10 ether;
        
        vm.prank(user1);
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Stake different amounts to each node
        uint256[] memory amounts1 = new uint256[](2);
        amounts1[0] = 8 ether;
        amounts1[1] = 4 ether;

        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = 7 ether;
        amounts2[1] = 3 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeIds[0], assets, amounts1);
        
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeIds[1], assets, amounts2);

        // Store initial balances for both nodes and both assets
        initialNodeBalances = new uint256[][](2);
        initialNodeBalances[0] = new uint256[](2);
        initialNodeBalances[1] = new uint256[](2);
        
        for (uint256 i = 0; i < nodeIds.length; i++) {
            initialNodeBalances[i][0] = liquidTokenManager.getStakedAssetBalanceNode(testToken, nodeIds[i]);
            initialNodeBalances[i][1] = liquidTokenManager.getStakedAssetBalanceNode(testToken2, nodeIds[i]);
        }

        return (nodeIds, initialNodeBalances);
    }

    function _performWithdrawNodeAssets(uint256[] memory nodeIds) internal returns (
        bytes32 redemptionId,
        bytes32[] memory requestIds,
        bytes32[] memory withdrawalRoots,
        uint256[] memory eventNodeIds
    ) {
        // Setup withdrawal assets for each node
        IERC20[][] memory withdrawalAssets = new IERC20[][](2);
        uint256[][] memory shares = new uint256[][](2);
        
        for (uint256 i = 0; i < nodeIds.length; i++) {
            withdrawalAssets[i] = new IERC20[](2);
            withdrawalAssets[i][0] = testToken;
            withdrawalAssets[i][1] = testToken2;
            
            shares[i] = new uint256[](2);
            shares[i][0] = 3 ether; // Withdraw 3 ETH of first token
            shares[i][1] = 1 ether; // Withdraw 1 ETH of second token
        }

        vm.recordLogs();
        vm.prank(admin);
        liquidTokenManager.withdrawNodeAssets(nodeIds, withdrawalAssets, shares);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForRebalancing(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId, requestIds, withdrawalRoots, eventNodeIds) = abi.decode(
                    entries[i].data, 
                    (bytes32, bytes32[], bytes32[], uint256[])
                );
                break;
            }
        }
        return (redemptionId, requestIds, withdrawalRoots, eventNodeIds);
    }

    function _verifyWithdrawNodeAssetsRedemption(
        bytes32 redemptionId,
        bytes32[] memory requestIds,
        bytes32[] memory withdrawalRoots,
        uint256[] memory eventNodeIds,
        uint256[] memory nodeIds,
        uint256[][] memory initialNodeBalances
    ) internal {
        // Verify redemption basic details
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemption.requestIds.length, requestIds.length, "Incorrect requestIds length");
        assertEq(redemption.withdrawalRoots.length, withdrawalRoots.length, "Incorrect withdrawalRoots length");
        assertEq(redemption.receiver, address(liquidToken), "Incorrect receiver");

        // Verify withdrawal requests for each node
        IWithdrawalManager.ELWithdrawalRequest[] memory elRequests = 
            withdrawalManager.getELWithdrawalRequests(withdrawalRoots);
        
        for (uint256 i = 0; i < nodeIds.length; i++) {
            // Verify request details
            assertEq(elRequests[i].withdrawal.staker, address(stakerNodeCoordinator.getNodeById(nodeIds[i])), "Incorrect staker address");
            assertEq(elRequests[i].withdrawal.delegatedTo, operatorAddress, "Incorrect operator address");
            
            // Verify withdrawal amounts for each asset
            assertEq(elRequests[i].withdrawal.shares[0], 3 ether, "Incorrect withdrawal amount for first token");
            assertEq(elRequests[i].withdrawal.shares[1], 1 ether, "Incorrect withdrawal amount for second token");
            
            // Verify correct assets
            assertEq(address(elRequests[i].assets[0]), address(testToken), "Incorrect first withdrawal asset");
            assertEq(address(elRequests[i].assets[1]), address(testToken2), "Incorrect second withdrawal asset");

            // Verify remaining balances for each asset in each node
            uint256 expectedRemainingBalance1 = initialNodeBalances[i][0] - 3 ether;
            uint256 expectedRemainingBalance2 = initialNodeBalances[i][1] - 1 ether;
            
            uint256 actualRemainingBalance1 = liquidTokenManager.getStakedAssetBalanceNode(testToken, nodeIds[i]);
            uint256 actualRemainingBalance2 = liquidTokenManager.getStakedAssetBalanceNode(testToken2, nodeIds[i]);
            
            assertEq(
                actualRemainingBalance1,
                expectedRemainingBalance1,
                string.concat("Incorrect remaining balance for token1 in node ", vm.toString(nodeIds[i]))
            );
            assertEq(
                actualRemainingBalance2,
                expectedRemainingBalance2,
                string.concat("Incorrect remaining balance for token2 in node ", vm.toString(nodeIds[i]))
            );
        }
    }

    function testWithdrawNodeAssetsDoesNotInflateShares() public {
        // Setup phase
        (uint256 nodeId, uint256 sharesBeforeWithdrawal) = _setupInflateSharesTest();
        
        // Perform withdrawal
        _performWithdrawalForInflateTest(nodeId);
        
        // Verify shares
        uint256 sharesAfterWithdrawal = liquidToken.calculateShares(testToken, 1 ether);
        assertEq(
            sharesBeforeWithdrawal,
            sharesAfterWithdrawal,
            "Token is mispriced due to inflated shares"
        );
    }

    function _setupInflateSharesTest() internal returns (uint256 nodeId, uint256 sharesBeforeWithdrawal) {
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        nodeId = 0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);

        sharesBeforeWithdrawal = liquidToken.calculateShares(testToken, 1 ether);
        return (nodeId, sharesBeforeWithdrawal);
    }

    function _performWithdrawalForInflateTest(uint256 nodeId) internal {
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        IERC20[][] memory withdrawalAssets = new IERC20[][](1);
        withdrawalAssets[0] = new IERC20[](1);
        withdrawalAssets[0][0] = testToken;
        
        uint256[][] memory shares = new uint256[][](1);
        shares[0] = new uint256[](1);
        shares[0][0] = 2 ether;

        vm.prank(admin);
        liquidTokenManager.withdrawNodeAssets(nodeIds, withdrawalAssets, shares);
    }

    function testSettleUserWithdrawals() public {
        uint256[] memory nodeIdsToDelegate = new uint256[](1);
        nodeIdsToDelegate[0] = 1;
        address[] memory operators = new address[](1);
        operators[0] = operatorAddress;
        ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
        bytes32[] memory salts = new bytes32[](1);
        
        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIdsToDelegate, operators, sigs, salts);

        // Setup phase: Create deposits and withdrawal requests
        (bytes32[] memory requestIds, uint256[] memory nodeIds, uint256[] memory initialBalances) = _setupSettleUserWithdrawalsTest();
        
        // Execute settlement and capture events
        bytes32 redemptionId = _performSettlement(requestIds, nodeIds);
        
        // Verify the results
        _verifySettlementResults(redemptionId, requestIds, initialBalances);
    }

    // Helper function to set up the test state
    function _setupSettleUserWithdrawalsTest() internal returns (
        bytes32[] memory requestIds,
        uint256[] memory nodeIds,
        uint256[] memory initialBalances
    ) {
        // Create test users
        address user3 = makeAddr("user3");
        
        // Setup tokens for user3 (user1 and user2 are setup in BaseTest)
        testToken.mint(user3, 100 ether);
        testToken2.mint(user3, 100 ether);
        vm.prank(user3);
        testToken.approve(address(liquidToken), type(uint256).max);
        vm.prank(user3);
        testToken2.approve(address(liquidToken), type(uint256).max);

        // Set up deposits for all users
        IERC20[] memory depositAssets = new IERC20[](2);
        depositAssets[0] = IERC20(address(testToken));
        depositAssets[1] = IERC20(address(testToken2));
        
        uint256[] memory user1Amounts = new uint256[](2);
        user1Amounts[0] = 10 ether;
        user1Amounts[1] = 5 ether;
        
        uint256[] memory user2Amounts = new uint256[](2);
        user2Amounts[0] = 8 ether;
        user2Amounts[1] = 4 ether;
        
        uint256[] memory user3Amounts = new uint256[](2);
        user3Amounts[0] = 6 ether;
        user3Amounts[1] = 3 ether;

        vm.prank(user1);
        liquidToken.deposit(depositAssets, user1Amounts, user1);
        
        vm.prank(user2);
        liquidToken.deposit(depositAssets, user2Amounts, user2);
        
        vm.prank(user3);
        liquidToken.deposit(depositAssets, user3Amounts, user3);

        // Stake 50% of assets to nodes
        nodeIds = new uint256[](2);
        nodeIds[0] = 0;
        nodeIds[1] = 1;

        uint256[] memory stakeAmounts = new uint256[](2);
        stakeAmounts[0] = 6 ether;
        stakeAmounts[1] = 3 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeIds[0], depositAssets, stakeAmounts);
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeIds[1], depositAssets, stakeAmounts);

        // Create withdrawal requests
        vm.prank(user1);
        bytes32 request1Id = liquidToken.initiateWithdrawal(depositAssets, user1Amounts);
        
        vm.prank(user2);
        bytes32 request2Id = liquidToken.initiateWithdrawal(depositAssets, user2Amounts);
        
        vm.prank(user3);
        bytes32 request3Id = liquidToken.initiateWithdrawal(depositAssets, user3Amounts);

        initialBalances = new uint256[](2);
        initialBalances[0] = testToken.balanceOf(address(withdrawalManager));
        initialBalances[1] = testToken2.balanceOf(address(withdrawalManager));
        
        requestIds = new bytes32[](3);
        requestIds[0] = request1Id;
        requestIds[1] = request2Id;
        requestIds[2] = request3Id;
        
        return (requestIds, nodeIds, initialBalances);
    }

    // Helper function to perform the settlement
    function _performSettlement(bytes32[] memory requestIds, uint256[] memory nodeIds) internal returns (bytes32 redemptionId) {
        // Setup unstaked portion parameters
        IERC20[] memory ltAssets = new IERC20[](2);
        ltAssets[0] = testToken;
        ltAssets[1] = testToken2;
        uint256[] memory ltAmounts = new uint256[](2);
        ltAmounts[0] = 12 ether;
        ltAmounts[1] = 6 ether;

        // Setup staked portion parameters
        IERC20[][] memory elAssets = new IERC20[][](2);
        elAssets[0] = new IERC20[](2);
        elAssets[0][0] = testToken;
        elAssets[0][1] = testToken2;
        elAssets[1] = new IERC20[](2);
        elAssets[1][0] = testToken;
        elAssets[1][1] = testToken2;
        
        uint256[][] memory elShares = new uint256[][](2);
        elShares[0] = new uint256[](2);
        elShares[0][0] = 6 ether;
        elShares[0][1] = 3 ether;
        elShares[1] = new uint256[](2);
        elShares[1][0] = 6 ether;
        elShares[1][1] = 3 ether;

        vm.recordLogs();
        
        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(
            requestIds,
            ltAssets,
            ltAmounts,
            nodeIds,
            elAssets,
            elShares
        );

        // Extract redemption ID from logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId,,, ) = abi.decode(
                    entries[i].data, 
                    (bytes32, bytes32[], bytes32[], uint256[])
                );
                break;
            }
        }
        
        return redemptionId;
    }

    // Helper function to verify settlement results
    function _verifySettlementResults(
        bytes32 redemptionId,
        bytes32[] memory requestIds,
        uint256[] memory initialBalances
    ) internal {
        // Verify transfer amounts for first token
        uint256 expectedUnstakedTransfer1 = 12 ether;
        uint256 actualUnstakedTransfer1 = testToken.balanceOf(address(withdrawalManager)) - initialBalances[0];
        assertEq(actualUnstakedTransfer1, expectedUnstakedTransfer1, "Incorrect unstaked transfer amount for first token");

        // Verify transfer amounts for second token
        uint256 expectedUnstakedTransfer2 = 6 ether;
        uint256 actualUnstakedTransfer2 = testToken2.balanceOf(address(withdrawalManager)) - initialBalances[1];
        assertEq(actualUnstakedTransfer2, expectedUnstakedTransfer2, "Incorrect unstaked transfer amount for second token");

        // Verify redemption details
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemption.requestIds.length, requestIds.length, "Incorrect number of request IDs");
        for (uint256 i = 0; i < requestIds.length; i++) {
            assertEq(redemption.requestIds[i], requestIds[i], string.concat("Incorrect requestId at index ", vm.toString(i)));
        }
        assertEq(redemption.receiver, address(withdrawalManager), "Incorrect receiver");
    }

    function testSettleUserWithdrawalsDoesNotInflateShares() public {
        // Setup phase
        (bytes32 requestId, uint256 nodeId, uint256 sharesBeforeSettlement) = _setupSharesInflationTest();
        
        // Perform settlement
        _performSettlementForSharesTest(requestId, nodeId);
        
        // Verify shares weren't inflated
        uint256 sharesAfterSettlement = liquidToken.calculateShares(testToken, 1 ether);
        assertEq(
            sharesBeforeSettlement,
            sharesAfterSettlement,
            "Token is mispriced due to inflated shares"
        );
    }

    // Helper function for shares inflation test setup
    function _setupSharesInflationTest() internal returns (
        bytes32 requestId,
        uint256 nodeId,
        uint256 sharesBeforeSettlement
    ) {
        vm.prank(user1);
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 10 ether;
        
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        nodeId = 0;
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, depositAssets, stakeAmounts);

        sharesBeforeSettlement = liquidToken.calculateShares(testToken, 1 ether);

        vm.prank(user1);
        requestId = liquidToken.initiateWithdrawal(depositAssets, depositAmounts);

        return (requestId, nodeId, sharesBeforeSettlement);
    }

    function _performSettlementForSharesTest(bytes32 requestId, uint256 nodeId) internal {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        // Set up unstaked portion parameters
        IERC20[] memory ltAssets = new IERC20[](1);
        ltAssets[0] = testToken;
        uint256[] memory ltAmounts = new uint256[](1);
        ltAmounts[0] = 5 ether;

        // Set up staked portion parameters
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        IERC20[][] memory elAssets = new IERC20[][](1);
        elAssets[0] = new IERC20[](1);
        elAssets[0][0] = testToken;
        
        uint256[][] memory elShares = new uint256[][](1);
        elShares[0] = new uint256[](1);
        elShares[0][0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(
            requestIds,
            ltAssets,
            ltAmounts,
            nodeIds,
            elAssets,
            elShares
        );
    }

    function testSettleUserWithdrawalsFailsIfAllRequestsDontSettle() public {
        // Setup test state
        bytes32 requestId = _setupFailureTest(10 ether);
        
        // Attempt settlement with insufficient amounts
        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.RequestsDoNotSettle.selector,
            address(testToken),
            9 ether,  // Total amount provided
            10 ether  // Amount requested
        ));
        _attemptInsufficientSettlement(requestId);
    }

    // Helper function for failure test setup
    function _setupFailureTest(uint256 amount) internal returns (bytes32) {
        vm.prank(user1);
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = amount;
        
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        uint256 nodeId = 0;
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, depositAssets, stakeAmounts);

        vm.prank(user1);
        return liquidToken.initiateWithdrawal(depositAssets, depositAmounts);
    }

    // Helper function to attempt settlement with insufficient amounts
    function _attemptInsufficientSettlement(bytes32 requestId) internal {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        IERC20[] memory ltAssets = new IERC20[](1);
        ltAssets[0] = testToken;
        uint256[] memory ltAmounts = new uint256[](1);
        ltAmounts[0] = 4 ether;

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 0;
        
        IERC20[][] memory elAssets = new IERC20[][](1);
        elAssets[0] = new IERC20[](1);
        elAssets[0][0] = testToken;
        
        uint256[][] memory elShares = new uint256[][](1);
        elShares[0] = new uint256[](1);
        elShares[0][0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(
            requestIds,
            ltAssets,
            ltAmounts,
            nodeIds,
            elAssets,
            elShares
        );
    }

    function testCompleteRedemptionNodeUndelegation() public {
        // First, set up the test state with node delegation and assets
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Get initial balances
        uint256 initialLiquidTokenBalance = testToken.balanceOf(address(liquidToken));

        uint256 nodeId = 0;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;
        
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);

        // Record events for undelegation
        vm.recordLogs();
        
        // Perform undelegation
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);

        // Get redemption details from emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForNodeUndelegation(bytes32,bytes32,bytes32[],uint256)")) {
                (redemptionId,, withdrawalRoots,) = abi.decode(
                    entries[i].data,
                    (bytes32, bytes32, bytes32[], uint256)
                );
                break;
            }
        }

        // Verify redemption exists before completion
        ILiquidTokenManager.Redemption memory redemptionBefore = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemptionBefore.withdrawalRoots.length, withdrawalRoots.length, "Redemption not properly recorded");

        // Advance time and blocks to meet EigenLayer's withdrawal delay requirements
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400); // Approximately 7 days worth of blocks

        // Prepare completion parameters
        uint256[] memory completionNodeIds = new uint256[](1);
        completionNodeIds[0] = nodeId;
        
        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](1);
        completionWithdrawalRoots[0] = withdrawalRoots;

        // Complete the redemption
        vm.prank(admin);
        liquidTokenManager.completeRedemption(
            redemptionId,
            completionNodeIds,
            completionWithdrawalRoots
        );

        // Verify results
        uint256 finalLiquidTokenBalance = testToken.balanceOf(address(liquidToken));
        assertEq(
            finalLiquidTokenBalance,
            initialLiquidTokenBalance,
            "Incorrect final balance"
        );

        // Verify redemption is completed (deleted)
        vm.expectRevert(abi.encodeWithSelector(
            IWithdrawalManager.RedemptionNotFound.selector,
            redemptionId
        ));
        withdrawalManager.getRedemption(redemptionId);
    }

    function testCompleteRedemptionNodeUndelegationFailsForPartialCompletion() public {
        // First, set up the test state with node delegation and assets
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256 nodeId = 0;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5 ether;
        amounts[1] = 5 ether;
        
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);

        // Record events for undelegation
        vm.recordLogs();
        
        // Perform undelegation
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);

        // Get redemption details from emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForNodeUndelegation(bytes32,bytes32,bytes32[],uint256)")) {
                (redemptionId,, withdrawalRoots,) = abi.decode(
                    entries[i].data,
                    (bytes32, bytes32, bytes32[], uint256)
                );
                break;
            }
        }

        // Verify redemption exists before attempt
        ILiquidTokenManager.Redemption memory redemptionBefore = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemptionBefore.withdrawalRoots.length, withdrawalRoots.length, "Redemption not properly recorded");

        // Advance time and blocks to meet EigenLayer's withdrawal delay requirements
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400); // Approximately 7 days worth of blocks

        // Prepare completion parameters with missing withdrawal root
        uint256[] memory completionNodeIds = new uint256[](1);
        completionNodeIds[0] = nodeId;
        
        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](1);
        completionWithdrawalRoots[0] = new bytes32[](1);
        completionWithdrawalRoots[0][0] = withdrawalRoots[0];  // Only include first root

        // Attempt to complete the redemption with missing withdrawal root
        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.WithdrawalRootMissing.selector,
            withdrawalRoots[1]  // The missing root
        ));
        vm.prank(admin);
        liquidTokenManager.completeRedemption(
            redemptionId,
            completionNodeIds,
            completionWithdrawalRoots
        );

        // Verify redemption still exists after failed attempt
        ILiquidTokenManager.Redemption memory redemptionAfter = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemptionAfter.withdrawalRoots.length, withdrawalRoots.length, "Redemption should still exist");
    }

    function testCompleteRedemptionNodeWithdrawal() public {
        // First, set up the test state with node delegation and assets
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256 nodeId = 0;
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;
        
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, stakeAmounts);

        // Get initial balances
        uint256 initialLiquidTokenBalance = testToken.balanceOf(address(liquidToken));

        // Prepare withdrawal parameters
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        IERC20[][] memory withdrawalAssets = new IERC20[][](1);
        withdrawalAssets[0] = new IERC20[](1);
        withdrawalAssets[0][0] = testToken;
        
        uint256[][] memory shares = new uint256[][](1);
        shares[0] = new uint256[](1);
        shares[0][0] = 2 ether;

        // Record events for withdrawal
        vm.recordLogs();
        
        vm.prank(admin);
        liquidTokenManager.withdrawNodeAssets(nodeIds, withdrawalAssets, shares);

        // Get redemption details from emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForRebalancing(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId,, withdrawalRoots,) = abi.decode(
                    entries[i].data,
                    (bytes32, bytes32[], bytes32[], uint256[])
                );
                break;
            }
        }

        // Verify redemption exists before completion
        ILiquidTokenManager.Redemption memory redemptionBefore = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemptionBefore.withdrawalRoots.length, withdrawalRoots.length, "Redemption not properly recorded");

        // Advance time and blocks to meet EigenLayer's withdrawal delay requirements
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400); // Approximately 7 days worth of blocks

        // Prepare completion parameters
        uint256[] memory completionNodeIds = new uint256[](1);
        completionNodeIds[0] = nodeId;
        
        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](1);
        completionWithdrawalRoots[0] = withdrawalRoots;

        // Complete the redemption
        vm.prank(admin);
        liquidTokenManager.completeRedemption(
            redemptionId,
            completionNodeIds,
            completionWithdrawalRoots
        );

        // Verify results
        uint256 finalLiquidTokenBalance = testToken.balanceOf(address(liquidToken));
        assertEq(
            finalLiquidTokenBalance,
            initialLiquidTokenBalance + 2 ether,
            "Incorrect final balance"
        );

        // Verify redemption is completed (deleted)
        vm.expectRevert(abi.encodeWithSelector(
            IWithdrawalManager.RedemptionNotFound.selector,
            redemptionId
        ));
        withdrawalManager.getRedemption(redemptionId);
    }

    function testCompleteRedemptionNodeWithdrawalFailsForPartialCompletion() public {
        // Set up initial delegation
        uint256[] memory nodeIdsToDelegate = new uint256[](1);
        nodeIdsToDelegate[0] = 1;
        address[] memory operators = new address[](1);
        operators[0] = operatorAddress;
        ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
        bytes32[] memory salts = new bytes32[](1);
        
        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIdsToDelegate, operators, sigs, salts);

        // Set up test state with multiple nodes and assets
        (
            uint256[] memory nodeIds,
            uint256[][] memory initialNodeBalances
        ) = _setupWithdrawNodeAssetsTest();
        
        // Perform withdrawal and get event data
        (
            bytes32 redemptionId,
            bytes32[] memory requestIds,
            bytes32[] memory withdrawalRoots,
            uint256[] memory eventNodeIds
        ) = _performWithdrawNodeAssets(nodeIds);
        
        // Create arrays for completion with missing withdrawal root
        uint256[] memory completionNodeIds = new uint256[](2);
        completionNodeIds[0] = nodeIds[0];
        completionNodeIds[1] = nodeIds[1];

        // Create 2D array of withdrawal roots where second node's root is missing
        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](2);
        // First node gets its withdrawal root
        completionWithdrawalRoots[0] = new bytes32[](1);
        completionWithdrawalRoots[0][0] = withdrawalRoots[0];
        // Second node gets an empty array (missing root)
        completionWithdrawalRoots[1] = new bytes32[](0);

        // Advance time and blocks to meet EigenLayer's withdrawal delay requirements
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400); // Approximately 7 days worth of blocks

        // Attempt to complete redemption with missing withdrawal root
        vm.expectRevert(abi.encodeWithSelector(
            ILiquidTokenManager.WithdrawalRootMissing.selector,
            withdrawalRoots[1]  // The missing root
        ));
        vm.prank(admin);
        liquidTokenManager.completeRedemption(
            redemptionId,
            completionNodeIds,
            completionWithdrawalRoots
        );

        // Verify node balances haven't changed
        for (uint256 i = 0; i < nodeIds.length; i++) {
            uint256 actualBalance1 = liquidTokenManager.getStakedAssetBalanceNode(testToken, nodeIds[i]);
            uint256 actualBalance2 = liquidTokenManager.getStakedAssetBalanceNode(testToken2, nodeIds[i]);
            
            // Initial balances minus the withdrawal amounts
            uint256 expectedBalance1 = initialNodeBalances[i][0] - 3 ether;
            uint256 expectedBalance2 = initialNodeBalances[i][1] - 1 ether;
            
            assertEq(
                actualBalance1,
                expectedBalance1,
                string.concat("Balance1 should remain unchanged for node 1")
            );
            assertEq(
                actualBalance2,
                expectedBalance2,
                string.concat("Balance2 should remain unchanged for node 2")
            );
        }
    }

    function testCompleteRedemptionUserWithdrawals() public {
        // Setup: user deposits and initiates withdrawal
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);

        // Stake some assets to a node
        uint256 nodeId = 0;
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, stakeAmounts);

        // Settle the withdrawal request
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        IERC20[] memory ltAssets = new IERC20[](1);
        ltAssets[0] = testToken;
        uint256[] memory ltAmounts = new uint256[](1);
        ltAmounts[0] = 5 ether; // unstaked portion

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;

        IERC20[][] memory elAssets = new IERC20[][](1);
        elAssets[0] = new IERC20[](1);
        elAssets[0][0] = testToken;

        uint256[][] memory elShares = new uint256[][](1);
        elShares[0] = new uint256[](1);
        elShares[0][0] = 5 ether; // staked portion

        // Capture the redemption ID from the event
        vm.recordLogs();
        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(requestIds, ltAssets, ltAmounts, nodeIds, elAssets, elShares);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId, , withdrawalRoots, ) = abi.decode(entries[i].data, (bytes32, bytes32[], bytes32[], uint256[]));
                break;
            }
        }

        // Advance time
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400);

        // Prepare completion parameters
        uint256[] memory completionNodeIds = new uint256[](1);
        completionNodeIds[0] = nodeId;

        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](1);
        completionWithdrawalRoots[0] = withdrawalRoots;

        // Complete the redemption
        vm.prank(admin);
        liquidTokenManager.completeRedemption(redemptionId, completionNodeIds, completionWithdrawalRoots);

        // Verify redemption is deleted
        vm.expectRevert(abi.encodeWithSelector(IWithdrawalManager.RedemptionNotFound.selector, redemptionId));
        withdrawalManager.getRedemption(redemptionId);

        // Check token balance of withdrawal manager
        assertEq(
            testToken.balanceOf(address(withdrawalManager)),
            10 ether,
            "Withdrawal manager did not receive redeemed funds"
        );
    }

    function testCompleteRedemptionUserWithdrawalsFailsForPartialCompletion() public {
        // Delegate 2nd node
        uint256[] memory nodeIdsToDelegate = new uint256[](1);
        nodeIdsToDelegate[0] = 1;
        address[] memory operators = new address[](1);
        operators[0] = operatorAddress;
        ISignatureUtils.SignatureWithExpiry[] memory sigs = new ISignatureUtils.SignatureWithExpiry[](1);
        bytes32[] memory salts = new bytes32[](1);

        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIdsToDelegate, operators, sigs, salts);

        // Setup: user deposits and initiates withdrawal
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 20 ether;
        liquidToken.deposit(assets, amounts, user1);

        // Stake to two nodes
        uint256 nodeId1 = 0;
        uint256 nodeId2 = 1;
        uint256[] memory stakeAmounts1 = new uint256[](1);
        stakeAmounts1[0] = 5 ether;
        uint256[] memory stakeAmounts2 = new uint256[](1);
        stakeAmounts2[0] = 5 ether;

        vm.startPrank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId1, assets, stakeAmounts1);
        liquidTokenManager.stakeAssetsToNode(nodeId2, assets, stakeAmounts2);
        vm.stopPrank();

        // User initiates withdrawal for 20 ether
        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);

        // Settle the withdrawal request
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        IERC20[] memory ltAssets = new IERC20[](1);
        ltAssets[0] = testToken;
        uint256[] memory ltAmounts = new uint256[](1);
        ltAmounts[0] = 10 ether; // unstaked portion

        uint256[] memory nodeIds = new uint256[](2);
        nodeIds[0] = nodeId1;
        nodeIds[1] = nodeId2;

        IERC20[][] memory elAssets = new IERC20[][](2);
        elAssets[0] = new IERC20[](1);
        elAssets[0][0] = testToken;
        elAssets[1] = new IERC20[](1);
        elAssets[1][0] = testToken;

        uint256[][] memory elShares = new uint256[][](2);
        elShares[0] = new uint256[](1);
        elShares[0][0] = 5 ether;
        elShares[1] = new uint256[](1);
        elShares[1][0] = 5 ether;

        vm.recordLogs();
        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(requestIds, ltAssets, ltAmounts, nodeIds, elAssets, elShares);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId, , withdrawalRoots, ) = abi.decode(entries[i].data, (bytes32, bytes32[], bytes32[], uint256[]));
                break;
            }
        }

        // There should be two withdrawal roots (one per node)
        assertEq(withdrawalRoots.length, 2, "Should have two withdrawal roots");

        // Advance time
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 50400);

        // Prepare completion parameters, omitting one withdrawal root
        uint256[] memory completionNodeIds = new uint256[](2);
        completionNodeIds[0] = nodeId1;
        completionNodeIds[1] = nodeId2;

        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](2);
        completionWithdrawalRoots[0] = new bytes32[](1);
        completionWithdrawalRoots[0][0] = withdrawalRoots[0]; // include first root
        completionWithdrawalRoots[1] = new bytes32[](0); // omit second root

        // Attempt to complete redemption
        vm.expectRevert(abi.encodeWithSelector(ILiquidTokenManager.WithdrawalRootMissing.selector, withdrawalRoots[1]));
        vm.prank(admin);
        liquidTokenManager.completeRedemption(redemptionId, completionNodeIds, completionWithdrawalRoots);

        // Verify redemption still exists
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemption.withdrawalRoots.length, 2, "Redemption should still have all roots");
    }

    function testFulfillWithdrawalByUser() public {
        // Setup: user deposits and initiates withdrawal
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);

        // Stake some assets to a node
        uint256 nodeId = 0;
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, stakeAmounts);

        // Settle the withdrawal request
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        IERC20[] memory ltAssets = new IERC20[](1);
        ltAssets[0] = testToken;
        uint256[] memory ltAmounts = new uint256[](1);
        ltAmounts[0] = 5 ether; // unstaked portion

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;

        IERC20[][] memory elAssets = new IERC20[][](1);
        elAssets[0] = new IERC20[](1);
        elAssets[0][0] = testToken;

        uint256[][] memory elShares = new uint256[][](1);
        elShares[0] = new uint256[](1);
        elShares[0][0] = 5 ether; // staked portion

        // Capture the redemption ID from the event
        vm.recordLogs();
        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(requestIds, ltAssets, ltAmounts, nodeIds, elAssets, elShares);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId, , withdrawalRoots, ) = abi.decode(entries[i].data, (bytes32, bytes32[], bytes32[], uint256[]));
                break;
            }
        }

        // Advance time to meet withdrawal delay
        vm.warp(block.timestamp + 14 days);
        vm.roll(block.number + 100800); // Approximately 14 days worth of blocks

        // Complete the redemption
        uint256[] memory completionNodeIds = new uint256[](1);
        completionNodeIds[0] = nodeId;
        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](1);
        completionWithdrawalRoots[0] = withdrawalRoots;
        vm.prank(admin);
        liquidTokenManager.completeRedemption(redemptionId, completionNodeIds, completionWithdrawalRoots);
        
        // User fulfills their withdrawal
        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId);
        
        // Verify the withdrawal was successful
        assertEq(testToken.balanceOf(user1), 100 ether, "User should receive full withdrawal amount");
    }

    function testFulfillWithdrawalByUserDoesNotInflateShares() public {
        // Setup: user deposits and initiates withdrawal
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);

        // Stake some assets to a node
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;
        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(0, assets, stakeAmounts);

        // Settle the withdrawal request
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        IERC20[] memory ltAssets = new IERC20[](1);
        ltAssets[0] = testToken;
        uint256[] memory ltAmounts = new uint256[](1);
        ltAmounts[0] = 5 ether; // unstaked portion

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = 0;

        IERC20[][] memory elAssets = new IERC20[][](1);
        elAssets[0] = new IERC20[](1);
        elAssets[0][0] = testToken;

        uint256[][] memory elShares = new uint256[][](1);
        elShares[0] = new uint256[](1);
        elShares[0][0] = 5 ether; // staked portion

        // Capture the redemption ID from the event
        vm.recordLogs();
        vm.prank(admin);
        liquidTokenManager.settleUserWithdrawals(requestIds, ltAssets, ltAmounts, nodeIds, elAssets, elShares);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 redemptionId;
        bytes32[] memory withdrawalRoots;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],uint256[])")) {
                (redemptionId, , withdrawalRoots, ) = abi.decode(entries[i].data, (bytes32, bytes32[], bytes32[], uint256[]));
                break;
            }
        }

        // Advance time to meet withdrawal delay
        vm.warp(block.timestamp + 14 days);
        vm.roll(block.number + 100800); // Approximately 14 days worth of blocks

        // Complete the redemption
        uint256[] memory completionNodeIds = new uint256[](1);
        completionNodeIds[0] = 0;
        bytes32[][] memory completionWithdrawalRoots = new bytes32[][](1);
        completionWithdrawalRoots[0] = withdrawalRoots;
        vm.prank(admin);
        liquidTokenManager.completeRedemption(redemptionId, completionNodeIds, completionWithdrawalRoots);

        // Check share calculation before fulfilment
        uint256 sharesBeforeFulfillment = liquidToken.calculateShares(testToken, 1 ether);
        
        // User fulfills their withdrawal
        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId);
        
        // Verify shares haven't been inflated
        assertEq(
            sharesBeforeFulfillment,
            liquidToken.calculateShares(testToken, 1 ether),
            "Token is mispriced due to inflated shares"
        );
    }

    function testFulfillWithdrawalByUserFailsForInvalidRequest() public {
        // Setup a withdrawal request for user1
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);
        
        // Try to fulfill as user2 (who didn't create the request)
        vm.prank(user2);
        vm.expectRevert(IWithdrawalManager.InvalidWithdrawalRequest.selector);
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    function testFulfillWithdrawalByUserFailsForWithdrawalDelayNotMet() public {
        // Setup a withdrawal request
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);
        
        // Advance time, but not enough to meet the delay
        vm.warp(block.timestamp + 13 days);
        
        // Try to fulfill before delay period
        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.WithdrawalDelayNotMet.selector);
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    function testFulfillWithdrawalByUserFailsForWithdrawalNotReadyToFulfill() public {
        // Setup a withdrawal request
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = testToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);
        
        // Advance time past delay
        vm.warp(block.timestamp + 14 days);
        
        // Try to fulfill before redemption is completed
        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.WithdrawalNotReadyToFulfill.selector);
        withdrawalManager.fulfillWithdrawal(requestId);
    }
}