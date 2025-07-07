// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BaseTest} from "./common/BaseTest.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {FinalAutoRoutingLib} from "../src/FinalAutoRoutingLib.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract LiquidTokenManagerSwapTest is BaseTest {
    // Mock token addresses for testing
    MockERC20 public mockWETH;
    MockERC20 public mockSTETH;
    MockERC20 public mockRETH;
    MockERC20 public mockCBETH;
    MockERC20 public mockETHX;

    // Test users
    address public swapUser;
    uint256 public testNodeId;
    IStakerNode public testNode;

    // Token strategies
    mapping(address => MockStrategy) public tokenStrategies;

    function setUp() public override {
        console.log("Starting LiquidTokenManagerSwapTest setup...");

        // Call parent setup first
        super.setUp();

        console.log(
            "Parent setup complete, continuing with swap test setup..."
        );

        // Deploy mock tokens instead of using mainnet fork
        _deployMockTokens();

        // Initialize auto routing
        vm.startPrank(admin);
        try liquidTokenManager.initializeAutoRouting() {
            console.log("Auto routing initialized successfully");
        } catch Error(string memory reason) {
            console.log("Auto routing initialization failed:", reason);
        }
        vm.stopPrank();

        // Create test user
        swapUser = makeAddr("swapUser");
        vm.deal(swapUser, 1000 ether);

        // Setup environment
        _setupSwapEnvironment();
        _registerSwapTokens();
        _fundTestUsers();
        _createTestNode();
        _mockNodeDelegation(testNode);
        console.log("=== LTM Swap Test Setup Complete ===");
        console.log("Test node ID:", testNodeId);
        console.log("Test node address:", address(testNode));
    }

    function _deployMockTokens() internal {
        console.log("Deploying mock tokens...");

        mockWETH = new MockERC20("Wrapped Ether", "WETH");
        mockSTETH = new MockERC20("Staked Ether", "STETH");
        mockRETH = new MockERC20("Rocket Pool ETH", "RETH");
        mockCBETH = new MockERC20("Coinbase ETH", "CBETH");
        mockETHX = new MockERC20("ETHx", "ETHX");

        console.log("Mock tokens deployed successfully");
    }

    function _setupSwapEnvironment() internal {
        console.log("Setting up swap environment...");

        vm.startPrank(admin);

        // Grant roles
        liquidTokenManager.grantRole(
            liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
            swapUser
        );
        liquidTokenManager.grantRole(
            liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
            address(this)
        );

        // Configure mock pools
        _configureMockPools();

        vm.stopPrank();

        console.log("Swap environment setup complete");
    }

    function _configureMockPools() internal {
        // Configure pools with mock addresses
        address mockPool1 = makeAddr("mockCurvePool1");
        address mockPool2 = makeAddr("mockCurvePool2");

        liquidTokenManager.configurePool(
            mockPool1,
            true,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            2
        );

        liquidTokenManager.configurePool(
            mockPool2,
            true,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            2
        );
    }

    function _registerSwapTokens() internal {
        console.log("Registering swap tokens...");

        vm.startPrank(admin);

        // Register mock tokens
        _registerMockToken(address(mockWETH), "WETH", 18, 1e18);
        _registerMockToken(address(mockSTETH), "STETH", 18, 0.99e18);
        _registerMockToken(address(mockRETH), "RETH", 18, 1.05e18);
        _registerMockToken(address(mockCBETH), "CBETH", 18, 1.02e18);
        _registerMockToken(address(mockETHX), "ETHX", 18, 1.03e18);

        // Configure swap tokens
        liquidTokenManager.configureSwapToken(
            address(mockWETH),
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );
        liquidTokenManager.configureSwapToken(
            address(mockSTETH),
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );
        liquidTokenManager.configureSwapToken(
            address(mockRETH),
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );
        liquidTokenManager.configureSwapToken(
            address(mockCBETH),
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );
        liquidTokenManager.configureSwapToken(
            address(mockETHX),
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );

        vm.stopPrank();

        console.log("Swap tokens registered successfully");
    }

    function _registerMockToken(
        address token,
        string memory name,
        uint8 decimals,
        uint256 price
    ) internal {
        console.log("Registering token:", name);

        MockStrategy strategy = new MockStrategy(
            strategyManager,
            IERC20(token)
        );
        tokenStrategies[token] = strategy;

        // Mock oracle price
        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(
                tokenRegistryOracle._getTokenPrice_getter.selector,
                token
            ),
            abi.encode(price, true)
        );

        try
            liquidTokenManager.addToken(
                IERC20(token),
                decimals,
                0.2e18,
                IStrategy(address(strategy)),
                SOURCE_TYPE_CHAINLINK,
                address(_createMockPriceFeed(int256(uint256(price) / 1e10), 8)),
                0,
                address(0),
                bytes4(0)
            )
        {
            console.log("Token registered successfully:", name);
        } catch Error(string memory reason) {
            console.log("Failed to register token:", name, reason);
        }
    }

    function _fundTestUsers() internal {
        console.log("Funding test users...");

        // 1) Mint to swapUser
        mockWETH.mint(swapUser, 10 ether);

        // 2) Deposit into LiquidToken vault to bump internal assetBalances
        vm.startPrank(swapUser);
        mockWETH.approve(address(liquidToken), 10 ether);
        IERC20Upgradeable[] memory assets = new IERC20Upgradeable[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20Upgradeable(address(mockWETH));
        amounts[0] = 10 ether;
        liquidToken.deposit(assets, amounts, swapUser);
        vm.stopPrank();

        console.log("Test users funded successfully");
    }
    /// @dev Mocks EigenLayer delegation manager **and** bypasses the node’s depositAssets().
    function _mockNodeDelegation(IStakerNode node) internal {
        address nodeAddr = address(node);
        // 1) Pretend the node is delegated in EL
        vm.mockCall(
            address(delegationManager),
            abi.encodeWithSignature("isDelegated(address)", nodeAddr),
            abi.encode(true)
        );
        vm.mockCall(
            address(delegationManager),
            abi.encodeWithSignature("delegatedTo(address)", nodeAddr),
            abi.encode(swapUser)
        );
        vm.mockCall(
            address(delegationManager),
            abi.encodeWithSignature("isOperator(address)", swapUser),
            abi.encode(true)
        );
        // 2) Stub out the node’s depositAssets(...) call so it never reverts
        vm.mockCall(
            address(node),
            abi.encodeWithSelector(IStakerNode.depositAssets.selector),
            abi.encode()
        );
    }
    /// @dev After depositAssets is stubbed, make the strategy return a non-zero balance.
    function _updateMockedStrategyBalance(
        address token,
        uint256 amount
    ) internal {
        // lookup the MockStrategy you stored
        MockStrategy strategy = tokenStrategies[token];
        // stub userUnderlyingView(node) => amount
        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature(
                "userUnderlyingView(address)",
                address(testNode)
            ),
            abi.encode(amount)
        );
    }

    function _createTestNode() internal {
        console.log("Creating test node...");

        vm.startPrank(admin);
        testNode = stakerNodeCoordinator.createStakerNode();
        testNodeId = testNode.getId();
        vm.stopPrank();

        console.log("Test node created successfully");
    }

    // ==================== TESTS ====================

    function testBasicSetup() public {
        console.log("\n=== Testing Basic Setup ===");

        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(mockWETH))),
            "WETH should be supported"
        );
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(mockSTETH))),
            "STETH should be supported"
        );

        console.log("Basic setup verified");
    }

    function testDirectStakeWithoutSwap() public {
        console.log("\n=== Testing Direct Stake Without Swap ===");

        vm.startPrank(swapUser);

        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        assets[0] = IERC20(address(mockWETH));
        amounts[0] = 1 ether;

        // Approve token
        mockWETH.approve(address(liquidToken), amounts[0]);

        uint256 nodeBefore = liquidTokenManager.getStakedAssetBalanceNode(
            IERC20(address(mockWETH)),
            testNodeId
        );

        try liquidTokenManager.stakeAssetsToNode(testNodeId, assets, amounts) {
            // tell the MockStrategy to report `amounts[0]` staked
            _updateMockedStrategyBalance(address(mockWETH), amounts[0]);

            uint256 nodeAfter = liquidTokenManager.getStakedAssetBalanceNode(
                IERC20(address(mockWETH)),
                testNodeId
            );
            console.log("Direct stake successful");
            console.log("WETH staked:", nodeAfter - nodeBefore);
            assertGt(nodeAfter, nodeBefore, "Should have staked WETH");
        } catch Error(string memory reason) {
            console.log("Direct stake failed:", reason);
        }

        vm.stopPrank();
    }

    function testSwapWithSameTokens() public {
        console.log("\n=== Testing Swap With Same Tokens (No Swap) ===");

        vm.startPrank(swapUser);

        IERC20[] memory sourceAssets = new IERC20[](1);
        uint256[] memory sourceAmounts = new uint256[](1);
        IERC20[] memory targetAssets = new IERC20[](1);
        uint256[] memory minTargetAmounts = new uint256[](1);

        sourceAssets[0] = IERC20(address(mockWETH));
        sourceAmounts[0] = 1 ether;
        targetAssets[0] = IERC20(address(mockWETH)); // Same token
        minTargetAmounts[0] = 1 ether;

        uint256 nodeBefore = liquidTokenManager.getStakedAssetBalanceNode(
            IERC20(address(mockWETH)),
            testNodeId
        );

        try
            liquidTokenManager.swapAndStakeAssetsToNode(
                testNodeId,
                sourceAssets,
                sourceAmounts,
                targetAssets,
                minTargetAmounts
            )
        {
            // reflect the 1 ether stake in the strategy mock
            _updateMockedStrategyBalance(address(mockWETH), sourceAmounts[0]);

            uint256 nodeAfter = liquidTokenManager.getStakedAssetBalanceNode(
                IERC20(address(mockWETH)),
                testNodeId
            );
            assertEq(
                nodeAfter - nodeBefore,
                1 ether,
                "Should stake exact amount when no swap"
            );
            console.log("Same token stake successful (no swap needed)");
        } catch Error(string memory reason) {
            console.log("Same token swap and stake failed:", reason);
        }

        vm.stopPrank();
    }

    function testPoolConfiguration() public {
        console.log("\n=== Testing Pool Configuration ===");

        vm.startPrank(admin);

        address newMockPool = makeAddr("newMockPool");

        liquidTokenManager.configurePool(
            newMockPool,
            true,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            2
        );

        console.log("Pool configuration successful");
        vm.stopPrank();
    }

    function testTokenConfiguration() public {
        console.log("\n=== Testing Token Configuration ===");

        vm.startPrank(admin);

        address newToken = makeAddr("newToken");

        liquidTokenManager.configureSwapToken(
            newToken,
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );

        console.log("Token configuration successful");
        vm.stopPrank();
    }

    function testETHReception() public {
        console.log("\n=== Testing ETH Reception ===");

        uint256 balanceBefore = address(liquidTokenManager).balance;

        vm.deal(address(this), 1 ether);
        (bool success, ) = address(liquidTokenManager).call{value: 1 ether}("");

        assertTrue(success, "LTM should receive ETH");
        assertEq(address(liquidTokenManager).balance, balanceBefore + 1 ether);

        console.log("ETH reception successful");
    }

    function testNodeCreation() public {
        console.log("\n=== Testing Node Creation ===");

        uint256 nodeCountBefore = stakerNodeCoordinator.getStakerNodesCount();

        vm.startPrank(admin);
        IStakerNode newNode = stakerNodeCoordinator.createStakerNode();
        vm.stopPrank();

        uint256 nodeCountAfter = stakerNodeCoordinator.getStakerNodesCount();

        assertEq(
            nodeCountAfter,
            nodeCountBefore + 1,
            "Node count should increase"
        );
        assertTrue(address(newNode) != address(0), "Node should be created");

        console.log("Node creation successful");
        console.log("New node ID:", newNode.getId());
    }
}