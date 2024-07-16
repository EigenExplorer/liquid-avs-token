// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LiquidAvsToken.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Mock AVS Token for testing purposes
contract MockAvsToken is ERC20 {
    constructor() ERC20("Mock AVS Token", "mAVS") {
        _mint(msg.sender, 1000000 * 10 ** decimals()); // Mint some initial tokens
    }
}

contract DeployLiquidAvsToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy a mock AVS token for testing purposes
        MockAvsToken mockAvsToken = new MockAvsToken();

        // Deploy the LiquidAvsToken contract
        LiquidAvsToken liquidAvsToken = new LiquidAvsToken(
            "Liquid AVS Token",
            "lAVS",
            IERC20(address(mockAvsToken))
        );

        vm.stopBroadcast();

        console.log("Mock AVS Token deployed at:", address(mockAvsToken));
        console.log("LiquidAvsToken deployed at:", address(liquidAvsToken));
    }
}
