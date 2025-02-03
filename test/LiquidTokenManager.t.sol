// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    event RedemptionCreatedForNodeUndelegation(
        bytes32 redemptionId,
        bytes32 requestId,
        bytes32[] withdrawalRoots,
        uint256 nodeId
    );

    event RedemptionCreatedForRebalancing(
        bytes32 redemptionId,
        bytes32[] requestIds,
        bytes32[] withdrawalRoots,
        uint256[] nodeIds
    );

    event RedemptionCreatedForUserWithdrawals(
        bytes32 redemptionId,
        bytes32[] requestIds,
        bytes32[] withdrawalRoots,
        uint256[] nodeIds
    );
    
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

        // Get node's deposits before undelegation
        (IStrategy[] memory strategies, uint256[] memory depositAmounts) = strategyManager.getDeposits(address(stakerNode));
        
        // Convert strategies to tokens for verification
        IERC20[] memory expectedAssets = new IERC20[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            expectedAssets[i] = liquidTokenManager.strategyTokens(strategies[i]);
        }
        
        // Set up event capture
        vm.recordLogs();
        
        // Perform undelegation
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

        // Get the recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Find our RedemptionCreatedForNodeUndelegation event
        // The event we want should be one of the last events emitted
        bytes32 redemptionId;
        bytes32 requestId;
        bytes32[] memory withdrawalRoots;
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RedemptionCreatedForNodeUndelegation(bytes32,bytes32,bytes32[],uint256)")) {
                (redemptionId, requestId, withdrawalRoots, nodeId) = abi.decode(
                    entries[i].data, 
                    (bytes32, bytes32, bytes32[], uint256)
                );
                break;
            }
        }
        
        // Get and verify the redemption details
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemption.requestIds.length, 1, "Incorrect requestIds length");
        assertEq(redemption.requestIds[0], requestId, "Incorrect requestId");
        assertEq(redemption.withdrawalRoots.length, withdrawalRoots.length, "Incorrect withdrawalRoots length");
        assertEq(redemption.withdrawalRoots[0], withdrawalRoots[0], "Incorrect withdrawalRoot");
        assertEq(redemption.receiver, address(liquidToken), "Incorrect receiver");
        
        // Get the withdrawal requests using the captured withdrawal roots
        IWithdrawalManager.ELWithdrawalRequest[] memory elRequests = withdrawalManager.getELWithdrawalRequests(withdrawalRoots);
        
        // Verify withdrawal request details
        assertEq(elRequests[0].withdrawal.staker, address(stakerNode), "Incorrect staker address");
        assertEq(elRequests[0].withdrawal.delegatedTo, operatorAddress, "Incorrect operator address");
        assertEq(elRequests[0].withdrawal.shares[0], depositAmounts[0], "Incorrect withdrawal amount");
        assertEq(address(elRequests[0].assets[0]), address(expectedAssets[0]), "Incorrect withdrawal asset");
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
        // Helper function to set up test state
        (uint256 nodeId, uint256 initialNodeBalance) = _setupWithdrawNodeAssetsTest();
        
        // Helper function to perform withdrawal and get event data
        (
            bytes32 redemptionId,
            bytes32[] memory requestIds,
            bytes32[] memory withdrawalRoots,
            uint256[] memory eventNodeIds
        ) = _performWithdrawNodeAssets(nodeId);
        
        // Verify redemption details
        _verifyWithdrawNodeAssetsRedemption(
            redemptionId,
            requestIds,
            withdrawalRoots,
            eventNodeIds,
            nodeId,
            initialNodeBalance
        );
    }

    // Helper functions to break down the test
    function _setupWithdrawNodeAssetsTest() internal returns (uint256 nodeId, uint256 initialNodeBalance) {
        // Setup: Deposit and stake assets to node
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

        initialNodeBalance = liquidTokenManager.getStakedAssetBalanceNode(testToken, nodeId);
        return (nodeId, initialNodeBalance);
    }

    function _performWithdrawNodeAssets(uint256 nodeId) internal returns (
        bytes32 redemptionId,
        bytes32[] memory requestIds,
        bytes32[] memory withdrawalRoots,
        uint256[] memory eventNodeIds
    ) {
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        IERC20[][] memory withdrawalAssets = new IERC20[][](1);
        withdrawalAssets[0] = new IERC20[](1);
        withdrawalAssets[0][0] = testToken;
        
        uint256[][] memory shares = new uint256[][](1);
        shares[0] = new uint256[](1);
        shares[0][0] = 2 ether;

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
        uint256 nodeId,
        uint256 initialNodeBalance
    ) internal {
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemption.requestIds.length, requestIds.length, "Incorrect requestIds length");
        assertEq(redemption.withdrawalRoots.length, withdrawalRoots.length, "Incorrect withdrawalRoots length");
        assertEq(redemption.receiver, address(liquidToken), "Incorrect receiver");

        IWithdrawalManager.ELWithdrawalRequest[] memory elRequests = 
            withdrawalManager.getELWithdrawalRequests(withdrawalRoots);
        assertEq(elRequests[0].withdrawal.staker, address(stakerNode), "Incorrect staker address");
        assertEq(elRequests[0].withdrawal.delegatedTo, operatorAddress, "Incorrect operator address");
        assertEq(elRequests[0].withdrawal.shares[0], 2 ether, "Incorrect withdrawal amount");
        assertEq(address(elRequests[0].assets[0]), address(testToken), "Incorrect withdrawal asset");

        uint256 expectedRemainingBalance = initialNodeBalance - 2 ether;
        uint256 actualRemainingBalance = liquidTokenManager.getStakedAssetBalanceNode(testToken, nodeId);
        assertEq(actualRemainingBalance, expectedRemainingBalance, "Incorrect remaining balance");
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
        // Setup phase: Create deposits and withdrawal requests
        (bytes32 requestId, uint256 nodeId, uint256 initialBalance) = _setupSettleUserWithdrawalsTest();
        
        // Execute settlement and capture events
        bytes32 redemptionId = _performSettlement(requestId, nodeId);
        
        // Verify the results
        _verifySettlementResults(redemptionId, requestId, initialBalance);
    }

    // Helper function to set up the test state
    function _setupSettleUserWithdrawalsTest() internal returns (
        bytes32 requestId, 
        uint256 nodeId,
        uint256 initialBalance
    ) {
        // Set up initial deposit
        vm.prank(user1);
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 10 ether;
        
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        // Create withdrawal request
        vm.prank(user1);
        requestId = liquidToken.initiateWithdrawal(depositAssets, depositAmounts);
        
        // Stake assets to node
        nodeId = 0;
        uint256[] memory stakeAmounts = new uint256[](1);
        stakeAmounts[0] = 5 ether;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, depositAssets, stakeAmounts);

        initialBalance = testToken.balanceOf(address(withdrawalManager));
        
        return (requestId, nodeId, initialBalance);
    }

    // Helper function to perform the settlement
    function _performSettlement(bytes32 requestId, uint256 nodeId) internal returns (bytes32 redemptionId) {
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
        bytes32 requestId,
        uint256 initialBalance
    ) internal {
        // Verify transfer amounts
        uint256 expectedUnstakedTransfer = 5 ether;
        uint256 actualUnstakedTransfer = testToken.balanceOf(address(withdrawalManager)) - initialBalance;
        assertEq(actualUnstakedTransfer, expectedUnstakedTransfer, "Incorrect unstaked transfer amount");

        // Verify redemption details
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);
        assertEq(redemption.requestIds[0], requestId, "Incorrect requestId");
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
            ILiquidTokenManager.RedemptionDoesNotSettleRequests.selector,
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
}