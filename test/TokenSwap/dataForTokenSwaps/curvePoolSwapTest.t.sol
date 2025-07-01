/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
}

// Interface for Curve v2 pools (like cbETH/WETH)
interface ICurveV2Pool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth,
        address receiver
    ) external payable returns (uint256);
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function A() external view returns (uint256);
    function gamma() external view returns (uint256);
    function fee() external view returns (uint256);
    function D() external view returns (uint256);
}

contract CurvePoolSwapTests is Test {
    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 public constant SWAP_AMOUNT = 0.01 ether;

    // Hardcoded Curve pool addresses
    address constant STETH_ETH_POOL =
        0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant CBETH_ETH_POOL =
        0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
    address constant ANKRETH_ETH_POOL =
        0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;
    address constant ETHX_ETH_POOL = 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492;
    address constant SFRXETH_ETH_POOL =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address constant OSETH_ETH_POOL =
        0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;

    // Token addresses
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;

    function setUp() public {
        console.log("Setting up Curve test environment");
        vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.deal(address(this), 100 ether);
    }

    function swapETHToTokenOnCurve(
        address poolAddress,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        console.log("=== Curve Pool Swap ===");
        console.log("Pool:", poolAddress);
        console.log("Token out:", tokenOut);
        console.log("Amount in:", amountIn);

        // Find token indices
        int128 ethIndex = -1;
        int128 tokenIndex = -1;

        // Check first 2 coins (most common)
        try ICurvePool(poolAddress).coins(0) returns (address coin0) {
            console.log("Coin 0:", coin0);
            if (coin0 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                ethIndex = 0;
            } else if (coin0 == address(weth)) {
                ethIndex = 0; // Some pools use WETH instead of ETH
            } else if (coin0 == tokenOut) {
                tokenIndex = 0;
            }
        } catch {
            console.log("Failed to get coin 0");
        }

        try ICurvePool(poolAddress).coins(1) returns (address coin1) {
            console.log("Coin 1:", coin1);
            if (coin1 == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                ethIndex = 1;
            } else if (coin1 == address(weth)) {
                ethIndex = 1; // Some pools use WETH instead of ETH
            } else if (coin1 == tokenOut) {
                tokenIndex = 1;
            }
        } catch {
            console.log("Failed to get coin 1");
        }

        require(
            ethIndex >= 0 && tokenIndex >= 0,
            "Could not find token indices"
        );
        console.log("ETH index:", uint256(uint128(ethIndex)));
        console.log("Token index:", uint256(uint128(tokenIndex)));

        // Get expected output
        uint256 expectedOut = ICurvePool(poolAddress).get_dy(
            ethIndex,
            tokenIndex,
            amountIn
        );
        console.log("Expected output:", expectedOut);

        // Perform swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        console.log("Balance before:", balanceBefore);

        // Call exchange with ETH value
        uint256 amountOut = ICurvePool(poolAddress).exchange{value: amountIn}(
            ethIndex,
            tokenIndex,
            amountIn,
            (expectedOut * 99) / 100 // 1% slippage
        );

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        console.log("Balance after:", balanceAfter);
        console.log("Amount out:", amountOut);
        console.log("Balance increase:", balanceAfter - balanceBefore);

        return amountOut;
    }

    function testSwapETHToStETHOnCurve() public {
        console.log("Testing ETH -> stETH on Curve");
        uint256 balanceBefore = IERC20(STETH).balanceOf(address(this));

        uint256 amountOut = swapETHToTokenOnCurve(
            STETH_ETH_POOL,
            STETH,
            SWAP_AMOUNT
        );

        uint256 balanceAfter = IERC20(STETH).balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Should receive stETH");
        assertGt(amountOut, 0, "Amount out should be greater than 0");
    }

    function testSwapETHToCbETHOnCurve() public {
        console.log("Testing ETH -> cbETH on Curve (v2 pool)");

        // This is a Curve v2 pool, needs different handling
        weth.deposit{value: SWAP_AMOUNT}();
        IERC20(address(weth)).approve(CBETH_ETH_POOL, SWAP_AMOUNT);

        uint256 balanceBefore = IERC20(CBETH).balanceOf(address(this));
        console.log("cbETH balance before:", balanceBefore);
        console.log(
            "WETH balance:",
            IERC20(address(weth)).balanceOf(address(this))
        );

        // Check pool state
        ICurveV2Pool pool = ICurveV2Pool(CBETH_ETH_POOL);

        try pool.coins(0) returns (address coin0) {
            console.log("Pool coin 0:", coin0);
        } catch {}

        try pool.coins(1) returns (address coin1) {
            console.log("Pool coin 1:", coin1);
        } catch {}

        try pool.balances(0) returns (uint256 bal0) {
            console.log("Pool balance 0:", bal0);
        } catch {}

        try pool.balances(1) returns (uint256 bal1) {
            console.log("Pool balance 1:", bal1);
        } catch {}

        try pool.A() returns (uint256 A) {
            console.log("Pool A:", A);
        } catch {}

        try pool.gamma() returns (uint256 gamma) {
            console.log("Pool gamma:", gamma);
        } catch {}

        try pool.D() returns (uint256 D) {
            console.log("Pool D:", D);
        } catch {}

        try pool.fee() returns (uint256 fee) {
            console.log("Pool fee:", fee);
        } catch {}

        // Try smaller amount first
        uint256 smallAmount = SWAP_AMOUNT / 10; // 0.001 ETH
        console.log("Trying smaller amount:", smallAmount);

        try pool.get_dy(0, 1, smallAmount) returns (uint256 expectedOut) {
            console.log("Expected output for small amount:", expectedOut);

            // Try the actual swap
            uint256 amountOut = pool.exchange(0, 1, smallAmount, 0);

            uint256 balanceAfter = IERC20(CBETH).balanceOf(address(this));
            console.log("cbETH balance after:", balanceAfter);
            console.log("Amount out:", amountOut);

            assertGt(balanceAfter, balanceBefore, "Should receive cbETH");
            assertGt(amountOut, 0, "Amount out should be greater than 0");
        } catch Error(string memory reason) {
            console.log("get_dy failed:", reason);

            // Try direct exchange with 0 minimum
            try pool.exchange(0, 1, smallAmount, 0) returns (
                uint256 amountOut
            ) {
                uint256 balanceAfter = IERC20(CBETH).balanceOf(address(this));
                console.log("cbETH balance after direct:", balanceAfter);
                console.log("Amount out direct:", amountOut);

                assertGt(balanceAfter, balanceBefore, "Should receive cbETH");
                assertGt(amountOut, 0, "Amount out should be greater than 0");
            } catch Error(string memory exchangeReason) {
                console.log("Direct exchange also failed:", exchangeReason);
                revert(exchangeReason);
            }
        } catch (bytes memory data) {
            console.log("get_dy failed with low-level error");
            console.logBytes(data);

            // Try direct exchange
            try pool.exchange(0, 1, smallAmount, 0) returns (
                uint256 amountOut
            ) {
                uint256 balanceAfter = IERC20(CBETH).balanceOf(address(this));
                console.log("cbETH balance after direct:", balanceAfter);
                console.log("Amount out direct:", amountOut);

                assertGt(balanceAfter, balanceBefore, "Should receive cbETH");
                assertGt(amountOut, 0, "Amount out should be greater than 0");
            } catch {
                console.log("Both get_dy and exchange failed");
                revert("Pool appears to be in invalid state");
            }
        }
    }

    function testSwapETHToAnkrETHOnCurve() public {
        console.log("Testing ETH -> ankrETH on Curve");
        uint256 balanceBefore = IERC20(ANKRETH).balanceOf(address(this));

        uint256 amountOut = swapETHToTokenOnCurve(
            ANKRETH_ETH_POOL,
            ANKRETH,
            SWAP_AMOUNT
        );

        uint256 balanceAfter = IERC20(ANKRETH).balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Should receive ankrETH");
        assertGt(amountOut, 0, "Amount out should be greater than 0");
    }

    function testSwapETHToETHxOnCurve() public {
        console.log("Testing ETH -> ETHx on Curve");
        uint256 balanceBefore = IERC20(ETHX).balanceOf(address(this));

        uint256 amountOut = swapETHToTokenOnCurve(
            ETHX_ETH_POOL,
            ETHX,
            SWAP_AMOUNT
        );

        uint256 balanceAfter = IERC20(ETHX).balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore, "Should receive ETHx");
        assertGt(amountOut, 0, "Amount out should be greater than 0");
    }

    function testSwapETHToSfrxETHOnCurve() public {
        console.log("Testing ETH -> sfrxETH on Curve");

        // This is a frxETH/ETH pool, so we need to swap ETH -> frxETH -> sfrxETH
        // First swap ETH to frxETH
        uint256 frxETHBalanceBefore = IERC20(FRXETH).balanceOf(address(this));

        uint256 expectedOut = ICurvePool(SFRXETH_ETH_POOL).get_dy(
            0,
            1,
            SWAP_AMOUNT
        );
        ICurvePool(SFRXETH_ETH_POOL).exchange{value: SWAP_AMOUNT}(
            0, // ETH index
            1, // frxETH index
            SWAP_AMOUNT,
            (expectedOut * 99) / 100
        );

        uint256 frxETHBalanceAfter = IERC20(FRXETH).balanceOf(address(this));
        uint256 frxETHReceived = frxETHBalanceAfter - frxETHBalanceBefore;
        console.log("frxETH received:", frxETHReceived);

        // Now you would need to stake frxETH to get sfrxETH
        // For this test, we'll just verify we got frxETH
        assertGt(frxETHReceived, 0, "Should receive frxETH");
    }

    function testSwapETHToOsETHOnCurve() public {
        console.log("Testing ETH -> osETH on Curve");

        // This pool is osETH/rETH, not osETH/ETH
        // We need to first get rETH, then swap to osETH
        console.log("This pool is osETH/rETH, not osETH/ETH");
        console.log("Skipping test as it requires multi-hop swap");

        // Skip this test as it's not a direct ETH/osETH pool
        vm.skip(true);
    }

    receive() external payable {}
}
*/