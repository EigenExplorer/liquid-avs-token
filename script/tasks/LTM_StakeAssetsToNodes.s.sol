// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this task (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script --via-ir script/tasks/LTM_StakeAssetsToNodes.s.sol:StakeAssetsToNodes --rpc-url $RPC_URL --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string,(uint256,address[],uint256[])[])" -- "/local/deployment_data.json" <ALLOCATIONS> -vvvv
contract StakeAssetsToNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(string memory configFileName, LiquidTokenManager.NodeAllocation[] calldata allocations) public {
        string memory configPath = string(bytes(string.concat("script/outputs", configFileName)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(
            config,
            ".contractDeployments.proxy.liquidTokenManager.address"
        );
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(liquidTokenManageraddress);

        vm.startBroadcast();
        liquidTokenManager.stakeAssetsToNodes(allocations);
        vm.stopBroadcast();
    }
}
