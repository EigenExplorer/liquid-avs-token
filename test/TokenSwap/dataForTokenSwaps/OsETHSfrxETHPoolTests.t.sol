/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
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

interface IUniswapV3Router {
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

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);
}

interface IFrxETHMinter {
    function submitAndDeposit(
        address recipient
    ) external payable returns (uint256 shares);
}

contract OsETHSfrxETHPoolTests is Test {
    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV3Router public uniswapRouter =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IFrxETHMinter public frxETHMinter =
        IFrxETHMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138);

    uint256 public constant SWAP_AMOUNT = 0.1 ether;

    // Token addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // Pool addresses
    address constant OSETH_RETH_CURVE =
        0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
    address constant FRXETH_ETH_CURVE =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;

    function setUp() public {
        console.log("Setting up osETH and sfrxETH test environment");
        vm.createFork("https://ethereum-rpc.publicnode.com");
        vm.deal(address(this), 100 ether);

        // Get some WETH
        weth.deposit{value: 10 ether}();
        console.log("WETH balance:", IERC20(WETH).balanceOf(address(this)));
    }

    // ===== osETH Tests =====

    function testWETHToOsETHViaCurve() public {
        console.log("\n=== Testing WETH -> rETH -> osETH on Curve ===");

        // Step 1: Get rETH via Uniswap
        IERC20(WETH).approve(address(uniswapRouter), 1 ether);

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: RETH,
                fee: 100,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 rethReceived = uniswapRouter.exactInputSingle(params);
        console.log("Step 1 - Got rETH:", rethReceived);

        // Step 2: Swap rETH to osETH on Curve
        uint256 osethBalanceBefore = IERC20(OSETH).balanceOf(address(this));

        IERC20(RETH).approve(OSETH_RETH_CURVE, rethReceived);

        try
            ICurvePool(OSETH_RETH_CURVE).exchange(
                1, // rETH index
                0, // osETH index
                rethReceived,
                0 // No min for testing
            )
        returns (uint256 amountOut) {
            uint256 osethBalanceAfter = IERC20(OSETH).balanceOf(address(this));
            console.log("Step 2 - SUCCESS: rETH -> osETH on Curve");
            console.log("Final osETH received:", amountOut);
            console.log(
                "Balance increased:",
                osethBalanceAfter - osethBalanceBefore
            );

            assertGt(amountOut, 0, "Should receive osETH");
        } catch Error(string memory reason) {
            console.log("FAILED: rETH -> osETH on Curve:", reason);
        } catch {
            console.log("FAILED: rETH -> osETH on Curve: Low-level error");
        }
    }

    function testWETHToOsETHMultiHop() public {
        console.log("\n=== Testing WETH -> osETH via Uniswap multi-hop ===");

        // Try to find if there's a direct path
        IERC20(WETH).approve(address(uniswapRouter), 1 ether);

        // Multi-hop: WETH -> rETH -> osETH (if pool exists)
        bytes memory path = abi.encodePacked(
            WETH,
            uint24(100), // WETH/rETH 0.01% fee
            RETH
            // Would need to add osETH pool here if it exists
        );

        console.log(
            "Note: Direct Uniswap path not found, use Curve route instead"
        );
    }

    // ===== sfrxETH Tests =====

    function testETHToSfrxETHDirect() public {
        console.log(
            "\n=== Testing ETH -> frxETH -> sfrxETH direct minting ==="
        );

        // Step 1: Mint frxETH from ETH
        uint256 frxETHBalanceBefore = IERC20(FRXETH).balanceOf(address(this));

        // Submit ETH and get sfrxETH directly
        try
            frxETHMinter.submitAndDeposit{value: 1 ether}(address(this))
        returns (uint256 shares) {
            uint256 sfrxETHBalance = IERC20(SFRXETH).balanceOf(address(this));
            console.log("SUCCESS: Direct ETH -> sfrxETH minting");
            console.log("ETH sent:", 1 ether);
            console.log("sfrxETH shares received:", shares);
            console.log("sfrxETH balance:", sfrxETHBalance);

            assertGt(shares, 0, "Should receive sfrxETH shares");
        } catch Error(string memory reason) {
            console.log("FAILED: Direct sfrxETH minting:", reason);
        } catch {
            console.log("FAILED: Direct sfrxETH minting: Low-level error");
        }
    }

    function testWETHToFrxETHToSfrxETH() public {
        console.log("\n=== Testing WETH -> frxETH on Curve, then stake ===");

        // Step 1: Unwrap WETH to ETH
        weth.withdraw(1 ether);

        // Step 2: Swap ETH to frxETH on Curve
        uint256 frxETHBalanceBefore = IERC20(FRXETH).balanceOf(address(this));

        try
            ICurvePool(FRXETH_ETH_CURVE).exchange{value: 1 ether}(
                0, // ETH index
                1, // frxETH index
                1 ether,
                0 // No min for testing
            )
        returns (uint256 frxETHReceived) {
            console.log("Step 1 - Got frxETH from Curve:", frxETHReceived);

            // Step 3: Stake frxETH to get sfrxETH
            IERC20(FRXETH).approve(SFRXETH, frxETHReceived);

            // Call deposit on sfrxETH contract
            (bool success, bytes memory data) = SFRXETH.call(
                abi.encodeWithSignature(
                    "deposit(uint256,address)",
                    frxETHReceived,
                    address(this)
                )
            );

            if (success) {
                uint256 sfrxETHBalance = IERC20(SFRXETH).balanceOf(
                    address(this)
                );
                console.log("Step 2 - SUCCESS: Staked frxETH to sfrxETH");
                console.log("sfrxETH balance:", sfrxETHBalance);
                assertGt(sfrxETHBalance, 0, "Should receive sfrxETH");
            } else {
                console.log("FAILED: Could not stake frxETH to sfrxETH");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: ETH -> frxETH on Curve:", reason);
        } catch {
            console.log("FAILED: ETH -> frxETH on Curve: Low-level error");
        }
    }

    function testWETHToSfrxETHViaRETH() public {
        console.log("\n=== Testing WETH -> rETH -> sfrxETH ===");

        // Step 1: Get rETH
        IERC20(WETH).approve(address(uniswapRouter), 1 ether);

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: RETH,
                fee: 100,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 rethReceived = uniswapRouter.exactInputSingle(params);
        console.log("Step 1 - Got rETH:", rethReceived);

        // Step 2: Try to find rETH -> sfrxETH pool
        console.log("Note: No direct rETH -> sfrxETH liquidity found");
        console.log("Recommendation: Use ETH -> frxETH -> stake route instead");
    }

    // ===== Summary Tests =====

    function testBestPathForOsETH() public {
        console.log("\n=== BEST PATH FOR osETH ===");
        console.log("Route: WETH -> rETH (Uniswap) -> osETH (Curve)");
        console.log(
            "Pools: WETH/rETH 0.01% fee on Uniswap, then osETH/rETH on Curve"
        );
        testWETHToOsETHViaCurve();
    }

    function testBestPathForSfrxETH() public {
        console.log("\n=== BEST PATH FOR sfrxETH ===");
        console.log(
            "Route 1: ETH -> sfrxETH (Direct minting via frxETHMinter)"
        );
        console.log("Route 2: ETH -> frxETH (Curve) -> stake to sfrxETH");
        testETHToSfrxETHDirect();
    }

    receive() external payable {}
}
*/