// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";

import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev To run this task (make sure terminal is at the root directory `/liquid-avs-token`):
// forge script script/tasks/LTM_DelegateNodes.s.sol:DelegateNodes --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string,uint256[],address[],(bytes,uint256)[],bytes32[])" -- "/local/deployment_data.json" <NODE_IDS> <OPERATORS> <SIGNATURES> <SALTS> -vvvv
contract DelegateNodes is Script, Test {
    Vm cheats = Vm(VM_ADDRESS);

    function run(
        string memory configFileName,
        uint256[] memory nodeIds,
        address[] memory operators,
        ISignatureUtilsMixinTypes.SignatureWithExpiry[] calldata approverSignatureAndExpiries,
        bytes32[] calldata approverSalts
    ) public {
        string memory configPath = string(bytes(string.concat("script/outputs", configFileName)));
        string memory config = vm.readFile(configPath);

        address liquidTokenManageraddress = stdJson.readAddress(
            config,
            ".contractDeployments.proxy.liquidTokenManager.address"
        );
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(liquidTokenManageraddress);

        // Create default signatures and salts if empty arrays are provided
        ISignatureUtilsMixinTypes.SignatureWithExpiry[] memory signatures;
        bytes32[] memory salts;

        if (approverSignatureAndExpiries.length == 0 || approverSalts.length == 0) {
            signatures = new ISignatureUtilsMixinTypes.SignatureWithExpiry[](nodeIds.length);
            salts = new bytes32[](nodeIds.length);
            for (uint256 i = 0; i < nodeIds.length; i++) {
                signatures[i] = ISignatureUtilsMixinTypes.SignatureWithExpiry({
                    signature: new bytes(0),
                    expiry: type(uint256).max
                });
                salts[i] = bytes32(0);
            }
        } else {
            signatures = approverSignatureAndExpiries;
            salts = approverSalts;
        }

        vm.startBroadcast();
        liquidTokenManager.delegateNodes(nodeIds, operators, signatures, salts);
        vm.stopBroadcast();
    }
}
