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
// forge script script/lp/curve/DeployGauge.s.sol:DeployGauge --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(address,string)" -- <POOL_ADDRESS> "<FILENAME_FROM_CONFIGS_FOLDER>.json" -vvvv

interface ICurveFactory {
    function deploy_gauge(address _pool) external returns (address);
}

contract DeployGauge is Script {
    using stdJson for string;

    address constant CURVE_FACTORY = 0xB9fC157394Af804a3578134A6585C0dc9cc990d4;

    function run(
        address pool,
        string memory configFileName
    ) external returns (address gauge) {
        console.log("[LP][Curve][Deploy] Deploying Gauge for ", pool);

        // Deploy gauge
        vm.startBroadcast();
        gauge = ICurveFactory(CURVE_FACTORY).deploy_gauge(pool);
        console.log("[LP][Curve][Deploy] Gauge deployed at: ", gauge);
        vm.stopBroadcast();

        // Write to output file
        _saveDeploymentResult(configFileName, gauge, pool);

        return gauge;
    }

    function _saveDeploymentResult(
        string memory configFileName,
        address gauge,
        address pool
    ) internal {
        string memory resultPath = string.concat(
            "./outputs/",
            configFileName,
            "-gauge.json"
        );
        string memory result = string.concat(
            '{"gauge":"',
            vm.toString(gauge),
            '","pool":"',
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
