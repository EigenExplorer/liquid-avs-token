// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

import {LiquidToken} from "../../../src/core/LiquidToken.sol";
import {ILiquidToken} from "../../../src/interfaces/ILiquidToken.sol";
import {TokenRegistryOracle} from "../../../src/utils/TokenRegistryOracle.sol";
import {ITokenRegistryOracle} from "../../../src/interfaces/ITokenRegistryOracle.sol";
import {LiquidTokenManager} from "../../../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../../../src/interfaces/ILiquidTokenManager.sol";
import {StakerNode} from "../../../src/core/StakerNode.sol";
import {StakerNodeCoordinator} from "../../../src/core/StakerNodeCoordinator.sol";
import {IStakerNodeCoordinator} from "../../../src/interfaces/IStakerNodeCoordinator.sol";
import {EmptyContract} from "../../../test/mocks/EmptyContract.sol";

contract DeployMainnet is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    /// @notice Struct for token deployment config
    struct TokenConfig {
        string name;
        string symbol;
        address addr;
        address strategy;
        uint8 decimals;
        uint256 pricePerUnit;
        uint256 volatilityThreshold;
    }

    // Paths to config files
    string constant NETWORK_CONFIG_PATH = "script/configs/mainnet.json";
    string constant DEPLOY_CONFIG_PATH = "script/configs/local/deploy_mainnet.anvil.config.json";
    
    // Path to output file
    string constant OUTPUT_PATH = "script/outputs/local/mainnet_deployment_data.json";

    // Network-level config
    address public strategyManager;
    address public delegationManager;
    TokenConfig[] public tokens;

    // Deployment-level config
    uint256 public STAKER_NODE_COORDINATOR_MAX_NODES;
    string public LIQUID_TOKEN_NAME;
    string public LIQUID_TOKEN_SYMBOL;

    address public admin;
    address public pauser;
    address public priceUpdater;

    // Contract instances
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;
    
    // Implementation contracts
    LiquidToken liquidTokenImpl;
    TokenRegistryOracle tokenRegistryOracleImpl;
    LiquidTokenManager liquidTokenManagerImpl;
    StakerNodeCoordinator stakerNodeCoordinatorImpl;
    StakerNode stakerNodeImpl;
    
    // Proxy contracts
    LiquidToken liquidToken;
    TokenRegistryOracle tokenRegistryOracle;
    LiquidTokenManager liquidTokenManager;
    StakerNodeCoordinator stakerNodeCoordinator;
    
    // Events
    event ContractDeployed(string name, address addr);
    event ProxyInitialized(string name, address proxy, address implementation);
    event VerificationComplete(string name, address addr);

    function run() external {
        // Load config files
        loadConfig();
        
        // Core deployment
        vm.startBroadcast();

        deployInfrastructure();
        deployImplementations();
        deployProxies();
        initializeProxies();
        configureSystem();
        transferOwnership();

        vm.stopBroadcast();

        // Post-deployment verification
        verifyDeployment();
        
        // Write deployment results
        writeDeploymentOutput();
    }

    function loadConfig() internal {
        // Load network-specific config
        string memory networkConfigData = vm.readFile(NETWORK_CONFIG_PATH);
        require(stdJson.readUint(networkConfigData, ".network.chainId") == block.chainid, "Wrong network");

        strategyManager = stdJson.readAddress(networkConfigData, ".network.eigenLayer.strategyManager");
        delegationManager = stdJson.readAddress(networkConfigData, ".network.eigenLayer.delegationManager");

        bytes memory tokenConfigsRaw = stdJson.parseRaw(networkConfigData, ".tokens");
        tokens = abi.decode(tokenConfigsRaw, (TokenConfig[]));

        // Load deployment-specific config
        string memory deployConfigData = vm.readFile(DEPLOY_CONFIG_PATH);
        admin = stdJson.readAddress(deployConfigData, ".roles.admin");
        pauser = stdJson.readAddress(deployConfigData, ".roles.pauser");
        priceUpdater = stdJson.readAddress(deployConfigData, ".roles.priceUpdater");

        STAKER_NODE_COORDINATOR_MAX_NODES = stdJson.readUint(deployConfigData, ".stakerNodeCoordinator.init.maxNodes");
        LIQUID_TOKEN_NAME = stdJson.readString(deployConfigData, ".liquidToken.init.name");
        LIQUID_TOKEN_SYMBOL = stdJson.readString(deployConfigData, ".liquidToken.init.symbol");
    }

    function deployInfrastructure() internal {
        proxyAdmin = new ProxyAdmin(admin);
        emit ContractDeployed("ProxyAdmin", address(proxyAdmin));

        emptyContract = new EmptyContract();
        emit ContractDeployed("EmptyContract", address(emptyContract));
    }

    function deployImplementations() internal {
        tokenRegistryOracleImpl = new TokenRegistryOracle();
        liquidTokenImpl = new LiquidToken();
        liquidTokenManagerImpl = new LiquidTokenManager();
        stakerNodeCoordinatorImpl = new StakerNodeCoordinator();
        stakerNodeImpl = new StakerNode();

        emit ContractDeployed("TokenRegistryOracle Implementation", address(tokenRegistryOracleImpl));
        emit ContractDeployed("LiquidToken Implementation", address(liquidTokenImpl));
        emit ContractDeployed("LiquidTokenManager Implementation", address(liquidTokenManagerImpl));
        emit ContractDeployed("StakerNodeCoordinator Implementation", address(stakerNodeCoordinatorImpl));
        emit ContractDeployed("StakerNode Implementation", address(stakerNodeImpl));
    }

    function deployProxies() internal {
        // Initially deploy all proxies with empty implementation
        tokenRegistryOracle = TokenRegistryOracle(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        liquidTokenManager = LiquidTokenManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        liquidToken = LiquidToken(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );

        emit ContractDeployed("TokenRegistryOracle Proxy", address(tokenRegistryOracle));
        emit ContractDeployed("LiquidTokenManager Proxy", address(liquidTokenManager));
        emit ContractDeployed("StakerNodeCoordinator Proxy", address(stakerNodeCoordinator));
        emit ContractDeployed("LiquidToken Proxy", address(liquidToken));
    }

    function initializeProxies() internal {
        _initializeTokenRegistryOracle();
        _initializeLiquidTokenManager();
        _initializeStakerNodeCoordinator();
        _initializeLiquidToken();
    }

    function _initializeTokenRegistryOracle() internal {
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(tokenRegistryOracle))),
            address(tokenRegistryOracleImpl),
            abi.encodeWithSelector(
                TokenRegistryOracle.initialize.selector,
                ITokenRegistryOracle.Init({
                    initialOwner: admin,
                    priceUpdater: priceUpdater,
                    liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
                })
            )
        );
        emit ProxyInitialized("TokenRegistryOracle", address(tokenRegistryOracle), address(tokenRegistryOracleImpl));
    }

    function _initializeLiquidTokenManager() internal {
        // Populate tokens from config
        IERC20[] memory assets = new IERC20[](tokens.length);
        IStrategy[] memory strategies = new IStrategy[](tokens.length);
        ILiquidTokenManager.TokenInfo[] memory tokenInfo = new ILiquidTokenManager.TokenInfo[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            assets[i] = IERC20(tokens[i].addr);
            strategies[i] = IStrategy(tokens[i].strategy);
            tokenInfo[i] = ILiquidTokenManager.TokenInfo({
                decimals: tokens[i].decimals,
                pricePerUnit: tokens[i].pricePerUnit,
                volatilityThreshold: tokens[i].volatilityThreshold
            });
        }

        // Initialize contract
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(liquidTokenManager))),
            address(liquidTokenManagerImpl),
            abi.encodeWithSelector(
                LiquidTokenManager.initialize.selector,
                ILiquidTokenManager.Init({
                    assets: assets,
                    tokenInfo: tokenInfo,
                    strategies: strategies,
                    liquidToken: liquidToken,
                    strategyManager: IStrategyManager(strategyManager),
                    delegationManager: IDelegationManager(delegationManager),
                    stakerNodeCoordinator: stakerNodeCoordinator,
                    initialOwner: admin,
                    strategyController: admin,
                    priceUpdater: address(tokenRegistryOracle)
                })
            )
        );
        emit ProxyInitialized("LiquidTokenManager", address(liquidTokenManager), address(liquidTokenManagerImpl));
    }

    function _initializeStakerNodeCoordinator() internal {
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(stakerNodeCoordinator))),
            address(stakerNodeCoordinatorImpl),
            abi.encodeWithSelector(
                StakerNodeCoordinator.initialize.selector,
                IStakerNodeCoordinator.Init({
                    liquidTokenManager: liquidTokenManager,
                    strategyManager: IStrategyManager(strategyManager),
                    delegationManager: IDelegationManager(delegationManager),
                    maxNodes: STAKER_NODE_COORDINATOR_MAX_NODES,
                    initialOwner: admin,
                    pauser: pauser,
                    stakerNodeCreator: admin,
                    stakerNodesDelegator: admin
                })
            )
        );
        emit ProxyInitialized("StakerNodeCoordinator", address(stakerNodeCoordinator), address(stakerNodeCoordinatorImpl));
    }

    function _initializeLiquidToken() internal {
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(liquidToken))),
            address(liquidTokenImpl),
            abi.encodeWithSelector(
                LiquidToken.initialize.selector,
                ILiquidToken.Init({
                    name: LIQUID_TOKEN_NAME,
                    symbol: LIQUID_TOKEN_SYMBOL,
                    initialOwner: admin,
                    pauser: pauser,
                    liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
                })
            )
        );
        emit ProxyInitialized("LiquidToken", address(liquidToken), address(liquidTokenImpl));
    }

    function configureSystem() internal {
        // Register StakerNode implementation
        stakerNodeCoordinator.registerStakerNodeImplementation(address(stakerNodeImpl));
    }

    function transferOwnership() internal {
        proxyAdmin.transferOwnership(admin);
        require(proxyAdmin.owner() == admin, "Proxy admin ownership transfer failed");
    }

    function verifyDeployment() internal view {
        _verifyProxyImplementations();
        _verifyContractConnections();
        _verifyRoles();
    }

    function _verifyProxyImplementations() internal view {
        // TODO: Make sure all proxy impl addresses are equal to actual impl addresses
    }

    function _verifyContractConnections() internal view {
        // Verify that contracts are properly connected to each other
        require(
            address(liquidToken.liquidTokenManager()) == address(liquidTokenManager),
            "LiquidToken: wrong liquidTokenManager"
        );
        require(
            address(liquidTokenManager.strategyManager()) == address(strategyManager),
            "LiquidTokenManager: wrong strategyManager"
        );
        require(
            address(liquidTokenManager.delegationManager()) == address(delegationManager),
            "LiquidTokenManager: wrong delegationManager"
        );
        require(
            address(stakerNodeCoordinator.liquidTokenManager()) == address(liquidTokenManager),
            "StakerNodeCoordinator: wrong liquidTokenManager"
        );
    }

    function _verifyRoles() internal view {
        // TODO: Verify all contracts have correct role settings
    }

    function writeDeploymentOutput() internal {
        string memory deployed_addresses = "addresses";

        // Core proxy contracts
        vm.serializeAddress(deployed_addresses, "proxyAdmin", address(proxyAdmin));
        vm.serializeAddress(deployed_addresses, "liquidToken", address(liquidToken));
        vm.serializeAddress(deployed_addresses, "liquidTokenManager", address(liquidTokenManager));
        vm.serializeAddress(deployed_addresses, "stakerNodeCoordinator", address(stakerNodeCoordinator));
        vm.serializeAddress(deployed_addresses, "tokenRegistryOracle", address(tokenRegistryOracle));
        
        // Implementation contracts
        vm.serializeAddress(deployed_addresses, "liquidTokenImpl", address(liquidTokenImpl));
        vm.serializeAddress(deployed_addresses, "liquidTokenManagerImpl", address(liquidTokenManagerImpl));
        vm.serializeAddress(deployed_addresses, "stakerNodeCoordinatorImpl", address(stakerNodeCoordinatorImpl));
        vm.serializeAddress(deployed_addresses, "tokenRegistryOracleImpl", address(tokenRegistryOracleImpl));
        vm.serializeAddress(deployed_addresses, "stakerNodeImpl", address(stakerNodeImpl));

        // Roles
        string memory roles = "roles";
        vm.serializeAddress(roles, "admin", admin);
        vm.serializeAddress(roles, "pauser", pauser);
        vm.serializeAddress(roles, "priceUpdater", priceUpdater);

        // Token configurations
        string memory tokensObj = "tokens";
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenConfig memory token = tokens[i];
            string memory tokenKey = string.concat("token", vm.toString(i));
            vm.serializeString(tokensObj, string.concat(tokenKey, "_symbol"), token.symbol);
            vm.serializeAddress(tokensObj, string.concat(tokenKey, "_address"), token.addr);
            vm.serializeAddress(tokensObj, string.concat(tokenKey, "_strategy"), token.strategy);
        }

        // Chain info
        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "chainId", block.chainid);
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        vm.serializeUint(chain_info, "timestamp", block.timestamp);

        // Combine all sections
        string memory finalJson = vm.serializeString("parent", "addresses", deployed_addresses);
        finalJson = vm.serializeString("parent", "roles", roles);
        finalJson = vm.serializeString("parent", "tokens", tokensObj);
        finalJson = vm.serializeString("parent", "chainInfo", chain_info);

        // Write to file
        vm.writeJson(finalJson, OUTPUT_PATH);
    }
}