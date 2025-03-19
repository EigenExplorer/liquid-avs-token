// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {TokenRegistryOracle} from "../../src/utils/TokenRegistryOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TRO_UpdatePrices is Script {
    // Function to batch update rates on a specific oracle
    function batchUpdateRates(
        address oracleAddress,
        address[] memory tokens,
        uint256[] memory prices
    ) external {
        vm.startBroadcast();
        TokenRegistryOracle oracle = TokenRegistryOracle(oracleAddress);

        // Convert the array of addresses to an array of IERC20 contracts
        IERC20[] memory tokenContracts = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenContracts[i] = IERC20(tokens[i]);
        }

        oracle.batchUpdateRates(tokenContracts, prices);
        vm.stopBroadcast();
    }

    // Function to update a single rate on a specific oracle
    function updateRate(
        address oracleAddress,
        address token,
        uint256 price
    ) external {
        vm.startBroadcast();
        TokenRegistryOracle oracle = TokenRegistryOracle(oracleAddress);
        oracle.updateRate(IERC20(token), price);
        vm.stopBroadcast();
    }
}
