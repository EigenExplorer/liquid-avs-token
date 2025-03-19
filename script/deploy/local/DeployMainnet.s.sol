// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
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

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this deploy script (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script script/deploy/local/DeployMainnet.s.sol:DeployMainnet --rpc-url http://localhost:8545 --broadcast --private-key $DEPLOYER_PRIVATE_KEY --sig "run(string,string)" -- "mainnet.json" "xeigenda_mainnet.anvil.config.json" -vvvv
contract DeployMainnet is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    // Structs for token deployment config
    struct TokenAddresses {
        address strategy;
        address token;
    }

    struct TokenParams {
        uint256 decimals;
        uint256 pricePerUnit;
        uint256 volatilityThreshold;
    }

    struct TokenConfig {
      TokenAddresses addresses;
      TokenParams params;
    }
    
    // Path to output file
    string constant OUTPUT_PATH = "script/outputs/local/mainnet_deployment_data.json";

    // Network-level config
    address public strategyManager;
    address public delegationManager;

    // Deployment-level config
    address public AVS_ADDRESS;
    uint256 public STAKER_NODE_COORDINATOR_MAX_NODES;
    string public LIQUID_TOKEN_NAME;
    string public LIQUID_TOKEN_SYMBOL;

    address public admin;
    address public pauser;
    address public priceUpdater;
    TokenConfig[] public tokens;

    // Contract instances
    ProxyAdmin public proxyAdmin;
    
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
    
    // Token-specific price updater contracts
    TokenRegistryOracle[] public tokenOracles;
    LiquidTokenManager[] public tokenManagers;
    LiquidToken[] public tokenLiquidTokens;

    // Deployment blocks and timestamps
    uint256 public proxyAdminDeployBlock;
    uint256 public proxyAdminDeployTimestamp;

    uint256 public tokenRegistryOracleImplDeployBlock;
    uint256 public tokenRegistryOracleImplDeployTimestamp;
    uint256 public liquidTokenImplDeployBlock;
    uint256 public liquidTokenImplDeployTimestamp;
    uint256 public liquidTokenManagerImplDeployBlock;
    uint256 public liquidTokenManagerImplDeployTimestamp;
    uint256 public stakerNodeCoordinatorImplDeployBlock;
    uint256 public stakerNodeCoordinatorImplDeployTimestamp;
    uint256 public stakerNodeImplDeployBlock;
    uint256 public stakerNodeImplDeployTimestamp;

    uint256 public tokenRegistryOracleProxyDeployBlock;
    uint256 public tokenRegistryOracleProxyDeployTimestamp;
    uint256 public liquidTokenProxyDeployBlock;
    uint256 public liquidTokenProxyDeployTimestamp;
    uint256 public liquidTokenManagerProxyDeployBlock;
    uint256 public liquidTokenManagerProxyDeployTimestamp;
    uint256 public stakerNodeCoordinatorProxyDeployBlock;
    uint256 public stakerNodeCoordinatorProxyDeployTimestamp;

    // Initialization timestamps and blocks
    uint256 public tokenRegistryOracleInitBlock;
    uint256 public tokenRegistryOracleInitTimestamp;
    uint256 public liquidTokenInitBlock;
    uint256 public liquidTokenInitTimestamp;
    uint256 public liquidTokenManagerInitBlock;
    uint256 public liquidTokenManagerInitTimestamp;
    uint256 public stakerNodeCoordinatorInitBlock;
    uint256 public stakerNodeCoordinatorInitTimestamp;

    function run(
      string memory networkConfigFileName,
      string memory deployConfigFileName
    ) external {
        // Load config files
        loadConfig(networkConfigFileName, deployConfigFileName);

        // Core deployment
        vm.startBroadcast();

        deployInfrastructure();
        deployImplementations();
        deployProxies();
        initializeProxies();
        deployPriceUpdaterEcosystem(); // Add price updater deployment to have it here instead of previously sepeate setup
        transferOwnership();

        vm.stopBroadcast();

        // Post-deployment verification
        verifyDeployment();
        
        // Write deployment results
        writeDeploymentOutput();
    }

    function loadConfig(
      string memory networkConfigFileName,
      string memory deployConfigFileName
    ) internal {
        // Load network-specific config
        string memory networkConfigPath = string(bytes(string.concat("script/configs/", networkConfigFileName)));
        string memory networkConfigData = vm.readFile(networkConfigPath);
        require(stdJson.readUint(networkConfigData, ".network.chainId") == block.chainid, "Wrong network");

        strategyManager = stdJson.readAddress(networkConfigData, ".network.eigenLayer.strategyManager");
        delegationManager = stdJson.readAddress(networkConfigData, ".network.eigenLayer.delegationManager");

        // Load deployment-specific config
        string memory deployConfigPath = string(bytes(string.concat("script/configs/local/", deployConfigFileName)));
        string memory deployConfigData = vm.readFile(deployConfigPath);
        admin = stdJson.readAddress(deployConfigData, ".roles.admin");
        pauser = stdJson.readAddress(deployConfigData, ".roles.pauser");
        priceUpdater = stdJson.readAddress(deployConfigData, ".roles.priceUpdater");
        tokens = abi.decode(stdJson.parseRaw(deployConfigData, ".tokens"), (TokenConfig[]));

        AVS_ADDRESS = stdJson.readAddress(deployConfigData, ".avsAddress");
        STAKER_NODE_COORDINATOR_MAX_NODES = stdJson.readUint(deployConfigData, ".contracts.stakerNodeCoordinator.init.maxNodes");
        LIQUID_TOKEN_NAME = stdJson.readString(deployConfigData, ".contracts.liquidToken.init.name");
        LIQUID_TOKEN_SYMBOL = stdJson.readString(deployConfigData, ".contracts.liquidToken.init.symbol");
    }

    function deployInfrastructure() internal {
        proxyAdminDeployBlock = block.number;
        proxyAdminDeployTimestamp = block.timestamp;
        proxyAdmin = new ProxyAdmin(msg.sender);
    }

    function deployImplementations() internal {
        tokenRegistryOracleImplDeployBlock = block.number;
        tokenRegistryOracleImplDeployTimestamp = block.timestamp;
        tokenRegistryOracleImpl = new TokenRegistryOracle();
        
        liquidTokenImplDeployBlock = block.number;
        liquidTokenImplDeployTimestamp = block.timestamp;
        liquidTokenImpl = new LiquidToken();
        
        liquidTokenManagerImplDeployBlock = block.number;
        liquidTokenManagerImplDeployTimestamp = block.timestamp;
        liquidTokenManagerImpl = new LiquidTokenManager();
        
        stakerNodeCoordinatorImplDeployBlock = block.number;
        stakerNodeCoordinatorImplDeployTimestamp = block.timestamp;
        stakerNodeCoordinatorImpl = new StakerNodeCoordinator();
        
        stakerNodeImplDeployBlock = block.number;
        stakerNodeImplDeployTimestamp = block.timestamp;
        stakerNodeImpl = new StakerNode();
    }

    function deployProxies() internal {
        tokenRegistryOracleProxyDeployBlock = block.number;
        tokenRegistryOracleProxyDeployTimestamp = block.timestamp;
        tokenRegistryOracle = TokenRegistryOracle(
            address(new TransparentUpgradeableProxy(
                address(tokenRegistryOracleImpl),
                address(proxyAdmin),
                ""
            ))
        );

        liquidTokenManagerProxyDeployBlock = block.number;
        liquidTokenManagerProxyDeployTimestamp = block.timestamp;
        liquidTokenManager = LiquidTokenManager(
            address(new TransparentUpgradeableProxy(
                address(liquidTokenManagerImpl),
                address(proxyAdmin),
                ""
            ))
        );

        stakerNodeCoordinatorProxyDeployBlock = block.number;
        stakerNodeCoordinatorProxyDeployTimestamp = block.timestamp;
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(new TransparentUpgradeableProxy(
                address(stakerNodeCoordinatorImpl),
                address(proxyAdmin),
                ""
            ))
        );

        liquidTokenProxyDeployBlock = block.number;
        liquidTokenProxyDeployTimestamp = block.timestamp;
        liquidToken = LiquidToken(
            address(new TransparentUpgradeableProxy(
                address(liquidTokenImpl),
                address(proxyAdmin),
                ""
            ))
        );
    }

    function initializeProxies() internal {
        _initializeTokenRegistryOracle();
        _initializeLiquidTokenManager();
        _initializeStakerNodeCoordinator();
        _initializeLiquidToken();
    }

    function _initializeTokenRegistryOracle() internal {
        tokenRegistryOracleInitBlock = block.number;
        tokenRegistryOracleInitTimestamp = block.timestamp;
        tokenRegistryOracle.initialize(
            ITokenRegistryOracle.Init({
                initialOwner: admin,
                priceUpdater: priceUpdater,
                liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
            })
        );
    }

    function _initializeLiquidTokenManager() internal {
        liquidTokenManagerInitBlock = block.number;
        liquidTokenManagerInitTimestamp = block.timestamp;
        IERC20[] memory assets = new IERC20[](tokens.length);
        IStrategy[] memory strategies = new IStrategy[](tokens.length);
        ILiquidTokenManager.TokenInfo[] memory tokenInfo = new ILiquidTokenManager.TokenInfo[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            assets[i] = IERC20(tokens[i].addresses.token);
            strategies[i] = IStrategy(tokens[i].addresses.strategy);
            tokenInfo[i] = ILiquidTokenManager.TokenInfo({
                decimals: uint8(tokens[i].params.decimals),
                pricePerUnit: uint256(tokens[i].params.pricePerUnit),
                volatilityThreshold: uint256(tokens[i].params.volatilityThreshold)
            });
        }

        liquidTokenManager.initialize(
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
        );
    }

    function _initializeStakerNodeCoordinator() internal {
        stakerNodeCoordinatorInitBlock = block.number;
        stakerNodeCoordinatorInitTimestamp = block.timestamp;
        stakerNodeCoordinator.initialize(
            IStakerNodeCoordinator.Init({
                liquidTokenManager: liquidTokenManager,
                strategyManager: IStrategyManager(strategyManager),
                delegationManager: IDelegationManager(delegationManager),
                maxNodes: STAKER_NODE_COORDINATOR_MAX_NODES,
                initialOwner: admin,
                pauser: pauser,
                stakerNodeCreator: admin,
                stakerNodesDelegator: address(liquidTokenManager),
                stakerNodeImplementation: address(stakerNodeImpl)
            })
        );
    }

    function _initializeLiquidToken() internal {
        liquidTokenInitBlock = block.number;
        liquidTokenInitTimestamp = block.timestamp;
        liquidToken.initialize(
            ILiquidToken.Init({
                name: LIQUID_TOKEN_NAME,
                symbol: LIQUID_TOKEN_SYMBOL,
                initialOwner: admin,
                pauser: pauser,
                liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
            })
        );
    }

    // Deploy price updater ecosystem contracts for each token

function deployPriceUpdaterEcosystem() internal {
    console.log("Deploying price updater ecosystem for %s tokens", tokens.length);

    // Initialize arrays to store token-specific contracts
    tokenOracles = new TokenRegistryOracle[](tokens.length);
    tokenLiquidTokens = new LiquidToken[](tokens.length);
    tokenManagers = new LiquidTokenManager[](tokens.length);
    
    for (uint256 i = 0; i < tokens.length; i++) {
        address tokenAddress = tokens[i].addresses.token;
        address strategyAddress = tokens[i].addresses.strategy;
        
        // Get symbol safely
        string memory tokenSymbol = getTokenSymbol(tokenAddress);
        console.log("Deploying price updater contracts for token: %s", tokenSymbol);
        
        // Deploy implementations
        TokenRegistryOracle oracleImpl = new TokenRegistryOracle();
        LiquidTokenManager managerImpl = new LiquidTokenManager();
        LiquidToken tokenImpl = new LiquidToken();
        
        // Deploy proxies
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(proxyAdmin),
            ""
        );
        
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
            address(managerImpl),
            address(proxyAdmin),
            ""
        );
        
        TransparentUpgradeableProxy tokenProxy = new TransparentUpgradeableProxy(
            address(tokenImpl),
            address(proxyAdmin),
            ""
        );
        
        // Store proxy addresses for later use
        tokenOracles[i] = TokenRegistryOracle(address(oracleProxy));
        tokenManagers[i] = LiquidTokenManager(address(managerProxy));
        tokenLiquidTokens[i] = LiquidToken(address(tokenProxy));
        
        // Prepare token info
        IERC20[] memory singleAsset = new IERC20[](1);
        singleAsset[0] = IERC20(tokenAddress);
        
        IStrategy[] memory singleStrategy = new IStrategy[](1);
        singleStrategy[0] = IStrategy(strategyAddress);
        
        ILiquidTokenManager.TokenInfo[] memory singleTokenInfo = new ILiquidTokenManager.TokenInfo[](1);
        singleTokenInfo[0] = ILiquidTokenManager.TokenInfo({
            decimals: uint8(tokens[i].params.decimals),
            pricePerUnit: tokens[i].params.pricePerUnit,
            volatilityThreshold: tokens[i].params.volatilityThreshold
        });
        
        // NOTE: Initialize oracle first with admin as both owner and priceUpdater
        TokenRegistryOracle(address(oracleProxy)).initialize(
            ITokenRegistryOracle.Init({
                initialOwner: admin,
                priceUpdater: priceUpdater, // Set priceUpdater as priceUpdater so they can update rates
                liquidTokenManager: ILiquidTokenManager(address(managerProxy))
            })
        );
        
        // Initialize manager with oracle reference
        LiquidTokenManager(address(managerProxy)).initialize(
            ILiquidTokenManager.Init({
                assets: singleAsset,
                tokenInfo: singleTokenInfo,
                strategies: singleStrategy,
                liquidToken: ILiquidToken(address(tokenProxy)),
                strategyManager: IStrategyManager(strategyManager),
                delegationManager: IDelegationManager(delegationManager),
                stakerNodeCoordinator: stakerNodeCoordinator,
                initialOwner: admin,
                strategyController: admin,
                priceUpdater: address(oracleProxy)
            })
        );
        
        // Initialize token
        string memory tokenName = string(abi.encodePacked("EigenDA Liquid ", tokenSymbol));
        string memory tokenPrefix = string(abi.encodePacked("x", tokenSymbol));
        
        LiquidToken(address(tokenProxy)).initialize(
            ILiquidToken.Init({
                name: tokenName,
                symbol: tokenPrefix,
                initialOwner: admin,
                pauser: pauser,
                liquidTokenManager: ILiquidTokenManager(address(managerProxy))
            })
        );
        
        // DON'T directly set prices here - we'll do this in run.sh after deployment
        
        console.log("Deployed price updater contracts for %s:", tokenSymbol);
        console.log("  - Oracle: %s", address(tokenOracles[i]));
        console.log("  - LiquidToken: %s", address(tokenLiquidTokens[i]));
        console.log("  - LiquidTokenManager: %s", address(tokenManagers[i]));
    }
}
    // Helper function to convert token address to symbol
function getTokenSymbol(address tokenAddress) internal pure returns (string memory) {
    // stETH address on mainnet
    if (tokenAddress == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) {
        return "stETH";
    } 
    // rETH address on mainnet
    else if (tokenAddress == 0xae78736Cd615f374D3085123A210448E74Fc6393) {
        return "rETH";
    } 
    // For other tokens or test environments
    else {
        return string(abi.encodePacked("Token", uint8(uint256(keccak256(abi.encodePacked(tokenAddress))) % 100)));
    }
}
    function transferOwnership() internal {
        proxyAdmin.transferOwnership(admin);
        require(proxyAdmin.owner() == admin, "Proxy admin ownership transfer failed");
    }

    function verifyDeployment() internal view {
        _verifyProxyImplementations();
        _verifyContractConnections();
        _verifyRoles();
        _verifyPriceUpdaterEcosystem();
    }

    function _verifyProxyImplementations() internal view {
        // TODO: Make sure all proxy impl addresses are equal to actual impl addresses
    }

    function _verifyContractConnections() internal view {
        // LiquidToken
        require(
            address(liquidToken.liquidTokenManager()) == address(liquidTokenManager),
            "LiquidToken: wrong liquidTokenManager"
        );

        // LiquidTokenManager
        require(
            address(liquidTokenManager.liquidToken()) == address(liquidToken),
            "LiquidTokenManager: wrong liquidToken"
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
            address(liquidTokenManager.stakerNodeCoordinator()) == address(stakerNodeCoordinator),
            "LiquidTokenManager: wrong stakerNodeCoordinator"
        );

        // StakerNodeCoordinator
        require(
            address(stakerNodeCoordinator.liquidTokenManager()) == address(liquidTokenManager),
            "StakerNodeCoordinator: wrong liquidTokenManager"
        );
        require(
            address(stakerNodeCoordinator.strategyManager()) == address(strategyManager),
            "StakerNodeCoordinator: wrong strategyManager"
        );
        require(
            address(stakerNodeCoordinator.delegationManager()) == address(delegationManager),
            "StakerNodeCoordinator: wrong delegationManager"
        );
        require(
            address(stakerNodeCoordinator.upgradeableBeacon().implementation()) == address(stakerNodeImpl),
            "StakerNodeCoordinator: wrong stakerNodeImplementation"
        );

        // TokenRegistryOracle
        require(
            address(tokenRegistryOracle.liquidTokenManager()) == address(liquidTokenManager),
            "TokenRegistryOracle: wrong liquidTokenManager"
        );

        // Assets and strategies
        IERC20[] memory registeredTokens = liquidTokenManager.getSupportedTokens();
        require(
            registeredTokens.length == tokens.length,
            "LiquidTokenManager: wrong number of registered tokens"
        );

        // Verify token and strategy info matches deployment config
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 configToken = IERC20(tokens[i].addresses.token);
            ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(configToken);
            require(
                tokenInfo.decimals == tokens[i].params.decimals,
                "LiquidTokenManager: wrong token decimals"
            );
            require(
                tokenInfo.pricePerUnit == tokens[i].params.pricePerUnit,
                "LiquidTokenManager: wrong token price"
            );
            require(
                tokenInfo.volatilityThreshold == tokens[i].params.volatilityThreshold,
                "LiquidTokenManager: wrong volatility threshold"
            );

            IStrategy registeredStrategy = liquidTokenManager.getTokenStrategy(configToken);
            require(
                address(registeredStrategy) == tokens[i].addresses.strategy,
                "LiquidTokenManager: wrong strategy address"
            );

            // Verify token is in supported tokens list
            bool tokenFound = false;
            for (uint256 j = 0; j < registeredTokens.length; j++) {
                if (address(registeredTokens[j]) == address(configToken)) {
                    tokenFound = true;
                    break;
                }
            }
            require(tokenFound, "LiquidTokenManager: token not in supported list");
        }
    }

    // Verify the price updater ecosystem was deployed correctly
    function _verifyPriceUpdaterEcosystem() internal view {
        require(tokenOracles.length == tokens.length, "Wrong number of token oracles");
        require(tokenLiquidTokens.length == tokens.length, "Wrong number of token liquid tokens");
        require(tokenManagers.length == tokens.length, "Wrong number of token managers");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenAddress = tokens[i].addresses.token;
            
            // Verify token-specific contracts are initialized
            require(address(tokenOracles[i]) != address(0), "Token oracle not deployed");
            require(address(tokenLiquidTokens[i]) != address(0), "Token liquid token not deployed");
            require(address(tokenManagers[i]) != address(0), "Token manager not deployed");
            
            // Verify tokenManager has the correct token registered
            IERC20[] memory supportedTokens = tokenManagers[i].getSupportedTokens();
            require(supportedTokens.length == 1, "Token manager should have exactly one token");
            require(address(supportedTokens[0]) == tokenAddress, "Token manager has wrong token registered");
            
            // Verify connections between token-specific contracts
            require(
                address(tokenManagers[i].liquidToken()) == address(tokenLiquidTokens[i]),
                "Token manager has wrong liquid token"
            );
        }
    }
    
    function _verifyRoles() internal view {
        // TODO: Verify all contracts have correct role settings
    }

    function writeDeploymentOutput() internal {
        string memory parent_object = "parent";
        
        // Top level properties
        vm.serializeAddress(parent_object, "proxyAddress", address(liquidToken));
        vm.serializeAddress(parent_object, "implementationAddress", address(liquidTokenImpl));
        vm.serializeString(parent_object, "name", LIQUID_TOKEN_NAME);
        vm.serializeString(parent_object, "symbol", LIQUID_TOKEN_SYMBOL);
        vm.serializeAddress(parent_object, "avsAddress", AVS_ADDRESS);
        vm.serializeUint(parent_object, "chainId", block.chainid);
        vm.serializeUint(parent_object, "maxNodes", STAKER_NODE_COORDINATOR_MAX_NODES); 
        vm.serializeUint(parent_object, "deploymentBlock", block.number);
        vm.serializeUint(parent_object, "deploymentTimestamp", block.timestamp * 1000); 
        
        // Contract deployments section
        string memory contractDeployments = "contractDeployments";
        
        // Implementation contracts
        string memory implementation = "implementation";
        
        // LiquidTokenManager implementation
        string memory liquidTokenManagerImpl_obj = "liquidTokenManager";
        vm.serializeAddress(liquidTokenManagerImpl_obj, "address", address(liquidTokenManagerImpl));
        vm.serializeUint(liquidTokenManagerImpl_obj, "block", liquidTokenManagerImplDeployBlock);
        string memory liquidTokenManagerImpl_output = vm.serializeUint(liquidTokenManagerImpl_obj, "timestamp", liquidTokenManagerImplDeployTimestamp * 1000);
        
        // StakerNodeCoordinator implementation
        string memory stakerNodeCoordinatorImpl_obj = "stakerNodeCoordinator";
        vm.serializeAddress(stakerNodeCoordinatorImpl_obj, "address", address(stakerNodeCoordinatorImpl));
        vm.serializeUint(stakerNodeCoordinatorImpl_obj, "block", stakerNodeCoordinatorImplDeployBlock);
        string memory stakerNodeCoordinatorImpl_output = vm.serializeUint(stakerNodeCoordinatorImpl_obj, "timestamp", stakerNodeCoordinatorImplDeployTimestamp * 1000);
        
        // StakerNode implementation
        string memory stakerNodeImpl_obj = "stakerNode";
        vm.serializeAddress(stakerNodeImpl_obj, "address", address(stakerNodeImpl));
        vm.serializeUint(stakerNodeImpl_obj, "block", stakerNodeImplDeployBlock);
        string memory stakerNodeImpl_output = vm.serializeUint(stakerNodeImpl_obj, "timestamp", stakerNodeImplDeployTimestamp * 1000);
        
        // TokenRegistryOracle implementation
        string memory tokenRegistryOracleImpl_obj = "tokenRegistryOracle";
        vm.serializeAddress(tokenRegistryOracleImpl_obj, "address", address(tokenRegistryOracleImpl));
        vm.serializeUint(tokenRegistryOracleImpl_obj, "block", tokenRegistryOracleImplDeployBlock);
        string memory tokenRegistryOracleImpl_output = vm.serializeUint(tokenRegistryOracleImpl_obj, "timestamp", tokenRegistryOracleImplDeployTimestamp * 1000);
        
        // Combine all implementation objects
        vm.serializeString(implementation, "liquidTokenManager", liquidTokenManagerImpl_output);
        vm.serializeString(implementation, "stakerNodeCoordinator", stakerNodeCoordinatorImpl_output);
        vm.serializeString(implementation, "stakerNode", stakerNodeImpl_output);
        string memory implementation_output = vm.serializeString(implementation, "tokenRegistryOracle", tokenRegistryOracleImpl_output);
        
        // Proxy contracts
        string memory proxy = "proxy";
        
        // LiquidTokenManager proxy
        string memory liquidTokenManager_obj = "liquidTokenManager";
        vm.serializeAddress(liquidTokenManager_obj, "address", address(liquidTokenManager));
        vm.serializeUint(liquidTokenManager_obj, "block", liquidTokenManagerProxyDeployBlock);
        string memory liquidTokenManager_output = vm.serializeUint(liquidTokenManager_obj, "timestamp", liquidTokenManagerProxyDeployTimestamp * 1000);
        
        // StakerNodeCoordinator proxy
        string memory stakerNodeCoordinator_obj = "stakerNodeCoordinator";
        vm.serializeAddress(stakerNodeCoordinator_obj, "address", address(stakerNodeCoordinator));
        vm.serializeUint(stakerNodeCoordinator_obj, "block", stakerNodeCoordinatorProxyDeployBlock);
        string memory stakerNodeCoordinator_output = vm.serializeUint(stakerNodeCoordinator_obj, "timestamp", stakerNodeCoordinatorProxyDeployTimestamp * 1000);
        
        // TokenRegistryOracle proxy
        string memory tokenRegistryOracle_obj = "tokenRegistryOracle";
        vm.serializeAddress(tokenRegistryOracle_obj, "address", address(tokenRegistryOracle));
        vm.serializeUint(tokenRegistryOracle_obj, "block", tokenRegistryOracleProxyDeployBlock);
        string memory tokenRegistryOracle_output = vm.serializeUint(tokenRegistryOracle_obj, "timestamp", tokenRegistryOracleProxyDeployTimestamp * 1000);
        
        // Combine all proxy objects
        vm.serializeString(proxy, "liquidTokenManager", liquidTokenManager_output);
        vm.serializeString(proxy, "stakerNodeCoordinator", stakerNodeCoordinator_output);
        string memory proxy_output = vm.serializeString(proxy, "tokenRegistryOracle", tokenRegistryOracle_output);
        
        // Combine implementation and proxy under contractDeployments
        vm.serializeString(contractDeployments, "implementation", implementation_output);
        string memory contractDeployments_output = vm.serializeString(contractDeployments, "proxy", proxy_output);
        
        // Roles section
        string memory roles = "roles";
        vm.serializeAddress(roles, "deployer", address(proxyAdmin));
        vm.serializeAddress(roles, "admin", admin);
        vm.serializeAddress(roles, "pauser", pauser);
        string memory roles_output = vm.serializeAddress(roles, "priceUpdater", priceUpdater);
        
        // Tokens section
        string memory tokens_array = "tokens";
        
        // Process each token
        for (uint256 i = 0; i < tokens.length; ++i) {
            // Create an object for each token
            string memory token_obj = string.concat("token", vm.toString(i));
            vm.serializeAddress(token_obj, "address", tokens[i].addresses.token);
            string memory token_output = vm.serializeAddress(token_obj, "strategy", tokens[i].addresses.strategy);
            
            // Add token object to the array using vm.serializeString
            if (i < tokens.length - 1) {
                vm.serializeString(tokens_array, vm.toString(i), token_output);
            }
        }
        
        // Get the complete tokens array (with the last element if there are any tokens)
        string memory tokens_array_output;
        if (tokens.length == 0) {
            tokens_array_output = "[]";
        } else {
            string memory lastTokenObj = string.concat("token", vm.toString(tokens.length - 1));
            vm.serializeAddress(lastTokenObj, "address", tokens[tokens.length - 1].addresses.token);
            string memory lastTokenOutput = vm.serializeAddress(lastTokenObj, "strategy", tokens[tokens.length - 1].addresses.strategy);
            tokens_array_output = vm.serializeString(tokens_array, vm.toString(tokens.length - 1), lastTokenOutput);
        }
        
        // Add price updater section
        string memory priceUpdater_section = "priceUpdater";
        
        if (tokens.length > 0) {
            // Add token-specific price updater info in expected format
            for (uint256 i = 0; i < tokens.length; i++) {
                string memory tokenSymbol = getTokenSymbol(tokens[i].addresses.token);
                string memory tokenSection = tokenSymbol;
                
                vm.serializeAddress(tokenSection, "liquidTokenManager", address(tokenManagers[i]));
                vm.serializeAddress(tokenSection, "liquidToken", address(tokenLiquidTokens[i]));
                string memory tokenOracleOutput = vm.serializeAddress(tokenSection, "oracle", address(tokenOracles[i]));
                
                vm.serializeString(priceUpdater_section, tokenSymbol, tokenOracleOutput);
            }
        }
        
        // Combine all sections into the parent object
        vm.serializeString(parent_object, "contractDeployments", contractDeployments_output);
        vm.serializeString(parent_object, "roles", roles_output);
        string memory finalJson = vm.serializeString(parent_object, "tokens", tokens_array_output);
        finalJson = vm.serializeString(parent_object, "priceUpdater", vm.serializeString(priceUpdater_section, "", ""));
        
        // Write the final JSON to output file
        vm.writeJson(finalJson, OUTPUT_PATH);
    }
}