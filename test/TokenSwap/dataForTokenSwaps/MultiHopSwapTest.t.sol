/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../../src/interfaces/IUniswapV3Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../src/interfaces/IWETH.sol";

contract MultiHopSwapTest is Test {
    // Addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant stBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address constant uniBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;

    // Uniswap Router
    IUniswapV3Router constant uniswapRouter =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IWETH constant weth = IWETH(WETH);

    // Test user
    address constant USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // Pool addresses from your config
    address constant WETH_WBTC_POOL_3000 =
        0xCBCdF9626bC03E24f779434178A73a0B4bad62eD; // fee 3000
    address constant WETH_WBTC_POOL_500 =
        0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0; // fee 500
    address constant WBTC_stBTC_POOL_500 =
        0x242017eE869bF0734Bc5E4feb086A52e6391Dd0d; // fee 500
    address constant WBTC_uniBTC_POOL_3000 =
        0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0; // fee 3000

    function setUp() public {
        vm.startPrank(USER);
        vm.deal(USER, 100 ether);

        // Get some WETH
        weth.deposit{value: 10 ether}();
        console.log(
            "Setup complete. WETH balance:",
            IERC20(WETH).balanceOf(USER)
        );
    }

    function testDirectUniswapRouterCalls() public {
        console.log("=== TESTING DIRECT UNISWAP ROUTER CALLS ===");

        // Test 1: Direct WETH -> WBTC swap (fee 3000)
        console.log("\n1. Testing WETH -> WBTC (fee 3000)");
        _testSingleSwap(WETH, WBTC, 1 ether, 3000, "WETH->WBTC fee 3000");

        // Test 2: Direct WETH -> WBTC swap (fee 500)
        console.log("\n2. Testing WETH -> WBTC (fee 500)");
        _testSingleSwap(WETH, WBTC, 1 ether, 500, "WETH->WBTC fee 500");

        // Test 3: Get some WBTC first for next tests
        console.log("\n3. Getting WBTC for further tests...");
        IERC20(WETH).approve(address(uniswapRouter), 2 ether);

        try
            uniswapRouter.exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: WBTC,
                    fee: 3000,
                    recipient: USER,
                    deadline: block.timestamp + 300,
                    amountIn: 2 ether,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )
        returns (uint256 wbtcReceived) {
            console.log(" Got WBTC:", wbtcReceived);
            console.log("WBTC balance:", IERC20(WBTC).balanceOf(USER));

            // Test 4: WBTC -> stBTC swap
            console.log("\n4. Testing WBTC -> stBTC (fee 500)");
            _testSingleSwap(
                WBTC,
                stBTC,
                wbtcReceived / 2,
                500,
                "WBTC->stBTC fee 500"
            );

            // Test 5: WBTC -> uniBTC swap
            console.log("\n5. Testing WBTC -> uniBTC (fee 3000)");
            _testSingleSwap(
                WBTC,
                uniBTC,
                wbtcReceived / 2,
                3000,
                "WBTC->uniBTC fee 3000"
            );
        } catch Error(string memory reason) {
            console.log(" Failed to get WBTC:", reason);
        }
    }

    function testMultiHopConfigFromJSON() public {
        console.log("=== TESTING MULTI-HOP FROM CONFIG ===");

        // Config 1: stBTC route (WETH->WBTC fee 500, WBTC->stBTC fee 500)
        console.log("\n1. Testing stBTC route from config...");
        bytes memory stBTCPath = abi.encodePacked(
            WETH,
            uint24(500), // fee from WETH to WBTC
            WBTC,
            uint24(500), // fee from WBTC to stBTC
            stBTC
        );
        _testMultiHopSwap(stBTCPath, stBTC, "stBTC route (500->500)");

        // Config 2: uniBTC route (WETH->WBTC fee 3000, WBTC->uniBTC fee 3000)
        console.log("\n2. Testing uniBTC route from config...");
        bytes memory uniBTCPath = abi.encodePacked(
            WETH,
            uint24(3000), // fee from WETH to WBTC
            WBTC,
            uint24(3000), // fee from WBTC to uniBTC
            uniBTC
        );
        _testMultiHopSwap(uniBTCPath, uniBTC, "uniBTC route (3000->3000)");
    }

    function testMixedFeeMultiHop() public {
        console.log("=== TESTING MIXED FEE MULTI-HOP ===");

        // Test mixed fee combinations that might work
        console.log("\n1. Testing WETH->WBTC(3000) -> stBTC(500)...");
        bytes memory mixedPath1 = abi.encodePacked(
            WETH,
            uint24(3000), // Use high liquidity pool
            WBTC,
            uint24(500), // stBTC pool fee
            stBTC
        );
        _testMultiHopSwap(mixedPath1, stBTC, "Mixed route (3000->500)");

        console.log("\n2. Testing WETH->WBTC(500) -> uniBTC(3000)...");
        bytes memory mixedPath2 = abi.encodePacked(
            WETH,
            uint24(500), // Lower fee pool
            WBTC,
            uint24(3000), // uniBTC pool fee
            uniBTC
        );
        _testMultiHopSwap(mixedPath2, uniBTC, "Mixed route (500->3000)");
    }

    function testPoolLiquidityCheck() public {
        console.log("=== CHECKING POOL LIQUIDITY ===");

        // Check if pools actually exist and have liquidity
        console.log("\nChecking pool contracts...");

        address[] memory pools = new address[](4);
        pools[0] = WETH_WBTC_POOL_3000;
        pools[1] = WETH_WBTC_POOL_500;
        pools[2] = WBTC_stBTC_POOL_500;
        pools[3] = WBTC_uniBTC_POOL_3000;

        string[] memory poolNames = new string[](4);
        poolNames[0] = "WETH/WBTC fee 3000";
        poolNames[1] = "WETH/WBTC fee 500";
        poolNames[2] = "WBTC/stBTC fee 500";
        poolNames[3] = "WBTC/uniBTC fee 3000";

        for (uint i = 0; i < pools.length; i++) {
            console.log("Pool:", poolNames[i]);
            console.log("Address:", pools[i]);
            // Check if contract exists
            uint256 codeSize;
            address pool = pools[i]; // <-- ADD THIS LINE
            assembly {
                codeSize := extcodesize(pool)
            }
            console.log("Code size:", codeSize);
            // Try to get some basic info
            if (codeSize > 0) {
                try this.getPoolInfo(pools[i]) returns (bool success) {
                    if (success) {
                        console.log(" Pool accessible");
                    } else {
                        console.log(" Pool not accessible");
                    }
                } catch {
                    console.log(" Pool call failed");
                }
            } else {
                console.log(" No contract at address");
            }
            console.log("---");
        }
    }

    // Helper function to test single swaps
    function _testSingleSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint24 fee,
        string memory description
    ) private {
        console.log("Testing:", description);
        console.log("Amount in:", amountIn);
        console.log("Fee:", fee);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(USER);
        console.log("Balance before:", balanceBefore);

        IERC20(tokenIn).approve(address(uniswapRouter), amountIn);

        try
            uniswapRouter.exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    recipient: USER,
                    deadline: block.timestamp + 300,
                    amountIn: amountIn,
                    amountOutMinimum: 0, // No slippage check for testing
                    sqrtPriceLimitX96: 0
                })
            )
        returns (uint256 amountOut) {
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(USER);
            console.log(" SUCCESS!");
            console.log("Amount out:", amountOut);
            console.log("Balance after:", balanceAfter);
            console.log("Balance change:", balanceAfter - balanceBefore);
        } catch Error(string memory reason) {
            console.log(" FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(" FAILED with low-level error");
            console.logBytes(lowLevelData);
        }
        console.log("");
    }

    // Helper function to test multi-hop swaps
    function _testMultiHopSwap(
        bytes memory path,
        address tokenOut,
        string memory description
    ) private {
        console.log("Testing:", description);
        console.log("Path length:", path.length);
        console.logBytes(path);

        uint256 amountIn = 1 ether;
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(USER);
        console.log("Amount in:", amountIn);
        console.log("Balance before:", balanceBefore);

        IERC20(WETH).approve(address(uniswapRouter), amountIn);

        try
            uniswapRouter.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: path,
                    recipient: USER,
                    deadline: block.timestamp + 300,
                    amountIn: amountIn,
                    amountOutMinimum: 0 // No slippage check for testing
                })
            )
        returns (uint256 amountOut) {
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(USER);
            console.log(" MULTI-HOP SUCCESS!");
            console.log("Amount out:", amountOut);
            console.log("Balance after:", balanceAfter);
            console.log("Balance change:", balanceAfter - balanceBefore);
        } catch Error(string memory reason) {
            console.log(" MULTI-HOP FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(" MULTI-HOP FAILED with low-level error");
            console.logBytes(lowLevelData);
        }
        console.log("");
    }

    // External function to check pool info (needed for try/catch)
    function getPoolInfo(address pool) external view returns (bool) {
        // Just try to call the pool - if it doesn't revert, pool exists
        (bool success, ) = pool.staticcall(abi.encodeWithSignature("fee()"));
        return success;
    }

    function testQuoteMultiHop() public {
        console.log("=== TESTING QUOTES FOR MULTI-HOP ===");

        // Use Uniswap quoter to see if paths are valid
        address quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

        console.log("\n1. Quoting stBTC route...");
        bytes memory stBTCPath = abi.encodePacked(
            WETH,
            uint24(500),
            WBTC,
            uint24(500),
            stBTC
        );
        _tryQuote(quoter, stBTCPath, 1 ether, "stBTC route");

        console.log("\n2. Quoting uniBTC route...");
        bytes memory uniBTCPath = abi.encodePacked(
            WETH,
            uint24(3000),
            WBTC,
            uint24(3000),
            uniBTC
        );
        _tryQuote(quoter, uniBTCPath, 1 ether, "uniBTC route");

        console.log("\n3. Quoting mixed route (3000->500)...");
        bytes memory mixedPath = abi.encodePacked(
            WETH,
            uint24(3000),
            WBTC,
            uint24(500),
            stBTC
        );
        _tryQuote(quoter, mixedPath, 1 ether, "mixed route");
    }

    function _tryQuote(
        address quoter,
        bytes memory path,
        uint256 amountIn,
        string memory description
    ) private {
        console.log("Quoting:", description);

        try IQuoter(quoter).quoteExactInput(path, amountIn) returns (
            uint256 amountOut
        ) {
            console.log(" Quote successful:", amountOut);
        } catch Error(string memory reason) {
            console.log(" Quote failed:", reason);
        } catch {
            console.log(" Quote failed with low-level error");
        }
    }
}

// Simple quoter interface
interface IQuoter {
    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    ) external returns (uint256 amountOut);
}
*/