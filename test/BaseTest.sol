// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {LiquidToken} from "../src/core/LiquidToken.sol";
import {TokenRegistry} from "../src/utils/TokenRegistry.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {StakerNode} from "../src/core/StakerNode.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {ITokenRegistry} from "../src/interfaces/ITokenRegistry.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BaseTest is Test {
    // Contracts
    LiquidToken public liquidToken;
    TokenRegistry public tokenRegistry;
    LiquidTokenManager public liquidTokenManager;
    StakerNode public stakerNode;

    // Mock contracts
    MockERC20 public testToken;
    MockERC20 public testToken2;
    MockStrategy public mockStrategy;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    // Addresses
    address public admin = address(this);
    address public pauser = address(2);
    address public user1 = address(3);
    address public user2 = address(4);

    // Private variables (with leading underscore)
    LiquidToken private _liquidTokenImplementation;
    TokenRegistry private _tokenRegistryImplementation;
    LiquidTokenManager private _liquidTokenManagerImplementation;
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
        strategyManager = IStrategyManager(
            0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
        );
        delegationManager = IDelegationManager(
            0xA44151489861Fe9e3055d95adC98FbD462B948e7
        );
    }

    function _deployMockContracts() private {
        testToken = new MockERC20("Test Token", "TEST");
        testToken2 = new MockERC20("Test Token 2", "TEST2");
        mockStrategy = new MockStrategy(strategyManager);
    }

    function _deployMainContracts() private {
        _tokenRegistryImplementation = new TokenRegistry();
        _liquidTokenManagerImplementation = new LiquidTokenManager();
        _stakerNodeImplementation = new StakerNode();
        _liquidTokenImplementation = new LiquidToken();
    }

    function _deployProxies() private {
        tokenRegistry = TokenRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(_tokenRegistryImplementation),
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
        stakerNode = StakerNode(
            address(
                new TransparentUpgradeableProxy(
                    address(_stakerNodeImplementation),
                    address(admin),
                    ""
                )
            )
        );
    }

    function _initializeProxies() private {
        _initializeTokenRegistry();
        _initializeLiquidTokenManager();
        _initializeLiquidToken();
        _initializeStakerNode();
    }

    function _initializeTokenRegistry() private {
        tokenRegistry.initialize(admin, admin);
    }

    function _initializeLiquidTokenManager() private {
        ILiquidTokenManager.Init memory init = ILiquidTokenManager.Init({
            assets: new IERC20[](2),
            strategies: new IStrategy[](2),
            liquidToken: ILiquidToken(address(liquidToken)),
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            admin: admin,
            strategyController: admin
        });
        init.assets[0] = IERC20(address(testToken));
        init.assets[1] = IERC20(address(testToken2));
        init.strategies[0] = IStrategy(address(mockStrategy));
        init.strategies[1] = IStrategy(address(mockStrategy));
        liquidTokenManager.initialize(init);
    }

    function _initializeLiquidToken() private {
        ILiquidToken.Init memory init = ILiquidToken.Init({
            name: "Liquid Staking Token",
            symbol: "LST",
            initialOwner: admin,
            pauser: pauser,
            unpauser: pauser,
            tokenRegistry: ITokenRegistry(address(tokenRegistry)),
            liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
        });
        liquidToken.initialize(init);
    }

    function _initializeStakerNode() private {
        IStakerNode.Init memory init = IStakerNode.Init({
            coordinator: IStakerNodeCoordinator(address(liquidTokenManager)),
            id: 1
        });
        stakerNode.initialize(init);
    }

    function _setupTestTokens() private {
        tokenRegistry.addToken(IERC20(address(testToken)), 18, 1e18);
        tokenRegistry.addToken(IERC20(address(testToken2)), 18, 1e18);

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
