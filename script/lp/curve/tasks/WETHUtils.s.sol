// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev To load env file:
// source .env

/// @dev To setup a local node (on a separate terminal instance):
// anvil --fork-url $RPC_URL

/// @dev Convert specific amount of ETH to WETH:
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(uint256)" -- "1000000000000000000" --value 1ether -vvvv

/// @dev Convert all available ETH to WETH:
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "convertAllEthToWeth()" --value 2ether -vvvv

/// @dev Convert WETH back to ETH:
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "convertWethToEth(uint256)" -- "1000000000000000000" -vvvv

/// @dev Transfer WETH to another address:
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "transferWeth(address,uint256)" -- "0xRecipientAddress" "1000000000000000000" -vvvv

/// @dev Approve WETH for a spender (e.g., Curve pool):
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "approveWeth(address,uint256)" -- "0xSpenderAddress" "1000000000000000000" -vvvv

/// @dev Check WETH balance (view function, no broadcast needed):
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --sig "getWethBalance()" -vvvv

/// @dev Check ETH balance (view function, no broadcast needed):
// forge script script/lp/curve/tasks/WethUtils.s.sol:WethUtils --rpc-url http://localhost:8545 --sig "getEthBalance()" -vvvv

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract WethUtils is Script {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run(
        uint256 amount
    ) external payable returns (uint256 wethBalance) {
        return convertEthToWeth(amount);
    }

    function convertEthToWeth(
        uint256 amount
    ) public payable returns (uint256 wethBalance) {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient ETH balance");

        console.log("[LP][WETH][Convert] Converting", amount, "ETH to WETH");
        console.log(
            "[LP][WETH][Convert] ETH balance before:",
            address(this).balance
        );

        vm.startBroadcast();
        IWETH(WETH).deposit{value: amount}();
        wethBalance = IWETH(WETH).balanceOf(address(this));
        vm.stopBroadcast();

        console.log(
            "[LP][WETH][Convert] ETH balance after:",
            address(this).balance
        );
        console.log("[LP][WETH][Convert] WETH balance:", wethBalance);
        console.log("[LP][WETH][Convert] Conversion completed");

        return wethBalance;
    }

    function convertAllEthToWeth()
        external
        payable
        returns (uint256 wethBalance)
    {
        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "No ETH to convert");

        return convertEthToWeth(ethBalance);
    }

    function convertWethToEth(
        uint256 amount
    ) external returns (uint256 ethBalance) {
        require(amount > 0, "Amount must be greater than 0");

        uint256 wethBalance = IWETH(WETH).balanceOf(address(this));
        require(wethBalance >= amount, "Insufficient WETH balance");

        console.log("[LP][WETH][Convert] Converting", amount, "WETH to ETH");
        console.log("[LP][WETH][Convert] WETH balance before:", wethBalance);

        vm.startBroadcast();

        // Convert WETH to ETH
        IWETH(WETH).withdraw(amount);

        // Get the ETH balance
        ethBalance = address(this).balance;

        vm.stopBroadcast();

        console.log("[LP][WETH][Convert] ETH balance after:", ethBalance);
        console.log("[LP][WETH][Convert] WETH to ETH conversion completed");

        return ethBalance;
    }

    function transferWeth(
        address to,
        uint256 amount
    ) external returns (bool success) {
        require(to != address(0), "Cannot transfer to zero address");
        require(amount > 0, "Amount must be greater than 0");

        uint256 wethBalance = IWETH(WETH).balanceOf(address(this));
        require(wethBalance >= amount, "Insufficient WETH balance");

        console.log("[LP][WETH][Convert] Transferring", amount, "WETH to:", to);

        vm.startBroadcast();
        success = IWETH(WETH).transfer(to, amount);
        vm.stopBroadcast();

        console.log(
            "[LP][WETH][Convert] Transfer",
            success ? "successful" : "failed"
        );

        return success;
    }

    function approveWeth(
        address spender,
        uint256 amount
    ) external returns (bool success) {
        require(spender != address(0), "Cannot approve zero address");
        require(amount > 0, "Amount must be greater than 0");

        console.log(
            "[LP][WETH][Convert] Approving",
            amount,
            "WETH for spender:",
            spender
        );

        vm.startBroadcast();
        success = IWETH(WETH).approve(spender, amount);
        vm.stopBroadcast();

        console.log(
            "[LP][WETH][Convert] Approval",
            success ? "successful" : "failed"
        );

        return success;
    }

    function getWethBalance() external view returns (uint256) {
        return IWETH(WETH).balanceOf(address(this));
    }

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        console.log("[LP][WETH][Convert] Received", msg.value, "ETH");
    }

    fallback() external payable {
        console.log(
            "[LP][WETH][Convert] Fallback called with",
            msg.value,
            "ETH"
        );
    }
}
