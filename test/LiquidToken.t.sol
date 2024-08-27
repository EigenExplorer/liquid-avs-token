// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./BaseTest.sol";
import "../src/core/LiquidToken.sol";
import "../src/core/Orchestrator.sol";
import "../src/interfaces/ILiquidToken.sol";
import "../src/utils/TokenRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract LiquidTokenTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testDeposit() public {
        vm.prank(user1);
        uint256 shares = liquidToken.deposit(
            IERC20(address(testToken)),
            10 ether,
            user1
        );

        assertEq(shares, 10 ether, "Incorrect number of shares minted");
        assertEq(
            liquidToken.balanceOf(user1),
            10 ether,
            "Incorrect balance after deposit"
        );
        assertEq(
            testToken.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect token balance in LiquidToken"
        );
    }

    function testRequestWithdrawal() public {
        vm.startPrank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        liquidToken.approve(user1, amounts[0]);
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();

        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect balance after withdrawal request"
        );
    }

    function testFulfillWithdrawal() public {
        vm.startPrank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        liquidToken.approve(user1, amounts[0]);
        liquidToken.requestWithdrawal(assets, amounts);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Fast forward time
        vm.warp(block.timestamp + 15 days);

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        assertEq(testToken.balanceOf(user1), 95 ether, "Incorrect token balance after withdrawal");
    }

    function testTransferAssetsToOrchestrator() public {
        vm.prank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(address(orchestrator));
        liquidToken.transferAssetsToOrchestrator(assets, amounts);

        assertEq(
            testToken.balanceOf(address(orchestrator)),
            5 ether,
            "Incorrect token balance in orchestrator"
        );
    }

    function testPause() public {
        vm.prank(pauser);
        liquidToken.pause();

        assertTrue(liquidToken.paused(), "Contract should be paused");

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
    }

    function testUnpause() public {
        vm.prank(pauser);
        liquidToken.pause();

        vm.prank(pauser);
        liquidToken.unpause();

        assertFalse(liquidToken.paused(), "Contract should be unpaused");

        vm.prank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
    }
}
