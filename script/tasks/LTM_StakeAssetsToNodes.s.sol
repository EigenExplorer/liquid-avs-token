// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

/// @dev To run this task:
// forge script --via-ir script/tasks/LTM_StakeAssetsToNodes.s.sol:StakeAssetsToNodes --rpc-url $RPC_URL --broadcast --sig "run(string memory configFileName,LiquidTokenManager.NodeAllocation[] calldata allocations)" -- "/local/mainnet_deployment_data.json" <ALLOCATIONS> -vvvv
contract StakeAssetsToNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(
      string memory configFileName,
      LiquidTokenManager.NodeAllocation[] calldata allocations
    ) public {
        string memory configPath = string(bytes(string.concat("script/outputs/", configFileName)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(config, ".addresses.liquidTokenManager");
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(liquidTokenManageraddress);

        vm.startBroadcast();
        liquidTokenManager.stakeAssetsToNodes(allocations);
        vm.stopBroadcast();
    }
}
