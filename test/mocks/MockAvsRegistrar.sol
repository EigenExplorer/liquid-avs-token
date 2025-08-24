// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

contract MockAVSRegistrar {
    function supportsAVS(address /*avs*/) external pure returns (bool) {
        return true;
    }

    function registerOperator(
        address /*operator*/,
        address /*avs*/,
        uint32[] calldata /*operatorSetIds*/,
        bytes calldata /*data*/
    ) external {}

    function deregisterOperator(address /*operator*/, address /*avs*/, uint32[] calldata /*operatorSetIds*/) external {}

    fallback() external {}
}
