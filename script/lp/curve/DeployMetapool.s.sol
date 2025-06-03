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
// forge script script/lp/curve/DeployMetapool.s.sol:DeployMetapool --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string)" -- "<FILENAME_FROM_CONFIGS_FOLDER>.json" -vvvv

interface ICurveFactory {
    function deploy_metapool(
        address _base_pool,
        string calldata _name,
        string calldata _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee,
        uint256 _implementation_idx
    ) external returns (address);
}

contract DeployMetapool is Script {
    using stdJson for string;

    address constant CURVE_FACTORY = 0xB9fC157394Af804a3578134A6585C0dc9cc990d4;
    address constant SBTC_POOL = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714;

    struct MetapoolConfig {
        address basePool;
        string name;
        string symbol;
        address token;
        uint256 A;
        uint256 fee;
        uint256 implementationIdx;
    }

    function run(
        string memory configFileName
    ) external returns (address metapool) {
        // Get pool config
        MetapoolConfig memory config = _loadConfig(configFileName);

        // Deploy pool
        vm.startBroadcast();
        metapool = _deployMetapool(config);
        vm.stopBroadcast();

        // Write to output file
        _saveDeploymentResult(configFileName, metapool);

        return metapool;
    }

    function _loadConfig(
        string memory configFileName
    ) internal view returns (MetapoolConfig memory config) {
        string memory configPath = string.concat(
            "./configs/",
            configFileName,
            ".json"
        );
        string memory json = vm.readFile(configPath);

        config.basePool = SBTC_POOL; // Default to SBTC pool
        config.name = json.readString(".name");
        config.symbol = json.readString(".symbol");
        config.token = json.readAddress(".token");
        config.A = json.readUint(".A");
        config.fee = json.readUint(".fee");
        config.implementationIdx = 0;

        console.log(
            "[LP][Curve][Deploy] Deploying Metapool for ",
            configFileName
        );
        console.log("[LP][Curve][Deploy] Base Pool:", config.basePool);
        console.log("[LP][Curve][Deploy] Metapool Name:", config.name);
        console.log("[LP][Curve][Deploy] Metapool Symbol:", config.symbol);
        console.log("[LP][Curve][Deploy] Token:", config.token);
        console.log("[LP][Curve][Deploy] A Parameter:", config.A);
        console.log("[LP][Curve][Deploy] Fee:", config.fee);
    }

    function _deployMetapool(
        MetapoolConfig memory config
    ) internal returns (address metapool) {
        metapool = ICurveFactory(CURVE_FACTORY).deploy_metapool(
            config.basePool,
            config.name,
            config.symbol,
            config.token,
            config.A,
            config.fee,
            config.implementationIdx
        );

        console.log("[LP][Curve][Deploy] Metapool deployed at: ", metapool);

        return metapool;
    }

    function _saveDeploymentResult(
        string memory configFileName,
        address metapool
    ) internal {
        string memory resultPath = string.concat(
            "./outputs/",
            configFileName,
            "-result.json"
        );
        string memory result = string.concat(
            '{"metapool":"',
            vm.toString(metapool),
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
