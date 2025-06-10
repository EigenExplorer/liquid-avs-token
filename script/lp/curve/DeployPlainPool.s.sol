// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script script/lp/curve/DeployPlainPool.s.sol:DeployPlainPool --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string)" -- "<FILENAME_FROM_CONFIGS_FOLDER>.json" -vvvv

interface ICurveFactory {
    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[4] calldata _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _asset_type,
        uint256 _implementation_idx
    ) external returns (address);
}

contract DeployPlainPool is Script {
    using stdJson for string;

    address constant CURVE_FACTORY = 0xB9fC157394Af804a3578134A6585C0dc9cc990d4;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct PlainPoolConfig {
        string name;
        string symbol;
        address token0;
        address token1;
        uint256 A;
        uint256 fee;
        uint256 assetType;
        uint256 implementationIdx;
    }

    function run(string memory configFileName) external returns (address pool) {
        // Get pool config
        PlainPoolConfig memory config = _loadConfig(configFileName);

        // Deploy pool
        vm.startBroadcast();
        pool = _deployPool(config);
        vm.stopBroadcast();

        // Write to output file
        _saveDeploymentResult(configFileName, pool);

        return pool;
    }

    function _loadConfig(string memory configFileName) internal view returns (PlainPoolConfig memory config) {
        string memory configPath = string.concat("./configs/", configFileName, ".json");
        string memory json = vm.readFile(configPath);

        config.name = json.readString(".name");
        config.symbol = json.readString(".symbol");
        config.token0 = json.readAddress(".token0");
        config.token1 = WETH; // Default to WETH
        config.A = json.readUint(".A");
        config.fee = json.readUint(".fee");
        config.assetType = 0; // ETH
        config.implementationIdx = 0;

        console.log("[LP][Curve][Deploy] Deploying Plain Pool for ", configFileName);
        console.log("[LP][Curve][Deploy] Pool Name:", config.name);
        console.log("[LP][Curve][Deploy] Pool Symbol:", config.symbol);
        console.log("[LP][Curve][Deploy] Token 0:", config.token0);
        console.log("[LP][Curve][Deploy] Token 1:", config.token1);
        console.log("[LP][Curve][Deploy] A Parameter:", config.A);
        console.log("[LP][Curve][Deploy] Fee:", config.fee);
    }

    function _deployPool(PlainPoolConfig memory config) internal returns (address pool) {
        address[4] memory coins = [config.token0, config.token1, address(0), address(0)];

        pool = ICurveFactory(CURVE_FACTORY).deploy_plain_pool(
            config.name,
            config.symbol,
            coins,
            config.A,
            config.fee,
            config.assetType,
            config.implementationIdx
        );

        console.log("[LP][Curve][Deploy] Plain Pool deployed at: ", pool);

        return pool;
    }

    function _saveDeploymentResult(string memory configFileName, address pool) internal {
        string memory resultPath = string.concat("./outputs/", configFileName, "-result.json");
        string memory result = string.concat(
            '{"pool":"',
            vm.toString(pool),
            '","timestamp":',
            vm.toString(block.timestamp),
            ',"deployer":"',
            vm.toString(msg.sender),
            '"}'
        );
        vm.writeFile(resultPath, result);
        console.log("[LP][Curve][Deploy] Output saved to:", resultPath);
    }
}
