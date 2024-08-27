// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./BaseTest.sol";
import "../src/core/LiquidToken.sol";
import "../src/core/LiquidTokenManager.sol";
import "../src/interfaces/ILiquidToken.sol";
import "../src/utils/TokenRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

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

        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after withdrawal"
        );
    }

    function testTransferAssets() public {
        vm.prank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(assets, amounts);

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token balance in liquid token manager"
        );
    }

    function testDepositMultipleAssets() public {
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        uint256 shares1 = liquidToken.deposit(
            IERC20(address(testToken)),
            10 ether,
            user1
        );
        uint256 shares2 = liquidToken.deposit(
            IERC20(address(testToken2)),
            5 ether,
            user1
        );

        assertEq(
            shares1,
            10 ether,
            "Incorrect number of shares minted for token1"
        );
        assertEq(
            shares2,
            5 ether,
            "Incorrect number of shares minted for token2"
        );
        assertEq(
            liquidToken.balanceOf(user1),
            15 ether,
            "Incorrect total balance after deposits"
        );
        vm.stopPrank();
    }

    function testRequestWithdrawalMultipleAssets() public {
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
        liquidToken.deposit(IERC20(address(testToken2)), 5 ether, user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5 ether;
        amounts[1] = 2 ether;

        liquidToken.approve(user1, 7 ether);
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();

        assertEq(
            liquidToken.balanceOf(user1),
            8 ether,
            "Incorrect balance after withdrawal request"
        );
    }

    function testFulfillWithdrawalMultipleAssets() public {
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
        liquidToken.deposit(IERC20(address(testToken2)), 5 ether, user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5 ether;
        amounts[1] = 2 ether;

        liquidToken.approve(user1, 7 ether);
        liquidToken.requestWithdrawal(assets, amounts);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Fast forward time
        vm.warp(block.timestamp + 15 days);

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token1 balance after withdrawal"
        );
        assertEq(
            testToken2.balanceOf(user1),
            97 ether,
            "Incorrect token2 balance after withdrawal"
        );
    }

    function testTransferMultipleAssets() public {
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
        liquidToken.deposit(IERC20(address(testToken2)), 5 ether, user1);
        vm.stopPrank();

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5 ether;
        amounts[1] = 2 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(assets, amounts);

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token1 balance in liquidTokenManager"
        );
        assertEq(
            testToken2.balanceOf(address(liquidTokenManager)),
            2 ether,
            "Incorrect token2 balance in liquidTokenManager"
        );
    }

    function testDepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ZeroAmount.selector);
        liquidToken.deposit(IERC20(address(testToken)), 0, user1);
    }

    function testDepositUnsupportedAsset() public {
        ERC20 unsupportedToken = new MockERC20("Unsupported Token", "UT");
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(unsupportedToken)
            )
        );
        liquidToken.deposit(IERC20(address(unsupportedToken)), 10 ether, user1);
    }

    function testRequestWithdrawalInsufficientBalance() public {
        vm.startPrank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 11 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.InsufficientBalance.selector,
                address(liquidToken),
                11 ether,
                10 ether
            )
        );
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();
    }

    function testFulfillWithdrawalBeforeDelay() public {
        vm.startPrank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        liquidToken.approve(user1, amounts[0]);
        liquidToken.requestWithdrawal(assets, amounts);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Fast forward time, but not enough
        vm.warp(block.timestamp + 13 days);

        vm.expectRevert(ILiquidToken.WithdrawalDelayNotMet.selector);
        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();
    }

    function testTransferAssetsNotLiquidTokenManager() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(ILiquidToken.NotLiquidTokenManager.selector, user1)
        );
        liquidToken.transferAssets(assets, amounts);
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
