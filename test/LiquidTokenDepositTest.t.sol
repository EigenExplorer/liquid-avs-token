// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LiquidToken} from "../src/core/LiquidToken.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//TODO:create mock for these 
//import {ERC20Mock} from "./mocks/ERC20Mock.sol";
//import {RebasingERC20Mock} from "./mocks/RebasingERC20Mock.sol";
//import {LiquidTokenManagerMock} from "./mocks/LiquidTokenManagerMock.sol";

contract LiquidTokenDepositTest is Test {
    LiquidToken liquidToken;
    LiquidTokenManagerMock manager;
    ERC20Mock standardToken;
    RebasingERC20Mock rebasingToken;
    ERC20Mock feeToken;
    address owner = address(0x1);
    address pauser = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);

    event AssetDeposited(
        address indexed from,
        address indexed to,
        IERC20 indexed asset,
        uint256 amount,
        uint256 shares
    );

    function setUp() public {
        // Setup standard token
        standardToken = new ERC20Mock("Standard Token", "STD");
        standardToken.mint(user1, 1000 ether);
        standardToken.mint(user2, 1000 ether);

        // Setup rebasing token that loses a small amount on transfer
        rebasingToken = new RebasingERC20Mock("Rebasing Token", "RBT");
        rebasingToken.mint(user1, 1000 ether);
        rebasingToken.mint(user2, 1000 ether);
        rebasingToken.setRebaseMode(RebasingERC20Mock.RebaseMode.LOSE_ON_TRANSFER);
        rebasingToken.setRebaseFactor(1); // Lose 1 wei per transfer
        
        // Setup fee-on-transfer token
        feeToken = new ERC20Mock("Fee Token", "FEE");
        feeToken.mint(user1, 1000 ether);
        feeToken.mint(user2, 1000 ether);
        feeToken.setFeePercent(1); // 1% fee on transfer
        
        // Deploy token manager mock
        manager = new LiquidTokenManagerMock();
        
        // Register tokens with manager
        manager.addSupportedToken(IERC20(address(standardToken)));
        manager.addSupportedToken(IERC20(address(rebasingToken)));
        manager.addSupportedToken(IERC20(address(feeToken)));
        
        // Deploy liquid token
        liquidToken = new LiquidToken();
        
        // Initialize liquid token
        LiquidToken.Init memory init = LiquidToken.Init({
            name: "Liquid Staking Token",
            symbol: "LST",
            initialOwner: owner,
            pauser: pauser,
            liquidTokenManager: ILiquidTokenManager(address(manager))
        });
        
        liquidToken.initialize(init);
        
        // Approve tokens for users
        vm.startPrank(user1);
        standardToken.approve(address(liquidToken), type(uint256).max);
        rebasingToken.approve(address(liquidToken), type(uint256).max);
        feeToken.approve(address(liquidToken), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        standardToken.approve(address(liquidToken), type(uint256).max);
        rebasingToken.approve(address(liquidToken), type(uint256).max);
        feeToken.approve(address(liquidToken), type(uint256).max);
        vm.stopPrank();
    }
    
    /* This test file include these Test Case Categories:
     * 1. Basic deposit functionality
     * 2. Rebasing token behavior
     * 3. Fee-on-transfer token behavior
     * 4. Error handling
     * 5. Edge cases
     * 6. Multi-asset deposits
     * 7. Gas edge cases
     */
    
    // ---------- Basic Deposit Functionality Tests ----------
    
    function testDepositSingleStandardToken() public {
        uint256 depositAmount = 10 ether;
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20(address(standardToken));
        amounts[0] = depositAmount;
        
        vm.startPrank(user1);
        
        uint256 userBalanceBefore = standardToken.balanceOf(user1);
        uint256 contractBalanceBefore = standardToken.balanceOf(address(liquidToken));
        
        vm.expectEmit(true, true, true, false);
        emit AssetDeposited(user1, user1, IERC20(address(standardToken)), depositAmount, depositAmount);
        
        uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
        
        uint256 userBalanceAfter = standardToken.balanceOf(user1);
        uint256 contractBalanceAfter = standardToken.balanceOf(address(liquidToken));
        
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Incorrect amount deducted from user");
        assertEq(contractBalanceAfter - contractBalanceBefore, depositAmount, "Incorrect amount received by contract");
        assertEq(sharesReceived[0], depositAmount, "Incorrect shares minted");
        assertEq(liquidToken.balanceOf(user1), depositAmount, "Incorrect token balance");
        assertEq(liquidToken.assetBalances(address(standardToken)), depositAmount, "Incorrect asset balance tracking");
        
        vm.stopPrank();
    }
    
    function testDepositToAnotherReceiver() public {
        uint256 depositAmount = 10 ether;
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20(address(standardToken));
        amounts[0] = depositAmount;
        
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, true, false);
        emit AssetDeposited(user1, user2, IERC20(address(standardToken)), depositAmount, depositAmount);
        
        liquidToken.deposit(assets, amounts, user2);
        
        assertEq(liquidToken.balanceOf(user1), 0, "User1 should not receive shares");
        assertEq(liquidToken.balanceOf(user2), depositAmount, "User2 should receive shares");
        
        vm.stopPrank();
    }
    
    // ---------- Rebasing Token Tests ----------
    
    function testDepositRebasingToken() public {
        uint256 depositAmount = 10 ether;
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20(address(rebasingToken));
        amounts[0] = depositAmount;
        
        vm.startPrank(user1);
        
        uint256 userBalanceBefore = rebasingToken.balanceOf(user1);
        uint256 contractBalanceBefore = rebasingToken.balanceOf(address(liquidToken));
        
        uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
        
        uint256 userBalanceAfter = rebasingToken.balanceOf(user1);
        uint256 contractBalanceAfter = rebasingToken.balanceOf(address(liquidToken));
        uint256 actualTransferred = contractBalanceAfter - contractBalanceBefore;
        
        // Should be depositAmount - 1 due to rebasing behavior
        assertEq(actualTransferred, depositAmount - 1, "Wrong amount received after rebasing");
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong amount deducted from user");
        assertEq(sharesReceived[0], depositAmount - 1, "Shares should be based on actual received amount");
        assertEq(liquidToken.assetBalances(address(rebasingToken)), depositAmount - 1, "Asset balance tracking incorrect");
        
        vm.stopPrank();
    }
    
    function testDepositRebasingTokenWithRebaseUp() public {
        // Setup rebasing token that gains value on transfer
        rebasingToken.setRebaseMode(RebasingERC20Mock.RebaseMode.GAIN_ON_TRANSFER);
        rebasingToken.setRebaseFactor(10); // Gain 10 wei per transfer
        
        uint256 depositAmount = 10 ether;
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20(address(rebasingToken));
        amounts[0] = depositAmount;
        
        vm.startPrank(user1);
        
        uint256 contractBalanceBefore = rebasingToken.balanceOf(address(liquidToken));
        
        uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
        
        uint256 contractBalanceAfter = rebasingToken.balanceOf(address(liquidToken));
        uint256 actualTransferred = contractBalanceAfter - contractBalanceBefore;
        
        // Should be depositAmount + 10 due to rebasing up
        assertEq(actualTransferred, depositAmount + 10, "Wrong amount received after rebasing up");
        assertEq(sharesReceived[0], depositAmount + 10, "Shares should be based on actual received amount");
        assertEq(liquidToken.assetBalances(address(rebasingToken)), depositAmount + 10, "Asset balance tracking incorrect");
        
        vm.stopPrank();
    }
    
    function testDepositRebasingTokenWithSuddenRebase() public {
        uint256 depositAmount = 10 ether;
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20(address(rebasingToken));
        amounts[0] = depositAmount;
        
        vm.startPrank(user1);
        
        // First deposit to establish baseline
        liquidToken.deposit(assets, amounts, user1);
        
        // Change rebase behavior dramatically
        rebasingToken.setRebaseFactor(1 ether / 10); // Lose 0.1 ETH per transfer
        
        // Second deposit should still work with new rebase factor
        uint256 contractBalanceBefore = rebasingToken.balanceOf(address(liquidToken));
        
        uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
        
        uint256 contractBalanceAfter = rebasingToken.balanceOf(address(liquidToken));
        uint256 actualTransferred = contractBalanceAfter - contractBalanceBefore;
        
        // Should be depositAmount - 0.1 ETH
        assertEq(actualTransferred, depositAmount - (1 ether / 10), "Wrong amount received after major rebase");
        assertEq(sharesReceived[0], depositAmount - (1 ether / 10), "Shares incorrect after major rebase");
        
        vm.stopPrank();
    }
    
    // ---------- Fee-On-Transfer Token Tests ----------
    
    function testDepositFeeToken() public {
        uint256 depositAmount = 10 ether;
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = IERC20(address(feeToken));
        amounts[0] = depositAmount;
        
        vm.startPrank(user1);
        
        uint256 userBalanceBefore = feeToken.balanceOf(user1);
        uint256 contractBalanceBefore = feeToken.balanceOf(address(liquidToken));
        
        uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
        
        uint256 userBalanceAfter = feeToken.balanceOf(user1);
        uint256 contractBalanceAfter = feeToken.balanceOf(address(liquidToken));
        uint256 actualTransferred = contractBalanceAfter - contractBalanceBefore;
        
        // 1% fee on 10 ether = 0.1 ether taken as fee
        uint256 expectedReceived = depositAmount * 99 / 100;
        
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Full amount should be deducted from user");
        assertEq(actualTransferred, expectedReceived, "Contract should receive amount minus fee");
        assertEq(sharesReceived[0], expectedReceived, "Shares should be based on actual received amount");
        assertEq(liquidToken.assetBalances(address(feeToken)), expectedReceived, "Asset balance tracking incorrect");
        
        vm.stopPrank();
    }
    
    // ---------- Error Cases Tests ----------
    
    function testRevertDepositArrayLengthMismatch() public {
        IERC20[] memory assets = new IERC20[](2);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        assets[1] = IERC20(address(rebasingToken));
        amounts[0] = 1 ether;
        
        vm.startPrank(user1);
        
        vm.expectRevert(LiquidToken.ArrayLengthMismatch.selector);
        liquidToken.deposit(assets, amounts, user1);
        
        vm.stopPrank();
    }
    
    function testRevertDepositZeroAmount() public {
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = 0;
        
        vm.startPrank(user1);
        
        vm.expectRevert(LiquidToken.ZeroAmount.selector);
        liquidToken.deposit(assets, amounts, user1);
        
        vm.stopPrank();
    }
    
    function testRevertDepositUnsupportedAsset() public {
        // Create unsupported token
        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported Token", "UNS");
        unsupportedToken.mint(user1, 1000 ether);
        
        vm.startPrank(user1);
        unsupportedToken.approve(address(liquidToken), type(uint256).max);
        
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(unsupportedToken));
        amounts[0] = 1 ether;
        
        vm.expectRevert(abi.encodeWithSelector(LiquidToken.UnsupportedAsset.selector, IERC20(address(unsupportedToken))));
        liquidToken.deposit(assets, amounts, user1);
        
        vm.stopPrank();
    }
    
    function testRevertWhenPaused() public {
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = 1 ether;
        
        // Pause the contract
        vm.prank(pauser);
        liquidToken.pause();
        
        vm.startPrank(user1);
        
        vm.expectRevert("Pausable: paused");
        liquidToken.deposit(assets, amounts, user1);
        
        vm.stopPrank();
    }
    
    function testRevertInsufficientAllowance() public {
        address newUser = address(0x5);
        standardToken.mint(newUser, 1000 ether);
        
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = 10 ether;
        
        vm.startPrank(newUser);
        // No approval given
        
        vm.expectRevert();
        liquidToken.deposit(assets, amounts, newUser);
        
        vm.stopPrank();
    }
    
    function testRevertInsufficientBalance() public {
        address poorUser = address(0x6);
        standardToken.mint(poorUser, 1 ether); // Only 1 ETH
        
        vm.startPrank(poorUser);
        standardToken.approve(address(liquidToken), type(uint256).max);
        
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = 10 ether; // Try to deposit 10 ETH
        
        vm.expectRevert();
        liquidToken.deposit(assets, amounts, poorUser);
        
        vm.stopPrank();
    }
    
    // ---------- Edge Cases Tests ----------
    
    function testDepositMaxAmount() public {
        // Test with an extremely large value
        uint256 largeAmount = 1000000 ether;
        standardToken.mint(user1, largeAmount);
        
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = largeAmount;
        
        vm.startPrank(user1);
        
        liquidToken.deposit(assets, amounts, user1);
        
        assertEq(liquidToken.balanceOf(user1), largeAmount);
        assertEq(liquidToken.assetBalances(address(standardToken)), largeAmount);
        
        vm.stopPrank();
    }
    
    function testDepositSmallAmount() public {
        // Test with a tiny amount
        uint256 smallAmount = 1; // 1 wei
        
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = smallAmount;
        
        vm.startPrank(user1);
        
        uint256[] memory shares = liquidToken.deposit(assets, amounts, user1);
        
        assertEq(shares[0], smallAmount);
        assertEq(liquidToken.balanceOf(user1), smallAmount);
        
        vm.stopPrank();
    }
    
    function testDepositWithZeroShares() public {
        // Configure token manager to return 0 shares
        manager.setConversionMode(LiquidTokenManagerMock.ConversionMode.RETURN_ZERO);
        
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        
        assets[0] = IERC20(address(standardToken));
        amounts[0] = 1 ether;
        
        vm.startPrank(user1);
        
        vm.expectRevert(LiquidToken.ZeroShares.selector);
        liquidToken.deposit(assets, amounts, user1);
        
        vm.stopPrank();
    }
    
    // ---------- Multi-Asset Deposits Tests ----------
    
    function testDepositMultipleAssets() public {
        IERC20[] memory assets = new IERC20[](3);
        uint256[] memory amounts = new uint256[](3);
        
        assets[0] = IERC20(address(standardToken));
        assets[1] = IERC20(address(rebasingToken));
        assets[2] = IERC20(address(feeToken));
        
        amounts[0] = 5 ether;
        amounts[1] = 10 ether;
        amounts[2] = 15 ether;
        
        vm.startPrank(user1);
        
        uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
        
        // Standard token
        assertEq(sharesReceived[0], 5 ether, "Standard token shares incorrect");
        
        // Rebasing token (loses 1 wei)
        assertEq(sharesReceived[1], 10 ether - 1, "Rebasing token shares incorrect");
        
        // Fee token (1% fee)
        assertEq(sharesReceived[2], 15 ether * 99 / 100, "Fee token shares incorrect");
        
        // Total shares should be sum of all
        uint256 expectedTotalShares = 5 ether + (10 ether - 1) + (15 ether * 99 / 100);
        assertEq(liquidToken.balanceOf(user1), expectedTotalShares, "Total shares incorrect");
        
        vm.stopPrank();
    }
    
    function testDepositMultipleAssetsWithOneFailing() public {
        IERC20[] memory assets = new IERC20[](3);
        uint256[] memory amounts = new uint256[](3);
        
        // Create token that will revert on transfer
        ERC20Mock revertingToken = new ERC20Mock("Reverting Token", "RVT");
        revertingToken.mint(user1, 1000 ether);
        revertingToken.setShouldRevert(true);
        
        // Add to supported tokens
        manager.addSupportedToken(IERC20(address(revertingToken)));
        
        assets[0] = IERC20(address(standardToken));
        assets[1] = IERC20(address(revertingToken)); // This one will revert
        assets[2] = IERC20(address(rebasingToken));
        
        amounts[0] = 5 ether;
        amounts[1] = 10 ether;
        amounts[2] = 15 ether;
        
        vm.startPrank(user1);
        revertingToken.approve(address(liquidToken), type(uint256).max);
        
        // The entire transaction should revert
        vm.expectRevert("ERC20Mock: transfer reverted");
        liquidToken.deposit(assets, amounts, user1);
        
        // Verify no partial effects occurred
        assertEq(liquidToken.balanceOf(user1), 0, "No shares should be minted on failure");
        assertEq(liquidToken.assetBalances(address(standardToken)), 0, "No assets should be tracked on failure");
        
        vm.stopPrank();
    }
    
    // ---------- Gas Optimization Edge Cases ----------
    
    function testDepositWithManyAssets() public {
        // Test with a lot of different assets
        uint256 assetCount = 10;
        IERC20[] memory assets = new IERC20[](assetCount);
        uint256[] memory amounts = new uint256[](assetCount);
        
        // Create and approve multiple tokens
        for (uint256 i = 0; i < assetCount; i++) {
            ERC20Mock token = new ERC20Mock(
                string(abi.encodePacked("Token ", i)),
                string(abi.encodePacked("TK", i))
            );
            token.mint(user1, 1000 ether);
            
            manager.addSupportedToken(IERC20(address(token)));
            
            vm.startPrank(user1);
            token.approve(address(liquidToken), type(uint256).max);
            vm.stopPrank();
            
            assets[i] = IERC20(address(token));
            amounts[i] = 1 ether;
        }
        
        vm.startPrank(user1);
        
        // Measure gas usage
        uint256 gasStart = gasleft();
        liquidToken.deposit(assets, amounts, user1);
        uint256 gasUsed = gasStart - gasleft();
        
        // TODO: check the Log gas used for reference
        //console.log("Gas used for depositing", assetCount, "assets:", gasUsed);
        
        // Check total shares
        assertEq(liquidToken.balanceOf(user1), assetCount * 1 ether);
        
        vm.stopPrank();
    }

    
    // ---------- Tests for Updated Deposit Function ----------

function testUpdateDepositRebasingToken() public {
    // This test verifies the updated deposit function handles rebasing tokens correctly
    uint256 depositAmount = 10 ether;
    IERC20[] memory assets = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);
    assets[0] = IERC20(address(rebasingToken));
    amounts[0] = depositAmount;
    
    // Set rebasing to lose 5% on transfer
    rebasingToken.setRebaseMode(RebasingERC20Mock.RebaseMode.LOSE_ON_TRANSFER);
    rebasingToken.setRebaseFactor(depositAmount * 5 / 100); // 5% loss
    
    vm.startPrank(user1);
    
    uint256 userBalanceBefore = rebasingToken.balanceOf(user1);
    uint256 contractBalanceBefore = rebasingToken.balanceOf(address(liquidToken));
    
    uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
    
    uint256 userBalanceAfter = rebasingToken.balanceOf(user1);
    uint256 contractBalanceAfter = rebasingToken.balanceOf(address(liquidToken));
    uint256 actualTransferred = contractBalanceAfter - contractBalanceBefore;
    
    // Expected amount after 5% rebasing loss
    uint256 expectedAmount = depositAmount * 95 / 100;
    
    // Check that full amount was deducted from user
    assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "User balance should be reduced by full amount");
    
    // Check that contract received rebased amount
    assertEq(actualTransferred, expectedAmount, "Contract should receive rebased amount");
    
    // Check that shares are based on actual received amount
    assertEq(sharesReceived[0], expectedAmount, "Shares should be based on actual received amount");
    
    // Check that asset balance tracking uses actual amount
    assertEq(liquidToken.assetBalances(address(rebasingToken)), expectedAmount, "Asset balance tracking should use actual amount");
    
    vm.stopPrank();
}

function testUpdateDepositFeeToken() public {
    // This test verifies the updated deposit function handles fee-on-transfer tokens correctly
    uint256 depositAmount = 10 ether;
    IERC20[] memory assets = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);
    assets[0] = IERC20(address(feeToken));
    amounts[0] = depositAmount;
    
    // Set fee to 5%
    feeToken.setFeePercent(5); // 5% fee
    
    vm.startPrank(user1);
    
    uint256 userBalanceBefore = feeToken.balanceOf(user1);
    uint256 contractBalanceBefore = feeToken.balanceOf(address(liquidToken));
    
    uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
    
    uint256 userBalanceAfter = feeToken.balanceOf(user1);
    uint256 contractBalanceAfter = feeToken.balanceOf(address(liquidToken));
    uint256 actualTransferred = contractBalanceAfter - contractBalanceBefore;
    
    // Expected amount after 5% fee
    uint256 expectedAmount = depositAmount * 95 / 100;
    
    // Check that full amount was deducted from user
    assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "User balance should be reduced by full amount");
    
    // Check that contract received amount minus fee
    assertEq(actualTransferred, expectedAmount, "Contract should receive amount minus fee");
    
    // Check that shares are based on actual received amount
    assertEq(sharesReceived[0], expectedAmount, "Shares should be based on actual received amount");
    
    // Check that asset balance tracking uses actual amount
    assertEq(liquidToken.assetBalances(address(feeToken)), expectedAmount, "Asset balance tracking should use actual amount");
    
    vm.stopPrank();
}

function testUpdateDepositWithVariableRebasing() public {
    // Test with rebasing that varies between transactions
    uint256 depositAmount = 10 ether;
    IERC20[] memory assets = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);
    assets[0] = IERC20(address(rebasingToken));
    amounts[0] = depositAmount;
    
    vm.startPrank(user1);
    
    // First deposit with 1% loss
    rebasingToken.setRebaseMode(RebasingERC20Mock.RebaseMode.LOSE_ON_TRANSFER);
    rebasingToken.setRebaseFactor(depositAmount * 1 / 100); // 1% loss
    
    uint256 contractBalanceBefore1 = rebasingToken.balanceOf(address(liquidToken));
    uint256[] memory sharesReceived1 = liquidToken.deposit(assets, amounts, user1);
    uint256 contractBalanceAfter1 = rebasingToken.balanceOf(address(liquidToken));
    uint256 actualTransferred1 = contractBalanceAfter1 - contractBalanceBefore1;
    
    // Second deposit with 3% loss
    rebasingToken.setRebaseFactor(depositAmount * 3 / 100); // 3% loss
    
    uint256 contractBalanceBefore2 = rebasingToken.balanceOf(address(liquidToken));
    uint256[] memory sharesReceived2 = liquidToken.deposit(assets, amounts, user1);
    uint256 contractBalanceAfter2 = rebasingToken.balanceOf(address(liquidToken));
    uint256 actualTransferred2 = contractBalanceAfter2 - contractBalanceBefore2;
    
    // First deposit should have 1% loss
    uint256 expectedAmount1 = depositAmount * 99 / 100;
    assertEq(actualTransferred1, expectedAmount1, "First deposit should receive 99% of amount");
    assertEq(sharesReceived1[0], expectedAmount1, "First deposit should get shares for 99% of amount");
    
    // Second deposit should have 3% loss
    uint256 expectedAmount2 = depositAmount * 97 / 100;
    assertEq(actualTransferred2, expectedAmount2, "Second deposit should receive 97% of amount");
    assertEq(sharesReceived2[0], expectedAmount2, "Second deposit should get shares for 97% of amount");
    
    vm.stopPrank();
}

function testUpdateDepositMultipleAssets() public {
    IERC20[] memory assets = new IERC20[](3);
    uint256[] memory amounts = new uint256[](3);
    
    assets[0] = IERC20(address(standardToken)); // No rebasing/fee
    assets[1] = IERC20(address(rebasingToken)); // Rebasing token
    assets[2] = IERC20(address(feeToken));      // Fee token
    
    amounts[0] = 5 ether;
    amounts[1] = 10 ether;
    amounts[2] = 15 ether;
    
    // Set rebasing to lose 2% on transfer
    rebasingToken.setRebaseMode(RebasingERC20Mock.RebaseMode.LOSE_ON_TRANSFER);
    rebasingToken.setRebaseFactor(amounts[1] * 2 / 100); // 2% loss
    
    // Set fee to 3%
    feeToken.setFeePercent(3); // 3% fee
    
    vm.startPrank(user1);
    
    uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
    
    // Standard token should be unchanged
    assertEq(sharesReceived[0], 5 ether, "Standard token shares incorrect");
    
    // Rebasing token should have 2% loss
    uint256 expectedRebasingShares = 10 ether * 98 / 100;
    assertEq(sharesReceived[1], expectedRebasingShares, "Rebasing token shares incorrect");
    
    // Fee token should have 3% fee
    uint256 expectedFeeShares = 15 ether * 97 / 100;
    assertEq(sharesReceived[2], expectedFeeShares, "Fee token shares incorrect");
    
    // Check asset balance tracking
    assertEq(liquidToken.assetBalances(address(standardToken)), 5 ether, "Standard token balance incorrect");
    assertEq(liquidToken.assetBalances(address(rebasingToken)), expectedRebasingShares, "Rebasing token balance incorrect");
    assertEq(liquidToken.assetBalances(address(feeToken)), expectedFeeShares, "Fee token balance incorrect");
    
    // Total shares should be sum of all
    uint256 expectedTotalShares = 5 ether + expectedRebasingShares + expectedFeeShares;
    assertEq(liquidToken.balanceOf(user1), expectedTotalShares, "Total shares incorrect");
    
    vm.stopPrank();
}



function testUpdateDepositWithZeroAmountReceived() public {
    // Test where transfer results in zero amount received
    uint256 depositAmount = 10 ether;
    IERC20[] memory assets = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);
    assets[0] = IERC20(address(rebasingToken));
    amounts[0] = depositAmount;
    
    // Set 100% loss on transfer
    rebasingToken.setRebaseMode(RebasingERC20Mock.RebaseMode.LOSE_ON_TRANSFER);
    rebasingToken.setRebaseFactor(depositAmount); // 100% loss
    
    vm.startPrank(user1);
    
    // Should revert with ZeroShares since the deposit results in zero tokens
    vm.expectRevert(LiquidToken.ZeroShares.selector);
    liquidToken.deposit(assets, amounts, user1);
    
    vm.stopPrank();
}

function testUpdateDepositOverflowManagement() public {
    // Test how the contract handles potential overflows in arithmetic
    uint256 depositAmount = type(uint256).max - 1000; // Very large deposit
    standardToken.mint(user1, depositAmount);
    
    IERC20[] memory assets = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);
    assets[0] = IERC20(address(standardToken));
    amounts[0] = depositAmount;
    
    vm.startPrank(user1);
    
    uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
    
    assertEq(sharesReceived[0], depositAmount, "Shares should equal deposit amount");
    assertEq(standardToken.balanceOf(address(liquidToken)), depositAmount, "Contract should receive full amount");
    assertEq(liquidToken.assetBalances(address(standardToken)), depositAmount, "Asset balance tracking should match");
    
    vm.stopPrank();
}

function testTransactionRevertSafetyWithFuzzing(uint256 amount) public {
    // Fuzz test to see if any amount causes unexpected behavior
    // TODO:Bound the amount to reasonable values
    amount = bound(amount, 1, 1000000 ether);
    
    standardToken.mint(user1, amount);
    
    IERC20[] memory assets = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);
    assets[0] = IERC20(address(standardToken));
    amounts[0] = amount;
    
    vm.startPrank(user1);
    
    uint256[] memory sharesReceived = liquidToken.deposit(assets, amounts, user1);
    
    assertEq(sharesReceived[0], amount, "Shares should equal deposit amount");
    assertEq(standardToken.balanceOf(address(liquidToken)), amount, "Contract should receive full amount");
    assertEq(liquidToken.assetBalances(address(standardToken)), amount, "Asset balance tracking should match");
    
    vm.stopPrank();
}
}

// Mock contract for rebasing ERC20 token
contract RebasingERC20Mock is ERC20Mock {
    enum RebaseMode { NONE, LOSE_ON_TRANSFER, GAIN_ON_TRANSFER }
    
    RebaseMode public rebaseMode = RebaseMode.NONE;
    uint256 public rebaseFactor = 0;
    
    constructor(string memory name, string memory symbol) ERC20Mock(name, symbol) {}
    
    function setRebaseMode(RebaseMode mode) external {
        rebaseMode = mode;
    }
    
    function setRebaseFactor(uint256 factor) external {
        rebaseFactor = factor;
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (rebaseMode == RebaseMode.LOSE_ON_TRANSFER) {
            // Transfer slightly less than requested
            uint256 actualAmount = amount > rebaseFactor ? amount - rebaseFactor : 0;
            return super.transfer(to, actualAmount);
        } else if (rebaseMode == RebaseMode.GAIN_ON_TRANSFER) {
            // Transfer slightly more than requested
            uint256 actualAmount = amount + rebaseFactor;
            // Mint the extra to the recipient
            _mint(to, rebaseFactor);
            return super.transfer(to, amount);
        } else {
            return super.transfer(to, amount);
        }
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (rebaseMode == RebaseMode.LOSE_ON_TRANSFER) {
            // Transfer slightly less than requested
            uint256 actualAmount = amount > rebaseFactor ? amount - rebaseFactor : 0;
            return super.transferFrom(from, to, actualAmount);
        } else if (rebaseMode == RebaseMode.GAIN_ON_TRANSFER) {
            // Transfer slightly more than requested
            _mint(to, rebaseFactor);
            return super.transferFrom(from, to, amount);
        } else {
            return super.transferFrom(from, to, amount);
        }
    }
}

// Mock contract for the LiquidTokenManager
contract LiquidTokenManagerMock is ILiquidTokenManager {
    enum ConversionMode { IDENTITY, RETURN_ZERO, CUSTOM_MULTIPLIER }
    
    mapping(address => bool) public supportedTokens;
    address[] public supportedTokenList;
    ConversionMode public conversionMode = ConversionMode.IDENTITY;
    uint256 public conversionMultiplier = 1;
    
    function addSupportedToken(IERC20 token) external {
        supportedTokens[address(token)] = true;
        supportedTokenList.push(address(token));
    }
    
    function setConversionMode(ConversionMode mode) external {
        conversionMode = mode;
    }
    
    function setConversionMultiplier(uint256 multiplier) external {
        conversionMultiplier = multiplier;
    }
    
    function tokenIsSupported(IERC20 token) external view override returns (bool) {
        return supportedTokens[address(token)];
    }
    
    function getSupportedTokens() external view override returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](supportedTokenList.length);
        for (uint256 i = 0; i < supportedTokenList.length; i++) {
            tokens[i] = IERC20(supportedTokenList[i]);
        }
        return tokens;
    }
    
    function convertToUnitOfAccount(IERC20 token, uint256 amount) external view override returns (uint256) {
        if (conversionMode == ConversionMode.RETURN_ZERO) {
            return 0;
        } else if (conversionMode == ConversionMode.CUSTOM_MULTIPLIER) {
            return amount * conversionMultiplier;
        } else {
            return amount; // Identity conversion
        }
    }
    
    function convertFromUnitOfAccount(IERC20 token, uint256 amount) external view override returns (uint256) {
        if (conversionMode == ConversionMode.RETURN_ZERO) {
            return 0;
        } else if (conversionMode == ConversionMode.CUSTOM_MULTIPLIER) {
            return amount / conversionMultiplier;
        } else {
            return amount; // Identity conversion
        }
    }
    
    function getStakedAssetBalance(IERC20 token) external view override returns (uint256) {
        return 0; // No staked assets in mock
    }
    
    // Not implementing unused functions for the mock
    function depositAssets(IERC20[] calldata, uint256[] calldata) external override {}
    function withdrawAssets(IERC20[] calldata, uint256[] calldata) external override {}
    function queueWithdrawal(address, IERC20[] calldata, uint256[] calldata) external override {}
    function processWithdrawalQueue() external override {}
}

// Extending ERC20Mock to support fees and custom behavior
contract ERC20Mock is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;
    uint256 private _totalSupply;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    bool public shouldRevert = false;
    uint256 public feePercent = 0; // Fee in percentage points (1 = 1%)
    
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }
    
    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }
    
    function setFeePercent(uint256 percent) external {
        require(percent <= 100, "Fee cannot exceed 100%");
        feePercent = percent;
    }
    
    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (shouldRevert) {
            revert("ERC20Mock: transfer reverted");
        }
        
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }
    
function allowance(address owner, address spender) public view override returns (uint256) {
    return _allowances[owner][spender];
}

function approve(address spender, uint256 amount) public override returns (bool) {
    _approve(msg.sender, spender, amount);
    return true;
}

function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
    if (shouldRevert) {
        revert("ERC20Mock: transferFrom reverted");
    }
    
    address spender = msg.sender;
    _spendAllowance(from, spender, amount);
    _transfer(from, to, amount);
    return true;
}

function mint(address account, uint256 amount) public {
    _mint(account, amount);
}

function burn(address account, uint256 amount) public {
    _burn(account, amount);
}

function _transfer(address from, address to, uint256 amount) internal {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");
    
    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
    
    // Calculate fee if enabled
    uint256 fee = amount * feePercent / 100;
    uint256 actualAmount = amount - fee;
    
    unchecked {
        _balances[from] = fromBalance - amount;
        _balances[to] += actualAmount;
    }
    
    emit Transfer(from, to, actualAmount);
}

function _mint(address account, uint256 amount) internal {
    require(account != address(0), "ERC20: mint to the zero address");
    
    _totalSupply += amount;
    unchecked {
        _balances[account] += amount;
    }
    emit Transfer(address(0), account, amount);
}

function _burn(address account, uint256 amount) internal {
    require(account != address(0), "ERC20: burn from the zero address");
    
    uint256 accountBalance = _balances[account];
    require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;
    }
    
    emit Transfer(account, address(0), amount);
}

function _approve(address owner, address spender, uint256 amount) internal {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");
    
    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
}

function _spendAllowance(address owner, address spender, uint256 amount) internal {
    uint256 currentAllowance = allowance(owner, spender);
    if (currentAllowance != type(uint256).max) {
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        unchecked {
            _approve(owner, spender, currentAllowance - amount);
        }
    }
}
}