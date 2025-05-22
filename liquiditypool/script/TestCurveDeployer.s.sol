// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import "../script/CurvePoolProductionDeployer.sol";

contract TestCurveDeployer is Script {
    function setUp() public {}

    function run() public {
        // Get private key from .env file or use a default test key
        uint256 privateKey = vm.envOr(
            "TEST_PRIVATE_KEY",
            uint256(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
            )
        );
        vm.startBroadcast(privateKey);

        // Run the deployer and send sufficient ETH with it
        CurvePoolProductionDeployer deployer = new CurvePoolProductionDeployer();

        // Send ETH with the call - enough for all pools that need funding
        // 4 pools will need ETH (ETH-pegged, xEigenDA/ETH, xARPA/ETH, plus some buffer)
        deployer.run{value: 5 ether}();

        vm.stopBroadcast();
    }
}