// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

contract DelegateNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(
      string memory configFile,
      uint256[] memory nodeIds,
      address[] memory operators,
      ISignatureUtils.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
      bytes32[] calldata approverSalts
    ) public {
        string memory configPath = string(bytes(string.concat("script/outputs/", configFile)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(config, ".addresses.liquidTokenManager");
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(liquidTokenManageraddress);

        vm.startBroadcast();
        liquidTokenManager.delegateNodes(nodeIds, operators, approverSignatureAndExpiries, approverSalts);
        vm.stopBroadcast();
    }
}
