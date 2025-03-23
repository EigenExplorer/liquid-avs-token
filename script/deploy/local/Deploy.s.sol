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

/// @dev To run this deploy script for local Mainnet deployment:
// forge script script/DeployMainnet.sol:DeployMainnet --rpc-url http://localhost:8545 --broadcast --private-key $DEPLOYER_PRIVATE_KEY -vvvv

/// @dev To run for Mainnet with verification:
// forge script script/DeployMainnet.sol:DeployMainnet --rpc-url $RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
contract DeployMainnet is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    // Mainnet Chain ID
    uint256 constant MAINNET_CHAIN_ID = 1;

    // Local or Public deployment flag
    bool public isLocalDeployment;

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
    
    // Path to output file - always mainnet for Ethereum mainnet
    string constant OUTPUT_PATH = "script/outputs/local/local_deployment_data.json";

    // Network-level config
    address public strategyManager;
    address public delegationManager;
    address public slasher;

    // Deployment-level config
    address public AVS_ADDRESS;
    uint256 public STAKER_NODE_COORDINATOR_MAX_NODES;
    string public LIQUID_TOKEN_NAME;
    string public LIQUID_TOKEN_SYMBOL;

    address public admin;
    address public pauser;
    address public priceUpdater;
    address public strategyController;
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

    function run() external {
        // Verify we're on Mainnet or a fork of Mainnet
        uint256 chainId = block.chainid;
        
        // Determine if we're on a local fork or actual Mainnet network
        if (chainId == MAINNET_CHAIN_ID) {
            // Check if this is a local deployment
            string memory deployment = vm.envOr("DEPLOYMENT", string(""));
            isLocalDeployment = keccak256(bytes(deployment)) == keccak256(bytes("local"));
            
            if (isLocalDeployment) {
                console.log("Running Mainnet LOCAL fork deployment");
            } else {
                console.log("Running Ethereum MAINNET production deployment");
                console.log(" WARNING: Deploying to REAL Ethereum mainnet! ");
            }
        } else {
            // If we're not on Mainnet chain ID, assume local development with a different chainId
            console.log("Warning: Not running on Mainnet chain ID (1). Current chain ID: %d", chainId);
            console.log("Continuing as local development deployment");
            isLocalDeployment = true;
        }
        
        console.log("ChainID: %d", block.chainid);
        
        // Load config based on network
        string memory network = vm.envOr("NETWORK", string("mainnet"));
        
        if (keccak256(bytes(network)) == keccak256(bytes("local"))) {
            // Use local config
            loadConfig("local.json", "xeigenda_mainnet.anvil.config.json", "local");
        } else if (keccak256(bytes(network)) == keccak256(bytes("holesky"))) {
            // Use Holesky config
            loadConfig("holesky.json", "xeigenda_holesky.anvil.config.json", "local");
        } else {
            // Default to Mainnet config
            if (isLocalDeployment) {
                loadConfig("mainnet.json", "xeigenda_mainnet.anvil.config.json", "local");
            } else {
                loadConfig("mainnet.json", "xeigenda_mainnet.config.json", "mainnet");
            }
        }

        // Core deployment
        vm.startBroadcast();

        deployInfrastructure();
        deployImplementations();
        deployProxies();
        initializeProxies();
        transferOwnership();

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("\n=== Verifying Deployment ===");
        verifyDeployment();
        
        // Write deployment results
        console.log("\n=== Writing Deployment Data ===");
        writeDeploymentOutput();
        
        // Push deployment data to GitHub
        pushToGitHub();
        
        console.log("\n=== Mainnet Deployment Complete ===");
        console.log("ProxyAdmin: %s", address(proxyAdmin));
        console.log("LiquidToken: %s", address(liquidToken));
        console.log("LiquidTokenManager: %s", address(liquidTokenManager));
        console.log("TokenRegistryOracle: %s", address(tokenRegistryOracle));
        console.log("StakerNodeCoordinator: %s", address(stakerNodeCoordinator));
    }

    function loadConfig(
        string memory networkConfigFileName,
        string memory deployConfigFileName,
        string memory configDir
    ) internal {
        // Network config path is always in script/configs/
        string memory networkConfigPath = string.concat("script/configs/", networkConfigFileName);
        
        // Deploy config path uses the provided configDir parameter
        string memory deployConfigPath = string.concat("script/configs/", configDir, "/", deployConfigFileName);
        
        console.log("Loading network config from: %s", networkConfigPath);
        console.log("Loading deploy config from: %s", deployConfigPath);
        
        // Load network-specific config
        string memory networkConfigData = vm.readFile(networkConfigPath);
        
        // Skip chain ID check for local deployments (when using Anvil)
        if (keccak256(bytes(configDir)) == keccak256(bytes("local"))) {
            console.log("Local Anvil deployment detected, skipping chain ID check");
        } else {
            require(stdJson.readUint(networkConfigData, ".network.chainId") == block.chainid, "Wrong network");
        }

        strategyManager = stdJson.readAddress(networkConfigData, ".network.eigenLayer.strategyManager");
        delegationManager = stdJson.readAddress(networkConfigData, ".network.eigenLayer.delegationManager");
        slasher = stdJson.readAddress(networkConfigData, ".network.eigenLayer.slasher");
        
        console.log("Loaded EigenLayer addresses:");
        console.log("  StrategyManager: %s", strategyManager);
        console.log("  DelegationManager: %s", delegationManager);
        console.log("  Slasher: %s", slasher);

        // Load deployment-specific config
        string memory deployConfigData = vm.readFile(deployConfigPath);
        admin = stdJson.readAddress(deployConfigData, ".roles.admin");
        pauser = stdJson.readAddress(deployConfigData, ".roles.pauser");
        priceUpdater = stdJson.readAddress(deployConfigData, ".roles.priceUpdater");
        
        // Handle optional strategy controller - defaults to admin if not provided
        if (vm.keyExists(deployConfigData, ".roles.strategyController")) {
            strategyController = stdJson.readAddress(deployConfigData, ".roles.strategyController");
        } else {
            strategyController = admin;
            console.log("Strategy controller not specified, defaulting to admin");
        }
        
        tokens = abi.decode(stdJson.parseRaw(deployConfigData, ".tokens"), (TokenConfig[]));

        AVS_ADDRESS = stdJson.readAddress(deployConfigData, ".avsAddress");
        STAKER_NODE_COORDINATOR_MAX_NODES = stdJson.readUint(deployConfigData, ".contracts.stakerNodeCoordinator.init.maxNodes");
        LIQUID_TOKEN_NAME = stdJson.readString(deployConfigData, ".contracts.liquidToken.init.name");
        LIQUID_TOKEN_SYMBOL = stdJson.readString(deployConfigData, ".contracts.liquidToken.init.symbol");
        
        console.log("Loaded roles:");
        console.log("  Admin: %s", admin);
        console.log("  Pauser: %s", pauser);
        console.log("  Price Updater: %s", priceUpdater);
        console.log("  Strategy Controller: %s", strategyController);
        
        console.log("Loaded contract parameters:");
        console.log("  AVS Address: %s", AVS_ADDRESS);
        console.log("  Max Nodes: %d", STAKER_NODE_COORDINATOR_MAX_NODES);
        console.log("  Token Name: %s", LIQUID_TOKEN_NAME);
        console.log("  Token Symbol: %s", LIQUID_TOKEN_SYMBOL);
        
        console.log("Loaded %d tokens:", tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("  Token %d:", i);
            console.log("    Address: %s", tokens[i].addresses.token);
            console.log("    Strategy: %s", tokens[i].addresses.strategy);
            console.log("    Decimals: %d", tokens[i].params.decimals);
            console.log("    Price Per Unit: %d", tokens[i].params.pricePerUnit);
            console.log("    Volatility Threshold: %d", tokens[i].params.volatilityThreshold);
        }
    }

    function deployInfrastructure() internal {
        console.log("\n=== Deploying Infrastructure ===");
        console.log("Deploying ProxyAdmin...");
        proxyAdminDeployBlock = block.number;
        proxyAdminDeployTimestamp = block.timestamp;
        proxyAdmin = new ProxyAdmin(msg.sender);
        console.log("ProxyAdmin deployed at: %s", address(proxyAdmin));
    }

    function deployImplementations() internal {
        console.log("\n=== Deploying Implementation Contracts ===");
        
        console.log("Deploying TokenRegistryOracle implementation...");
        tokenRegistryOracleImplDeployBlock = block.number;
        tokenRegistryOracleImplDeployTimestamp = block.timestamp;
        tokenRegistryOracleImpl = new TokenRegistryOracle();
        console.log("TokenRegistryOracle implementation deployed at: %s", address(tokenRegistryOracleImpl));
        
        console.log("Deploying LiquidToken implementation...");
        liquidTokenImplDeployBlock = block.number;
        liquidTokenImplDeployTimestamp = block.timestamp;
        liquidTokenImpl = new LiquidToken();
        console.log("LiquidToken implementation deployed at: %s", address(liquidTokenImpl));
        
        console.log("Deploying LiquidTokenManager implementation...");
        liquidTokenManagerImplDeployBlock = block.number;
        liquidTokenManagerImplDeployTimestamp = block.timestamp;
        liquidTokenManagerImpl = new LiquidTokenManager();
        console.log("LiquidTokenManager implementation deployed at: %s", address(liquidTokenManagerImpl));
        
        console.log("Deploying StakerNodeCoordinator implementation...");
        stakerNodeCoordinatorImplDeployBlock = block.number;
        stakerNodeCoordinatorImplDeployTimestamp = block.timestamp;
        stakerNodeCoordinatorImpl = new StakerNodeCoordinator();
        console.log("StakerNodeCoordinator implementation deployed at: %s", address(stakerNodeCoordinatorImpl));
        
        console.log("Deploying StakerNode implementation...");
        stakerNodeImplDeployBlock = block.number;
        stakerNodeImplDeployTimestamp = block.timestamp;
        stakerNodeImpl = new StakerNode();
        console.log("StakerNode implementation deployed at: %s", address(stakerNodeImpl));
    }

  function deployProxies() internal {
        console.log("\n=== Deploying Proxy Contracts ===");
        
        console.log("Deploying TokenRegistryOracle proxy...");
        tokenRegistryOracleProxyDeployBlock = block.number;
        tokenRegistryOracleProxyDeployTimestamp = block.timestamp;
        tokenRegistryOracle = TokenRegistryOracle(
            address(new TransparentUpgradeableProxy(
                address(tokenRegistryOracleImpl),
                address(proxyAdmin),
                ""
            ))
        );
        console.log("TokenRegistryOracle proxy deployed at: %s", address(tokenRegistryOracle));

        console.log("Deploying LiquidTokenManager proxy...");
        liquidTokenManagerProxyDeployBlock = block.number;
        liquidTokenManagerProxyDeployTimestamp = block.timestamp;
        liquidTokenManager = LiquidTokenManager(
            address(new TransparentUpgradeableProxy(
                address(liquidTokenManagerImpl),
                address(proxyAdmin),
                ""
            ))
        );
        console.log("LiquidTokenManager proxy deployed at: %s", address(liquidTokenManager));

        console.log("Deploying StakerNodeCoordinator proxy...");
        stakerNodeCoordinatorProxyDeployBlock = block.number;
        stakerNodeCoordinatorProxyDeployTimestamp = block.timestamp;
        stakerNodeCoordinator = StakerNodeCoordinator(
            address(new TransparentUpgradeableProxy(
                address(stakerNodeCoordinatorImpl),
                address(proxyAdmin),
                ""
            ))
        );
        console.log("StakerNodeCoordinator proxy deployed at: %s", address(stakerNodeCoordinator));

        console.log("Deploying LiquidToken proxy...");
        liquidTokenProxyDeployBlock = block.number;
        liquidTokenProxyDeployTimestamp = block.timestamp;
        liquidToken = LiquidToken(
            address(new TransparentUpgradeableProxy(
                address(liquidTokenImpl),
                address(proxyAdmin),
                ""
            ))
        );
        console.log("LiquidToken proxy deployed at: %s", address(liquidToken));
    }

    function initializeProxies() internal {
        console.log("\n=== Initializing Contracts ===");
        _initializeTokenRegistryOracle();
        _initializeLiquidTokenManager();
        _initializeStakerNodeCoordinator();
        _initializeLiquidToken();
    }

    function _initializeTokenRegistryOracle() internal {
        console.log("Initializing TokenRegistryOracle...");
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
        console.log("Initializing LiquidTokenManager...");
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
            
            console.log("  Token %d: %s, Strategy: %s", i, tokens[i].addresses.token, tokens[i].addresses.strategy);
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
                strategyController: strategyController,
                priceUpdater: address(tokenRegistryOracle)
            })
        );
    }

    function _initializeStakerNodeCoordinator() internal {
        console.log("Initializing StakerNodeCoordinator...");
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
        console.log("Initializing LiquidToken...");
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
    
    function transferOwnership() internal {
        console.log("\n=== Transferring Ownership ===");
        console.log("Transferring ProxyAdmin ownership to: %s", admin);
        proxyAdmin.transferOwnership(admin);
        require(proxyAdmin.owner() == admin, "Proxy admin ownership transfer failed");
    }

    function verifyDeployment() internal view {
        _verifyProxyImplementations();
        _verifyContractConnections();
        _verifyRoles();
    }

    function _verifyProxyImplementations() internal view {
        console.log("\n=== Verifying Proxy Implementations ===");
        
        // Get implementation address through TransparentUpgradeableProxy's storage slot
        address liquidTokenProxyImpl = _getImplementationFromProxy(address(liquidToken));
        address liquidTokenManagerProxyImpl = _getImplementationFromProxy(address(liquidTokenManager));
        address tokenRegistryOracleProxyImpl = _getImplementationFromProxy(address(tokenRegistryOracle));
        address stakerNodeCoordinatorProxyImpl = _getImplementationFromProxy(address(stakerNodeCoordinator));
        
        // Verify implementations
        bool liquidTokenImplMatch = liquidTokenProxyImpl == address(liquidTokenImpl);
        console.log("LiquidToken implementation match: %s", liquidTokenImplMatch ? "Yes" : "No");
        console.log("  Expected: %s", address(liquidTokenImpl));
        console.log("  Actual:   %s", liquidTokenProxyImpl);
        require(liquidTokenImplMatch, "LiquidToken proxy implementation mismatch");
        
        // Verify liquid token manager implementation
        bool liquidTokenManagerImplMatch = liquidTokenManagerProxyImpl == address(liquidTokenManagerImpl);
        console.log("LiquidTokenManager implementation match: %s", liquidTokenManagerImplMatch ? "Yes" : "No");
        console.log("  Expected: %s", address(liquidTokenManagerImpl));
        console.log("  Actual:   %s", liquidTokenManagerProxyImpl);
        require(liquidTokenManagerImplMatch, "LiquidTokenManager proxy implementation mismatch");
        
        // Verify token registry oracle implementation
        bool tokenRegistryOracleImplMatch = tokenRegistryOracleProxyImpl == address(tokenRegistryOracleImpl);
        console.log("TokenRegistryOracle implementation match: %s", tokenRegistryOracleImplMatch ? "Yes" : "No");
        console.log("  Expected: %s", address(tokenRegistryOracleImpl));
        console.log("  Actual:   %s", tokenRegistryOracleProxyImpl);
        require(tokenRegistryOracleImplMatch, "TokenRegistryOracle proxy implementation mismatch");
        
        // Verify staker node coordinator implementation
        bool stakerNodeCoordinatorImplMatch = stakerNodeCoordinatorProxyImpl == address(stakerNodeCoordinatorImpl);
        console.log("StakerNodeCoordinator implementation match: %s", stakerNodeCoordinatorImplMatch ? "Yes" : "No");
        console.log("  Expected: %s", address(stakerNodeCoordinatorImpl));
        console.log("  Actual:   %s", stakerNodeCoordinatorProxyImpl);
        require(stakerNodeCoordinatorImplMatch, "StakerNodeCoordinator proxy implementation mismatch");
    }

    function _verifyContractConnections() internal view {
        console.log("\n=== Verifying Contract Connections ===");
        
        // LiquidToken
        bool liquidTokenManagerCheck = address(liquidToken.liquidTokenManager()) == address(liquidTokenManager);
        console.log("LiquidToken -> LiquidTokenManager: %s", liquidTokenManagerCheck ? "Valid" : "Invalid");
        require(liquidTokenManagerCheck, "LiquidToken: wrong liquidTokenManager");

        // LiquidTokenManager
        bool liquidTokenCheck = address(liquidTokenManager.liquidToken()) == address(liquidToken);
        console.log("LiquidTokenManager -> LiquidToken: %s", liquidTokenCheck ? "Valid" : "Invalid");
        require(liquidTokenCheck, "LiquidTokenManager: wrong liquidToken");
        
        bool strategyManagerCheck = address(liquidTokenManager.strategyManager()) == address(strategyManager);
        console.log("LiquidTokenManager -> StrategyManager: %s", strategyManagerCheck ? "Valid" : "Invalid");
        require(strategyManagerCheck, "LiquidTokenManager: wrong strategyManager");
        
        bool delegationManagerCheck = address(liquidTokenManager.delegationManager()) == address(delegationManager);
        console.log("LiquidTokenManager -> DelegationManager: %s", delegationManagerCheck ? "Valid" : "Invalid");
        require(delegationManagerCheck, "LiquidTokenManager: wrong delegationManager");
        
        bool stakerNodeCoordinatorCheck = address(liquidTokenManager.stakerNodeCoordinator()) == address(stakerNodeCoordinator);
        console.log("LiquidTokenManager -> StakerNodeCoordinator: %s", stakerNodeCoordinatorCheck ? "Valid" : "Invalid");
        require(stakerNodeCoordinatorCheck, "LiquidTokenManager: wrong stakerNodeCoordinator");

        // StakerNodeCoordinator
        bool liquidTokenManagerCheckFromCoordinator = address(stakerNodeCoordinator.liquidTokenManager()) == address(liquidTokenManager);
        console.log("StakerNodeCoordinator -> LiquidTokenManager: %s", liquidTokenManagerCheckFromCoordinator ? "Valid" : "Invalid");
        require(liquidTokenManagerCheckFromCoordinator, "StakerNodeCoordinator: wrong liquidTokenManager");
        
        bool strategyManagerCheckFromCoordinator = address(stakerNodeCoordinator.strategyManager()) == address(strategyManager);
        console.log("StakerNodeCoordinator -> StrategyManager: %s", strategyManagerCheckFromCoordinator ? "Valid" : "Invalid");
        require(strategyManagerCheckFromCoordinator, "StakerNodeCoordinator: wrong strategyManager");
        
        bool delegationManagerCheckFromCoordinator = address(stakerNodeCoordinator.delegationManager()) == address(delegationManager);
        console.log("StakerNodeCoordinator -> DelegationManager: %s", delegationManagerCheckFromCoordinator ? "Valid" : "Invalid");
        require(delegationManagerCheckFromCoordinator, "StakerNodeCoordinator: wrong delegationManager");
        
        bool stakerNodeImplCheck = address(stakerNodeCoordinator.upgradeableBeacon().implementation()) == address(stakerNodeImpl);
        console.log("StakerNodeCoordinator -> StakerNodeImpl: %s", stakerNodeImplCheck ? "Valid" : "Invalid");
        require(stakerNodeImplCheck, "StakerNodeCoordinator: wrong stakerNodeImplementation");

        // TokenRegistryOracle
        bool liquidTokenManagerCheckFromOracle = address(tokenRegistryOracle.liquidTokenManager()) == address(liquidTokenManager);
        console.log("TokenRegistryOracle -> LiquidTokenManager: %s", liquidTokenManagerCheckFromOracle ? "Valid" : "Invalid");
        require(liquidTokenManagerCheckFromOracle, "TokenRegistryOracle: wrong liquidTokenManager");

        // Assets and strategies
        IERC20[] memory registeredTokens = liquidTokenManager.getSupportedTokens();
        bool tokenCountMatch = registeredTokens.length == tokens.length;
        console.log("Token count match: %s (%d registered, %d expected)", tokenCountMatch ? "Yes" : "No", registeredTokens.length, tokens.length);
        require(tokenCountMatch, "LiquidTokenManager: wrong number of registered tokens");

        // Verify each token and its strategy
        console.log("\nVerifying individual token configurations:");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 configToken = IERC20(tokens[i].addresses.token);
            ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(configToken);
            
            bool decimalsMatch = tokenInfo.decimals == uint8(tokens[i].params.decimals);
            bool priceMatch = tokenInfo.pricePerUnit == tokens[i].params.pricePerUnit;
            bool thresholdMatch = tokenInfo.volatilityThreshold == tokens[i].params.volatilityThreshold;
            
            console.log("Token %d (%s):", i, tokens[i].addresses.token);
            console.log("  Decimals match: %s", decimalsMatch ? "Yes" : "No");
            console.log("  Price match: %s", priceMatch ? "Yes" : "No");
            console.log("  Threshold match: %s", thresholdMatch ? "Yes" : "No");
            
            require(decimalsMatch, "LiquidTokenManager: wrong token decimals");
            require(priceMatch, "LiquidTokenManager: wrong token price");
            require(thresholdMatch, "LiquidTokenManager: wrong volatility threshold");

            IStrategy registeredStrategy = liquidTokenManager.getTokenStrategy(configToken);
            bool strategyMatch = address(registeredStrategy) == tokens[i].addresses.strategy;
            console.log("  Strategy match: %s", strategyMatch ? "Yes" : "No");
            require(strategyMatch, "LiquidTokenManager: wrong strategy address");

            // Verify token is in supported tokens list
            bool tokenFound = false;
            for (uint256 j = 0; j < registeredTokens.length; j++) {
                if (address(registeredTokens[j]) == address(configToken)) {
                    tokenFound = true;
                    break;
                }
            }
            console.log("  Token in supported list: %s", tokenFound ? "Yes" : "No");
            require(tokenFound, "LiquidTokenManager: token not in supported list");
        }
    }

    function _verifyRoles() internal view {
        console.log("\n=== Verifying Role Assignments ===");
        
        // Default admin role constant
        bytes32 adminRole = 0x00;
        
        // LiquidToken roles
        console.log("\nLiquidToken roles:");
        bool hasLTAdminRole = liquidToken.hasRole(adminRole, admin);
        bool hasLTPauserRole = liquidToken.hasRole(liquidToken.PAUSER_ROLE(), pauser);
        
        console.log("  Admin role assigned to %s: %s", admin, hasLTAdminRole ? "Yes" : "No");
        console.log("  Pauser role assigned to %s: %s", pauser, hasLTPauserRole ? "Yes" : "No");
        
        require(hasLTAdminRole, "Admin role not assigned in LiquidToken");
        require(hasLTPauserRole, "Pauser role not assigned in LiquidToken");
        
        // LiquidTokenManager roles
        console.log("\nLiquidTokenManager roles:");
        bool hasLTMAdminRole = liquidTokenManager.hasRole(adminRole, admin);
        bool hasLTMStrategyControllerRole = liquidTokenManager.hasRole(
            liquidTokenManager.STRATEGY_CONTROLLER_ROLE(), 
            strategyController
        );
        bool hasLTMPriceUpdaterRole = liquidTokenManager.hasRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(), 
            address(tokenRegistryOracle)
        );
        
        console.log("  Admin role assigned to %s: %s", admin, hasLTMAdminRole ? "Yes" : "No");
        console.log("  Strategy Controller role assigned to %s: %s", strategyController, hasLTMStrategyControllerRole ? "Yes" : "No");
        console.log("  Price Updater role assigned to %s: %s", address(tokenRegistryOracle), hasLTMPriceUpdaterRole ? "Yes" : "No");
        
        require(hasLTMAdminRole, "Admin role not assigned in LiquidTokenManager");
        require(hasLTMStrategyControllerRole, "Strategy Controller role not assigned in LiquidTokenManager");
        require(hasLTMPriceUpdaterRole, "Price Updater role not assigned in LiquidTokenManager");
        
        // StakerNodeCoordinator roles
        console.log("\nStakerNodeCoordinator roles:");
        bool hasSNCAdminRole = stakerNodeCoordinator.hasRole(adminRole, admin);
        bool hasSNCCreatorRole = stakerNodeCoordinator.hasRole(
            stakerNodeCoordinator.STAKER_NODE_CREATOR_ROLE(), 
            admin
        );
        bool hasSNCDelegatorRole = stakerNodeCoordinator.hasRole(
            stakerNodeCoordinator.STAKER_NODES_DELEGATOR_ROLE(), 
            address(liquidTokenManager)
        );
        
        console.log("  Admin role assigned to %s: %s", admin, hasSNCAdminRole ? "Yes" : "No");
        console.log("  Staker Node Creator role assigned to %s: %s", admin, hasSNCCreatorRole ? "Yes" : "No");
        console.log("  Staker Nodes Delegator role assigned to %s: %s", address(liquidTokenManager), hasSNCDelegatorRole ? "Yes" : "No");
        
        require(hasSNCAdminRole, "Admin role not assigned in StakerNodeCoordinator");
        require(hasSNCCreatorRole, "Staker Node Creator role not assigned in StakerNodeCoordinator");
        require(hasSNCDelegatorRole, "Staker Nodes Delegator role not assigned in StakerNodeCoordinator");
        
        // TokenRegistryOracle roles
        console.log("\nTokenRegistryOracle roles:");
        bool hasTROAdminRole = tokenRegistryOracle.hasRole(adminRole, admin);
        bool hasTRORateUpdaterRole = tokenRegistryOracle.hasRole(
            tokenRegistryOracle.RATE_UPDATER_ROLE(), 
            priceUpdater
        );
        
        console.log("  Admin role assigned to %s: %s", admin, hasTROAdminRole ? "Yes" : "No");
        console.log("  Rate Updater role assigned to %s: %s", priceUpdater, hasTRORateUpdaterRole ? "Yes" : "No");
        
        require(hasTROAdminRole, "Admin role not assigned in TokenRegistryOracle");
        require(hasTRORateUpdaterRole, "Rate Updater role not assigned in TokenRegistryOracle");
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
        vm.serializeUint(parent_object, "deploymentTimestamp", block.timestamp * 1000); // Converting to milliseconds
        
        // Contract deployments section
        string memory contractDeployments = "contractDeployments";
        
        // Implementation contracts
        string memory implementation = "implementation";
        
        // LiquidToken implementation
        string memory liquidTokenImpl_obj = "liquidToken";
        vm.serializeAddress(liquidTokenImpl_obj, "address", address(liquidTokenImpl));
        vm.serializeUint(liquidTokenImpl_obj, "block", liquidTokenImplDeployBlock);
        string memory liquidTokenImpl_output = vm.serializeUint(liquidTokenImpl_obj, "timestamp", liquidTokenImplDeployTimestamp * 1000);
        
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
        vm.serializeString(implementation, "liquidToken", liquidTokenImpl_output);
        vm.serializeString(implementation, "liquidTokenManager", liquidTokenManagerImpl_output);
        vm.serializeString(implementation, "stakerNodeCoordinator", stakerNodeCoordinatorImpl_output);
        vm.serializeString(implementation, "stakerNode", stakerNodeImpl_output);
        string memory implementation_output = vm.serializeString(implementation, "tokenRegistryOracle", tokenRegistryOracleImpl_output);
        
        // Proxy contracts
        string memory proxy = "proxy";
        
        // LiquidToken proxy
        string memory liquidToken_obj = "liquidToken";
        vm.serializeAddress(liquidToken_obj, "address", address(liquidToken));
        vm.serializeUint(liquidToken_obj, "block", liquidTokenProxyDeployBlock);
        string memory liquidToken_output = vm.serializeUint(liquidToken_obj, "timestamp", liquidTokenProxyDeployTimestamp * 1000);
        
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
        vm.serializeString(proxy, "liquidToken", liquidToken_output);
        vm.serializeString(proxy, "liquidTokenManager", liquidTokenManager_output);
        vm.serializeString(proxy, "stakerNodeCoordinator", stakerNodeCoordinator_output);
        string memory proxy_output = vm.serializeString(proxy, "tokenRegistryOracle", tokenRegistryOracle_output);
        
        // Combine implementation and proxy under contractDeployments
        vm.serializeString(contractDeployments, "implementation", implementation_output);
        string memory contractDeployments_output = vm.serializeString(contractDeployments, "proxy", proxy_output);
        
        // Initialization timestamps
        string memory initialization = "initialization";
        vm.serializeUint(initialization, "liquidTokenManagerBlock", liquidTokenManagerInitBlock);
        vm.serializeUint(initialization, "liquidTokenManagerTimestamp", liquidTokenManagerInitTimestamp * 1000);
        vm.serializeUint(initialization, "stakerNodeCoordinatorBlock", stakerNodeCoordinatorInitBlock);
        vm.serializeUint(initialization, "stakerNodeCoordinatorTimestamp", stakerNodeCoordinatorInitTimestamp * 1000);
        vm.serializeUint(initialization, "tokenRegistryOracleBlock", tokenRegistryOracleInitBlock);
        vm.serializeUint(initialization, "tokenRegistryOracleTimestamp", tokenRegistryOracleInitTimestamp * 1000);
        vm.serializeUint(initialization, "liquidTokenBlock", liquidTokenInitBlock);
        string memory initialization_output = vm.serializeUint(initialization, "liquidTokenTimestamp", liquidTokenInitTimestamp * 1000);
        
        // Roles section
        string memory roles = "roles";
        vm.serializeAddress(roles, "deployer", msg.sender);
        vm.serializeAddress(roles, "proxyAdmin", address(proxyAdmin));
        vm.serializeAddress(roles, "admin", admin);
        vm.serializeAddress(roles, "pauser", pauser);
        vm.serializeAddress(roles, "priceUpdater", priceUpdater);
        string memory roles_output = vm.serializeAddress(roles, "strategyController", strategyController);
        
        // Tokens section
        string memory tokens_array = "tokens";
        
        // Process each token
        for (uint256 i = 0; i < tokens.length; ++i) {
            // Create an object for each token
            string memory token_obj = string.concat("token", vm.toString(i));
            vm.serializeAddress(token_obj, "address", tokens[i].addresses.token);
            vm.serializeAddress(token_obj, "strategy", tokens[i].addresses.strategy);
            vm.serializeUint(token_obj, "decimals", tokens[i].params.decimals);
            vm.serializeUint(token_obj, "pricePerUnit", tokens[i].params.pricePerUnit);
            string memory token_output = vm.serializeUint(token_obj, "volatilityThreshold", tokens[i].params.volatilityThreshold);
            
            // Add token object to the array
            if (i < tokens.length - 1) {
                vm.serializeString(tokens_array, vm.toString(i), token_output);
            } else {
                tokens_array = vm.serializeString(tokens_array, vm.toString(i), token_output);
            }
        }
        
        // Combine all sections into the parent object
        vm.serializeString(parent_object, "contractDeployments", contractDeployments_output);
        vm.serializeString(parent_object, "initialization", initialization_output);
        vm.serializeString(parent_object, "roles", roles_output);
        string memory finalJson = vm.serializeString(parent_object, "tokens", tokens_array);
        
        // Write the final JSON to output file
        vm.writeJson(finalJson, OUTPUT_PATH);
        console.log("Deployment data written to: %s", OUTPUT_PATH);
    }

    // Helper function to get implementation from proxy
    function _getImplementationFromProxy(address proxy) internal view returns (address) {
        // Implementation slot for TransparentUpgradeableProxy (EIP-1967)
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        
        // Use VM cheatcode to read storage at the implementation slot
        bytes32 data = vm.load(proxy, implementationSlot);
        return address(uint160(uint256(data)));
    }
    
    /**
     * @notice Pushes deployment data to GitHub repository
     * @dev This function is called after verification to push deployment data to GitHub
     */
    function pushToGitHub() internal {
        // Check if GitHub integration is enabled
        bool enableGitHubIntegration = vm.envOr("ENABLE_GITHUB_INTEGRATION", false);
        if (!enableGitHubIntegration) {
            console.log("GitHub integration not enabled. Set ENABLE_GITHUB_INTEGRATION=true to enable.");
            return;
        }
        
        // Get GitHub configuration from environment variables
        string memory githubToken = vm.envString("GITHUB_TOKEN");
        string memory githubRepo = vm.envString("GITHUB_REPO");
        string memory githubBranch = vm.envOr("GITHUB_BRANCH", string("lat-deployments-test"));
        
        console.log("\n=== Pushing Deployment Data to GitHub ===");
        console.log("Repository: %s", githubRepo);
        console.log("Branch: %s", githubBranch);
        
        // Read the deployment data from the output file
        string memory deploymentData = vm.readFile(OUTPUT_PATH);
        
        // Generate the path in the repository (same as local path)
        string memory network = vm.envOr("NETWORK", string("local"));
        string memory githubPath = string.concat("script/outputs/", network, "/", network, "_deployment_data.json");
        
        // Construct the GitHub API URL
        string memory apiUrl = string.concat(
            "https://api.github.com/repos/", 
            githubRepo, 
            "/contents/", 
            githubPath
        );
        
        // Prepare the curl command
        string[] memory curlCommand = new string[](11);
        curlCommand[0] = "curl";
        curlCommand[1] = "-X";
        curlCommand[2] = "PUT";
        curlCommand[3] = apiUrl;
        curlCommand[4] = "-H";
        curlCommand[5] = string.concat("Authorization: token ", githubToken);
        curlCommand[6] = "-H";
        curlCommand[7] = "Accept: application/vnd.github.v3+json";
        curlCommand[8] = "-d";
        
        // For GitHub API, we need to encode the content in base64
        // Since we can't use vm.encodeBase64 directly, we'll use a simpler approach
        // that works for our JSON deployment data
        
        // First, let's create a shell script to handle the base64 encoding and GitHub API call
        string memory scriptPath = "script/github_push.sh";
        string memory scriptContent = string.concat(
            "#!/bin/bash\n",
            "# This script pushes deployment data to GitHub\n",
            "GITHUB_TOKEN=\"", githubToken, "\"\n",
            "GITHUB_REPO=\"", githubRepo, "\"\n",
            "GITHUB_BRANCH=\"", githubBranch, "\"\n",
            "GITHUB_PATH=\"script/outputs/", network, "/", network, "_deployment_data.json\"\n",
            "DEPLOYMENT_DATA_PATH=\"", OUTPUT_PATH, "\"\n\n",
            "# Encode the content to base64\n",
            "CONTENT=$(base64 -i $DEPLOYMENT_DATA_PATH)\n\n",
            "# Create the request body\n",
            "REQUEST_BODY=\"{\\\"message\\\":\\\"Update deployment data for ", network, "\\\",\\\"branch\\\":\\\"$GITHUB_BRANCH\\\",\\\"content\\\":\\\"$CONTENT\\\"}\"\n\n",
            "# Make the API call\n",
            "curl -X PUT \"https://api.github.com/repos/$GITHUB_REPO/contents/$GITHUB_PATH\" ",
            "-H \"Authorization: token $GITHUB_TOKEN\" ",
            "-H \"Accept: application/vnd.github.v3+json\" ",
            "-d \"$REQUEST_BODY\" ",
            "--silent"
        );
        
        // Write the script to a file
        vm.writeFile(scriptPath, scriptContent);
        
        // Make the script executable
        string[] memory chmodCommand = new string[](3);
        chmodCommand[0] = "chmod";
        chmodCommand[1] = "+x";
        chmodCommand[2] = scriptPath;
        vm.ffi(chmodCommand);
        
        // Execute the script
        string[] memory execCommand = new string[](1);
        execCommand[0] = scriptPath;
        bytes memory result = vm.ffi(execCommand);
        
        // Check if the script executed successfully
        if (result.length > 0) {
            console.log("Successfully pushed deployment data to GitHub");
            console.log("Path: script/outputs/%s/%s_deployment_data.json", network, network);
        } else {
            console.log("Failed to push deployment data to GitHub");
            console.log("Check your GitHub token and repository settings");
        }
    }
}