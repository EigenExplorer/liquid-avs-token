// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenRegistryOracle} from "../../src/utils/TokenRegistryOracle.sol";
import {ITokenRegistryOracle} from "../../src/interfaces/ITokenRegistryOracle.sol";
import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../../src/interfaces/ILiquidTokenManager.sol";
import {LiquidToken} from "../../src/core/LiquidToken.sol";
import {ILiquidToken} from "../../src/interfaces/ILiquidToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IStakerNodeCoordinator} from "../../src/interfaces/IStakerNodeCoordinator.sol";

contract DeployPriceUpdater is Script {
    struct EcosystemAddresses {
        address token;
        address strategy;
        address oracle;
        address manager;
        address liquidToken;
    }

    function run(string memory outputPath) external {
        // Read parameters
        string memory paramsPath = string.concat(vm.projectRoot(), "/script/inputs/", outputPath);
        string memory paramsJson = vm.readFile(paramsPath);
        
        // Parse parameters
        address adminAddress = vm.parseJsonAddress(paramsJson, ".admin");
        address strategyManager = vm.parseJsonAddress(paramsJson, ".strategyManager");
        address delegationManager = vm.parseJsonAddress(paramsJson, ".delegationManager");
        address stakerNodeCoordinator = vm.parseJsonAddress(paramsJson, ".stakerNodeCoordinator");
        
        // Parse token array
        string[] memory tokenKeys = vm.parseJsonStringArray(paramsJson, ".tokenKeys");
        address[] memory tokens = new address[](tokenKeys.length);
        address[] memory strategies = new address[](tokenKeys.length);
        
        for (uint256 i = 0; i < tokenKeys.length; i++) {
            tokens[i] = vm.parseJsonAddress(paramsJson, string.concat(".tokens.", tokenKeys[i], ".address"));
            strategies[i] = vm.parseJsonAddress(paramsJson, string.concat(".tokens.", tokenKeys[i], ".strategy"));
        }
        
        vm.startBroadcast();

        // Deploy ecosystem for each token
        EcosystemAddresses[] memory ecosystems = new EcosystemAddresses[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            ecosystems[i] = deployTokenEcosystem(
                getTokenSymbol(tokens[i]),
                getTokenSymbol(tokens[i]),
                getTokenDecimals(tokens[i]),
                1e18, // Initial price (1:1 for simplicity)
                adminAddress,
                tokens[i],
                strategies[i],
                strategyManager,
                delegationManager,
                stakerNodeCoordinator
            );
        }

        vm.stopBroadcast();

        // Write output
        string memory network = vm.envOr("NETWORK", string("local"));
        string memory outputDir = string(abi.encodePacked(
            vm.projectRoot(),
            "/script/outputs/",
            network,
            "/"
        ));
        vm.createDir(outputDir, true);

        vm.writeJson(
            generateAddressesJson(ecosystems),
            string(abi.encodePacked(outputDir, "price_updater_addresses.json"))
        );
    }

    function getTokenSymbol(address tokenAddress) internal view returns (string memory) {
        (bool success, bytes memory data) = tokenAddress.staticcall(
            abi.encodeWithSignature("symbol()")
        );
        require(success, "Symbol call failed");
        return abi.decode(data, (string));
    }

    function getTokenDecimals(address tokenAddress) internal view returns (uint8) {
        (bool success, bytes memory data) = tokenAddress.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        require(success, "Decimals call failed");
        return abi.decode(data, (uint8));
    }

    function deployTokenEcosystem(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 initialPrice,
        address initialOwner,
        address tokenAddress,
        address strategyAddress,
        address strategyManagerAddress,
        address delegationManagerAddress,
        address stakerNodeCoordinatorAddress
    ) internal returns (EcosystemAddresses memory) {
        // Use existing token and strategy
        IERC20 token = IERC20(tokenAddress);
        IStrategy strategy = IStrategy(strategyAddress);

        // Deploy implementations
        TokenRegistryOracle oracleImpl = new TokenRegistryOracle();
        LiquidTokenManager managerImpl = new LiquidTokenManager();
        LiquidToken liquidTokenImpl = new LiquidToken();

        // Deploy proxies
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            initialOwner,
            ""
        );
        TransparentUpgradeableProxy managerProxy = new TransparentUpgradeableProxy(
            address(managerImpl),
            initialOwner,
            ""
        );
        TransparentUpgradeableProxy liquidTokenProxy = new TransparentUpgradeableProxy(
            address(liquidTokenImpl),
            initialOwner,
            ""
        );

        // Initialize Oracle
        ITokenRegistryOracle.Init memory oracleInit = ITokenRegistryOracle.Init({
            initialOwner: initialOwner,
            priceUpdater: initialOwner,
            liquidTokenManager: ILiquidTokenManager(address(managerProxy))
        });
        TokenRegistryOracle(address(oracleProxy)).initialize(oracleInit);

        // Initialize Manager
        IERC20[] memory assets = new IERC20[](1);
        ILiquidTokenManager.TokenInfo[] memory tokenInfo = new ILiquidTokenManager.TokenInfo[](1);
        IStrategy[] memory strategies = new IStrategy[](1);

        assets[0] = token;
        tokenInfo[0] = ILiquidTokenManager.TokenInfo(
            tokenDecimals,
            initialPrice,
            0 // volatilityThreshold
        );
        strategies[0] = strategy;

        ILiquidTokenManager.Init memory managerInit = ILiquidTokenManager.Init({
            assets: assets,
            tokenInfo: tokenInfo,
            strategies: strategies,
            liquidToken: ILiquidToken(address(liquidTokenProxy)),
            strategyManager: IStrategyManager(strategyManagerAddress),
            delegationManager: IDelegationManager(delegationManagerAddress),
            stakerNodeCoordinator: IStakerNodeCoordinator(stakerNodeCoordinatorAddress),
            initialOwner: initialOwner,
            strategyController: initialOwner,
            priceUpdater: address(oracleProxy)
        });
        LiquidTokenManager(address(managerProxy)).initialize(managerInit);

        // Initialize LiquidToken
        ILiquidToken.Init memory tokenInit = ILiquidToken.Init({
            name: string(abi.encodePacked("Liquid ", tokenName)),
            symbol: string(abi.encodePacked("L", tokenSymbol)),
            initialOwner: initialOwner,
            pauser: initialOwner,
            liquidTokenManager: ILiquidTokenManager(address(managerProxy))
        });
        LiquidToken(address(liquidTokenProxy)).initialize(tokenInit);

        return EcosystemAddresses(
            address(token),
            address(strategy),
            address(oracleProxy),
            address(managerProxy),
            address(liquidTokenProxy)
        );
    }

    function generateAddressesJson(EcosystemAddresses[] memory ecosystems) internal pure returns (string memory) {
        string memory json = '{"contracts":{';
        
        for (uint256 i = 0; i < ecosystems.length; i++) {
            string memory prefix = i == 0 ? "" : ",";
            json = string(abi.encodePacked(
                json,
                prefix,
                '"token', vm.toString(i), '":"', vm.toString(ecosystems[i].token), '",',
                '"liquidToken', vm.toString(i), '":"', vm.toString(ecosystems[i].liquidToken), '",',
                '"oracle', vm.toString(i), '":"', vm.toString(ecosystems[i].oracle), '",',
                '"manager', vm.toString(i), '":"', vm.toString(ecosystems[i].manager), '",',
                '"strategy', vm.toString(i), '":"', vm.toString(ecosystems[i].strategy), '"'
            ));
        }
        
        json = string(abi.encodePacked(json, '}}'));
        return json;
    }
}