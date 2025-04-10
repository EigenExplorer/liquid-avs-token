// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/permissions/PauserRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

import {LiquidToken} from "../../src/core/LiquidToken.sol";
import {TokenRegistryOracle} from "../../src/utils/TokenRegistryOracle.sol";
import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";
import {StakerNode} from "../../src/core/StakerNode.sol";
import {StakerNodeCoordinator} from "../../src/core/StakerNodeCoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";
import {IStakerNodeCoordinator} from "../../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../../src/interfaces/IStakerNode.sol";
import {ILiquidToken} from "../../src/interfaces/ILiquidToken.sol";
import {ITokenRegistryOracle} from "../../src/interfaces/ITokenRegistryOracle.sol";
import {ILiquidTokenManager} from "../../src/interfaces/ILiquidTokenManager.sol";
import {NetworkAddresses} from "../utils/NetworkAddresses.sol";

contract BaseTest is Test {
    // EigenLayer Contracts
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    // Contracts
    LiquidToken public liquidToken;
    TokenRegistryOracle public tokenRegistryOracle;
    LiquidTokenManager public liquidTokenManager;
    StakerNodeCoordinator public stakerNodeCoordinator;
    StakerNode public stakerNodeImplementation;

    // Mock contracts
    MockERC20 public testToken;
    MockERC20 public testToken2;
    MockStrategy public mockStrategy;
    MockStrategy public mockStrategy2;

    // Addresses
    address public proxyAdminAddress = address(0xABCD); // Proxy admin address
    address public admin = address(this);
    address public deployer = address(0x1234); // Non-admin address for interacting with proxies
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
        _setupELContracts();
        _deployMockContracts();
        _deployMainContracts();
        _deployProxies();
        // Initialize with deployer as the initialOwner
        _initializeProxies();
        _setupTestTokens();
    }

    function testZeroAddressInitialization() public {
        LiquidTokenManager newLiquidTokenManager = new LiquidTokenManager();
        StakerNodeCoordinator newStakerNodeCoordinator = new StakerNodeCoordinator();
        LiquidToken newLiquidToken = new LiquidToken();

        // LiquidTokenManager Initialization Tests
        {
            ILiquidTokenManager.Init memory validInit = ILiquidTokenManager
                .Init({
                    assets: new IERC20[](2),
                    tokenInfo: new ILiquidTokenManager.TokenInfo[](2),
                    strategies: new IStrategy[](2),
                    liquidToken: liquidToken,
                    strategyManager: strategyManager,
                    delegationManager: delegationManager,
                    stakerNodeCoordinator: stakerNodeCoordinator,
                    initialOwner: deployer,
                    strategyController: deployer,
                    priceUpdater: address(tokenRegistryOracle)
                });

            validInit.assets[0] = IERC20(address(testToken));
            validInit.assets[1] = IERC20(address(testToken2));
            validInit.strategies[0] = IStrategy(address(mockStrategy));
            validInit.strategies[1] = IStrategy(address(mockStrategy2));
            validInit.tokenInfo[0] = ILiquidTokenManager.TokenInfo({
                decimals: 18,
                pricePerUnit: 1e18,
                volatilityThreshold: 0.1 * 1e18
            });
            validInit.tokenInfo[1] = ILiquidTokenManager.TokenInfo({
                decimals: 18,
                pricePerUnit: 1e18,
                volatilityThreshold: 0
            });

            // Test each parameter individually
            ILiquidTokenManager.Init memory testInit;

            // Zero address for owner
            testInit = validInit;
            testInit.initialOwner = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address for liquidToken
            testInit = validInit;
            testInit.liquidToken = ILiquidToken(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address for strategyManager
            testInit = validInit;
            testInit.strategyManager = IStrategyManager(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address for delegationManager
            testInit = validInit;
            testInit.delegationManager = IDelegationManager(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address for stakerNodeCoordinator
            testInit = validInit;
            testInit.stakerNodeCoordinator = IStakerNodeCoordinator(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address for strategyController
            testInit = validInit;
            testInit.strategyController = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address for priceUpdater
            testInit = validInit;
            testInit.priceUpdater = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address in assets array
            testInit = validInit;
            testInit.assets[0] = IERC20(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);

            // Zero address in strategies array
            testInit = validInit;
            testInit.strategies[0] = IStrategy(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidTokenManager.initialize(testInit);
        }

        // LiquidToken Initialization Tests
        {
            ILiquidToken.Init memory validInit = ILiquidToken.Init({
                name: "Liquid Staking Token",
                symbol: "LST",
                initialOwner: deployer,
                pauser: pauser,
                liquidTokenManager: ILiquidTokenManager(
                    address(liquidTokenManager)
                ),
                tokenRegistryOracle: ITokenRegistryOracle(
                    address(tokenRegistryOracle)
                ) // Added this line
            });

            // Test each parameter individually
            ILiquidToken.Init memory testInit;

            // Zero address for owner
            testInit = validInit;
            testInit.initialOwner = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidToken.initialize(testInit);

            // Zero address for pauser
            testInit = validInit;
            testInit.pauser = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidToken.initialize(testInit);

            // Zero address for liquidTokenManager
            testInit = validInit;
            testInit.liquidTokenManager = ILiquidTokenManager(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newLiquidToken.initialize(testInit);
        }

        // StakerNodeCoordinator Initialization Tests
        {
            IStakerNodeCoordinator.Init
                memory validInit = IStakerNodeCoordinator.Init({
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

            // Test each parameter individually
            IStakerNodeCoordinator.Init memory testInit;

            // Zero address for owner
            testInit = validInit;
            testInit.initialOwner = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for pauser
            testInit = validInit;
            testInit.pauser = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for stakerNodeCreator
            testInit = validInit;
            testInit.stakerNodeCreator = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for stakerNodesDelegator
            testInit = validInit;
            testInit.stakerNodesDelegator = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for liquidTokenManager
            testInit = validInit;
            testInit.liquidTokenManager = ILiquidTokenManager(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for strategyManager
            testInit = validInit;
            testInit.strategyManager = IStrategyManager(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for delegationManager
            testInit = validInit;
            testInit.delegationManager = IDelegationManager(address(0));
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);

            // Zero address for stakerNodeImplementation
            testInit = validInit;
            testInit.stakerNodeImplementation = address(0);
            vm.prank(deployer);
            vm.expectRevert();
            newStakerNodeCoordinator.initialize(testInit);
        }
    }

    function _setupELContracts() private {
        uint256 chainId = block.chainid;
        NetworkAddresses.Addresses memory addresses = NetworkAddresses
            .getAddresses(chainId);

        strategyManager = IStrategyManager(addresses.strategyManager);
        delegationManager = IDelegationManager(addresses.delegationManager);
    }

    function _deployMockContracts() private {
        testToken = new MockERC20("Test Token", "TEST");
        testToken2 = new MockERC20("Test Token 2", "TEST2");
        mockStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(testToken))
        );
        mockStrategy2 = new MockStrategy(
            strategyManager,
            IERC20(address(testToken2))
        );
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
            address(
                new TransparentUpgradeableProxy(
                    address(_tokenRegistryOracleImplementation),
                    proxyAdminAddress,
                    ""
                )
            )
        );
        liquidTokenManager = LiquidTokenManager(
            address(
                new TransparentUpgradeableProxy(
                    address(_liquidTokenManagerImplementation),
                    proxyAdminAddress,
                    ""
                )
            )
        );
        liquidToken = LiquidToken(
            address(
                new TransparentUpgradeableProxy(
                    address(_liquidTokenImplementation),
                    proxyAdminAddress,
                    ""
                )
            )
        );
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(_stakerNodeCoordinatorImplementation),
                    proxyAdminAddress,
                    ""
                )
            )
        );
    }

    function _initializeProxies() private {
        _initializeTokenRegistryOracle();
        _initializeLiquidTokenManager();
        _initializeStakerNodeCoordinator();
        _initializeLiquidToken();

        // Grant admin role to the admin address for all contracts
        _grantRolesToAdmin();
    }

    function _initializeTokenRegistryOracle() private {
        ITokenRegistryOracle.Init memory init = ITokenRegistryOracle.Init({
            initialOwner: deployer, // Initialize with deployer as owner
            priceUpdater: user2,
            liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
        });
        vm.prank(deployer);
        tokenRegistryOracle.initialize(init);
    }

    function _initializeLiquidTokenManager() private {
        ILiquidTokenManager.Init memory init = ILiquidTokenManager.Init({
            assets: new IERC20[](2),
            tokenInfo: new ILiquidTokenManager.TokenInfo[](2),
            strategies: new IStrategy[](2),
            liquidToken: liquidToken,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            stakerNodeCoordinator: stakerNodeCoordinator,
            initialOwner: deployer, // Initialize with deployer as owner
            strategyController: deployer, // Initialize with deployer
            priceUpdater: address(tokenRegistryOracle)
        });
        init.assets[0] = IERC20(address(testToken));
        init.assets[1] = IERC20(address(testToken2));
        init.tokenInfo[0] = ILiquidTokenManager.TokenInfo({
            decimals: 18,
            pricePerUnit: 1e18,
            volatilityThreshold: 0.1 * 1e18
        });
        init.tokenInfo[1] = ILiquidTokenManager.TokenInfo({
            decimals: 18,
            pricePerUnit: 1e18,
            volatilityThreshold: 0
        });
        init.strategies[0] = IStrategy(address(mockStrategy));
        init.strategies[1] = IStrategy(address(mockStrategy2));

        vm.prank(deployer);
        liquidTokenManager.initialize(init);
    }

    function _initializeLiquidToken() private {
        ILiquidToken.Init memory init = ILiquidToken.Init({
            name: "Liquid Staking Token",
            symbol: "LST",
            initialOwner: deployer, // Initialize with deployer as owner
            pauser: pauser,
            liquidTokenManager: ILiquidTokenManager(
                address(liquidTokenManager)
            ),
            tokenRegistryOracle: ITokenRegistryOracle(
                address(tokenRegistryOracle)
            ) // Added this line
        });

        vm.prank(deployer);
        liquidToken.initialize(init);
    }

    function _initializeStakerNodeCoordinator() private {
        IStakerNodeCoordinator.Init memory init = IStakerNodeCoordinator.Init({
            liquidTokenManager: liquidTokenManager,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            maxNodes: 10,
            initialOwner: deployer, // Initialize with deployer as owner
            pauser: pauser,
            stakerNodeCreator: deployer, // Initialize with deployer
            stakerNodesDelegator: deployer, // Initialize with deployer
            stakerNodeImplementation: address(stakerNodeImplementation)
        });

        vm.prank(deployer);
        stakerNodeCoordinator.initialize(init);
    }

    // Now grant admin roles to the admin address
    function _grantRolesToAdmin() private {
        // Grant roles from deployer (who has them) to admin
        vm.startPrank(deployer);

        // Transfer ownership of TokenRegistryOracle
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.DEFAULT_ADMIN_ROLE(),
            admin
        );

        // Transfer ownership of LiquidTokenManager
        liquidTokenManager.grantRole(
            liquidTokenManager.DEFAULT_ADMIN_ROLE(),
            admin
        );
        liquidTokenManager.grantRole(
            liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
            admin
        );

        // Transfer ownership of LiquidToken
        liquidToken.grantRole(liquidToken.DEFAULT_ADMIN_ROLE(), admin);

        // Transfer ownership of StakerNodeCoordinator
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.DEFAULT_ADMIN_ROLE(),
            admin
        );
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(),
            admin
        );
        stakerNodeCoordinator.grantRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
            admin
        );

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
}