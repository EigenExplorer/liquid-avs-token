// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import 'forge-std/Script.sol';
import 'forge-std/Test.sol';
import 'forge-std/console.sol';

import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ITransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ProxyAdmin} from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IStrategyManager} from '@eigenlayer/contracts/interfaces/IStrategyManager.sol';
import {IDelegationManager} from '@eigenlayer/contracts/interfaces/IDelegationManager.sol';
import {IStrategy} from '@eigenlayer/contracts/interfaces/IStrategy.sol';

import {LiquidToken} from '../../../src/core/LiquidToken.sol';
import {ILiquidToken} from '../../../src/interfaces/ILiquidToken.sol';
import {TokenRegistryOracle} from '../../../src/utils/TokenRegistryOracle.sol';
import {ITokenRegistryOracle} from '../../../src/interfaces/ITokenRegistryOracle.sol';
import {LiquidTokenManager} from '../../../src/core/LiquidTokenManager.sol';
import {ILiquidTokenManager} from '../../../src/interfaces/ILiquidTokenManager.sol';
import {StakerNode} from '../../../src/core/StakerNode.sol';
import {StakerNodeCoordinator} from '../../../src/core/StakerNodeCoordinator.sol';
import {IStakerNodeCoordinator} from '../../../src/interfaces/IStakerNodeCoordinator.sol';

/// @dev To load env file:
// source .env

/// @dev To run this deploy script (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script script/deploy/local/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --broadcast --private-key $DEPLOYER_PRIVATE_KEY --sig "run(string,string)" -- "xeigenda.anvil.config.json" "mainnet" -vvvv

event RoleAssigned(string contractName, string role, address recipient);

// Oracle config struct for per-token price source
struct OracleConfig {
    uint8 sourceType;
    address primarySource;
    uint8 needsArg;
    address fallbackSource;
    bytes4 fallbackSelector;
}

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
    string constant OUTPUT_PATH = 'script/outputs/local/deployment_data.json';

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
    uint256 public oracleSalt;

    function run(string memory deployConfigFileName, string memory chain) external {
        // Load config file
        loadConfig(deployConfigFileName, chain);
        oracleSalt = vm.envUint('ORACLE_SALT');
        require(admin != address(0), 'Admin address must not be zero');
        require(admin != msg.sender, 'Deployer and admin must be different');

        // Core deployment
        vm.startBroadcast();

        deployInfrastructure();
        deployImplementations();
        deployProxies();
        initializeProxies();
        addAndConfigureTokens(chain);
        transferOwnership();

        verifyDeployment();

        vm.stopBroadcast();
        writeDeploymentOutput();
    }

    // Helper function to count array entries
    function _countTokens(string memory deployConfigData) internal returns (uint256) {
        uint256 i = 0;
        while (true) {
            string memory prefix = string.concat('.tokens[', vm.toString(i), '].addresses.token');
            try this._readAddress(deployConfigData, prefix) returns (address) {
                i++;
            } catch {
                break;
            }
        }
        return i;
    }

    // Helper for try/catch (must be external or public)
    function _readAddress(string memory deployConfigData, string memory jsonPath) external pure returns (address) {
        return stdJson.readAddress(deployConfigData, jsonPath);
    }

    function loadConfig(string memory deployConfigFileName, string memory chain) internal {
        // Load network-specific config
        string memory networkConfigPath = string.concat('script/configs/', chain, '.json');
        string memory networkConfigData = vm.readFile(networkConfigPath);
        require(stdJson.readUint(networkConfigData, '.network.chainId') == block.chainid, 'Wrong network');

        strategyManager = stdJson.readAddress(networkConfigData, '.network.eigenLayer.strategyManager');
        delegationManager = stdJson.readAddress(networkConfigData, '.network.eigenLayer.delegationManager');

        // Load deployment-specific config
        string memory deployConfigPath = string(bytes(string.concat('script/configs/local/', deployConfigFileName)));
        string memory deployConfigData = vm.readFile(deployConfigPath);

        admin = stdJson.readAddress(deployConfigData, '.roles.admin');
        pauser = stdJson.readAddress(deployConfigData, '.roles.pauser');
        priceUpdater = stdJson.readAddress(deployConfigData, '.roles.priceUpdater');
        AVS_ADDRESS = stdJson.readAddress(deployConfigData, '.avsAddress');
        STAKER_NODE_COORDINATOR_MAX_NODES = stdJson.readUint(
            deployConfigData,
            '.contracts.stakerNodeCoordinator.init.maxNodes'
        );
        LIQUID_TOKEN_NAME = stdJson.readString(deployConfigData, '.contracts.liquidToken.init.name');
        LIQUID_TOKEN_SYMBOL = stdJson.readString(deployConfigData, '.contracts.liquidToken.init.symbol');

        // Detect the number of tokens in the JSON array
        uint256 numTokens = _countTokens(deployConfigData);
        tokens = new TokenConfig[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            string memory prefix = string.concat('.tokens[', vm.toString(i), ']');

            // Addresses
            TokenAddresses memory addrs;
            addrs.token = stdJson.readAddress(deployConfigData, string.concat(prefix, '.addresses.token'));
            addrs.strategy = stdJson.readAddress(deployConfigData, string.concat(prefix, '.addresses.strategy'));
            // Params
            TokenParams memory params;
            params.decimals = stdJson.readUint(deployConfigData, string.concat(prefix, '.params.decimals'));
            params.volatilityThreshold = stdJson.readUint(
                deployConfigData,
                string.concat(prefix, '.params.volatilityThreshold')
            );
            // Oracle
            OracleConfig memory oracle;
            string memory op = string.concat(prefix, '.oracle');
            oracle.sourceType = uint8(stdJson.readUint(deployConfigData, string.concat(op, '.sourceType')));
            oracle.primarySource = stdJson.readAddress(deployConfigData, string.concat(op, '.primarySource'));
            oracle.needsArg = uint8(stdJson.readUint(deployConfigData, string.concat(op, '.needsArg')));
            oracle.fallbackSource = stdJson.readAddress(deployConfigData, string.concat(op, '.fallbackSource'));
            // fallbackSelector is a hex string, parse as bytes4
            string memory selStr = stdJson.readString(deployConfigData, string.concat(op, '.fallbackSelector'));
            bytes memory selBytes = vm.parseBytes(selStr);
            require(selBytes.length == 4, 'Invalid fallbackSelector');
            bytes4 fallbackSelector;
            assembly {
                fallbackSelector := mload(add(selBytes, 32))
            }
            oracle.fallbackSelector = fallbackSelector;
            // Name (optional)
            string memory name = stdJson.readString(deployConfigData, string.concat(prefix, '.name'));

            tokens[i] = TokenConfig({name: name, addresses: addrs, params: params, oracle: oracle});
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
            address(new TransparentUpgradeableProxy(address(tokenRegistryOracleImpl), address(proxyAdmin), ''))
        );

        liquidTokenManagerProxyDeployBlock = block.number;
        liquidTokenManagerProxyDeployTimestamp = block.timestamp;
        liquidTokenManager = LiquidTokenManager(
            address(new TransparentUpgradeableProxy(address(liquidTokenManagerImpl), address(proxyAdmin), ''))
        );

        stakerNodeCoordinatorProxyDeployBlock = block.number;
        stakerNodeCoordinatorProxyDeployTimestamp = block.timestamp;
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(new TransparentUpgradeableProxy(address(stakerNodeCoordinatorImpl), address(proxyAdmin), ''))
        );

        liquidTokenProxyDeployBlock = block.number;
        liquidTokenProxyDeployTimestamp = block.timestamp;
        liquidToken = LiquidToken(
            address(new TransparentUpgradeableProxy(address(liquidTokenImpl), address(proxyAdmin), ''))
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
                initialOwner: msg.sender, // burner, will transfer to admin
                priceUpdater: priceUpdater,
                liquidToken: address(liquidToken),
                liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager))
            }),
            oracleSalt
        );
    }

    function _initializeLiquidTokenManager() internal {
        liquidTokenManagerInitBlock = block.number;
        liquidTokenManagerInitTimestamp = block.timestamp;

        liquidTokenManager.initialize(
            ILiquidTokenManager.Init({
                liquidToken: liquidToken,
                strategyManager: IStrategyManager(strategyManager),
                delegationManager: IDelegationManager(delegationManager),
                stakerNodeCoordinator: stakerNodeCoordinator,
                tokenRegistryOracle: ITokenRegistryOracle(address(tokenRegistryOracle)),
                initialOwner: msg.sender, // burner, will transfer to admin
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
                liquidTokenManager: ILiquidTokenManager(address(liquidTokenManager)),
                tokenRegistryOracle: ITokenRegistryOracle(address(tokenRegistryOracle))
            })
        );
    }

    function addAndConfigureTokens(string memory chain) internal {
        TokenConfig[] memory addable = _getAddableTokens(tokens);
        for (uint256 i = 0; i < addable.length; ++i) {
            liquidTokenManager.addToken(
                IERC20(addable[i].addresses.token),
                uint8(addable[i].params.decimals),
                uint256(addable[i].params.volatilityThreshold),
                IStrategy(addable[i].addresses.strategy),
                addable[i].oracle.sourceType,
                addable[i].oracle.primarySource,
                addable[i].oracle.needsArg,
                addable[i].oracle.fallbackSource,
                addable[i].oracle.fallbackSelector
            );
        }

        // Configure curve pools that require reentrancy locks
        string memory networkConfigPath = string.concat('script/configs/', chain, '.json');
        string memory networkConfigData = vm.readFile(networkConfigPath);

        uint256 poolCount = 0;
        while (true) {
            string memory poolPath = string.concat('.curvePoolsRequireLock[', vm.toString(poolCount), ']');
            try this._readAddress(networkConfigData, poolPath) returns (address) {
                poolCount++;
            } catch {
                break;
            }
        }

        if (poolCount > 0) {
            address[] memory pools = new address[](poolCount);
            bool[] memory settings = new bool[](poolCount);

            for (uint256 i = 0; i < poolCount; i++) {
                string memory poolPath = string.concat('.curvePoolsRequireLock[', vm.toString(i), ']');
                pools[i] = stdJson.readAddress(networkConfigData, poolPath);
                settings[i] = true;
            }

            tokenRegistryOracle.batchSetRequiresLock(pools, settings);
        }
    }

    function transferOwnership() internal {
        // Transfer ProxyAdmin ownership first
        proxyAdmin.transferOwnership(admin);
        require(proxyAdmin.owner() == admin, 'Proxy admin ownership transfer failed');

        // Grant all roles meant for `initialOwner` to admin and renounce the same from deployer
        tokenRegistryOracle.grantRole(tokenRegistryOracle.DEFAULT_ADMIN_ROLE(), admin);
        tokenRegistryOracle.grantRole(tokenRegistryOracle.ORACLE_ADMIN_ROLE(), admin);
        liquidTokenManager.grantRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), admin);

        tokenRegistryOracle.renounceRole(tokenRegistryOracle.DEFAULT_ADMIN_ROLE(), msg.sender);
        tokenRegistryOracle.renounceRole(tokenRegistryOracle.ORACLE_ADMIN_ROLE(), msg.sender);
        liquidTokenManager.renounceRole(liquidTokenManager.DEFAULT_ADMIN_ROLE(), msg.sender);
    }

    function verifyDeployment() internal view {
        _verifyProxyImplementations();
        _verifyContractConnections();
        _verifyRoles();
    }

    function _verifyProxyImplementations() internal view {
        // LiquidToken
        require(
            _getImplementationFromProxy(address(liquidToken)) == address(liquidTokenImpl),
            'LiquidToken proxy implementation mismatch'
        );

        // LiquidTokenManager
        require(
            _getImplementationFromProxy(address(liquidTokenManager)) == address(liquidTokenManagerImpl),
            'LiquidTokenManager proxy implementation mismatch'
        );

        // StakerNodeCoordinator
        require(
            _getImplementationFromProxy(address(stakerNodeCoordinator)) == address(stakerNodeCoordinatorImpl),
            'StakerNodeCoordinator proxy implementation mismatch'
        );

        // TokenRegistryOracle
        require(
            _getImplementationFromProxy(address(tokenRegistryOracle)) == address(tokenRegistryOracleImpl),
            'TokenRegistryOracle proxy implementation mismatch'
        );
    }

    function _verifyContractConnections() internal view {
        // LiquidToken
        require(
            address(liquidToken.liquidTokenManager()) == address(liquidTokenManager),
            'LiquidToken: wrong liquidTokenManager'
        );

        // LiquidTokenManager
        require(
            address(liquidTokenManager.liquidToken()) == address(liquidToken),
            'LiquidTokenManager: wrong liquidToken'
        );
        require(
            address(liquidTokenManager.strategyManager()) == address(strategyManager),
            'LiquidTokenManager: wrong strategyManager'
        );
        require(
            address(liquidTokenManager.delegationManager()) == address(delegationManager),
            'LiquidTokenManager: wrong delegationManager'
        );
        require(
            address(liquidTokenManager.stakerNodeCoordinator()) == address(stakerNodeCoordinator),
            'LiquidTokenManager: wrong stakerNodeCoordinator'
        );

        // StakerNodeCoordinator
        require(
            address(stakerNodeCoordinator.liquidTokenManager()) == address(liquidTokenManager),
            'StakerNodeCoordinator: wrong liquidTokenManager'
        );
        require(
            address(stakerNodeCoordinator.strategyManager()) == address(strategyManager),
            'StakerNodeCoordinator: wrong strategyManager'
        );
        require(
            address(stakerNodeCoordinator.delegationManager()) == address(delegationManager),
            'StakerNodeCoordinator: wrong delegationManager'
        );
        require(
            address(stakerNodeCoordinator.upgradeableBeacon().implementation()) == address(stakerNodeImpl),
            'StakerNodeCoordinator: wrong stakerNodeImplementation'
        );

        // TokenRegistryOracle
        require(
            address(tokenRegistryOracle.liquidTokenManager()) == address(liquidTokenManager),
            'TokenRegistryOracle: wrong liquidTokenManager'
        );

        // Assets and strategies
        IERC20[] memory registeredTokens = liquidTokenManager.getSupportedTokens();
        TokenConfig[] memory addableTokens = _getAddableTokens(tokens);
        require(
            registeredTokens.length == addableTokens.length,
            'LiquidTokenManager: wrong number of registered tokens'
        );

        for (uint256 i = 0; i < addableTokens.length; i++) {
            IERC20 configToken = IERC20(addableTokens[i].addresses.token);
            ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(configToken);

            // Decimals check (always required)
            require(tokenInfo.decimals == addableTokens[i].params.decimals, 'LiquidTokenManager: wrong token decimals');
            // Volatility threshold check (always required)
            require(
                tokenInfo.volatilityThreshold == addableTokens[i].params.volatilityThreshold,
                'LiquidTokenManager: wrong volatility threshold'
            );
            // Strategy check (always required, including native tokens!)
            IStrategy registeredStrategy = liquidTokenManager.getTokenStrategy(configToken);
            require(
                address(registeredStrategy) == addableTokens[i].addresses.strategy,
                'LiquidTokenManager: wrong strategy address'
            );
            // Price check
            if (addableTokens[i].oracle.sourceType == 0 && addableTokens[i].oracle.primarySource == address(0)) {
                // Native token: price should be exactly 1e18
                require(tokenInfo.pricePerUnit == 1e18, 'LiquidTokenManager: native price should be 1e18');
            } else {
                // Non-native: price must be >0
                require(tokenInfo.pricePerUnit > 0, 'LiquidTokenManager: price should be set');
            }
            // Token must be present in supportedTokens
            bool tokenFound = false;
            for (uint256 j = 0; j < registeredTokens.length; j++) {
                if (address(registeredTokens[j]) == address(configToken)) {
                    tokenFound = true;
                    break;
                }
            }
            require(tokenFound, 'LiquidTokenManager: token not in supported list');
        }
    }

    function _verifyRoles() internal view {
        bytes32 adminRole = 0x00;

        // LiquidToken
        require(liquidToken.hasRole(adminRole, admin), 'Admin role not assigned in LiquidToken');
        require(liquidToken.hasRole(liquidToken.PAUSER_ROLE(), pauser), 'Pauser role not assigned in LiquidToken');

        // LiquidTokenManager
        require(liquidTokenManager.hasRole(adminRole, admin), 'Admin role not assigned in LiquidTokenManager');
        require(
            liquidTokenManager.hasRole(liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), admin),
            'Strategy Controller role not assigned in LiquidTokenManager'
        );
        require(
            liquidTokenManager.hasRole(liquidTokenManager.PRICE_UPDATER_ROLE(), address(tokenRegistryOracle)),
            'Price Updater role not assigned in LiquidTokenManager'
        );

        // StakerNodeCoordinator
        require(stakerNodeCoordinator.hasRole(adminRole, admin), 'Admin role not assigned in StakerNodeCoordinator');
        require(
            stakerNodeCoordinator.hasRole(stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), admin),
            'Staker Node Creator role not assigned in StakerNodeCoordinator'
        );
        require(
            stakerNodeCoordinator.hasRole(
                stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(),
                address(liquidTokenManager)
            ),
            'Staker Nodes Delegator role not assigned in StakerNodeCoordinator'
        );

        // TokenRegistryOracle
        require(tokenRegistryOracle.hasRole(adminRole, admin), 'Admin role not assigned in TokenRegistryOracle');
        require(
            tokenRegistryOracle.hasRole(tokenRegistryOracle.RATE_UPDATER_ROLE(), priceUpdater),
            'Rate Updater role not assigned to priceUpdater in TokenRegistryOracle'
        );

        require(
            tokenRegistryOracle.hasRole(tokenRegistryOracle.RATE_UPDATER_ROLE(), address(liquidToken)),
            'Rate Updater role not assigned to LiquidToken in TokenRegistryOracle'
        );
    }

    function writeDeploymentOutput() internal {
        string memory parent_object = 'parent';

        // Top level properties
        vm.serializeAddress(parent_object, 'proxyAddress', address(liquidToken));
        vm.serializeAddress(parent_object, 'implementationAddress', address(liquidTokenImpl));
        vm.serializeString(parent_object, 'name', LIQUID_TOKEN_NAME);
        vm.serializeString(parent_object, 'symbol', LIQUID_TOKEN_SYMBOL);
        vm.serializeAddress(parent_object, 'avsAddress', AVS_ADDRESS);
        vm.serializeUint(parent_object, 'chainId', block.chainid);
        vm.serializeUint(parent_object, 'maxNodes', STAKER_NODE_COORDINATOR_MAX_NODES);
        vm.serializeUint(parent_object, 'deploymentBlock', block.number);
        vm.serializeUint(parent_object, 'deploymentTimestamp', block.timestamp * 1000);

        // Contract deployments section
        string memory contractDeployments = 'contractDeployments';

        // Implementation contracts
        string memory implementation = 'implementation';

        // LiquidTokenManager implementation
        string memory liquidTokenManagerImpl_obj = 'liquidTokenManager';
        vm.serializeAddress(liquidTokenManagerImpl_obj, 'address', address(liquidTokenManagerImpl));
        vm.serializeUint(liquidTokenManagerImpl_obj, 'block', liquidTokenManagerImplDeployBlock);
        string memory liquidTokenManagerImpl_output = vm.serializeUint(
            liquidTokenManagerImpl_obj,
            'timestamp',
            liquidTokenManagerImplDeployTimestamp * 1000
        );

        // StakerNodeCoordinator implementation
        string memory stakerNodeCoordinatorImpl_obj = 'stakerNodeCoordinator';
        vm.serializeAddress(stakerNodeCoordinatorImpl_obj, 'address', address(stakerNodeCoordinatorImpl));
        vm.serializeUint(stakerNodeCoordinatorImpl_obj, 'block', stakerNodeCoordinatorImplDeployBlock);
        string memory stakerNodeCoordinatorImpl_output = vm.serializeUint(
            stakerNodeCoordinatorImpl_obj,
            'timestamp',
            stakerNodeCoordinatorImplDeployTimestamp * 1000
        );

        // StakerNode implementation
        string memory stakerNodeImpl_obj = 'stakerNode';
        vm.serializeAddress(stakerNodeImpl_obj, 'address', address(stakerNodeImpl));
        vm.serializeUint(stakerNodeImpl_obj, 'block', stakerNodeImplDeployBlock);
        string memory stakerNodeImpl_output = vm.serializeUint(
            stakerNodeImpl_obj,
            'timestamp',
            stakerNodeImplDeployTimestamp * 1000
        );

        // TokenRegistryOracle implementation
        string memory tokenRegistryOracleImpl_obj = 'tokenRegistryOracle';
        vm.serializeAddress(tokenRegistryOracleImpl_obj, 'address', address(tokenRegistryOracleImpl));
        vm.serializeUint(tokenRegistryOracleImpl_obj, 'block', tokenRegistryOracleImplDeployBlock);
        string memory tokenRegistryOracleImpl_output = vm.serializeUint(
            tokenRegistryOracleImpl_obj,
            'timestamp',
            tokenRegistryOracleImplDeployTimestamp * 1000
        );

        // Combine all implementation objects
        vm.serializeString(implementation, 'liquidTokenManager', liquidTokenManagerImpl_output);
        vm.serializeString(implementation, 'stakerNodeCoordinator', stakerNodeCoordinatorImpl_output);
        vm.serializeString(implementation, 'stakerNode', stakerNodeImpl_output);
        string memory implementation_output = vm.serializeString(
            implementation,
            'tokenRegistryOracle',
            tokenRegistryOracleImpl_output
        );

        // Proxy contracts
        string memory proxy = 'proxy';

        // LiquidTokenManager proxy
        string memory liquidTokenManager_obj = 'liquidTokenManager';
        vm.serializeAddress(liquidTokenManager_obj, 'address', address(liquidTokenManager));
        vm.serializeUint(liquidTokenManager_obj, 'block', liquidTokenManagerProxyDeployBlock);
        string memory liquidTokenManager_output = vm.serializeUint(
            liquidTokenManager_obj,
            'timestamp',
            liquidTokenManagerProxyDeployTimestamp * 1000
        );

        // StakerNodeCoordinator proxy
        string memory stakerNodeCoordinator_obj = 'stakerNodeCoordinator';
        vm.serializeAddress(stakerNodeCoordinator_obj, 'address', address(stakerNodeCoordinator));
        vm.serializeUint(stakerNodeCoordinator_obj, 'block', stakerNodeCoordinatorProxyDeployBlock);
        string memory stakerNodeCoordinator_output = vm.serializeUint(
            stakerNodeCoordinator_obj,
            'timestamp',
            stakerNodeCoordinatorProxyDeployTimestamp * 1000
        );

        // TokenRegistryOracle proxy
        string memory tokenRegistryOracle_obj = 'tokenRegistryOracle';
        vm.serializeAddress(tokenRegistryOracle_obj, 'address', address(tokenRegistryOracle));
        vm.serializeUint(tokenRegistryOracle_obj, 'block', tokenRegistryOracleProxyDeployBlock);
        string memory tokenRegistryOracle_output = vm.serializeUint(
            tokenRegistryOracle_obj,
            'timestamp',
            tokenRegistryOracleProxyDeployTimestamp * 1000
        );

        // Combine all proxy objects
        vm.serializeString(proxy, 'liquidTokenManager', liquidTokenManager_output);
        vm.serializeString(proxy, 'stakerNodeCoordinator', stakerNodeCoordinator_output);
        string memory proxy_output = vm.serializeString(proxy, 'tokenRegistryOracle', tokenRegistryOracle_output);

        // Combine implementation and proxy under contractDeployments
        vm.serializeString(contractDeployments, 'implementation', implementation_output);
        string memory contractDeployments_output = vm.serializeString(contractDeployments, 'proxy', proxy_output);

        // Roles section
        string memory roles = 'roles';
        vm.serializeAddress(roles, 'deployer', address(proxyAdmin));
        vm.serializeAddress(roles, 'admin', admin);
        vm.serializeAddress(roles, 'pauser', pauser);
        string memory roles_output = vm.serializeAddress(roles, 'priceUpdater', priceUpdater);

        // Tokens section
        string memory tokens_array = 'tokens';

        // Process each token
        for (uint256 i = 0; i < tokens.length; ++i) {
            // Create an object for each token
            string memory token_obj = string.concat('token', vm.toString(i));
            vm.serializeAddress(token_obj, 'address', tokens[i].addresses.token);
            string memory token_output = vm.serializeAddress(token_obj, 'strategy', tokens[i].addresses.strategy);

            // Add token object to the array using vm.serializeString
            if (i < tokens.length - 1) {
                vm.serializeString(tokens_array, vm.toString(i), token_output);
            }
        }

        // Get the complete tokens array (with the last element if there are any tokens)
        string memory tokens_array_output;
        if (tokens.length == 0) {
            tokens_array_output = '[]';
        } else {
            string memory lastTokenObj = string.concat('token', vm.toString(tokens.length - 1));
            vm.serializeAddress(lastTokenObj, 'address', tokens[tokens.length - 1].addresses.token);
            string memory lastTokenOutput = vm.serializeAddress(
                lastTokenObj,
                'strategy',
                tokens[tokens.length - 1].addresses.strategy
            );
            tokens_array_output = vm.serializeString(tokens_array, vm.toString(tokens.length - 1), lastTokenOutput);
        }

        // Combine all sections into the parent object
        vm.serializeString(parent_object, 'contractDeployments', contractDeployments_output);
        vm.serializeString(parent_object, 'roles', roles_output);
        string memory finalJson = vm.serializeString(parent_object, 'tokens', tokens_array_output);

        // Write the final JSON to output file
        vm.writeJson(finalJson, OUTPUT_PATH);
    }

    // --- Helper functions ---
    function _getImplementationFromProxy(address proxy) internal view returns (address) {
        return
            address(
                uint160(uint256(vm.load(proxy, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)))
            );
    }

    function _getAddableTokens(TokenConfig[] memory tokens) internal pure returns (TokenConfig[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i].oracle.sourceType == 0 && tokens[i].oracle.primarySource == address(0)) {
                continue; // Skip native tokens (like Eigen)
            }
            count++;
        }
        TokenConfig[] memory filtered = new TokenConfig[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i].oracle.sourceType == 0 && tokens[i].oracle.primarySource == address(0)) {
                continue;
            }
            filtered[j++] = tokens[i];
        }
        return filtered;
    }
}
