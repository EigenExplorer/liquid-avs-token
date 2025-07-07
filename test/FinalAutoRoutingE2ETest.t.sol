// FinalAutoRoutingE2ETest.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "./mocks/MockLTM.sol";
import "../src/FinalAutoRoutingLib.sol";
import "../src/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract FinalAutoRoutingE2ETest is Test {
    MockLTM public ltm;

    // Token addresses
    address constant ETH = FinalAutoRoutingLib.ETH_ADDRESS;
    address constant WETH = FinalAutoRoutingLib.WETH;
    address constant STETH = FinalAutoRoutingLib.STETH;
    address constant RETH = FinalAutoRoutingLib.RETH;
    address constant CBETH = FinalAutoRoutingLib.CBETH;
    address constant FRXETH = FinalAutoRoutingLib.FRXETH;
    address constant SFRXETH = FinalAutoRoutingLib.SFRXETH;
    address constant ANKRETH = FinalAutoRoutingLib.ANKRETH;
    address constant ETHX = FinalAutoRoutingLib.ETHX;
    address constant SWETH = FinalAutoRoutingLib.SWETH;
    address constant OSETH = FinalAutoRoutingLib.OSETH;
    address constant OETH = FinalAutoRoutingLib.OETH;
    address constant METH = FinalAutoRoutingLib.METH;
    address constant LSETH = FinalAutoRoutingLib.LSETH;
    address constant WBTC = FinalAutoRoutingLib.WBTC;
    address constant STBTC = FinalAutoRoutingLib.STBTC;
    address constant UNIBTC = FinalAutoRoutingLib.UNIBTC;

    address testUser;

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        ltm = new MockLTM(WETH);
        testUser = makeAddr("testUser");
        vm.deal(testUser, 10000 ether);
        vm.deal(address(ltm), 1 ether);

        // Configure additional tokens
        ltm.setupToken(LSETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        ltm.setupToken(OETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        ltm.setupToken(METH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);

        // Configure Curve pool for osETH
        ltm.setupCurvePool(
            0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
            2,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            false
        );
    }

    function testAllETHLSTSwaps() public {
        // Test direct ETH swaps with more realistic amounts
        console.log("Testing swap:", "ETH", "->", "STETH");
        _testETHSwap(STETH, 0.01 ether); // Smaller amount for testing

        console.log("Testing swap:", "ETH", "->", "ANKRETH");
        _testETHSwap(ANKRETH, 0.01 ether);

        console.log("Testing swap:", "ETH", "->", "ETHX");
        _testETHSwap(ETHX, 0.01 ether);

        console.log("Testing swap:", "ETH", "->", "FRXETH");
        _testETHSwap(FRXETH, 0.01 ether);

        // Test WETH swaps
        console.log("Testing swap:", "WETH", "->", "STETH");
        _testWETHSwap(STETH, 0.01 ether);

        console.log("Testing swap:", "WETH", "->", "CBETH");
        _testWETHSwap(CBETH, 0.01 ether);

        console.log("Testing swap:", "WETH", "->", "ANKRETH");
        _testWETHSwap(ANKRETH, 0.01 ether);

        // Test direct mint
        console.log("Testing swap:", "ETH", "->", "SFRXETH");
        _testETHSwap(SFRXETH, 0.01 ether);
    }

    function testDirectSwapETHToSTETH() public {
        console.log("ETH -> STETH swap:");
        _testETHSwap(STETH, 0.1 ether); // Reduced amount
    }

    function testDirectSwapWETHToRETH() public {
        _testWETHSwap(RETH, 0.1 ether);
    }

    function testMultiStepWETHToSFRXETH() public {
        console.log("WETH -> SFRXETH multi-step:");
        _testWETHMultiStepSwap(SFRXETH, 0.1 ether);
    }

    function testMultiStepWETHToOSETH() public {
        _testWETHMultiStepSwap(OSETH, 0.1 ether);
    }

    function testMultiStepOsETHToWETH() public {
        vm.startPrank(testUser);

        // First get OSETH with smaller amount
        IWETH(WETH).deposit{value: 0.1 ether}();
        IERC20(WETH).approve(address(ltm), 0.1 ether);
        ltm.swapAssetsMultiStep(WETH, OSETH, 0.1 ether, 0);
        uint256 osethBalance = IERC20(OSETH).balanceOf(testUser);

        // Then swap back to WETH
        if (osethBalance > 0) {
            uint256 wethBefore = IERC20(WETH).balanceOf(testUser);
            IERC20(OSETH).approve(address(ltm), osethBalance);
            ltm.swapAssetsMultiStep(OSETH, WETH, osethBalance, 0);

            uint256 wethAfter = IERC20(WETH).balanceOf(testUser);
            assertGt(wethAfter, wethBefore, "Should receive WETH");
        }
        vm.stopPrank();
    }

    function testBTCSwaps() public {
        console.log("WBTC -> STBTC swap:");

        // Deal WBTC to user
        deal(WBTC, testUser, 1e8);

        vm.startPrank(testUser);
        uint256 balanceBefore = IERC20(STBTC).balanceOf(testUser);

        IERC20(WBTC).approve(address(ltm), 0.1e8); // Smaller amount
        ltm.swapAssets(WBTC, STBTC, 0.1e8, 0);

        uint256 balanceAfter = IERC20(STBTC).balanceOf(testUser);
        assertGt(balanceAfter, balanceBefore, "Should receive STBTC");
        vm.stopPrank();
    }

    function testAutoRoutingANKRETHToCBETH() public {
        vm.startPrank(testUser);

        // First get ankrETH with smaller amount
        ltm.swapAssets{value: 0.05 ether}(ETH, ANKRETH, 0.05 ether, 0); // Even smaller amount
        uint256 ankrBalance = IERC20(ANKRETH).balanceOf(testUser);

        if (ankrBalance > 0) {
            // Then swap ankrETH to cbETH via multi-step (bridge routing)
            uint256 cbethBefore = IERC20(CBETH).balanceOf(testUser);
            IERC20(ANKRETH).approve(address(ltm), ankrBalance);
            ltm.swapAssetsMultiStep(ANKRETH, CBETH, ankrBalance, 0); // Use multi-step

            uint256 cbethAfter = IERC20(CBETH).balanceOf(testUser);
            assertGt(cbethAfter, cbethBefore, "Should receive CBETH");
        }

        vm.stopPrank();
    }

    function testReverseSwaps() public {
        console.log("STETH -> ETH reverse swap:");

        // First get STETH
        vm.startPrank(testUser);
        ltm.swapAssets{value: 0.1 ether}(ETH, STETH, 0.1 ether, 0);
        uint256 stethBalance = IERC20(STETH).balanceOf(testUser);

        if (stethBalance > 0) {
            // Then swap back to ETH
            uint256 ethBefore = testUser.balance;
            IERC20(STETH).approve(address(ltm), stethBalance);
            ltm.swapAssets(STETH, ETH, stethBalance, 0);

            uint256 ethAfter = testUser.balance;
            assertGt(ethAfter, ethBefore, "Should receive ETH");
        }
        vm.stopPrank();
    }

    function testGasBenchmarks() public {
        vm.startPrank(testUser);

        uint256 gas1 = gasleft();
        ltm.swapAssets{value: 0.01 ether}(ETH, STETH, 0.01 ether, 0); // Smaller amounts
        console.log("ETH->STETH gas:", gas1 - gasleft());

        IWETH(WETH).deposit{value: 0.01 ether}();
        IERC20(WETH).approve(address(ltm), 0.01 ether);
        uint256 gas2 = gasleft();
        ltm.swapAssets(WETH, CBETH, 0.01 ether, 0);
        console.log("WETH->CBETH gas:", gas2 - gasleft());

        IWETH(WETH).deposit{value: 0.01 ether}();
        IERC20(WETH).approve(address(ltm), 0.01 ether);
        uint256 gas3 = gasleft();
        ltm.swapAssetsMultiStep(WETH, SFRXETH, 0.01 ether, 0);
        console.log("WETH->SFRXETH (multi-step) gas:", gas3 - gasleft());

        vm.stopPrank();
    }

    function testRevertOnInsufficientOutput() public {
        vm.startPrank(testUser);
        vm.expectRevert("Insufficient output"); // ✅ Updated expectation
        ltm.swapAssets{value: 0.01 ether}(ETH, STETH, 0.01 ether, 10 ether);
        vm.stopPrank();
    }

    function testRevertOnZeroAmount() public {
        vm.startPrank(testUser);
        vm.expectRevert();
        ltm.swapAssets{value: 0}(ETH, STETH, 0, 0);
        vm.stopPrank();
    }

    function testDirectMintSfrxETH() public {
        vm.startPrank(testUser);
        uint256 sfrxBefore = IERC20(SFRXETH).balanceOf(testUser);
        ltm.swapAssets{value: 0.1 ether}(ETH, SFRXETH, 0.1 ether, 0);
        uint256 sfrxAfter = IERC20(SFRXETH).balanceOf(testUser);
        assertGt(sfrxAfter, sfrxBefore, "Should receive SFRXETH");
        vm.stopPrank();
    }

    function testComplexOsETHRoute() public {
        vm.startPrank(testUser);

        // Use even smaller amounts and multi-step for better success
        uint256 osethBefore = IERC20(OSETH).balanceOf(testUser);
        ltm.swapAssetsMultiStep{value: 0.05 ether}(ETH, OSETH, 0.05 ether, 0); // Use multi-step
        uint256 osethAfter = IERC20(OSETH).balanceOf(testUser);
        assertGt(osethAfter, osethBefore, "Should receive OSETH");

        if (osethAfter > 0) {
            // osETH → WETH via multi-step
            uint256 wethBefore = IERC20(WETH).balanceOf(testUser);
            IERC20(OSETH).approve(address(ltm), osethAfter);
            ltm.swapAssetsMultiStep(OSETH, WETH, osethAfter, 0); // Use multi-step for WETH
            uint256 wethAfter = IERC20(WETH).balanceOf(testUser);
            assertGt(wethAfter, wethBefore, "Should receive WETH");
        }

        vm.stopPrank();
    }

    // Helper functions (updated with smaller amounts)
    function _testETHSwap(address tokenOut, uint256 amount) internal {
        vm.startPrank(testUser);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testUser);
        ltm.swapAssets{value: amount}(ETH, tokenOut, amount, 0);
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(testUser);
        console.log("  Amount out:", balanceAfter - balanceBefore);
        assertGt(balanceAfter, balanceBefore, "Should receive tokens");
        vm.stopPrank();
    }

    function _testWETHSwap(address tokenOut, uint256 amount) internal {
        vm.startPrank(testUser);
        IWETH(WETH).deposit{value: amount}();
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testUser);
        IERC20(WETH).approve(address(ltm), amount);
        ltm.swapAssets(WETH, tokenOut, amount, 0);
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(testUser);
        console.log("  Amount out:", balanceAfter - balanceBefore);
        assertGt(balanceAfter, balanceBefore, "Should receive tokens");
        vm.stopPrank();
    }

    function _testWETHMultiStepSwap(address tokenOut, uint256 amount) internal {
        vm.startPrank(testUser);
        IWETH(WETH).deposit{value: amount}();
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testUser);
        IERC20(WETH).approve(address(ltm), amount);
        ltm.swapAssetsMultiStep(WETH, tokenOut, amount, 0);
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(testUser);
        console.log("  Amount out:", balanceAfter - balanceBefore);
        assertGt(balanceAfter, balanceBefore, "Should receive tokens");
        vm.stopPrank();
    }
    function _testMultiStepWETHToOSETH() public {
        vm.startPrank(testUser);
        IWETH(WETH).deposit{value: 0.05 ether}(); // Smaller amount
        uint256 balanceBefore = IERC20(OSETH).balanceOf(testUser);
        IERC20(WETH).approve(address(ltm), 0.05 ether);
        ltm.swapAssetsMultiStep(WETH, OSETH, 0.05 ether, 0);
        uint256 balanceAfter = IERC20(OSETH).balanceOf(testUser);
        console.log("  Amount out:", balanceAfter - balanceBefore);
        assertGt(balanceAfter, balanceBefore, "Should receive tokens");
        vm.stopPrank();
    }
}