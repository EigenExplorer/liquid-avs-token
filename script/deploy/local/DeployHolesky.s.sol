// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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
// forge script script/deploy/local/DeployHolesky.s.sol:DeployHolesky --rpc-url http://localhost:8545 --broadcast --private-key $DEPLOYER_PRIVATE_KEY --sig "run(string,string)" -- "holesky.json" "xeigenda_holesky.anvil.config.json" -vvvv

event RoleAssigned(string contractName, string role, address recipient);

// Oracle config struct for per-token price source
struct OracleConfig {
    uint8 sourceType;
    address primarySource;
    uint8 needsArg;
    address fallbackSource;
    bytes4 fallbackSelector;
}

// Add name (optional) and oracle config to TokenConfig
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
    string name; // For logging/debugging
    TokenAddresses addresses;
    TokenParams params;
    OracleConfig oracle;
}

contract Deploy is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    // Path to output file
    string constant OUTPUT_PATH = "script/outputs/holesky/deployment_data.json";

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

    function run(string memory deployConfigFileName) external {
        // Load config files
        loadConfig(deployConfigFileName);

        // Core deployment
        vm.startBroadcast();

        deployInfrastructure();
        deployImplementations();
        deployProxies();
        initializeProxies();

        configureTokens();
        //configureRoles();

        transferOwnership();

        vm.stopBroadcast();

        // Post-deployment verification
        verifyDeployment();

        // Write deployment results
        writeDeploymentOutput();
    }

    // -------------------- BEGIN CHANGED SECTION: loadConfig parses new oracle fields --------------------
    function loadConfig(string memory deployConfigFileName) internal {
        // Load network-specific config
        string memory networkConfigPath = "script/configs/holesky.json";
        string memory networkConfigData = vm.readFile(networkConfigPath);
        require(
            stdJson.readUint(networkConfigData, ".network.chainId") ==
                block.chainid,
            "Wrong network"
        );

        strategyManager = stdJson.readAddress(
            networkConfigData,
            ".network.eigenLayer.strategyManager"
        );
        delegationManager = stdJson.readAddress(
            networkConfigData,
            ".network.eigenLayer.delegationManager"
        );

        // Load deployment-specific config
        string memory deployConfigPath = string(
            bytes(
                string.concat("script/configs/holesky/", deployConfigFileName)
            )
        );
        string memory deployConfigData = vm.readFile(deployConfigPath);

        admin = stdJson.readAddress(deployConfigData, ".roles.admin");
        pauser = stdJson.readAddress(deployConfigData, ".roles.pauser");
        priceUpdater = stdJson.readAddress(
            deployConfigData,
            ".roles.priceUpdater"
        );
        AVS_ADDRESS = stdJson.readAddress(deployConfigData, ".avsAddress");
        STAKER_NODE_COORDINATOR_MAX_NODES = stdJson.readUint(
            deployConfigData,
            ".contracts.stakerNodeCoordinator.init.maxNodes"
        );
        LIQUID_TOKEN_NAME = stdJson.readString(
            deployConfigData,
            ".contracts.liquidToken.init.name"
        );
        LIQUID_TOKEN_SYMBOL = stdJson.readString(
            deployConfigData,
            ".contracts.liquidToken.init.symbol"
        );

        // Detect the number of tokens in the JSON array
        uint256 numTokens = stdJson.readUint(
            deployConfigData,
            ".tokens.length"
        );
        tokens = new TokenConfig[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            string memory prefix = string.concat(
                ".tokens[",
                vm.toString(i),
                "]"
            );
            // Addresses
            TokenAddresses memory addrs;
            addrs.token = stdJson.readAddress(
                deployConfigData,
                string.concat(prefix, ".addresses.token")
            );
            addrs.strategy = stdJson.readAddress(
                deployConfigData,
                string.concat(prefix, ".addresses.strategy")
            );
            // Params
            TokenParams memory params;
            params.decimals = stdJson.readUint(
                deployConfigData,
                string.concat(prefix, ".params.decimals")
            );
            params.pricePerUnit = stdJson.readUint(
                deployConfigData,
                string.concat(prefix, ".params.pricePerUnit")
            );
            params.volatilityThreshold = stdJson.readUint(
                deployConfigData,
                string.concat(prefix, ".params.volatilityThreshold")
            );
            // Oracle
            OracleConfig memory oracle;
            string memory op = string.concat(prefix, ".oracle");
            oracle.sourceType = uint8(
                stdJson.readUint(
                    deployConfigData,
                    string.concat(op, ".sourceType")
                )
            );
            oracle.primarySource = stdJson.readAddress(
                deployConfigData,
                string.concat(op, ".primarySource")
            );
            oracle.needsArg = uint8(
                stdJson.readUint(
                    deployConfigData,
                    string.concat(op, ".needsArg")
                )
            );
            oracle.fallbackSource = stdJson.readAddress(
                deployConfigData,
                string.concat(op, ".fallbackSource")
            );
            // fallbackSelector is a hex string, parse as bytes4
            string memory selStr = stdJson.readString(
                deployConfigData,
                string.concat(op, ".fallbackSelector")
            );
            bytes memory selBytes = vm.parseBytes(selStr);
            require(selBytes.length == 4, "Invalid fallbackSelector");
            bytes4 fallbackSelector;
            assembly {
                fallbackSelector := mload(add(selBytes, 32))
            }
            oracle.fallbackSelector = fallbackSelector;
            // Name (optional)
            string memory name = stdJson.readString(
                deployConfigData,
                string.concat(prefix, ".name")
            );

            tokens[i] = TokenConfig({
                name: name,
                addresses: addrs,
                params: params,
                oracle: oracle
            });
        }
    }

    function deployInfrastructure() internal {
        proxyAdminDeployBlock = block.number;
        proxyAdminDeployTimestamp = block.timestamp;
        proxyAdmin = new ProxyAdmin();
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
            address(
                new TransparentUpgradeableProxy(
                    address(tokenRegistryOracleImpl),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        liquidTokenManagerProxyDeployBlock = block.number;
        liquidTokenManagerProxyDeployTimestamp = block.timestamp;
        liquidTokenManager = LiquidTokenManager(
            address(
                new TransparentUpgradeableProxy(
                    address(liquidTokenManagerImpl),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        stakerNodeCoordinatorProxyDeployBlock = block.number;
        stakerNodeCoordinatorProxyDeployTimestamp = block.timestamp;
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(stakerNodeCoordinatorImpl),
                    address(proxyAdmin),
                    ""
                )
            )
        );

        liquidTokenProxyDeployBlock = block.number;
        liquidTokenProxyDeployTimestamp = block.timestamp;
        liquidToken = LiquidToken(
            address(
                new TransparentUpgradeableProxy(
                    address(liquidTokenImpl),
                    address(proxyAdmin),
                    ""
                )
            )
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
                priceUpdater: priceUpdater, // <-- off-chain EOA/bot etc
                liquidToken: address(liquidToken), // <-- on-chain contract
                liquidTokenManager: ILiquidTokenManager(
                    address(liquidTokenManager)
                )
            })
        );
    }
    function _initializeLiquidTokenManager() internal {
        liquidTokenManagerInitBlock = block.number;
        liquidTokenManagerInitTimestamp = block.timestamp;
        IERC20[] memory assets = new IERC20[](tokens.length);
        IStrategy[] memory strategies = new IStrategy[](tokens.length);
        ILiquidTokenManager.TokenInfo[]
            memory tokenInfo = new ILiquidTokenManager.TokenInfo[](
                tokens.length
            );

        for (uint256 i = 0; i < tokens.length; i++) {
            assets[i] = IERC20(tokens[i].addresses.token);
            strategies[i] = IStrategy(tokens[i].addresses.strategy);
            tokenInfo[i] = ILiquidTokenManager.TokenInfo({
                decimals: uint8(tokens[i].params.decimals),
                pricePerUnit: uint256(tokens[i].params.pricePerUnit),
                volatilityThreshold: uint256(
                    tokens[i].params.volatilityThreshold
                )
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
                tokenRegistryOracle: ITokenRegistryOracle(
                    address(tokenRegistryOracle)
                ),
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
                liquidTokenManager: ILiquidTokenManager(
                    address(liquidTokenManager)
                ),
                tokenRegistryOracle: ITokenRegistryOracle(
                    address(tokenRegistryOracle)
                )
            })
        );
    }

    // -------------------- BEGIN CHANGED SECTION: configureTokens() --------------------
    function configureTokens() internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            // Skip tokens that already exist
            if (
                liquidTokenManager.tokenIsSupported(
                    IERC20(tokens[i].addresses.token)
                )
            ) {
                continue;
            }

            TokenConfig memory t = tokens[i];
            liquidTokenManager.addToken(
                IERC20(t.addresses.token),
                uint8(t.params.decimals),
                uint256(t.params.pricePerUnit),
                uint256(t.params.volatilityThreshold),
                IStrategy(t.addresses.strategy),
                t.oracle.sourceType,
                t.oracle.primarySource,
                t.oracle.needsArg,
                t.oracle.fallbackSource,
                t.oracle.fallbackSelector
            );
        }
    }

    // -------------------- END CHANGED SECTION --------------------

    function transferOwnership() internal {
        proxyAdmin.transferOwnership(admin);
        require(
            proxyAdmin.owner() == admin,
            "Proxy admin ownership transfer failed"
        );
    }

    function verifyDeployment() internal view {
        _verifyProxyImplementations();
        _verifyContractConnections();
        _verifyRoles();
    }

    function _verifyProxyImplementations() internal view {
        // LiquidToken
        require(
            _getImplementationFromProxy(address(liquidToken)) ==
                address(liquidTokenImpl),
            "LiquidToken proxy implementation mismatch"
        );

        // LiquidTokenManager
        require(
            _getImplementationFromProxy(address(liquidTokenManager)) ==
                address(liquidTokenManagerImpl),
            "LiquidTokenManager proxy implementation mismatch"
        );

        // StakerNodeCoordinator
        require(
            _getImplementationFromProxy(address(stakerNodeCoordinator)) ==
                address(stakerNodeCoordinatorImpl),
            "StakerNodeCoordinator proxy implementation mismatch"
        );

        // TokenRegistryOracle
        require(
            _getImplementationFromProxy(address(tokenRegistryOracle)) ==
                address(tokenRegistryOracleImpl),
            "TokenRegistryOracle proxy implementation mismatch"
        );
    }

    function _verifyContractConnections() internal view {
        // LiquidToken
        require(
            address(liquidToken.liquidTokenManager()) ==
                address(liquidTokenManager),
            "LiquidToken: wrong liquidTokenManager"
        );

        // LiquidTokenManager
        require(
            address(liquidTokenManager.liquidToken()) == address(liquidToken),
            "LiquidTokenManager: wrong liquidToken"
        );
        require(
            address(liquidTokenManager.strategyManager()) ==
                address(strategyManager),
            "LiquidTokenManager: wrong strategyManager"
        );
        require(
            address(liquidTokenManager.delegationManager()) ==
                address(delegationManager),
            "LiquidTokenManager: wrong delegationManager"
        );
        require(
            address(liquidTokenManager.stakerNodeCoordinator()) ==
                address(stakerNodeCoordinator),
            "LiquidTokenManager: wrong stakerNodeCoordinator"
        );

        // StakerNodeCoordinator
        require(
            address(stakerNodeCoordinator.liquidTokenManager()) ==
                address(liquidTokenManager),
            "StakerNodeCoordinator: wrong liquidTokenManager"
        );
        require(
            address(stakerNodeCoordinator.strategyManager()) ==
                address(strategyManager),
            "StakerNodeCoordinator: wrong strategyManager"
        );
        require(
            address(stakerNodeCoordinator.delegationManager()) ==
                address(delegationManager),
            "StakerNodeCoordinator: wrong delegationManager"
        );
        require(
            address(
                stakerNodeCoordinator.upgradeableBeacon().implementation()
            ) == address(stakerNodeImpl),
            "StakerNodeCoordinator: wrong stakerNodeImplementation"
        );

        // TokenRegistryOracle
        require(
            address(tokenRegistryOracle.liquidTokenManager()) ==
                address(liquidTokenManager),
            "TokenRegistryOracle: wrong liquidTokenManager"
        );

        // Assets and strategies
        IERC20[] memory registeredTokens = liquidTokenManager
            .getSupportedTokens();
        require(
            registeredTokens.length == tokens.length,
            "LiquidTokenManager: wrong number of registered tokens"
        );

        // Verify token and strategy info matches deployment config
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 configToken = IERC20(tokens[i].addresses.token);
            ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager
                .getTokenInfo(configToken);
            require(
                tokenInfo.decimals == tokens[i].params.decimals,
                "LiquidTokenManager: wrong token decimals"
            );
            require(
                tokenInfo.pricePerUnit == tokens[i].params.pricePerUnit,
                "LiquidTokenManager: wrong token price"
            );
            require(
                tokenInfo.volatilityThreshold ==
                    tokens[i].params.volatilityThreshold,
                "LiquidTokenManager: wrong volatility threshold"
            );

            IStrategy registeredStrategy = liquidTokenManager.getTokenStrategy(
                configToken
            );
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
            require(
                tokenFound,
                "LiquidTokenManager: token not in supported list"
            );
        }
    }

    function _verifyRoles() internal view {
        bytes32 adminRole = 0x00;

        // LiquidToken
        require(
            liquidToken.hasRole(adminRole, admin),
            "Admin role not assigned in LiquidToken"
        );
        require(
            liquidToken.hasRole(liquidToken.PAUSER_ROLE(), pauser),
            "Pauser role not assigned in LiquidToken"
        );

        // LiquidTokenManager
        require(
            liquidTokenManager.hasRole(adminRole, admin),
            "Admin role not assigned in LiquidTokenManager"
        );
        require(
            liquidTokenManager.hasRole(
                liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
                admin
            ),
            "Strategy Controller role not assigned in LiquidTokenManager"
        );
        require(
            liquidTokenManager.hasRole(
                liquidTokenManager.PRICE_UPDATER_ROLE(),
                address(tokenRegistryOracle)
            ),
            "Price Updater role not assigned in LiquidTokenManager"
        );

        // StakerNodeCoordinator
        require(
            stakerNodeCoordinator.hasRole(adminRole, admin),
            "Admin role not assigned in StakerNodeCoordinator"
        );
        require(
            stakerNodeCoordinator.hasRole(
                stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(),
                admin
            ),
            "Staker Node Creator role not assigned in StakerNodeCoordinator"
        );
        require(
            stakerNodeCoordinator.hasRole(
                stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
                address(liquidTokenManager)
            ),
            "Staker Nodes Delegator role not assigned in StakerNodeCoordinator"
        );

        // TokenRegistryOracle
        require(
            tokenRegistryOracle.hasRole(adminRole, admin),
            "Admin role not assigned in TokenRegistryOracle"
        );
        require(
            tokenRegistryOracle.hasRole(
                tokenRegistryOracle.RATE_UPDATER_ROLE(),
                address(liquidToken)
            ),
            "Rate Updater role not assigned in TokenRegistryOracle"
        );
    }
    /*
    function configureRoles() internal {
        // Grant RATE_UPDATER_ROLE to LiquidToken to enable price updates during deposits
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.RATE_UPDATER_ROLE(),
            address(liquidToken)
        );

        // Log the role assignment to help with verification
        emit RoleAssigned(
            "TokenRegistryOracle",
            "RATE_UPDATER_ROLE",
            address(liquidToken)
        );
    }
    */

    function writeDeploymentOutput() internal {
        string memory parent_object = "parent";

        // Top level properties
        vm.serializeAddress(
            parent_object,
            "proxyAddress",
            address(liquidToken)
        );
        vm.serializeAddress(
            parent_object,
            "implementationAddress",
            address(liquidTokenImpl)
        );
        vm.serializeString(parent_object, "name", LIQUID_TOKEN_NAME);
        vm.serializeString(parent_object, "symbol", LIQUID_TOKEN_SYMBOL);
        vm.serializeAddress(parent_object, "avsAddress", AVS_ADDRESS);
        vm.serializeUint(parent_object, "chainId", block.chainid);
        vm.serializeUint(
            parent_object,
            "maxNodes",
            STAKER_NODE_COORDINATOR_MAX_NODES
        ); // Adjust as needed
        vm.serializeUint(parent_object, "deploymentBlock", block.number);
        vm.serializeUint(
            parent_object,
            "deploymentTimestamp",
            block.timestamp * 1000
        ); // Converting to milliseconds

        // Contract deployments section
        string memory contractDeployments = "contractDeployments";

        // Implementation contracts
        string memory implementation = "implementation";

        // LiquidTokenManager implementation
        string memory liquidTokenManagerImpl_obj = "liquidTokenManager";
        vm.serializeAddress(
            liquidTokenManagerImpl_obj,
            "address",
            address(liquidTokenManagerImpl)
        );
        vm.serializeUint(
            liquidTokenManagerImpl_obj,
            "block",
            liquidTokenManagerImplDeployBlock
        );
        string memory liquidTokenManagerImpl_output = vm.serializeUint(
            liquidTokenManagerImpl_obj,
            "timestamp",
            liquidTokenManagerImplDeployTimestamp * 1000
        );

        // StakerNodeCoordinator implementation
        string memory stakerNodeCoordinatorImpl_obj = "stakerNodeCoordinator";
        vm.serializeAddress(
            stakerNodeCoordinatorImpl_obj,
            "address",
            address(stakerNodeCoordinatorImpl)
        );
        vm.serializeUint(
            stakerNodeCoordinatorImpl_obj,
            "block",
            stakerNodeCoordinatorImplDeployBlock
        );
        string memory stakerNodeCoordinatorImpl_output = vm.serializeUint(
            stakerNodeCoordinatorImpl_obj,
            "timestamp",
            stakerNodeCoordinatorImplDeployTimestamp * 1000
        );

        // StakerNode implementation
        string memory stakerNodeImpl_obj = "stakerNode";
        vm.serializeAddress(
            stakerNodeImpl_obj,
            "address",
            address(stakerNodeImpl)
        );
        vm.serializeUint(
            stakerNodeImpl_obj,
            "block",
            stakerNodeImplDeployBlock
        );
        string memory stakerNodeImpl_output = vm.serializeUint(
            stakerNodeImpl_obj,
            "timestamp",
            stakerNodeImplDeployTimestamp * 1000
        );

        // TokenRegistryOracle implementation
        string memory tokenRegistryOracleImpl_obj = "tokenRegistryOracle";
        vm.serializeAddress(
            tokenRegistryOracleImpl_obj,
            "address",
            address(tokenRegistryOracleImpl)
        );
        vm.serializeUint(
            tokenRegistryOracleImpl_obj,
            "block",
            tokenRegistryOracleImplDeployBlock
        );
        string memory tokenRegistryOracleImpl_output = vm.serializeUint(
            tokenRegistryOracleImpl_obj,
            "timestamp",
            tokenRegistryOracleImplDeployTimestamp * 1000
        );

        // Combine all implementation objects
        vm.serializeString(
            implementation,
            "liquidTokenManager",
            liquidTokenManagerImpl_output
        );
        vm.serializeString(
            implementation,
            "stakerNodeCoordinator",
            stakerNodeCoordinatorImpl_output
        );
        vm.serializeString(implementation, "stakerNode", stakerNodeImpl_output);
        string memory implementation_output = vm.serializeString(
            implementation,
            "tokenRegistryOracle",
            tokenRegistryOracleImpl_output
        );

        // Proxy contracts
        string memory proxy = "proxy";

        // LiquidTokenManager proxy
        string memory liquidTokenManager_obj = "liquidTokenManager";
        vm.serializeAddress(
            liquidTokenManager_obj,
            "address",
            address(liquidTokenManager)
        );
        vm.serializeUint(
            liquidTokenManager_obj,
            "block",
            liquidTokenManagerProxyDeployBlock
        );
        string memory liquidTokenManager_output = vm.serializeUint(
            liquidTokenManager_obj,
            "timestamp",
            liquidTokenManagerProxyDeployTimestamp * 1000
        );

        // StakerNodeCoordinator proxy
        string memory stakerNodeCoordinator_obj = "stakerNodeCoordinator";
        vm.serializeAddress(
            stakerNodeCoordinator_obj,
            "address",
            address(stakerNodeCoordinator)
        );
        vm.serializeUint(
            stakerNodeCoordinator_obj,
            "block",
            stakerNodeCoordinatorProxyDeployBlock
        );
        string memory stakerNodeCoordinator_output = vm.serializeUint(
            stakerNodeCoordinator_obj,
            "timestamp",
            stakerNodeCoordinatorProxyDeployTimestamp * 1000
        );

        // TokenRegistryOracle proxy
        string memory tokenRegistryOracle_obj = "tokenRegistryOracle";
        vm.serializeAddress(
            tokenRegistryOracle_obj,
            "address",
            address(tokenRegistryOracle)
        );
        vm.serializeUint(
            tokenRegistryOracle_obj,
            "block",
            tokenRegistryOracleProxyDeployBlock
        );
        string memory tokenRegistryOracle_output = vm.serializeUint(
            tokenRegistryOracle_obj,
            "timestamp",
            tokenRegistryOracleProxyDeployTimestamp * 1000
        );

        // Combine all proxy objects
        vm.serializeString(
            proxy,
            "liquidTokenManager",
            liquidTokenManager_output
        );
        vm.serializeString(
            proxy,
            "stakerNodeCoordinator",
            stakerNodeCoordinator_output
        );
        string memory proxy_output = vm.serializeString(
            proxy,
            "tokenRegistryOracle",
            tokenRegistryOracle_output
        );

        // Combine implementation and proxy under contractDeployments
        vm.serializeString(
            contractDeployments,
            "implementation",
            implementation_output
        );
        string memory contractDeployments_output = vm.serializeString(
            contractDeployments,
            "proxy",
            proxy_output
        );

        // Roles section
        string memory roles = "roles";
        vm.serializeAddress(roles, "deployer", address(proxyAdmin));
        vm.serializeAddress(roles, "admin", admin);
        vm.serializeAddress(roles, "pauser", pauser);
        string memory roles_output = vm.serializeAddress(
            roles,
            "priceUpdater",
            priceUpdater
        );

        // Tokens section
        string memory tokens_array = "tokens";

        // Process each token
        for (uint256 i = 0; i < tokens.length; ++i) {
            // Create an object for each token
            string memory token_obj = string.concat("token", vm.toString(i));
            vm.serializeAddress(
                token_obj,
                "address",
                tokens[i].addresses.token
            );
            string memory token_output = vm.serializeAddress(
                token_obj,
                "strategy",
                tokens[i].addresses.strategy
            );

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
            string memory lastTokenObj = string.concat(
                "token",
                vm.toString(tokens.length - 1)
            );
            vm.serializeAddress(
                lastTokenObj,
                "address",
                tokens[tokens.length - 1].addresses.token
            );
            string memory lastTokenOutput = vm.serializeAddress(
                lastTokenObj,
                "strategy",
                tokens[tokens.length - 1].addresses.strategy
            );
            tokens_array_output = vm.serializeString(
                tokens_array,
                vm.toString(tokens.length - 1),
                lastTokenOutput
            );
        }

        // Combine all sections into the parent object
        vm.serializeString(
            parent_object,
            "contractDeployments",
            contractDeployments_output
        );
        vm.serializeString(parent_object, "roles", roles_output);
        string memory finalJson = vm.serializeString(
            parent_object,
            "tokens",
            tokens_array_output
        );

        // Write the final JSON to output file
        vm.writeJson(finalJson, OUTPUT_PATH);
    }

    // --- Helper functions ---
    function _getImplementationFromProxy(
        address proxy
    ) internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        vm.load(
                            proxy,
                            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
                        )
                    )
                )
            );
    }
}