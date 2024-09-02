// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {LiquidToken} from "../src/core/LiquidToken.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {TokenRegistry} from "../src/utils/TokenRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract LiquidTokenTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testDeposit() public {
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256[] memory mintedShares = liquidToken.deposit(assets, amounts, user1);
        uint256 shares = mintedShares[0];

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

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));

        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        liquidToken.approve(user1, amountsToWithdraw[0]);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();

        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect balance after withdrawal request"
        );
    }

    function testFulfillWithdrawal() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        liquidToken.approve(user1, amountsToWithdraw[0]);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Record the total supply and total assets before fulfillment
        uint256 totalSupplyBefore = liquidToken.totalSupply();
        uint256 totalAssetsBefore = liquidToken.totalAssets();

        // Fast forward time
        vm.warp(block.timestamp + 15 days);

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        // Assert that User1's token balance is correct after withdrawal
        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after withdrawal"
        );

        // Check if the correct amount of tokens were burned
        assertEq(
            liquidToken.totalSupply(),
            totalSupplyBefore - 5 ether,
            "Incorrect total supply after withdrawal (tokens not burned)"
        );

        // Check the user's remaining balance
        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect remaining balance after withdrawal"
        );

        // Check that the contract's balance of liquid tokens has decreased
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after fulfillment"
        );

        // Assert that the total assets reduces after the withdrawal
        assertEq(
            liquidToken.totalAssets(),
            totalAssetsBefore - 5 ether,
            "Incorrect total assets after withdrawal"
        );
    }

    function testTransferAssets() public {
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 5 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(assets, amountsToTransfer);

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token balance in liquid token manager"
        );
    }

    function testDepositMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        uint256[] memory mintedShares = liquidToken.deposit(assets, amountsToDeposit, user1);
        uint256 shares1 = mintedShares[0];
        uint256 shares2 = mintedShares[1];

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

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](2);
        amountsToWithdraw[0] = 5 ether;
        amountsToWithdraw[1] = 2 ether;

        liquidToken.approve(user1, 7 ether);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();

        assertEq(
            liquidToken.balanceOf(user1),
            8 ether,
            "Incorrect balance after withdrawal request"
        );
    }

    function testFulfillWithdrawalMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](2);
        amountsToWithdraw[0] = 5 ether;
        amountsToWithdraw[1] = 2 ether;

        liquidToken.approve(user1, 7 ether);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

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

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(assets, amountsToDeposit, user1);
        vm.stopPrank();

        uint256[] memory amountsToTransfer = new uint256[](2);
        amountsToTransfer[0] = 5 ether;
        amountsToTransfer[1] = 2 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(assets, amountsToTransfer);

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
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 0 ether;

        vm.expectRevert(ILiquidToken.ZeroAmount.selector);
        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testDepositUnsupportedAsset() public {
        ERC20 unsupportedToken = new MockERC20("Unsupported Token", "UT");
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(unsupportedToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(unsupportedToken)
            )
        );
        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testRequestWithdrawalInsufficientBalance() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 11 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.InsufficientBalance.selector,
                address(liquidToken),
                11 ether,
                10 ether
            )
        );
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();
    }

    function testFulfillWithdrawalBeforeDelay() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        liquidToken.approve(user1, amountsToWithdraw[0]);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

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
            abi.encodeWithSelector(
                ILiquidToken.NotLiquidTokenManager.selector,
                user1
            )
        );
        liquidToken.transferAssets(assets, amounts);
    }

    function testPause() public {
        vm.prank(pauser);
        liquidToken.pause();

        assertTrue(liquidToken.paused(), "Contract should be paused");

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(user1);
        
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testUnpause() public {
        vm.prank(pauser);
        liquidToken.pause();

        vm.prank(admin);
        liquidToken.unpause();

        assertFalse(liquidToken.paused(), "Contract should be unpaused");

        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testZeroAddressInput() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(0));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        // Attempt to deposit with an incorrect address (address(0))
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                IERC20(address(0))
            )
        );
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Valid deposit
        assets[0] = IERC20(address(testToken));
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Attempt to withdraw with a zero address
        assets[0] = IERC20(address(0));
        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(assets[0])
            )
        );
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();

        // Attempt to transfer assets with a zero address
        vm.prank(address(liquidTokenManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(assets[0])
            )
        );

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 5 ether;
        liquidToken.transferAssets(assets, amountsToTransfer);
    }

    function testConsecutiveWithdrawalRequestsWithFulfillments() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory withdrawal1Amounts = new uint256[](1);
        withdrawal1Amounts[0] = 5 ether;
        liquidToken.requestWithdrawal(assets, withdrawal1Amounts);

        // Second withdrawal request before fulfilling the first
        uint256[] memory withdrawal2Amounts = new uint256[](1);
        withdrawal2Amounts[0] = 2 ether;
        liquidToken.requestWithdrawal(assets, withdrawal2Amounts);

        assertEq(
            liquidToken.balanceOf(user1),
            3 ether,
            "Incorrect balance after second withdrawal request"
        );

        // There should be two withdrawal requests in the queue
        assertEq(
            liquidToken.getUserWithdrawalRequests(user1).length,
            2,
            "Incorrect number of withdrawal requests"
        );

        vm.warp(block.timestamp + 15 days);

        // Fulfill the first withdrawal request
        bytes32 firstRequestId = liquidToken.getUserWithdrawalRequests(user1)[
            0
        ];
        uint256 totalSupplyBeforeFirstFulfillment = liquidToken.totalSupply();
        liquidToken.fulfillWithdrawal(firstRequestId);

        // Check balances after the first fulfillment
        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after first withdrawal fulfillment"
        );
        assertEq(
            liquidToken.totalSupply(),
            totalSupplyBeforeFirstFulfillment - 5 ether,
            "Incorrect total supply after first withdrawal (tokens not burned)"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            2 ether,
            "Contract should not hold first deposit liquid tokens after first fulfillment"
        );

        // Fulfill the second withdrawal request
        bytes32 secondRequestId = liquidToken.getUserWithdrawalRequests(user1)[
            1
        ];
        uint256 totalSupplyBeforeSecondFulfillment = liquidToken.totalSupply();
        liquidToken.fulfillWithdrawal(secondRequestId);

        // Check balances after the second fulfillment
        assertEq(
            testToken.balanceOf(user1),
            97 ether,
            "Incorrect testToken balance after second withdrawal"
        );
        assertEq(
            liquidToken.totalSupply(),
            totalSupplyBeforeSecondFulfillment - 2 ether,
            "Incorrect total supply after second withdrawal (tokens not burned)"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after second fulfillment"
        );

        vm.stopPrank();
    }

    function testMultipleUsersMultipleWithdrawals() public {
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDepositUser1 = new uint256[](1);
        amountsToDepositUser1[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDepositUser1, user1);

        vm.prank(user2);
        uint256[] memory amountsToDepositUser2 = new uint256[](1);
        amountsToDepositUser2[0] = 20 ether;
        liquidToken.deposit(assets, amountsToDepositUser2, user2);

        vm.startPrank(user1);
        uint256[] memory amountsUser1Withdrawal = new uint256[](1);
        amountsUser1Withdrawal[0] = 5 ether;
        liquidToken.requestWithdrawal(assets, amountsUser1Withdrawal);

        bytes32 requestIdUser1 = liquidToken.getUserWithdrawalRequests(user1)[
            0
        ];
        vm.warp(block.timestamp + 15 days);
        liquidToken.fulfillWithdrawal(requestIdUser1);

        // Check balances for User1
        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after withdrawal for User1"
        );
        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect remaining balance after withdrawal for User1"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after User1's fulfillment"
        );

        vm.stopPrank();
        vm.startPrank(user2);

        uint256[] memory amountsUser2Withdrawal = new uint256[](1);
        amountsUser2Withdrawal[0] = 10 ether;
        liquidToken.requestWithdrawal(assets, amountsUser2Withdrawal);

        bytes32 requestIdUser2 = liquidToken.getUserWithdrawalRequests(user2)[
            0
        ];
        vm.warp(block.timestamp + 15 days);
        liquidToken.fulfillWithdrawal(requestIdUser2);

        // Check balances for User2
        assertEq(
            testToken.balanceOf(user2),
            90 ether,
            "Incorrect token balance after withdrawal for User2"
        );
        assertEq(
            liquidToken.balanceOf(user2),
            10 ether,
            "Incorrect remaining balance after withdrawal for User2"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after User2's fulfillment"
        );

        vm.stopPrank();
    }
}
