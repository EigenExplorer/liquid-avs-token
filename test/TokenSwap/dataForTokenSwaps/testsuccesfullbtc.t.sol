/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract StBTCSwapTest is Test {
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant stBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WBTC_WHALE = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28; // Avalanche Bridge

    uint24 constant WORKING_FEE = 500; // 0.05% - This works!

    IERC20 wbtc = IERC20(WBTC);
    IERC20 stbtc = IERC20(stBTC);
    ISwapRouter router = ISwapRouter(SWAP_ROUTER);

    function setUp() public {
        vm.createSelectFork("https://eth.drpc.org");
        vm.label(WBTC, "WBTC");
        vm.label(stBTC, "stBTC");
        vm.label(SWAP_ROUTER, "SwapRouter");
    }

    function testSuccessfulWBTCToStBTCSwap() public {
        console.log("=== WBTC -> stBTC SWAP TEST ===");

        // Get WBTC from whale
        vm.startPrank(WBTC_WHALE);
        uint256 swapAmount = 0.01e8; // 0.01 WBTC
        wbtc.transfer(address(this), swapAmount);
        vm.stopPrank();

        console.log("WBTC balance:", wbtc.balanceOf(address(this)));
        console.log("Initial stBTC balance:", stbtc.balanceOf(address(this)));

        // Approve router
        wbtc.approve(SWAP_ROUTER, swapAmount);

        // Execute swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WBTC,
                tokenOut: stBTC,
                fee: WORKING_FEE, // 500 = 0.05%
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: swapAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = router.exactInputSingle(params);

        console.log("Swap successful!");
        console.log("stBTC received:", amountOut);
        console.log("Final stBTC balance:", stbtc.balanceOf(address(this)));

        // Verify we received stBTC
        assertGt(amountOut, 0, "Should receive stBTC");
        assertEq(
            stbtc.balanceOf(address(this)),
            amountOut,
            "Balance should match output"
        );
    }

    function testBothDirectionSwaps() public {
        console.log("=== BIDIRECTIONAL SWAP TEST ===");

        // First get some WBTC
        vm.prank(WBTC_WHALE);
        wbtc.transfer(address(this), 0.1e8); // 0.1 WBTC

        uint256 wbtcAmount = 0.05e8; // 0.05 WBTC for first swap

        // 1. WBTC -> stBTC
        wbtc.approve(SWAP_ROUTER, wbtcAmount);

        ISwapRouter.ExactInputSingleParams memory params1 = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WBTC,
                tokenOut: stBTC,
                fee: WORKING_FEE,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: wbtcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 stbtcReceived = router.exactInputSingle(params1);
        console.log("WBTC -> stBTC: Received", stbtcReceived, "stBTC");

        // 2. stBTC -> WBTC (reverse)
        stbtc.approve(SWAP_ROUTER, stbtcReceived);

        ISwapRouter.ExactInputSingleParams memory params2 = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: stBTC,
                tokenOut: WBTC,
                fee: WORKING_FEE,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: stbtcReceived,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 wbtcBack = router.exactInputSingle(params2);
        console.log("stBTC -> WBTC: Received", wbtcBack, "WBTC");

        // Calculate slippage
        uint256 slippage = ((wbtcAmount - wbtcBack) * 10000) / wbtcAmount;
        console.log("Round-trip slippage:", slippage / 100, ".");
        console.log(slippage % 100, "%");
    }

    function testLargeSwapImpact() public {
        console.log("=== TESTING LARGE SWAP PRICE IMPACT ===");

        // Test different swap sizes
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 0.001e8; // 0.001 WBTC
        amounts[1] = 0.01e8; // 0.01 WBTC
        amounts[2] = 0.1e8; // 0.1 WBTC
        amounts[3] = 1e8; // 1 WBTC

        for (uint i = 0; i < amounts.length; i++) {
            // Get WBTC
            vm.prank(WBTC_WHALE);
            wbtc.transfer(address(this), amounts[i]);

            // Approve and swap
            wbtc.approve(SWAP_ROUTER, amounts[i]);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: WBTC,
                    tokenOut: stBTC,
                    fee: WORKING_FEE,
                    recipient: address(this),
                    deadline: block.timestamp + 300,
                    amountIn: amounts[i],
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

            try router.exactInputSingle(params) returns (uint256 amountOut) {
                uint256 rate = (amountOut * 1e8) / amounts[i];
                console.log("Amount:", amounts[i] / 1e8, "WBTC -> Rate:");
                console.log(rate / 1e18, "stBTC per WBTC");
            } catch {
                console.log(
                    "Amount:",
                    amounts[i] / 1e8,
                    "WBTC -> FAILED (too large for pool)"
                );
            }
        }
    }
}
*/