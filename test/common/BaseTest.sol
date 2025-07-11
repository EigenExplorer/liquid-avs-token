// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/permissions/PauserRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {FinalAutoRouting} from "../../src/FinalAutoRouting.sol";

import {LiquidToken} from "../../src/core/LiquidToken.sol";
import {TokenRegistryOracle} from "../../src/utils/TokenRegistryOracle.sol";
import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";
import {StakerNode} from "../../src/core/StakerNode.sol";
import {StakerNodeCoordinator} from "../../src/core/StakerNodeCoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";
import {MockChainlinkFeed} from "../mocks/MockChainlinkFeed.sol";
import {MockCurvePool} from "../mocks/MockCurvePool.sol";
import {MockProtocolToken} from "../mocks/MockProtocolToken.sol";
import {MockFailingOracle} from "../mocks/MockFailingOracle.sol";
import {IStakerNodeCoordinator} from "../../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../../src/interfaces/IStakerNode.sol";
import {ILiquidToken} from "../../src/interfaces/ILiquidToken.sol";
import {ITokenRegistryOracle} from "../../src/interfaces/ITokenRegistryOracle.sol";
import {ILiquidTokenManager} from "../../src/interfaces/ILiquidTokenManager.sol";
import {NetworkAddresses} from "../utils/NetworkAddresses.sol";

// ✅ NEW: Import interfaces for FAR mocks
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IUniswapV3Router} from "../../src/interfaces/IUniswapV3Router.sol";
import {IUniswapV3Quoter} from "../../src/interfaces/IUniswapV3Quoter.sol";
import {IFrxETHMinter} from "../../src/interfaces/IFrxETHMinter.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {MockUniswapV3Router} from "../mocks/MockUniswapV3Router.sol";
import {MockUniswapV3Quoter} from "../mocks/MockUniswapV3Quoter.sol";
import {MockFrxETHMinter} from "../mocks/MockFrxETHMinter.sol";
contract BaseTest is Test {
    // Source type constants
    uint8 constant SOURCE_TYPE_CHAINLINK = 1;
    uint8 constant SOURCE_TYPE_CURVE = 2;
    uint8 constant SOURCE_TYPE_PROTOCOL = 3;
    uint8 constant SOURCE_TYPE_NATIVE = 0;

    // Price freshness constants
    uint256 constant PRICE_FRESHNESS_PERIOD = 12 hours;
    //random salt
    uint256 internal constant SAMPLE_SALT = 0xabcdef1234567890;

    // EigenLayer Contracts
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    // Contracts
    LiquidToken public liquidToken;
    TokenRegistryOracle public tokenRegistryOracle;
    LiquidTokenManager public liquidTokenManager;
    StakerNodeCoordinator public stakerNodeCoordinator;
    StakerNode public stakerNodeImplementation;

    // ✅ NEW: Mock contracts for FAR dependencies
    MockWETH public mockWETH;
    address public mockUniswapRouter;
    address public mockUniswapQuoter;
    address public mockFrxETHMinter;
    address public mockRouteManager;
    bytes32 public constant MOCK_ROUTE_PASSWORD_HASH = keccak256("test_password");

    // Mock contracts - base test tokens
    MockERC20 public testToken;
    MockERC20 public testToken2;
    MockStrategy public mockStrategy;
    MockStrategy public mockStrategy2;

    // Mock price feeds for basic test tokens
    MockChainlinkFeed public testTokenFeed;
    MockChainlinkFeed public testToken2Feed;

    // Common function selectors for price sources
    bytes4 public exchangeRateSelector;
    bytes4 public getPooledEthBySharesSelector;
    bytes4 public convertToAssetsSelector;
    bytes4 public getRateSelector;
    bytes4 public stEthPerTokenSelector;
    bytes4 public swETHToETHRateSelector;
    bytes4 public ratioSelector;
    bytes4 public underlyingBalanceFromSharesSelector;
    bytes4 public mETHToETHSelector;

    // Addresses
    address public proxyAdminAddress = address(0xABCD);
    address public admin = address(this);
    address public deployer = address(0x1234);
    address public pauser = address(2);
    address public user1 = address(3);
    address public user2 = address(4);

    // Private variables (with leading underscore)
    LiquidToken private _liquidTokenImplementation;
    TokenRegistryOracle private _tokenRegistryOracleImplementation;
    LiquidTokenManager private _liquidTokenManagerImplementation;
    StakerNodeCoordinator private _stakerNodeCoordinatorImplementation;

    // Helper method to use deployer for proxy interactions
    modifier asDeployer() {
        vm.startPrank(deployer);
        _;
        vm.stopPrank();
    }

    function setUp() public virtual {
        console.log("Starting test setup...");
        _initializeSelectors();
        _setupELContracts();
        _deployMockContracts();
        _deployMainContracts();
        _deployProxies();

        // Initialize contracts in the correct order to avoid dependency issues
        // 1. First initialize TokenRegistryOracle
        _initializeTokenRegistryOracle();

        // 2. Setup oracle sources
        _setupOracleSources();

        // 3. Initialize LiquidTokenManager (✅ FIXED: New signature)
        _initializeLiquidTokenManager();

        // 4. Initialize LiquidToken (depends on LiquidTokenManager)
        _initializeLiquidToken();

        // 5. Initialize StakerNodeCoordinator (depends on LiquidTokenManager)
        _initializeStakerNodeCoordinator();

        // 6. Add tokens after all initializations
        _addTestTokens();

        // 7. Setup test token balances
        _setupTestTokens();

        // 8. Renounce roles at the end
        _renounceAllRoles();
    }

    function _addTestTokens() internal {
        console.log("Adding tokens to LiquidTokenManager...");

        // Print role statuses for debugging
        console.log("Role checks before adding tokens:");
        console.log(
            "Deployer has DEFAULT_ADMIN_ROLE:",
            liquidTokenManager.hasRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), deployer)
        );
        console.log(
            "Deployer has STRATEGY_CONTROLLER_ROLE:",
            liquidTokenManager.hasRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), deployer)
        );
        console.log(
            "admin has TOKEN_CONFIGURATOR_ROLE:",
            tokenRegistryOracle.hasRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), admin)
        );

        // Get price feed data using proper try/catch syntax
        try testTokenFeed.latestRoundData() returns (uint80, int256 price, uint256, uint256, uint80) {
            console.log("testTokenFeed price:", uint256(price));
        } catch {
            console.log("Failed to get testTokenFeed price");
        }
        // Add tokens as deployer (who must have admin role)
        vm.startPrank(deployer);

        try
            liquidTokenManager.addToken(
                IERC20(address(testToken)),
                18,
                0.1e18,
                IStrategy(address(mockStrategy)),
                SOURCE_TYPE_CHAINLINK,
                address(testTokenFeed),
                0,
                address(0),
                bytes4(0)
            )
        {
            console.log("First token added successfully");
        } catch Error(string memory reason) {
            console.log("First token add failed:", reason);
        } catch {
            console.log("First token add failed with unknown error");
        }
        try
            liquidTokenManager.addToken(
                IERC20(address(testToken2)),
                18,
                0,
                IStrategy(address(mockStrategy2)),
                SOURCE_TYPE_CHAINLINK,
                address(testToken2Feed),
                0,
                address(0),
                bytes4(0)
            )
        {
            console.log("Second token added successfully");
        } catch Error(string memory reason) {
            console.log("Second token add failed:", reason);
        } catch {
            console.log("Second token add failed with unknown error");
        }
        vm.stopPrank();
    }

    function _renounceAllRoles() private {
        vm.startPrank(deployer);

        // LiquidTokenManager
        if (liquidTokenManager.hasRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), deployer)) {
            liquidTokenManager.renounceRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), deployer);
        }
        if (liquidTokenManager.hasRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), deployer)) {
            liquidTokenManager.renounceRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), deployer);
        }

        // TokenRegistryOracle
        if (tokenRegistryOracle.hasRole(tokenRegistryOracle.DEFAULT_ADMIN_ROLE(), deployer)) {
            tokenRegistryOracle.renounceRole(tokenRegistryOracle.DEFAULT_ADMIN_ROLE(), deployer);
        }
        if (tokenRegistryOracle.hasRole(tokenRegistryOracle.ORACLE_ADMIN_ROLE(), deployer)) {
            tokenRegistryOracle.renounceRole(tokenRegistryOracle.ORACLE_ADMIN_ROLE(), deployer);
        }
        if (tokenRegistryOracle.hasRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), deployer)) {
            tokenRegistryOracle.renounceRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), deployer);
        }
        if (tokenRegistryOracle.hasRole(tokenRegistryOracle.RATE_UPDATER_ROLE(), deployer)) {
            tokenRegistryOracle.renounceRole(tokenRegistryOracle.RATE_UPDATER_ROLE(), deployer);
        }

        // StakerNodeCoordinator
        if (stakerNodeCoordinator.hasRole(stakerNodeCoordinator.DEFAULT_ADMIN_ROLE(), deployer)) {
            stakerNodeCoordinator.renounceRole(stakerNodeCoordinator.DEFAULT_ADMIN_ROLE(), deployer);
        }
        if (stakerNodeCoordinator.hasRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), deployer)) {
            stakerNodeCoordinator.renounceRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), deployer);
        }
        if (stakerNodeCoordinator.hasRole(stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), deployer)) {
            stakerNodeCoordinator.renounceRole(stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), deployer);
        }

        // LiquidToken
        if (liquidToken.hasRole(liquidToken.DEFAULT_ADMIN_ROLE(), deployer)) {
            liquidToken.renounceRole(liquidToken.DEFAULT_ADMIN_ROLE(), deployer);
        }
        if (liquidToken.hasRole(liquidToken.PAUSER_ROLE(), deployer)) {
            liquidToken.renounceRole(liquidToken.PAUSER_ROLE(), deployer);
        }
        vm.stopPrank();
    }

    function _initializeSelectors() internal {
        // Initialize all common function selectors for price sources
        exchangeRateSelector = bytes4(keccak256("exchangeRate()"));
        getPooledEthBySharesSelector = bytes4(keccak256("getPooledEthByShares(uint256)"));
        convertToAssetsSelector = bytes4(keccak256("convertToAssets(uint256)"));
        getRateSelector = bytes4(keccak256("getRate()"));
        stEthPerTokenSelector = bytes4(keccak256("stEthPerToken()"));
        swETHToETHRateSelector = bytes4(keccak256("swETHToETHRate()"));
        ratioSelector = bytes4(keccak256("ratio()"));
        underlyingBalanceFromSharesSelector = bytes4(keccak256("underlyingBalanceFromShares(uint256)"));
        mETHToETHSelector = bytes4(keccak256("mETHToETH(uint256)"));
    }

    function _setupELContracts() private {
        uint256 chainId = block.chainid;
        NetworkAddresses.Addresses memory addresses = NetworkAddresses.getAddresses(chainId);

        strategyManager = IStrategyManager(addresses.strategyManager);
        delegationManager = IDelegationManager(addresses.delegationManager);
    }

    function _deployMockContracts() private {
        // Base test tokens
        testToken = new MockERC20("Test Token", "TEST");
        testToken2 = new MockERC20("Test Token 2", "TEST2");
        mockStrategy = new MockStrategy(strategyManager, IERC20(address(testToken)));
        mockStrategy2 = new MockStrategy(strategyManager, IERC20(address(testToken2)));

        // Deploy price feed mocks with realistic values for test tokens
        testTokenFeed = new MockChainlinkFeed(int256(100000000), 8); // 1 ETH per TEST (8 decimals)
        testToken2Feed = new MockChainlinkFeed(int256(50000000), 8); // 0.5 ETH per TEST2 (8 decimals)

        // ✅ FIXED: Deploy proper FAR mock dependencies
        mockWETH = new MockWETH(); // ✅ Use MockWETH instead of MockERC20

        // Deploy actual mock contracts instead of simple addresses
        MockUniswapV3Router mockRouterContract = new MockUniswapV3Router();
        MockUniswapV3Quoter mockQuoterContract = new MockUniswapV3Quoter();
        MockFrxETHMinter mockMinterContract = new MockFrxETHMinter();

        mockUniswapRouter = address(mockRouterContract);
        mockUniswapQuoter = address(mockQuoterContract);
        mockFrxETHMinter = address(mockMinterContract);
        mockRouteManager = address(0x9999); // Simple address for route manager
    }
    function _deployMainContracts() private {
        _tokenRegistryOracleImplementation = new TokenRegistryOracle();
        _liquidTokenImplementation = new LiquidToken();
        _liquidTokenManagerImplementation = new LiquidTokenManager();
        _stakerNodeCoordinatorImplementation = new StakerNodeCoordinator();
        stakerNodeImplementation = new StakerNode();
    }

    function _deployProxies() private {
        tokenRegistryOracle = TokenRegistryOracle(
            address(new TransparentUpgradeableProxy(address(_tokenRegistryOracleImplementation), proxyAdminAddress, ""))
        );

        // ✅ FIXED: Use payable casting for LiquidTokenManager
        liquidTokenManager = LiquidTokenManager(
            payable(
                address(
                    new TransparentUpgradeableProxy(address(_liquidTokenManagerImplementation), proxyAdminAddress, "")
                )
            )
        );

        liquidToken = LiquidToken(
            address(new TransparentUpgradeableProxy(address(_liquidTokenImplementation), proxyAdminAddress, ""))
        );
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(
                new TransparentUpgradeableProxy(address(_stakerNodeCoordinatorImplementation), proxyAdminAddress, "")
            )
        );
    }

    function _setupOracleSources() private {
        console.log("Setting up oracle sources...");

        // Grant TOKEN_CONFIGURATOR_ROLE to admin
        vm.startPrank(deployer);
        tokenRegistryOracle.grantRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), admin);

        // Grant TOKEN_CONFIGURATOR_ROLE to deployer too
        tokenRegistryOracle.grantRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), deployer);
        vm.stopPrank();

        vm.startPrank(admin);
        // Configure test tokens with Chainlink sources
        console.log("Configuring testToken in oracle...");
        tokenRegistryOracle.configureToken(
            address(testToken),
            SOURCE_TYPE_CHAINLINK,
            address(testTokenFeed),
            0, // No args needed
            address(0), // No fallback source
            bytes4(0) // No fallback function
        );

        console.log("Configuring testToken2 in oracle...");
        tokenRegistryOracle.configureToken(
            address(testToken2),
            SOURCE_TYPE_CHAINLINK,
            address(testToken2Feed),
            0, // No args needed
            address(0), // No fallback source
            bytes4(0) // No fallback function
        );
        vm.stopPrank();

        // Update prices with proper try/catch syntax
        vm.startPrank(user2);
        try tokenRegistryOracle.updateAllPricesIfNeeded() {
            console.log("Price update successful");
        } catch Error(string memory reason) {
            console.log("Price update failed with reason:", reason);
        } catch {
            console.log("Price update failed with unknown error");
        }
        vm.stopPrank();
    }

    function _initializeTokenRegistryOracle() private {
        console.log("Initializing TokenRegistryOracle...");
        ITokenRegistryOracle.Init memory init = ITokenRegistryOracle.Init({
            initialOwner: deployer,
            priceUpdater: user2,
            liquidToken: address(liquidToken),
            liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
        });

        vm.prank(deployer);
        tokenRegistryOracle.initialize(init, SAMPLE_SALT);

        // Grant roles
        vm.startPrank(deployer);
        tokenRegistryOracle.grantRole(tokenRegistryOracle.DEFAULT_ADMIN_ROLE(), address(this));
        tokenRegistryOracle.grantRole(tokenRegistryOracle.ORACLE_ADMIN_ROLE(), address(this));
        tokenRegistryOracle.grantRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), address(this));

        // Critical: Grant TOKEN_CONFIGURATOR_ROLE to deployer who will add tokens
        tokenRegistryOracle.grantRole(tokenRegistryOracle.TOKEN_CONFIGURATOR_ROLE(), deployer);

        // Grant RATE_UPDATER_ROLE to user2
        tokenRegistryOracle.grantRole(tokenRegistryOracle.RATE_UPDATER_ROLE(), user2);

        // Grant RATE_UPDATER_ROLE to deployer temporarily
        tokenRegistryOracle.grantRole(tokenRegistryOracle.RATE_UPDATER_ROLE(), deployer);
        vm.stopPrank();
    }

    // ✅ FIXED: Updated LiquidTokenManager initialization with new signature
    function _initializeLiquidTokenManager() private {
        console.log("Initializing LiquidTokenManager...");

        // LTM Init struct
        ILiquidTokenManager.Init memory ltmInit = ILiquidTokenManager.Init({
            liquidToken: liquidToken,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            stakerNodeCoordinator: stakerNodeCoordinator,
            tokenRegistryOracle: ITokenRegistryOracle(address(tokenRegistryOracle)),
            initialOwner: deployer,
            strategyController: deployer,
            priceUpdater: address(tokenRegistryOracle)
        });

        // ✅ FIXED: Initialize LTM with mock addresses
        vm.prank(deployer);
        liquidTokenManager.initialize(
            ltmInit,
            address(mockWETH), // wethAddr
            mockUniswapRouter, // routerAddr
            mockUniswapQuoter, // quoterAddr
            mockFrxETHMinter, // minterAddr
            mockRouteManager, // routeMgrAddr
            MOCK_ROUTE_PASSWORD_HASH // routePasswordHash
        );

        // ✅ NEW: Configure test environment after initialization
        vm.startPrank(deployer);

        // Set mock addresses in FAR (inherited by LTM)
        liquidTokenManager.setMockAddresses(
            address(mockWETH),
            mockUniswapRouter,
            mockUniswapQuoter,
            mockFrxETHMinter,
            mockRouteManager
        );

        // Add test tokens to FAR
        address[] memory testTokenAddresses = new address[](2);
        FinalAutoRouting.AssetType[] memory testTokenTypes = new FinalAutoRouting.AssetType[](2);
        uint8[] memory testTokenDecimals = new uint8[](2);

        testTokenAddresses[0] = address(testToken);
        testTokenAddresses[1] = address(testToken2);
        testTokenTypes[0] = FinalAutoRouting.AssetType.ETH_LST;
        testTokenTypes[1] = FinalAutoRouting.AssetType.ETH_LST;
        testTokenDecimals[0] = 18;
        testTokenDecimals[1] = 18;

        liquidTokenManager.addTestTokens(testTokenAddresses, testTokenTypes, testTokenDecimals);

        // Add test route (testToken -> testToken2)
        FinalAutoRouting.RouteConfig memory testRoute = FinalAutoRouting.RouteConfig({
            protocol: FinalAutoRouting.Protocol.UniswapV3,
            pool: mockUniswapRouter, // Use mock router as pool
            fee: 3000,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        liquidTokenManager.addTestRoute(address(testToken), address(testToken2), testRoute);

        // Set test slippage
        liquidTokenManager.setTestSlippage(address(testToken), address(testToken2), 1000); // 10%

        vm.stopPrank();

        // Grant roles
        vm.startPrank(deployer);
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), address(this));
        liquidTokenManager.grantRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), address(this));
        vm.stopPrank();
    }

    function _initializeStakerNodeCoordinator() private {
        console.log("Initializing StakerNodeCoordinator...");
        IStakerNodeCoordinator.Init memory init = IStakerNodeCoordinator.Init({
            liquidTokenManager: liquidTokenManager,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            maxNodes: 10,
            initialOwner: deployer,
            pauser: pauser,
            stakerNodeCreator: deployer,
            stakerNodesDelegator: deployer,
            stakerNodeImplementation: address(stakerNodeImplementation)
        });

        vm.prank(deployer);
        stakerNodeCoordinator.initialize(init);

        // Grant roles
        vm.startPrank(deployer);
        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.DEFAULT_ADMIN_ROLE(), address(this));
        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), address(this));
        stakerNodeCoordinator.grantRole(stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), address(this));
        vm.stopPrank();
    }

    function _initializeLiquidToken() private {
        console.log("Initializing LiquidToken...");
        ILiquidToken.Init memory init = ILiquidToken.Init({
            name: "Liquid Staking Token",
            symbol: "LST",
            initialOwner: deployer,
            pauser: pauser,
            liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager)),
            tokenRegistryOracle: ITokenRegistryOracle(address(tokenRegistryOracle))
        });

        vm.prank(deployer);
        liquidToken.initialize(init);

        // Grant roles
        vm.startPrank(deployer);
        liquidToken.grantRole(liquidToken.DEFAULT_ADMIN_ROLE(), address(this));
        liquidToken.grantRole(liquidToken.PAUSER_ROLE(), pauser);
        vm.stopPrank();
    }

    function _setupTestTokens() private {
        testToken.mint(user1, 100 ether);
        testToken.mint(user2, 100 ether);
        testToken2.mint(user1, 100 ether);
        testToken2.mint(user2, 100 ether);

        vm.prank(user1);
        testToken.approve(address(liquidToken), type(uint256).max);
        vm.prank(user1);
        testToken2.approve(address(liquidToken), type(uint256).max);
        vm.prank(user2);
        testToken.approve(address(liquidToken), type(uint256).max);
        vm.prank(user2);
        testToken2.approve(address(liquidToken), type(uint256).max);
    }

    // ================= PRICE ORACLE HELPER METHODS =================

    /**
     * @dev Updates prices for all configured tokens
     * Note: This function is now marked virtual so derived contracts can override it
     */
    function _updateAllPrices() internal virtual {
        vm.prank(user2); // user2 has RATE_UPDATER_ROLE
        tokenRegistryOracle.updateAllPricesIfNeeded();
    }

    /**
     * @dev Makes prices stale by advancing time past the freshness period
     * Note: This function is now marked virtual so derived contracts can override it
     */
    function _makePricesStale() internal virtual {
        vm.warp(block.timestamp + PRICE_FRESHNESS_PERIOD + 1 hours);
    }

    /**
     * @dev Configures a token with Chainlink as the primary price source
     */
    function _setupChainlinkToken(address token, address feed) internal {
        vm.prank(admin);
        tokenRegistryOracle.configureToken(
            token,
            SOURCE_TYPE_CHAINLINK,
            feed,
            0, // No args needed
            address(0), // No fallback
            bytes4(0) // No fallback function
        );
    }

    /**
     * @dev Configures a token with Protocol rate as the primary price source
     */
    function _setupProtocolToken(address token, address contract_, bytes4 selector, bool needsArg) internal {
        vm.prank(admin);
        tokenRegistryOracle.configureToken(
            token,
            SOURCE_TYPE_PROTOCOL,
            contract_,
            needsArg ? 1 : 0, // Set if argument is needed
            address(0), // No fallback
            selector
        );
    }

    /**
     * @dev Configures a token with Curve pool as the primary price source
     */
    function _setupCurveToken(address token, address curvePool) internal {
        vm.prank(admin);
        tokenRegistryOracle.configureToken(
            token,
            SOURCE_TYPE_CURVE,
            curvePool,
            0, // No args needed
            address(0), // No fallback
            bytes4(0) // No fallback function
        );
    }

    /**
     * @dev Configures a token with primary and fallback price sources
     */
    function _setupTokenWithFallback(
        address token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn
    ) internal {
        vm.prank(admin);
        tokenRegistryOracle.configureToken(token, primaryType, primarySource, needsArg, fallbackSource, fallbackFn);
    }

    /**
     * @dev Gets the price of a token directly from TokenRegistryOracle
     */
    function _getTokenPrice(address token) internal returns (uint256) {
        return tokenRegistryOracle.getTokenPrice(token);
    }

    // Helper functions for inheriting contracts to use
    function _actAsAdmin(function() internal fn) internal {
        vm.startPrank(admin);
        fn();
        vm.stopPrank();
    }

    function _actAsDeployer(function() internal fn) internal {
        vm.startPrank(deployer);
        fn();
        vm.stopPrank();
    }

    function _actAsUser1(function() internal fn) internal {
        vm.startPrank(user1);
        fn();
        vm.stopPrank();
    }

    function _actAsUser2(function() internal fn) internal {
        vm.startPrank(user2);
        fn();
        vm.stopPrank();
    }

    // Helper to create a new price source mock for a token - updated to use int256
    function _createMockPriceFeed(int256 price, uint8 decimals) internal returns (MockChainlinkFeed) {
        return new MockChainlinkFeed(price, decimals);
    }

    function _createMockProtocolToken(uint256 exchangeRate) internal returns (MockProtocolToken) {
        MockProtocolToken token = new MockProtocolToken();
        token.setExchangeRate(exchangeRate);
        return token;
    }

    function _createMockCurvePool(uint256 virtualPrice) internal returns (MockCurvePool) {
        MockCurvePool pool = new MockCurvePool();
        pool.setVirtualPrice(virtualPrice);
        return pool;
    }

    function _createMockFailingOracle() internal returns (MockFailingOracle) {
        return new MockFailingOracle();
    }
}