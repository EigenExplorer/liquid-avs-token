// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this task (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script --via-ir script/tasks/LTM_StakeAssetsToNode.s.sol:StakeAssetsToNode --rpc-url $RPC_URL --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string,uint256,address[],uint256[])" -- "/local/deployment_data.json" <NODE_ID> <ASSETS> <AMOUNTS> -vvvv
contract StakeAssetsToNode is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(
        string memory configFileName,
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) public {
        string memory configPath = string(bytes(string.concat("script/outputs", configFileName)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(
            config,
            ".contractDeployments.proxy.liquidTokenManager.address"
        );

        LiquidTokenManager liquidTokenManager = LiquidTokenManager(payable(liquidTokenManageraddress));

        vm.startBroadcast();
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
        vm.stopBroadcast();
    }
}
