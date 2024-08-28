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

        // Record the total supply before fulfillment
        uint256 totalSupplyBefore = liquidToken.totalSupply();

        // Fast forward time
        vm.warp(block.timestamp + 15 days);

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

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
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
    }

    function testUnpause() public {
        vm.prank(pauser);
        liquidToken.pause();

        vm.prank(admin);
        liquidToken.unpause();

        assertFalse(liquidToken.paused(), "Contract should be unpaused");

        vm.prank(user1);
        liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);
    }

    function testConsecutiveWithdrawalRequestsWithDelayedFulfillment() public {
    vm.startPrank(user1);

    liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

    IERC20[] memory assets = new IERC20[](1);
    assets[0] = IERC20(address(testToken));
    uint256[] memory withdrawal1Amount = new uint256[](1);
    withdrawal1Amount[0] = 5 ether;
    liquidToken.requestWithdrawal(assets, withdrawal1Amount);

    // Second withdrawal request before fulfilling the first
    uint256[] memory withdrawal2Amount = new uint256[](1);
    withdrawal2Amount[0] = 2 ether;
    liquidToken.requestWithdrawal(assets, withdrawal2Amount);

    assertEq(
        liquidToken.balanceOf(user1), 
        3 ether, 
        "Incorrect LiquidToken balance after second withdrawal request"
    );
    assertEq(
        testToken.balanceOf(address(liquidToken)), 
        10 ether, 
        "testToken balance in LiquidToken contract should remain unchanged after second withdrawal request"
    );

    // There should be two withdrawal requests in the queue
    assertEq(
        liquidToken.getUserWithdrawalRequests(user1).length, 
        2, 
        "Incorrect number of withdrawal requests"
    );

    vm.warp(block.timestamp + 15 days);

    // Fulfill the first withdrawal request
    bytes32 firstRequestId = liquidToken.getUserWithdrawalRequests(user1)[0];
    uint256 totalSupplyBeforeFirstFulfillment = liquidToken.totalSupply();
    liquidToken.fulfillWithdrawal(firstRequestId);

    // Check balances after the first fulfillment
    assertEq(
        testToken.balanceOf(user1),
        95 ether,
        "Incorrect testToken balance after first withdrawal fulfillment"
    );
    assertEq(
        liquidToken.totalSupply(),
        totalSupplyBeforeFirstFulfillment - 5 ether,
        "Incorrect total supply after first withdrawal (tokens not burned)"
    );
    assertEq(
        liquidToken.balanceOf(user1),
        3 ether,
        "Incorrect LiquidToken balance after first withdrawal fulfillment"
    );

    // Fulfill the second withdrawal request
    bytes32 secondRequestId = liquidToken.getUserWithdrawalRequests(user1)[1];
    uint256 totalSupplyBeforeSecondFulfillment = liquidToken.totalSupply();
    liquidToken.fulfillWithdrawal(secondRequestId);

    // Check balances after the second fulfillment
    assertEq(
        testToken.balanceOf(user1),
        97 ether,
        "Incorrect testToken balance after second withdrawal fulfillment"
    );
    assertEq(
        liquidToken.totalSupply(),
        totalSupplyBeforeSecondFulfillment - 2 ether,
        "Incorrect total supply after second withdrawal (tokens not burned)"
    );
    assertEq(
        liquidToken.balanceOf(user1),
        3 ether,
        "Incorrect LiquidToken balance after second withdrawal fulfillment"
    );

    vm.stopPrank();
}

function testZeroAddressInput() public {
    // Attempt to deposit with an incorrect address (address(0))
    vm.prank(user1);
    vm.expectRevert(
        abi.encodeWithSelector(
            ILiquidToken.UnsupportedAsset.selector,
            IERC20(address(0))
        )
    );
    liquidToken.deposit(IERC20(address(0)), 10 ether, user1);

    // Valid deposit
    vm.prank(user1);
    liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

    // Attempt to withdraw with a zero address
    vm.startPrank(user1);
    IERC20[] memory assets = new IERC20[](1);
    assets[0] = IERC20(address(0));  // Incorrect asset address
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 5 ether;

    vm.expectRevert(
        abi.encodeWithSelector(
            ILiquidToken.UnsupportedAsset.selector,
            address(assets[0])
        )
    );
    liquidToken.requestWithdrawal(assets, amounts);
    vm.stopPrank();

    // Attempt to transfer assets with a zero address
    IERC20[] memory assetsToRetrieve = new IERC20[](1);
    assetsToRetrieve[0] = IERC20(address(0));  // Incorrect asset address
    uint256[] memory amountsToRetrieve = new uint256[](1);
    amountsToRetrieve[0] = 5 ether;

    vm.prank(address(liquidTokenManager));
    vm.expectRevert(
        abi.encodeWithSelector(
            ILiquidToken.UnsupportedAsset.selector,
            address(assetsToRetrieve[0])
        )
    );
    liquidToken.transferAssets(assetsToRetrieve, amountsToRetrieve);
}

function testMultipleStakersMultipleWithdrawals() public {
    vm.prank(user1);
    liquidToken.deposit(IERC20(address(testToken)), 10 ether, user1);

    vm.prank(user2);
    liquidToken.deposit(IERC20(address(testToken)), 20 ether, user2);

    vm.startPrank(user1);
    IERC20[] memory assets = new IERC20[](1);
    assets[0] = IERC20(address(testToken));
    uint256[] memory amountsUser1Withdrawal1 = new uint256[](1);
    amountsUser1Withdrawal1[0] = 5 ether;
    liquidToken.requestWithdrawal(assets, amountsUser1Withdrawal1);

    bytes32 requestIdUser1 = liquidToken.getUserWithdrawalRequests(user1)[0];
    vm.warp(block.timestamp + 15 days);
    liquidToken.fulfillWithdrawal(requestIdUser1);

    // Check balances for User1
    assertEq(testToken.balanceOf(user1), 95 ether, "User1 token balance after withdrawal is incorrect");
    assertEq(liquidToken.balanceOf(user1), 5 ether, "User1 liquid token balance after withdrawal is incorrect");

    vm.stopPrank();
    vm.startPrank(user2);

    uint256[] memory amountsUser2Withdrawal1 = new uint256[](1);
    amountsUser2Withdrawal1[0] = 10 ether;
    liquidToken.requestWithdrawal(assets, amountsUser2Withdrawal1);

    bytes32 requestIdUser2 = liquidToken.getUserWithdrawalRequests(user2)[0];
    vm.warp(block.timestamp + 15 days);
    liquidToken.fulfillWithdrawal(requestIdUser2);

    // Check balances for User2
    assertEq(testToken.balanceOf(user2), 90 ether, "User2 token balance after withdrawal is incorrect");
    assertEq(liquidToken.balanceOf(user2), 10 ether, "User2 liquid token balance after withdrawal is incorrect");

    vm.stopPrank();

    vm.prank(user1);
    uint256[] memory amountsUser1Withdrawal2 = new uint256[](1);
    amountsUser1Withdrawal2[0] = 10 ether;
    vm.expectRevert(
        abi.encodeWithSelector(
            ILiquidToken.InsufficientBalance.selector,
            address(liquidToken),
            10 ether,
            5 ether
        )
    );
    liquidToken.requestWithdrawal(assets, amountsUser1Withdrawal2);

    vm.prank(user2);
    uint256[] memory amountsUser2Withdrawal2 = new uint256[](1);
    amountsUser2Withdrawal2[0] = 15 ether;
    vm.expectRevert(
        abi.encodeWithSelector(
            ILiquidToken.InsufficientBalance.selector,
            address(liquidToken),
            15 ether,
            10 ether
        )
    );
    liquidToken.requestWithdrawal(assets, amountsUser2Withdrawal2);
}
}