// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    // Mock contracts
    MockERC20 public testToken;
    MockERC20 public testToken2;
    MockStrategy public mockStrategy;
    MockStrategy public mockStrategy2;

    // Addresses
    address public admin = address(this);
    address public pauser = address(2);
    address public user1 = address(3);
    address public user2 = address(4);

    // Private variables (with leading underscore)
    LiquidToken private _liquidTokenImplementation;
    TokenRegistryOracle private _tokenRegistryOracleImplementation;
    LiquidTokenManager private _liquidTokenManagerImplementation;
    StakerNodeCoordinator private _stakerNodeCoordinatorImplementation;
    StakerNode private _stakerNodeImplementation;

    function setUp() public virtual {
        _setupELContracts();
        _deployMockContracts();
        _deployMainContracts();
        _deployProxies();
        _initializeProxies();
        _setupTestTokens();
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
        _stakerNodeImplementation = new StakerNode();
    }

    function _deployProxies() private {
        tokenRegistryOracle = TokenRegistryOracle(
            address(
                new TransparentUpgradeableProxy(
                    address(_tokenRegistryOracleImplementation),
                    address(admin),
                    ""
                )
            )
        );
        liquidTokenManager = LiquidTokenManager(
            address(
                new TransparentUpgradeableProxy(
                    address(_liquidTokenManagerImplementation),
                    address(admin),
                    ""
                )
            )
        );
        liquidToken = LiquidToken(
            address(
                new TransparentUpgradeableProxy(
                    address(_liquidTokenImplementation),
                    address(admin),
                    ""
                )
            )
        );
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(_stakerNodeCoordinatorImplementation),
                    address(admin),
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
    }

    function _initializeTokenRegistryOracle() private {
        ITokenRegistryOracle.Init memory init = ITokenRegistryOracle.Init({
            initialOwner: admin,
            priceUpdater: user2,
            liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
        });
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
            initialOwner: admin,
            strategyController: admin,
            priceUpdater: address(tokenRegistryOracle)
        });
        init.assets[0] = IERC20(address(testToken));
        init.assets[1] = IERC20(address(testToken2));
        init.tokenInfo[0] = ILiquidTokenManager.TokenInfo({
            decimals: 18,
            pricePerUnit: 1e18
        });
        init.tokenInfo[1] = ILiquidTokenManager.TokenInfo({
            decimals: 18,
            pricePerUnit: 1e18
        });
        init.strategies[0] = IStrategy(address(mockStrategy));
        init.strategies[1] = IStrategy(address(mockStrategy2));
        liquidTokenManager.initialize(init);
    }

    function _initializeLiquidToken() private {
        ILiquidToken.Init memory init = ILiquidToken.Init({
            name: "Liquid Staking Token",
            symbol: "LST",
            initialOwner: admin,
            pauser: pauser,
            liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
        });
        liquidToken.initialize(init);
    }

    function _initializeStakerNodeCoordinator() private {
        IStakerNodeCoordinator.Init memory init = IStakerNodeCoordinator.Init({
            liquidTokenManager: liquidTokenManager,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            maxNodes: 10,
            initialOwner: admin,
            pauser: pauser,
            stakerNodeCreator: admin,
            stakerNodesDelegator: admin
        });
        stakerNodeCoordinator.initialize(init);
        stakerNodeCoordinator.registerStakerNodeImplementation(
            address(_stakerNodeImplementation)
        );
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
}
