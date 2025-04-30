// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {TokenRegistryOracle} from "../../src/utils/TokenRegistryOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this task (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script script/tasks/TRO_UpdateAllPricesIfNeeded.s.sol:UpdateAllPricesIfNeeded --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string)" -- "/local/deployment_data.json" -vvvv
contract UpdateAllPricesIfNeeded is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(string memory configFileName) public {
        string memory configPath = string(bytes(string.concat("script/outputs", configFileName)));
        string memory config = vm.readFile(configPath);

        address oracleAddress = stdJson.readAddress(config, ".contractDeployments.proxy.tokenRegistryOracle.address");
        TokenRegistryOracle oracle = TokenRegistryOracle(oracleAddress);

        vm.startBroadcast();

        oracle.updateAllPricesIfNeeded();

        vm.stopBroadcast();
    }
}
