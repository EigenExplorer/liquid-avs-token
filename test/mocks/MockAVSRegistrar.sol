// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAVSRegistrar} from "eigenlayer-contracts/src/contracts/interfaces/IAVSRegistrar.sol";

contract MockAVSRegistrar is IAVSRegistrar {
    function registerOperator(
        address operator,
        address avs,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external override {
        // Do nothing - stub implementation
    }

    function deregisterOperator(address operator, address avs, uint32[] calldata operatorSetIds) external override {
        // Do nothing - stub implementation
    }

    function supportsAVS(address avs) external pure override returns (bool) {
        return true;
    }
}
