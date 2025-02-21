// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

contract UndelegateNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(
      string memory configFile,
      uint256[] memory nodeIds
    ) public {
        string memory configPath = string(bytes(string.concat("script/outputs/", configFile)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(config, ".addresses.liquidTokenManager");
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(liquidTokenManageraddress);

        vm.startBroadcast();
        liquidTokenManager.undelegateNodes(nodeIds);
        vm.stopBroadcast();
    }
}
