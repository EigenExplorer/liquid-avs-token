/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/AssetSwapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AssetSwapperTest is Test {
    AssetSwapper public assetSwapper;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNISWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant mETH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address _frxETHMinter = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    address owner = address(0x1234);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("https://ethereum-rpc.publicnode.com"));

        vm.prank(owner);
        assetSwapper = new AssetSwapper(WETH, UNISWAP_ROUTER, _frxETHMinter);

        // Fund owner with ETH
        vm.deal(owner, 100 ether);
    }

    function testSwapWETHToMETH() public {
        uint256 amountIn = 1 ether;

        // Wrap ETH to WETH
        vm.startPrank(owner);
        IWETH(WETH).deposit{value: amountIn}();
        IERC20(WETH).approve(address(assetSwapper), amountIn);

        // Prepare swap params
        bytes memory routeData = abi.encode(
            AssetSwapper.UniswapV3Route({
                pool: 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
                fee: 500,
                isMultiHop: false,
                path: ""
            })
        );

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: WETH,
            tokenOut: mETH,
            amountIn: amountIn,
            minAmountOut: 0.9 ether, // 10% slippage
            protocol: AssetSwapper.Protocol.UniswapV3,
            routeData: routeData
        });

        // Execute swap
        uint256 balanceBefore = IERC20(mETH).balanceOf(owner);
        uint256 amountOut = assetSwapper.swapAssets(params);
        uint256 balanceAfter = IERC20(mETH).balanceOf(owner);

        // Assertions
        assertGt(amountOut, 0, "Should receive mETH");
        assertEq(
            balanceAfter - balanceBefore,
            amountOut,
            "Balance should increase by amount out"
        );
        assertGt(amountOut, params.minAmountOut, "Should meet minimum output");

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(owner);

        // Test pause
        assetSwapper.pause();
        assertTrue(assetSwapper.paused(), "Should be paused");

        // Test unpause
        assetSwapper.unpause();
        assertFalse(assetSwapper.paused(), "Should be unpaused");

        vm.stopPrank();
    }

    function testOnlyOwnerCanSwap() public {
        address notOwner = address(0x5678);

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: WETH,
            tokenOut: mETH,
            amountIn: 1 ether,
            minAmountOut: 0.9 ether,
            protocol: AssetSwapper.Protocol.UniswapV3,
            routeData: ""
        });

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        assetSwapper.swapAssets(params);
    }
}
*/