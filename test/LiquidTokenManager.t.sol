// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {BaseTest} from "./common/BaseTest.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockERC20, MockERC20NoDecimals} from "./mocks/MockERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

contract LiquidTokenManagerTest is BaseTest {
    IStakerNode public stakerNode;

    function _isHoleskyTestnet() internal view returns (bool) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId == 17000;
    }

    // Add a helper function to safely handle contract interactions on Holesky
    function _safeRegisterOperator(address operator) internal {
        vm.prank(operator);
        delegationManager.registerAsOperator(address(0), 1, "ipfs://");
    }

    function setUp() public override {
        super.setUp();

        // Create a staker node for testing
        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(),
            admin
        );
        IStakerNode node = stakerNodeCoordinator.createStakerNode();
        stakerNode = node;

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

        // Use the safe helper function
        _safeRegisterOperator(operatorAddress);

        // Strategy whitelist
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](1);

        strategiesToWhitelist[0] = IStrategy(address(mockStrategy));

        vm.prank(strategyManager.strategyWhitelister());
        strategyManager.addStrategiesToDepositWhitelist(strategiesToWhitelist);

        // Check if operator is registered before trying to delegate
        bool isOperatorRegistered;
        try delegationManager.isOperator(operatorAddress) returns (
            bool result
        ) {
            isOperatorRegistered = result;
        } catch {
            isOperatorRegistered = false;
        }

        if (isOperatorRegistered) {
            // Delegate the staker node to EL
            stakerNode.delegate(operatorAddress, signature, bytes32(0));
        }
    }

    // Helper function to ensure a node is delegated
    function _ensureNodeIsDelegated(uint256 nodeId) internal {
        IStakerNode node = stakerNodeCoordinator.getAllNodes()[nodeId];
        address currentOperator = node.getOperatorDelegation();

        if (currentOperator == address(0)) {
            // Create and register a test operator
            address testOperator = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                block.timestamp,
                                block.prevrandao,
                                nodeId
                            )
                        )
                    )
                )
            );

            _safeRegisterOperator(testOperator);

            // Delegate the node
            vm.prank(admin);
            ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySig;
            node.delegate(testOperator, emptySig, bytes32(0));
        }
    }

    function testInitialize() public {
        assertEq(
            address(liquidTokenManager.liquidToken()),
            address(liquidToken)
        );
        assertEq(
            address(
                liquidTokenManager.getTokenStrategy(IERC20(address(testToken)))
            ),
            address(mockStrategy)
        );
        assertEq(
            address(
                liquidTokenManager.getTokenStrategy(IERC20(address(testToken2)))
            ),
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

        liquidTokenManager.addToken(
            newToken,
            decimals,
            initialPrice,
            volatilityThreshold,
            newStrategy,
            0, // primaryType - 0 means uninitialized
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );

        // Verify that the token was successfully added
        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager
            .getTokenInfo(newToken);
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
        assertEq(address(strategy), address(newStrategy), "Incorrect strategy");

        // Verify that the token is now supported
        assertTrue(
            liquidTokenManager.tokenIsSupported(newToken),
            "Token should be supported"
        );

        // Verify that the token is included in the supportedTokens array
        IERC20[] memory supportedTokens = liquidTokenManager
            .getSupportedTokens();
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
        liquidTokenManager.addToken(
            newToken,
            decimals,
            initialPrice,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenZeroAddress() public {
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(0))
        );

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.ZeroAddress.selector);
        liquidTokenManager.addToken(
            IERC20(address(0)),
            decimals,
            initialPrice,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenStrategyZeroAddress() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.ZeroAddress.selector);
        liquidTokenManager.addToken(
            newToken,
            decimals,
            initialPrice,
            volatilityThreshold,
            IStrategy(address(0)),
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenFailsIfAlreadySupported() public {
        // Try to add testToken which was already added in setUp()
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy duplicateStrategy = new MockStrategy(
            strategyManager,
            testToken
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenExists.selector,
                address(testToken)
            )
        );
        liquidTokenManager.addToken(
            testToken,
            decimals,
            initialPrice,
            volatilityThreshold,
            duplicateStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenFailsForZeroDecimals() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidDecimals.selector);
        liquidTokenManager.addToken(
            newToken,
            0,
            initialPrice,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenFailsForMismatchedDecimals() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 6; // Actual decimals value is 18
        uint256 price = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.expectRevert(ILiquidTokenManager.InvalidDecimals.selector);
        liquidTokenManager.addToken(
            newToken,
            decimals,
            price,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenSuccessForNoDecimalsFunction() public {
        IERC20 newToken = IERC20(address(new MockERC20NoDecimals())); // Doesn't have a `decimals()` function
        uint8 decimals = 6;
        uint256 price = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        liquidTokenManager.addToken(
            newToken,
            decimals,
            price,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );

        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager
            .getTokenInfo(newToken);
        assertEq(tokenInfo.decimals, decimals, "Incorrect decimals");
    }

    function testAddTokenFailsForZeroInitialPrice() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidPrice.selector);
        liquidTokenManager.addToken(
            newToken,
            decimals,
            0,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testAddTokenFailsForInvalidThreshold() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 price = 1e18;
        uint256 volatilityThreshold = 50;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidThreshold.selector);
        liquidTokenManager.addToken(
            newToken,
            decimals,
            price,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
    }

    function testGetTokenInfoFailsForUnsupportedToken() public {
        MockERC20 unsupportedToken = new MockERC20(
            "Unsupported Token",
            "UNSUP"
        );
        assertFalse(
            liquidTokenManager.tokenIsSupported(
                IERC20(address(unsupportedToken))
            ),
            "Token should not be reported as supported"
        );

        // Token should not be in supported tokens array
        IERC20[] memory supportedTokens = liquidTokenManager
            .getSupportedTokens();
        bool isInArray = false;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (address(supportedTokens[i]) == address(unsupportedToken)) {
                isInArray = true;
                break;
            }
        }
        assertFalse(
            isInArray,
            "Unsupported token should not be in supported tokens array"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenNotSupported.selector,
                address(unsupportedToken)
            )
        );
        liquidTokenManager.getTokenInfo(IERC20(address(unsupportedToken)));
    }

    function testRemoveTokenSuccess() public {
        // First add a new token that we'll remove
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint8 decimals = 18;
        uint256 initialPrice = 1e18;
        uint256 volatilityThreshold = 0;
        MockStrategy newStrategy = new MockStrategy(strategyManager, newToken);

        vm.prank(admin);
        liquidTokenManager.addToken(
            newToken,
            decimals,
            initialPrice,
            volatilityThreshold,
            newStrategy,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );

        // Verify token was added
        assertTrue(liquidTokenManager.tokenIsSupported(newToken));

        // Remove the token
        vm.prank(admin);
        liquidTokenManager.removeToken(newToken);

        // Verify token was removed
        assertFalse(liquidTokenManager.tokenIsSupported(newToken));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenNotSupported.selector,
                newToken
            )
        );
        liquidTokenManager.getTokenInfo(newToken);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.StrategyNotFound.selector,
                newToken
            )
        );
        liquidTokenManager.getTokenStrategy(newToken);

        // Verify token is not in supported tokens array
        IERC20[] memory supportedTokens = liquidTokenManager
            .getSupportedTokens();
        bool isTokenInArray = false;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == newToken) {
                isTokenInArray = true;
                break;
            }
        }
        assertFalse(
            isTokenInArray,
            "Token should not be in the supportedTokens array"
        );
    }

    function testRemoveTokenFailsForUnsupportedToken() public {
        IERC20 unsupportedToken = IERC20(
            address(new MockERC20("Unsupported", "UNS"))
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenNotSupported.selector,
                unsupportedToken
            )
        );
        liquidTokenManager.removeToken(unsupportedToken);
    }

    function testRemoveTokenFailsForNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        liquidTokenManager.removeToken(testToken);
    }

    function testRemoveTokenFailsIfNonZeroAssetBalance() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        vm.prank(user1);
        liquidToken.deposit(_convertToUpgradeable(assets), amounts, user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(testToken)
            )
        );
        liquidTokenManager.removeToken(testToken);
    }

    function testRemoveTokenFailsIfNodeHasShares() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        vm.prank(user1);
        liquidToken.deposit(_convertToUpgradeable(assets), amounts, user1);

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

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRemoveTokenFailsIfNonZeroQueuedAssetBalance() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);
        
        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );

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

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        liquidTokenManager.undelegateNodes(nodeIds);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(testToken)
            )
        );
        liquidTokenManager.removeToken(testToken);
    }
    */

    function testStakeAssetsToNode() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);

        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );

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
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.LengthMismatch.selector,
                1,
                2
            )
        );
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
    }

    function testInvalidStakingAmount() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0 ether;

        uint256 nodeId = 0;
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.InvalidStakingAmount.selector,
                0
            )
        ); // Expect InvalidStakingAmount with 0 value
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
    }

    function testGetStakedAssetBalanceInvalidNodeId() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);

        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );

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
        liquidTokenManager.getStakedAssetBalanceNode(testToken, invalidNodeId);
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
        liquidTokenManager.grantRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(),
            admin
        );

        liquidTokenManager.setVolatilityThreshold(
            IERC20(address(testToken)),
            0
        ); // Disable volatility check
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 2e18); // 1 testToken = 2 units
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 unit
        vm.stopPrank();

        // User1 deposits 10 ether of testToken
        vm.prank(user1);
        IERC20[] memory assetsToDepositUser1 = new IERC20[](1);
        assetsToDepositUser1[0] = IERC20(address(testToken));
        uint256[] memory amountsToDepositUser1 = new uint256[](1);
        amountsToDepositUser1[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assetsToDepositUser1),
            amountsToDepositUser1,
            user1
        );

        // User2 deposits 20 ether of testToken2
        vm.prank(user2);
        IERC20[] memory assetsToDepositUser2 = new IERC20[](1);
        assetsToDepositUser2[0] = IERC20(address(testToken2));
        uint256[] memory amountsToDepositUser2 = new uint256[](1);
        amountsToDepositUser2[0] = 20 ether;
        liquidToken.deposit(
            _convertToUpgradeable(assetsToDepositUser2),
            amountsToDepositUser2,
            user2
        );

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
        liquidTokenManager.grantRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(),
            admin
        );

        liquidTokenManager.setVolatilityThreshold(
            IERC20(address(testToken)),
            0
        ); // Disable volatility check
        liquidTokenManager.setVolatilityThreshold(
            IERC20(address(testToken2)),
            0
        ); // Disable volatility check
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 2e18); // 1 testToken = 2 units
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 unit
        vm.stopPrank();

        // User1 deposits 10 ether of testToken
        vm.prank(user1);
        IERC20[] memory assetsToDepositUser1 = new IERC20[](1);
        assetsToDepositUser1[0] = IERC20(address(testToken));
        uint256[] memory amountsToDepositUser1 = new uint256[](1);
        amountsToDepositUser1[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assetsToDepositUser1),
            amountsToDepositUser1,
            user1
        );

        // User2 deposits 20 ether of testToken2
        vm.prank(user2);
        IERC20[] memory assetsToDepositUser2 = new IERC20[](1);
        assetsToDepositUser2[0] = IERC20(address(testToken2));
        uint256[] memory amountsToDepositUser2 = new uint256[](1);
        amountsToDepositUser2[0] = 20 ether;
        liquidToken.deposit(
            _convertToUpgradeable(assetsToDepositUser2),
            amountsToDepositUser2,
            user2
        );

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

    function testPriceUpdateFailsIfVolatilityThresholdHit() public {
        vm.prank(admin);
        liquidTokenManager.grantRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.VolatilityThresholdHit.selector,
                testToken,
                1e18
            )
        );
        liquidTokenManager.updatePrice(testToken, 2e18); // 100% increase but only 10% is allowed
    }

    function testSetVolatilityThresholdSuccess() public {
        vm.prank(admin);
        liquidTokenManager.grantRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(),
            admin
        );

        vm.prank(admin);
        liquidTokenManager.setVolatilityThreshold(testToken, 0);
        liquidTokenManager.updatePrice(testToken, 10e18); // 10x increase should pass
    }

    function testSetVolatilityThresholdFailsForInvalidValue() public {
        vm.prank(admin);
        liquidTokenManager.grantRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(ILiquidTokenManager.InvalidThreshold.selector);
        liquidTokenManager.setVolatilityThreshold(testToken, 20);
    }

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testQueuedAssetBalancesUpdateAfterWithdrawalRequest() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);
        
        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
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
        liquidTokenManager.undelegateNodes(nodeIds);

        uint256 finalQueuedBalance = liquidToken.queuedAssetBalances(address(testToken));
        assertEq(
            finalQueuedBalance, 
            50 ether, 
            "Queued assets balance should match original staked amount"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testQueuedWithdrawalsDoNotInflateShares() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);
        
        vm.prank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50 ether;        

        vm.prank(user1);
        liquidToken.deposit(assets, amounts, user1);

        uint256 nodeId = 0;
        uint256[] memory strategyAmounts = new uint256[](1);
        strategyAmounts[0] = 10 ether;
        IStrategy[] memory strategiesForNode = new IStrategy[](1);
        strategiesForNode[0] = mockStrategy;

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, strategyAmounts);

        uint256 sharesBeforeWithdrawalQueued = liquidToken.calculateShares(testToken, 1 ether);

        // Create EL withdrawal via node undelegation
        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        liquidTokenManager.undelegateNodes(nodeIds);

        uint256 expectedTotal = 50 ether;
        assertEq(liquidToken.totalAssets(), expectedTotal, "Total assets should include queued withdrawals");

        uint256 sharesAfterWithdrawalQueued = liquidToken.calculateShares(testToken, 1 ether);
        assertEq(sharesBeforeWithdrawalQueued, sharesAfterWithdrawalQueued, "Token is mispriced due to inflated shares");
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testFulfillWithdrawal() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);
        
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

        vm.startPrank(user1);
        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        liquidToken.approve(user1, amountsToWithdraw[0]);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Record the total supply and total assets before fulfillment
        uint256 totalSupplyBefore = liquidToken.totalSupply();
        uint256 totalAssetsBefore = liquidToken.totalAssets();

        // Fast forward time
        vm.warp(block.timestamp + 14 days);

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        // Assert that User1's token balance is correct after withdrawal
        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after withdrawal"
        );

        // Check if the correct amount of tokens were burned
        assertEq(
            liquidToken.totalSupply(),
            totalSupplyBefore - 5 ether,
            "Incorrect total supply after withdrawal (tokens not burned)"
        );

        // Check the user's remaining balance
        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect remaining balance after withdrawal"
        );

        // Check that the contract's balance of liquid tokens has decreased
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after fulfillment"
        );

        // Assert that the total assets reduces after the withdrawal
        assertEq(
            liquidToken.totalAssets(),
            totalAssetsBefore - 5 ether,
            "Incorrect total assets after withdrawal"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testFulfillWithdrawalFailsForInsufficientBalance() public {
        // Ensure node 0 is delegated
        _ensureNodeIsDelegated(0);
        
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
        vm.warp(block.timestamp + 14 days);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.InsufficientBalance.selector,
                address(testToken),
                5 ether,
                9 ether
            )
        );

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();
    }
    */

    function testCannotDelegateDelegatedNode() public {
        address testOperator = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp + 1, // Different from setUp() operator
                            block.prevrandao
                        )
                    )
                )
            )
        );

        _safeRegisterOperator(testOperator);

        address currentOperator = stakerNode.getOperatorDelegation();

        // If the node is not already delegated, delegate it first
        if (currentOperator == address(0)) {
            vm.prank(admin);
            ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySig;
            stakerNode.delegate(testOperator, emptySig, bytes32(0));
            currentOperator = testOperator;
        }

        assertTrue(currentOperator != address(0), "Node should be delegated");

        vm.prank(admin);
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakerNode.NodeIsDelegated.selector,
                currentOperator
            )
        );
        stakerNode.delegate(testOperator, signature, bytes32(0));
    }

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testCannotUndelegateUndelegatedNode() public {
        // Make sure the node is delegated first
        address currentOperator = stakerNode.getOperatorDelegation();
        if (currentOperator == address(0)) {
            // Create and register a test operator
            address testOperator = address(uint160(uint256(keccak256(abi.encodePacked(
                block.timestamp + 1,
                block.prevrandao
            )))));
            
            vm.prank(testOperator);
            _safeRegisterOperator(testOperator);
            
            // Delegate the node
            vm.prank(admin);
            ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySig;
            stakerNode.delegate(testOperator, emptySig, bytes32(0));
        }
        
        vm.prank(admin);
        stakerNode.undelegate();

        address operator = stakerNode.getOperatorDelegation();
        assertEq(operator, address(0), "Node should be undelegated");

        vm.prank(admin);
        vm.expectRevert(IStakerNode.NodeIsNotDelegated.selector);
        stakerNode.undelegate();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testMultipleDepositWithdrawInDifferentOrders() public {
        // Setup new user
        address user3 = address(10);
        testToken.mint(user3, 100 ether);
        testToken2.mint(user3, 100 ether);
        
        vm.prank(user3);
        testToken.approve(address(liquidToken), type(uint256).max);
        vm.prank(user3);
        testToken2.approve(address(liquidToken), type(uint256).max);

        uint256 initialUser1TestToken = testToken.balanceOf(user1);
        uint256 initialUser1TestToken2 = testToken2.balanceOf(user1);
        uint256 initialUser2TestToken = testToken.balanceOf(user2);
        uint256 initialUser2TestToken2 = testToken2.balanceOf(user2);
        uint256 initialUser3TestToken = testToken.balanceOf(user3);
        uint256 initialUser3TestToken2 = testToken2.balanceOf(user3);

        // User1 deposits 10 testToken and 5 testToken2
        vm.startPrank(user1);
        IERC20[] memory depositAssets1 = new IERC20[](2);
        depositAssets1[0] = IERC20(address(testToken));
        depositAssets1[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts1 = new uint256[](2);
        depositAmounts1[0] = 10 ether;
        depositAmounts1[1] = 5 ether;
        liquidToken.deposit(depositAssets1, depositAmounts1, user1);
        vm.stopPrank();

        // User2 deposits 20 testToken and 10 testToken2
        vm.startPrank(user2);
        IERC20[] memory depositAssets2 = new IERC20[](2);
        depositAssets2[0] = IERC20(address(testToken));
        depositAssets2[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts2 = new uint256[](2);
        depositAmounts2[0] = 20 ether;
        depositAmounts2[1] = 10 ether;
        liquidToken.deposit(depositAssets2, depositAmounts2, user2);
        vm.stopPrank();

        // User3 deposits 5 testToken and 15 testToken2
        vm.startPrank(user3);
        IERC20[] memory depositAssets3 = new IERC20[](2);
        depositAssets3[0] = IERC20(address(testToken));
        depositAssets3[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts3 = new uint256[](2);
        depositAmounts3[0] = 5 ether;
        depositAmounts3[1] = 15 ether;
        liquidToken.deposit(depositAssets3, depositAmounts3, user3);
        vm.stopPrank();

        // Request withdrawals in different orders
        // User1: partial then remaining
        vm.startPrank(user1);
        IERC20[] memory withdrawAssets1 = new IERC20[](2);
        withdrawAssets1[0] = IERC20(address(testToken));
        withdrawAssets1[1] = IERC20(address(testToken2));
        uint256[] memory withdrawAmounts1a = new uint256[](2);
        withdrawAmounts1a[0] = 5 ether;
        withdrawAmounts1a[1] = 3 ether;
        liquidToken.requestWithdrawal(withdrawAssets1, withdrawAmounts1a);
        
        uint256[] memory withdrawAmounts1b = new uint256[](2);
        withdrawAmounts1b[0] = 5 ether;
        withdrawAmounts1b[1] = 2 ether;
        liquidToken.requestWithdrawal(withdrawAssets1, withdrawAmounts1b);
        vm.stopPrank();

        // User2: full withdrawal
        vm.startPrank(user2);
        IERC20[] memory withdrawAssets2 = new IERC20[](2);
        withdrawAssets2[0] = IERC20(address(testToken));
        withdrawAssets2[1] = IERC20(address(testToken2));
        uint256[] memory withdrawAmounts2 = new uint256[](2);
        withdrawAmounts2[0] = 20 ether;
        withdrawAmounts2[1] = 10 ether;
        liquidToken.requestWithdrawal(withdrawAssets2, withdrawAmounts2);
        vm.stopPrank();

        // User3: reverse asset order
        vm.startPrank(user3);
        IERC20[] memory withdrawAssets3 = new IERC20[](2);
        withdrawAssets3[0] = IERC20(address(testToken2));
        withdrawAssets3[1] = IERC20(address(testToken));
        uint256[] memory withdrawAmounts3 = new uint256[](2);
        withdrawAmounts3[0] = 15 ether;
        withdrawAmounts3[1] = 5 ether;
        liquidToken.requestWithdrawal(withdrawAssets3, withdrawAmounts3);
        vm.stopPrank();

        // Fulfill in random order
        vm.warp(block.timestamp + 14 days);

        bytes32[] memory user1Requests = liquidToken.getUserWithdrawalRequests(user1);
        bytes32[] memory user2Requests = liquidToken.getUserWithdrawalRequests(user2);
        bytes32[] memory user3Requests = liquidToken.getUserWithdrawalRequests(user3);

        vm.prank(user3);
        liquidToken.fulfillWithdrawal(user3Requests[0]);

        vm.prank(user1);
        liquidToken.fulfillWithdrawal(user1Requests[1]);

        vm.prank(user2);
        liquidToken.fulfillWithdrawal(user2Requests[0]);

        vm.prank(user1);
        liquidToken.fulfillWithdrawal(user1Requests[0]);

        // Verify final balances match initial
        assertEq(testToken.balanceOf(user1), initialUser1TestToken, "User1 testToken balance mismatch");
        assertEq(testToken2.balanceOf(user1), initialUser1TestToken2, "User1 testToken2 balance mismatch");
        assertEq(testToken.balanceOf(user2), initialUser2TestToken, "User2 testToken balance mismatch");
        assertEq(testToken2.balanceOf(user2), initialUser2TestToken2, "User2 testToken2 balance mismatch");
        assertEq(testToken.balanceOf(user3), initialUser3TestToken, "User3 testToken balance mismatch");
        assertEq(testToken2.balanceOf(user3), initialUser3TestToken2, "User3 testToken2 balance mismatch");

        // Contract balances should be zero
        assertEq(testToken.balanceOf(address(liquidToken)), 0, "testToken contract balance not zero");
        assertEq(testToken2.balanceOf(address(liquidToken)), 0, "testToken2 contract balance not zero");
        assertEq(liquidToken.totalSupply(), 0, "LiquidToken total supply not zero");
    }
    */

    /// Tests for undelegation functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testUndelegationSecurity() public {        
        // Setup: Create and delegate a node
        vm.startPrank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(),
            admin
        );
        vm.stopPrank();

        // Create initial deposits
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;
        liquidToken.deposit(assets, amounts, user1);
        vm.stopPrank();

        // Record initial states
        uint256 initialTotalSupply = liquidToken.totalSupply();
        uint256 initialUser1Balance = liquidToken.balanceOf(user1);
        
        // Setup node and delegate
        vm.startPrank(admin);
        IStakerNode node = stakerNodeCoordinator.createStakerNode();
        uint256 nodeId = stakerNodeCoordinator.getAllNodes().length - 1;
        vm.stopPrank();

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        address[] memory operators = new address[](1);
        address testOperator = address(uint160(uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao
        )))));
        operators[0] = testOperator;

        ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySig;
        bytes32[] memory salts = new bytes32[](1);
        salts[0] = bytes32(0);
        ISignatureUtilsMixinTypes.SignatureWithExpiry[] memory sigs = new ISignatureUtilsMixinTypes.SignatureWithExpiry[](1);
        sigs[0] = emptySig;

        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIds, operators, sigs, salts);

        // Try undelegating with non-admin (should fail)
        vm.prank(user2);
        vm.expectRevert();
        liquidTokenManager.undelegateNodes(nodeIds);

        // Properly undelegate with admin
        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);

        // Verify share consistency
        assertEq(liquidToken.totalSupply(), initialTotalSupply, "Total supply should not change after undelegation");
        assertEq(liquidToken.balanceOf(user1), initialUser1Balance, "User balance should not change after undelegation");
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testMultipleUndelegationScenarios() public {
        // Setup: Create multiple nodes and delegate them
        vm.startPrank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(),
            admin
        );
        vm.stopPrank();

        // Create deposits from multiple users
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50 ether;
        liquidToken.deposit(assets, amounts, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        liquidToken.deposit(assets, amounts, user2);
        vm.stopPrank();

        // Record initial states
        uint256 initialTotalSupply = liquidToken.totalSupply();
        uint256 initialUser1Balance = liquidToken.balanceOf(user1);
        uint256 initialUser2Balance = liquidToken.balanceOf(user2);

        // Create multiple nodes
        vm.startPrank(admin);
        IStakerNode node1 = stakerNodeCoordinator.createStakerNode();
        IStakerNode node2 = stakerNodeCoordinator.createStakerNode();
        uint256[] memory nodeIds = new uint256[](2);
        nodeIds[0] = stakerNodeCoordinator.getAllNodes().length - 2;  // First node
        nodeIds[1] = stakerNodeCoordinator.getAllNodes().length - 1;  // Second node
        vm.stopPrank();

        // Ensure both nodes are delegated
        _ensureNodeIsDelegated(nodeIds[0]);
        _ensureNodeIsDelegated(nodeIds[1]);

        // Undelegate nodes one by one
        vm.startPrank(admin);
        uint256[] memory singleNodeId = new uint256[](1);
        
        // Undelegate first node
        singleNodeId[0] = nodeIds[0];
        liquidTokenManager.undelegateNodes(singleNodeId);
        
        // Verify share consistency after first undelegation
        assertEq(liquidToken.totalSupply(), initialTotalSupply, "Total supply should not change after first undelegation");
        assertEq(liquidToken.balanceOf(user1), initialUser1Balance, "User1 balance should not change after first undelegation");
        assertEq(liquidToken.balanceOf(user2), initialUser2Balance, "User2 balance should not change after first undelegation");

        // Undelegate second node
        singleNodeId[0] = nodeIds[1];
        liquidTokenManager.undelegateNodes(singleNodeId);
        
        // Verify final share consistency
        assertEq(liquidToken.totalSupply(), initialTotalSupply, "Total supply should not change after all undelegations");
        assertEq(liquidToken.balanceOf(user1), initialUser1Balance, "User1 balance should not change after all undelegations");
        assertEq(liquidToken.balanceOf(user2), initialUser2Balance, "User2 balance should not change after all undelegations");
        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testShareInflationPreventionDuringUndelegation() public {        
        // Setup: Create and delegate a node
        vm.startPrank(admin);
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            address(liquidTokenManager)
        );
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(),
            admin
        );
        vm.stopPrank();

        // Create initial deposits with multiple assets
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;
        liquidToken.deposit(assets, amounts, user1);
        vm.stopPrank();

        // Record initial states
        uint256 initialTotalSupply = liquidToken.totalSupply();
        uint256 initialUser1Balance = liquidToken.balanceOf(user1);
        
        // Create and delegate node
        vm.startPrank(admin);
        IStakerNode node = stakerNodeCoordinator.createStakerNode();
        uint256 nodeId = stakerNodeCoordinator.getAllNodes().length - 1;
        vm.stopPrank();

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = nodeId;
        
        address[] memory operators = new address[](1);
        address testOperator = address(uint160(uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao
        )))));
        operators[0] = testOperator;
        
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory emptySig;
        bytes32[] memory salts = new bytes32[](1);
        salts[0] = bytes32(0);
        ISignatureUtilsMixinTypes.SignatureWithExpiry[] memory sigs = new ISignatureUtilsMixinTypes.SignatureWithExpiry[](1);
        sigs[0] = emptySig;

        vm.prank(admin);
        liquidTokenManager.delegateNodes(nodeIds, operators, sigs, salts);

        // Update asset prices to simulate value changes
        vm.startPrank(admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);
        // Disable volatility checks for both tokens
        liquidTokenManager.setVolatilityThreshold(IERC20(address(testToken)), 0);
        liquidTokenManager.setVolatilityThreshold(IERC20(address(testToken2)), 0);
        // Update prices
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 2e18);  // Double the price
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 0.5e18);  // Halve the price
        vm.stopPrank();

        // Undelegate node
        vm.prank(admin);
        liquidTokenManager.undelegateNodes(nodeIds);

        // Verify share consistency despite price changes
        assertEq(liquidToken.totalSupply(), initialTotalSupply, "Total supply should not change after undelegation");
        assertEq(liquidToken.balanceOf(user1), initialUser1Balance, "User balance should not change after undelegation");

        // Verify no share inflation through multiple operations
        vm.startPrank(user1);
        uint256[] memory withdrawShares = new uint256[](2);
        withdrawShares[0] = 10 ether;
        withdrawShares[1] = 5 ether;
        liquidToken.requestWithdrawal(assets, withdrawShares);
        vm.stopPrank();

        assertEq(
            liquidToken.totalSupply(),
            initialTotalSupply,
            "Total supply should remain constant after withdrawal request"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testStrategyDisablingSafety() public {
        // Setup initial state
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        // Create deposits
        vm.startPrank(user1);
        liquidToken.deposit(assets, amounts, user1);
        vm.stopPrank();

        // Try to disable strategy with active shares (should fail)
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(testToken)
            )
        );
        liquidTokenManager.removeToken(IERC20(address(testToken)));
        vm.stopPrank();

        // Withdraw all shares
        vm.startPrank(user1);
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();

        // Move time forward to allow withdrawal
        vm.warp(block.timestamp + 14 days);

        vm.startPrank(user1);
        bytes32[] memory requestIds = liquidToken.getUserWithdrawalRequests(user1);
        require(requestIds.length > 0, "No withdrawal requests found");
        liquidToken.fulfillWithdrawal(requestIds[0]);
        vm.stopPrank();

        // Now should be able to disable strategy
        vm.startPrank(admin);
        liquidTokenManager.removeToken(IERC20(address(testToken)));

        // Verify strategy is disabled
        assertFalse(
            liquidTokenManager.tokenIsSupported(IERC20(address(testToken))),
            "Token should not be supported"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.StrategyNotFound.selector,
                address(testToken)
            )
        );
        liquidTokenManager.getTokenStrategy(IERC20(address(testToken)));

        // Add token back with a new strategy
        MockStrategy newStrategy = new MockStrategy(strategyManager, IERC20(address(testToken)));
        liquidTokenManager.addToken(
            IERC20(address(testToken)),
            18,
            1e18,
            0,
            newStrategy
        );

        // Verify token and strategy are added back
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(testToken))),
            "Token should be supported"
        );
        assertEq(
            address(liquidTokenManager.getTokenStrategy(IERC20(address(testToken)))),
            address(newStrategy),
            "Wrong strategy"
        );
        vm.stopPrank();
    }
    */
    function testMultipleTokenStrategyManagement() public {
        // Create a new token and strategy for testing
        MockERC20 token3 = new MockERC20("Test Token 3", "TEST3");
        MockERC20 token4 = new MockERC20("Test Token 4", "TEST4");
        MockStrategy strategy3 = new MockStrategy(
            strategyManager,
            IERC20(address(token3))
        );
        MockStrategy strategy4 = new MockStrategy(
            strategyManager,
            IERC20(address(token4))
        );

        vm.startPrank(admin);
        // Add first token with its strategy
        liquidTokenManager.addToken(
            IERC20(address(token3)),
            18,
            1e18,
            0,
            strategy3,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );

        // Add second token with its strategy
        liquidTokenManager.addToken(
            IERC20(address(token4)),
            18,
            1e18,
            0,
            strategy4,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );

        // Verify both tokens are enabled
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(token3))),
            "Token3 should be supported"
        );
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(token4))),
            "Token4 should be supported"
        );

        // Remove second token (which has no shares)
        liquidTokenManager.removeToken(IERC20(address(token4)));

        // Verify states
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(token3))),
            "Token3 should still be supported"
        );
        assertFalse(
            liquidTokenManager.tokenIsSupported(IERC20(address(token4))),
            "Token4 should not be supported"
        );

        // Try to get token info for removed token (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenNotSupported.selector,
                address(token4)
            )
        );
        liquidTokenManager.getTokenInfo(IERC20(address(token4)));

        // Try to get strategy for removed token (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.StrategyNotFound.selector,
                address(token4)
            )
        );
        liquidTokenManager.getTokenStrategy(IERC20(address(token4)));

        vm.stopPrank();
    }

    function testTokenStrategyShareValueConsistency() public {
        // Create new tokens and strategies for testing (use completely different names)
        MockERC20 tokenM = new MockERC20("Test Token M", "TESTM");
        MockERC20 tokenN = new MockERC20("Test Token N", "TESTN");
        MockStrategy strategyM = new MockStrategy(
            strategyManager,
            IERC20(address(tokenM))
        );
        MockStrategy strategyN = new MockStrategy(
            strategyManager,
            IERC20(address(tokenN))
        );

        vm.startPrank(admin);
        // Add tokens with their strategies
        liquidTokenManager.addToken(
            IERC20(address(tokenM)),
            18,
            1e18,
            0,
            strategyM,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
        liquidTokenManager.addToken(
            IERC20(address(tokenN)),
            18,
            1e18,
            0,
            strategyN,
            0, // primaryType
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
        vm.stopPrank();

        // Create deposits for both tokens
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(tokenM));
        assets[1] = IERC20(address(tokenN));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        vm.startPrank(user1);
        tokenM.mint(user1, 100 ether);
        tokenN.mint(user1, 100 ether);
        tokenM.approve(address(liquidToken), type(uint256).max);
        tokenN.approve(address(liquidToken), type(uint256).max);
        liquidToken.deposit(_convertToUpgradeable(assets), amounts, user1);
        vm.stopPrank();

        // Record share values
        uint256 initialTotalSupply = liquidToken.totalSupply();
        uint256 initialUser1Balance = liquidToken.balanceOf(user1);

        // Try to remove first token (should fail due to active shares)
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(tokenM)
            )
        );
        liquidTokenManager.removeToken(IERC20(address(tokenM)));

        // Try to remove second token (should fail due to active shares)
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(tokenN)
            )
        );
        liquidTokenManager.removeToken(IERC20(address(tokenN)));

        // Verify share value consistency
        assertEq(
            liquidToken.totalSupply(),
            initialTotalSupply,
            "Total supply should not change"
        );
        assertEq(
            liquidToken.balanceOf(user1),
            initialUser1Balance,
            "User balance should not change"
        );
        vm.stopPrank();
    }
    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testStrategyManagementSafety() public {
        // Setup initial state
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        // Create deposits
        vm.startPrank(user1);
        liquidToken.deposit(assets, amounts, user1);
        vm.stopPrank();

        // Try to remove token (and its strategy) with active shares (should fail)
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenInUse.selector,
                address(testToken)
            )
        );
        liquidTokenManager.removeToken(IERC20(address(testToken)));
        vm.stopPrank();

        // Withdraw all shares
        vm.startPrank(user1);
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();

        // Move time forward to allow withdrawal
        vm.warp(block.timestamp + 14 days);

        vm.startPrank(user1);
        bytes32[] memory requestIds = liquidToken.getUserWithdrawalRequests(user1);
        require(requestIds.length > 0, "No withdrawal requests found");
        liquidToken.fulfillWithdrawal(requestIds[0]);
        vm.stopPrank();

        // Now should be able to remove token and its strategy
        vm.startPrank(admin);
        liquidTokenManager.removeToken(IERC20(address(testToken)));

        // Verify token and strategy are removed
        assertFalse(
            liquidTokenManager.tokenIsSupported(IERC20(address(testToken))),
            "Token should not be supported"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.StrategyNotFound.selector,
                address(testToken)
            )
        );
        liquidTokenManager.getTokenStrategy(IERC20(address(testToken)));

        // Add token back with a new strategy
        MockStrategy newStrategy = new MockStrategy(strategyManager, IERC20(address(testToken)));
        liquidTokenManager.addToken(
            IERC20(address(testToken)),
            18,
            1e18,
            0,
            newStrategy
        );

        // Verify token and strategy are added back
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(testToken))),
            "Token should be supported"
        );
        assertEq(
            address(liquidTokenManager.getTokenStrategy(IERC20(address(testToken)))),
            address(newStrategy),
            "Wrong strategy"
        );
        vm.stopPrank();
    }
    */

    // Helper function to convert IERC20[] to IERC20Upgradeable[]
    function _convertToUpgradeable(
        IERC20[] memory tokens
    ) internal pure returns (IERC20Upgradeable[] memory) {
        IERC20Upgradeable[] memory upgradeableTokens = new IERC20Upgradeable[](
            tokens.length
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            upgradeableTokens[i] = IERC20Upgradeable(address(tokens[i]));
        }
        return upgradeableTokens;
    }
}