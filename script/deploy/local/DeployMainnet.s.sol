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
// forge script script/deploy/local/DeployMainnet.s.sol:DeployMainnet --rpc-url http://localhost:8545 --broadcast --private-key $DEPLOYER_PRIVATE_KEY --sig "run(string memory networkConfigFileName,string memory deployConfigFileName)" -- "mainnet.json" "deploy_mainnet.anvil.config.json" -vvvv
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
        tokens = abi.decode(stdJson.parseRaw(networkConfigData, ".tokens"), (TokenConfig[]));

        // Load deployment-specific config
        string memory deployConfigPath = string(bytes(string.concat("script/configs/local/", deployConfigFileName)));
        string memory deployConfigData = vm.readFile(deployConfigPath);
        admin = stdJson.readAddress(deployConfigData, ".roles.admin");
        pauser = stdJson.readAddress(deployConfigData, ".roles.pauser");
        priceUpdater = stdJson.readAddress(deployConfigData, ".roles.priceUpdater");

        STAKER_NODE_COORDINATOR_MAX_NODES = stdJson.readUint(deployConfigData, ".contracts.stakerNodeCoordinator.init.maxNodes");
        LIQUID_TOKEN_NAME = stdJson.readString(deployConfigData, ".contracts.liquidToken.init.name");
        LIQUID_TOKEN_SYMBOL = stdJson.readString(deployConfigData, ".contracts.liquidToken.init.symbol");
    }

    function deployInfrastructure() internal {
        proxyAdmin = new ProxyAdmin(msg.sender);
        emit ContractDeployed("ProxyAdmin", address(proxyAdmin));
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
        tokenRegistryOracle = TokenRegistryOracle(
            address(new TransparentUpgradeableProxy(
                address(tokenRegistryOracleImpl),
                address(proxyAdmin),
                ""
            ))
        );

        liquidTokenManager = LiquidTokenManager(
            address(new TransparentUpgradeableProxy(
                address(liquidTokenManagerImpl),
                address(proxyAdmin),
                ""
            ))
        );

        stakerNodeCoordinator = StakerNodeCoordinator(
            address(new TransparentUpgradeableProxy(
                address(stakerNodeCoordinatorImpl),
                address(proxyAdmin),
                ""
            ))
        );

        liquidToken = LiquidToken(
            address(new TransparentUpgradeableProxy(
                address(liquidTokenImpl),
                address(proxyAdmin),
                ""
            ))
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
        tokenRegistryOracle.initialize(
            ITokenRegistryOracle.Init({
                initialOwner: admin,
                priceUpdater: priceUpdater,
                liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
            })
        );
        emit ProxyInitialized("TokenRegistryOracle", address(tokenRegistryOracle), address(tokenRegistryOracleImpl));
    }

    function _initializeLiquidTokenManager() internal {
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
        emit ProxyInitialized("LiquidTokenManager", address(liquidTokenManager), address(liquidTokenManagerImpl));
    }

    function _initializeStakerNodeCoordinator() internal {
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
        emit ProxyInitialized("StakerNodeCoordinator", address(stakerNodeCoordinator), address(stakerNodeCoordinatorImpl));
    }

    function _initializeLiquidToken() internal {
        liquidToken.initialize(
            ILiquidToken.Init({
                name: LIQUID_TOKEN_NAME,
                symbol: LIQUID_TOKEN_SYMBOL,
                initialOwner: admin,
                pauser: pauser,
                liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
            })
        );
        emit ProxyInitialized("LiquidToken", address(liquidToken), address(liquidTokenImpl));
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

    function _verifyRoles() internal view {
        // TODO: Verify all contracts have correct role settings
    }

    function writeDeploymentOutput() internal {
    string memory parent_object = "parent";
    string memory deployed_addresses = "addresses";
    
    // Core proxy contracts
    vm.serializeAddress(deployed_addresses, "proxyAdmin", address(proxyAdmin));
    vm.serializeAddress(deployed_addresses, "liquidToken", address(liquidToken));
    vm.serializeAddress(deployed_addresses, "liquidTokenManager", address(liquidTokenManager));
    vm.serializeAddress(deployed_addresses, "stakerNodeCoordinator", address(stakerNodeCoordinator));
    string memory deployed_addresses_output = vm.serializeAddress(
        deployed_addresses, 
        "tokenRegistryOracle", 
        address(tokenRegistryOracle)
    );

    // Implementation contracts
    string memory implementations = "implementations";
    vm.serializeAddress(implementations, "liquidTokenImpl", address(liquidTokenImpl));
    vm.serializeAddress(implementations, "liquidTokenManagerImpl", address(liquidTokenManagerImpl));
    vm.serializeAddress(implementations, "stakerNodeCoordinatorImpl", address(stakerNodeCoordinatorImpl));
    vm.serializeAddress(implementations, "tokenRegistryOracleImpl", address(tokenRegistryOracleImpl));
    string memory implementations_output = vm.serializeAddress(
        implementations, 
        "stakerNodeImpl", 
        address(stakerNodeImpl)
    );

    deployed_addresses_output = vm.serializeString(
        deployed_addresses, 
        "implementations", 
        implementations_output
    );

    // Roles
    string memory roles = "roles";
    vm.serializeAddress(roles, "admin", admin);
    vm.serializeAddress(roles, "pauser", pauser);
    string memory roles_output = vm.serializeAddress(roles, "priceUpdater", priceUpdater);

    // Tokens
    string memory tokensObj = "tokens";
    for (uint256 i = 0; i < tokens.length; ++i) {
        TokenConfig memory token = tokens[i];
        string memory tokenKey = string.concat("token", vm.toString(i));
        vm.serializeAddress(tokensObj, string.concat(tokenKey, "_address"), token.addresses.token);
        if (i == tokens.length - 1) {
            vm.serializeAddress(tokensObj, string.concat(tokenKey, "_strategy"), token.addresses.strategy);
        } else {
            vm.serializeAddress(tokensObj, string.concat(tokenKey, "_strategy"), token.addresses.strategy);
        }
    }
    string memory tokens_output = tokens.length == 0 ? "" : vm.serializeAddress(
        tokensObj,
        string.concat("token", vm.toString(tokens.length - 1), "_strategy"),
        tokens[tokens.length - 1].addresses.strategy
    );

    // Chain info
    string memory chain_info = "chainInfo";
    vm.serializeUint(chain_info, "chainId", block.chainid);
    vm.serializeUint(chain_info, "deploymentBlock", block.number);
    string memory chain_info_output = vm.serializeUint(chain_info, "timestamp", block.timestamp);

    // Combine all sections
    vm.serializeString(parent_object, "addresses", deployed_addresses_output);
    vm.serializeString(parent_object, "roles", roles_output);
    vm.serializeString(parent_object, "tokens", tokens_output);
    string memory finalJson = vm.serializeString(parent_object, "chainInfo", chain_info_output);

    // Write the final JSON to output file
    vm.writeJson(finalJson, OUTPUT_PATH);
}
}