// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {StakerNodeCoordinator} from "../../src/core/StakerNodeCoordinator.sol";
import {IStakerNode} from "../../src/interfaces/IStakerNode.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this task (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script script/tasks/SNC_CreateStakerNodes.s.sol:CreateStakerNodes --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string,uint256)" -- "/local/mainnet_deployment_data.json" <COUNT> -vvvv
contract CreateStakerNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(string memory configFileName, uint256 count) public returns (uint256[] memory) {
        string memory configPath = string(bytes(string.concat("script/outputs", configFileName)));
        string memory config = vm.readFile(configPath);

        address stakerNodeCoordinatorAddress = stdJson.readAddress(config, ".contractDeployments.proxy.stakerNodeCoordinator.address");
        StakerNodeCoordinator stakerNodeCoordinator = StakerNodeCoordinator(stakerNodeCoordinatorAddress);
        uint256[] memory nodeIds = new uint256[](count);

        vm.startBroadcast();

        require(
            stakerNodeCoordinator.getStakerNodesCount() + count <= stakerNodeCoordinator.maxNodes(),
            "Will exceed max allowed nodes"
        );
        unchecked {
            for (uint256 i = 0; i < count; i++) {
                IStakerNode node = stakerNodeCoordinator.createStakerNode();
                nodeIds[i] = node.getId();
            }
        }
        
        vm.stopBroadcast();

        return nodeIds;
    }
}
