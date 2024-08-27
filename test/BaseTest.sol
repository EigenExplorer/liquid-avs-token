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
import {Orchestrator} from "../src/core/Orchestrator.sol";
import {StakerNode} from "../src/core/StakerNode.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {ITokenRegistry} from "../src/interfaces/ITokenRegistry.sol";
import {IOrchestrator} from "../src/interfaces/IOrchestrator.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BaseTest is Test {
    // Contracts
    LiquidToken public liquidTokenImplementation;
    LiquidToken public liquidToken;
    TokenRegistry public tokenRegistryImplementation;
    TokenRegistry public tokenRegistry;
    Orchestrator public orchestratorImplementation;
    Orchestrator public orchestrator;
    StakerNode public stakerNodeImplementation;
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

    function setUp() public virtual {
        // Setup EL contracts
        strategyManager = IStrategyManager(
            0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
        );
        delegationManager = IDelegationManager(
            0xA44151489861Fe9e3055d95adC98FbD462B948e7
        );

        // Deploy mock contracts
        testToken = new MockERC20("Test Token", "TEST");
        testToken2 = new MockERC20("Test Token 2", "TEST2");
        mockStrategy = new MockStrategy(strategyManager);

        // Deploy main contracts
        tokenRegistryImplementation = new TokenRegistry();
        orchestratorImplementation = new Orchestrator();
        stakerNodeImplementation = new StakerNode();
        liquidTokenImplementation = new LiquidToken();

        // Deploy and initialize TokenRegistry proxy
        bytes memory tokenRegistryData = abi.encodeWithSelector(
            TokenRegistry.initialize.selector,
            admin,
            admin
        );
        tokenRegistry = TokenRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(tokenRegistryImplementation),
                    address(admin),
                    tokenRegistryData
                )
            )
        );

        // Deploy and initialize Orchestrator proxy
        bytes memory orchestratorData = abi.encodeWithSelector(
            Orchestrator.initialize.selector,
            strategyManager,
            delegationManager,
            admin,
            admin
        );
        orchestrator = Orchestrator(
            address(
                new TransparentUpgradeableProxy(
                    address(orchestratorImplementation),
                    address(admin),
                    orchestratorData
                )
            )
        );

        // Deploy and initialize LiquidToken proxy
        ILiquidToken.Init memory init = ILiquidToken.Init({
            name: "Liquid Staking Token",
            symbol: "LST",
            initialOwner: admin,
            pauser: pauser,
            unpauser: pauser,
            tokenRegistry: ITokenRegistry(address(tokenRegistry)),
            orchestrator: IOrchestrator(address(orchestrator))
        });
        bytes memory liquidTokenData = abi.encodeWithSelector(
            LiquidToken.initialize.selector,
            init
        );
        liquidToken = LiquidToken(
            address(
                new TransparentUpgradeableProxy(
                    address(liquidTokenImplementation),
                    address(admin),
                    liquidTokenData
                )
            )
        );

        // Deploy and initialize StakerNode proxy
        IStakerNode.Init memory nodeInit = IStakerNode.Init({
            coordinator: IStakerNodeCoordinator(address(orchestrator)),
            id: 1
        });
        bytes memory stakerNodeData = abi.encodeWithSelector(
            StakerNode.initialize.selector,
            nodeInit
        );
        stakerNode = StakerNode(
            address(
                new TransparentUpgradeableProxy(
                    address(stakerNodeImplementation),
                    address(admin),
                    stakerNodeData
                )
            )
        );

        // Setup test token
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
