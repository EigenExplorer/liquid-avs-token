// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OUT OF SCOPE FOR V1: This entire file is related to undelegation functionality
// which is not implemented in v1 of the Liquid AVS Token project.

/**
import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev This script is for undelegating nodes - OUT OF SCOPE FOR V1
/// Original command:
// forge script --via-ir script/tasks/LTM_UndelegateNodes.s.sol:UndelegateNodes --rpc-url $RPC_URL --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string,uint256[])" -- "/local/mainnet_deployment_data.json" <NODE_IDS> -vvvv

contract UndelegateNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(
      string memory configFileName,
      uint256[] memory nodeIds
    ) public {
        string memory configPath = string(bytes(string.concat("script/outputs", configFileName)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(config, ".contractDeployments.proxy.liquidTokenManager.address");
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(liquidTokenManageraddress);

        vm.startBroadcast();
        liquidTokenManager.undelegateNodes(nodeIds);
        vm.stopBroadcast();
    }
}
*/
