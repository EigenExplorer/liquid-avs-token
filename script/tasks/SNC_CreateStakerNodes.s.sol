// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {StakerNodeCoordinator} from "../../src/core/StakerNodeCoordinator.sol";

contract CreateStakerNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(string memory configFile, uint256 count) public {
        string memory configPath = string(bytes(string.concat("script/outputs/", configFile)));
        string memory config = vm.readFile(configPath);

        address stakerNodeCoordinatorAddress = stdJson.readAddress(config, ".addresses.stakerNodeCoordinator");
        StakerNodeCoordinator stakerNodeCoordinator = StakerNodeCoordinator(stakerNodeCoordinatorAddress);

        vm.startBroadcast();

        require(stakerNodeCoordinator.getStakerNodesCount() + count <= stakerNodeCoordinator.maxNodes(), "Will exceed max allowed nodes");
        unchecked {
            for (uint256 i = 0; i < count; i++) {
                stakerNodeCoordinator.createStakerNode();
            }
        }
        
        vm.stopBroadcast();
    }
}
