/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function liquidity() external view returns (uint128);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface ICurvePool {
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
    function balances(uint256 i) external view returns (uint256);
}

contract SlippageAnalysisTest is Test {
    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
    }

    function testMeasureRealSlippage() public view {
        console.log(
            "\n========== SLIPPAGE ANALYSIS FROM YOUR CONFIG ==========\n"
        );

        // WETH routes from your config
        analyzeUniswapRoute(
            "WETH",
            "ankrETH",
            0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E,
            3000
        );
        analyzeUniswapRoute(
            "WETH",
            "cbETH",
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            500
        );
        analyzeUniswapRoute(
            "WETH",
            "lsETH",
            0x5d811a9d059dDAB0C18B385ad3b752f734f011cB,
            500
        );
        analyzeUniswapRoute(
            "WETH",
            "mETH",
            0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
            500
        );
        analyzeUniswapRoute(
            "WETH",
            "OETH",
            0x52299416C469843F4e0d54688099966a6c7d720f,
            500
        );
        analyzeUniswapRoute(
            "WETH",
            "rETH",
            0x553e9C493678d8606d6a5ba284643dB2110Df823,
            100
        );
        analyzeUniswapRoute(
            "WETH",
            "stETH",
            0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D,
            10000
        );
        analyzeUniswapRoute(
            "WETH",
            "swETH",
            0x30eA22C879628514f1494d4BBFEF79D21A6B49A2,
            500
        );

        // Multi-hop routes (WETH -> WBTC -> BTC tokens)
        analyzeMultiHopRoute(
            "WETH",
            "stBTC",
            0xCBCdF9626bC03E24f779434178A73a0B4bad62eD, // WETH->WBTC
            0x242017eE869bF0734Bc5E4feb086A52e6391Dd0d // WBTC->stBTC
        );

        // FIXED ADDRESS - removed extra character
        analyzeMultiHopRoute(
            "WETH",
            "uniBTC",
            0xCBCdF9626bC03E24f779434178A73a0B4bad62eD, // WETH->WBTC
            0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0 // WBTC->uniBTC (corrected)
        );

        // Curve routes from your config
        analyzeCurveRoute(
            "ETH",
            "ankrETH",
            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
            0,
            1
        );
        analyzeCurveRoute(
            "ETH",
            "ETHx",
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
            0,
            1
        );
        analyzeCurveRoute(
            "ETH",
            "frxETH",
            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
            0,
            1
        );
        analyzeCurveRoute(
            "ETH",
            "stETH",
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            0,
            1
        );
        analyzeCurveRoute(
            "rETH",
            "osETH",
            0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
            1,
            0
        );

        console.log("\n========== FINAL SLIPPAGE RECOMMENDATIONS ==========\n");
        outputFinalRecommendations();
    }

    function analyzeUniswapRoute(
        string memory tokenIn,
        string memory tokenOut,
        address pool,
        uint24 fee
    ) internal view {
        console.log(string.concat("\nUniswap V3: ", tokenIn, " -> ", tokenOut));
        console.log("Pool:", pool);
        console.log("Fee:", fee, "bps");

        try IUniswapV3Pool(pool).slot0() returns (
            uint160 sqrtPrice,
            int24,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            if (sqrtPrice > 0) {
                // Get pool liquidity
                uint128 liquidity = IUniswapV3Pool(pool).liquidity();
                address token0 = IUniswapV3Pool(pool).token0();
                address token1 = IUniswapV3Pool(pool).token1();

                uint256 balance0 = IERC20(token0).balanceOf(pool);
                uint256 balance1 = IERC20(token1).balanceOf(pool);

                console.log("Active liquidity:", liquidity);
                console.log("Token balances:");
                console.log("  Token0:", balance0 / 1e15, "milli");
                console.log("  Token1:", balance1 / 1e15, "milli");

                // Analyze liquidity level and recommend slippage
                uint256 recommendedSlippage;
                if (liquidity > 1e22) {
                    // Very high liquidity
                    recommendedSlippage = 150; // 1.5%
                    console.log("LIQUIDITY: VERY HIGH");
                } else if (liquidity > 1e21) {
                    // High liquidity
                    recommendedSlippage = 200; // 2%
                    console.log("LIQUIDITY: HIGH");
                } else if (liquidity > 1e20) {
                    // Medium liquidity
                    recommendedSlippage = 300; // 3%
                    console.log("LIQUIDITY: MEDIUM");
                } else {
                    // Low liquidity
                    recommendedSlippage = 500; // 5%
                    console.log("LIQUIDITY: LOW");
                }

                // Adjust for fee tier (higher fees = more slippage expected)
                if (fee >= 10000)
                    recommendedSlippage += 100; // +1% for 1% fee pools
                else if (fee >= 3000) recommendedSlippage += 50; // +0.5% for 0.3% fee pools

                console.log(
                    "RECOMMENDED SLIPPAGE:",
                    recommendedSlippage,
                    "bps"
                );
            } else {
                console.log("POOL INACTIVE");
            }
        } catch {
            console.log("FAILED TO READ POOL");
        }
    }

    function analyzeMultiHopRoute(
        string memory tokenIn,
        string memory tokenOut,
        address pool1,
        address pool2
    ) internal view {
        console.log(
            string.concat("\nMulti-hop: ", tokenIn, " -> WBTC -> ", tokenOut)
        );
        console.log("Pool 1:", pool1);
        console.log("Pool 2:", pool2);

        uint256 slippage1 = getPoolSlippage(pool1);
        uint256 slippage2 = getPoolSlippage(pool2);

        // Multi-hop adds slippage from both pools + coordination risk
        uint256 totalSlippage = slippage1 + slippage2 + 100; // +1% for multi-hop risk

        console.log("Pool 1 slippage:", slippage1, "bps");
        console.log("Pool 2 slippage:", slippage2, "bps");
        console.log("TOTAL RECOMMENDED SLIPPAGE:", totalSlippage, "bps");
    }

    function getPoolSlippage(address pool) internal view returns (uint256) {
        try IUniswapV3Pool(pool).liquidity() returns (uint128 liquidity) {
            if (liquidity > 1e21) return 200;
            // 2%
            else if (liquidity > 1e20) return 300;
            // 3%
            else return 500; // 5%
        } catch {
            return 500; // Default 5% if can't read
        }
    }

    function analyzeCurveRoute(
        string memory tokenIn,
        string memory tokenOut,
        address pool,
        int128 indexIn,
        int128 indexOut
    ) internal view {
        console.log(string.concat("\nCurve: ", tokenIn, " -> ", tokenOut));
        console.log("Pool:", pool);

        uint256[] memory testAmounts = new uint256[](3);
        testAmounts[0] = 0.1 ether; // 0.1 ETH
        testAmounts[1] = 1 ether; // 1 ETH
        testAmounts[2] = 10 ether; // 10 ETH

        try ICurvePool(pool).get_dy(indexIn, indexOut, testAmounts[0]) returns (
            uint256 out1
        ) {
            uint256 out2 = ICurvePool(pool).get_dy(
                indexIn,
                indexOut,
                testAmounts[1]
            );
            uint256 out3 = ICurvePool(pool).get_dy(
                indexIn,
                indexOut,
                testAmounts[2]
            );

            // Calculate price impact
            uint256 price1 = (out1 * 1e18) / testAmounts[0];
            uint256 price2 = (out2 * 1e18) / testAmounts[1];
            uint256 price3 = (out3 * 1e18) / testAmounts[2];

            console.log("Price analysis:");
            console.log("  0.1 ETH price:", price1 / 1e15, "milli");
            console.log("  1 ETH price:", price2 / 1e15, "milli");
            console.log("  10 ETH price:", price3 / 1e15, "milli");

            // Calculate slippage from small to large trade
            uint256 slippage = price1 > price3
                ? ((price1 - price3) * 10000) / price1
                : 0;

            uint256 recommendedSlippage = slippage + 100; // Add 1% buffer

            // Special case for stETH (often has bonus)
            if (keccak256(bytes(tokenOut)) == keccak256(bytes("stETH"))) {
                if (out1 >= testAmounts[0]) {
                    console.log(
                        "BONUS TOKENS DETECTED - Positive slippage possible"
                    );
                    recommendedSlippage = 100; // Only 1% for bonus cases
                }
            }

            console.log("Price impact:", slippage, "bps");
            console.log("RECOMMENDED SLIPPAGE:", recommendedSlippage, "bps");
        } catch {
            console.log("CURVE POOL FAILED - Use 300 bps default");
        }
    }

    function outputFinalRecommendations() internal view {
        console.log("COPY THESE VALUES TO YOUR ASSETSWAPPER CONTRACT:");
        console.log("");
        console.log("// High liquidity ETH liquid staking - 2%");
        console.log(
            "slippageTolerance[WETH][0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa] = 200; // mETH"
        );
        console.log(
            "slippageTolerance[WETH][0xae78736Cd615f374D3085123A210448E74Fc6393] = 200; // rETH"
        );
        console.log(
            "slippageTolerance[WETH][0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3] = 200; // OETH"
        );
        console.log(
            "slippageTolerance[WETH][0xf951E335afb289353dc249e82926178EaC7DEd78] = 200; // swETH"
        );
        console.log("");
        console.log("// Medium liquidity ETH pairs - 2.5%");
        console.log(
            "slippageTolerance[WETH][0xBe9895146f7AF43049ca1c1AE358B0541Ea49704] = 250; // cbETH"
        );
        console.log(
            "slippageTolerance[WETH][0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549] = 250; // lsETH"
        );
        console.log("");
        console.log("// High fee tier stETH - 3% (due to 1% pool fee)");
        console.log(
            "slippageTolerance[WETH][0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84] = 300; // stETH"
        );
        console.log("");
        console.log("// Multi-hop BTC routes - 4%");
        console.log(
            "slippageTolerance[WETH][0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3] = 400; // stBTC"
        );
        console.log(
            "slippageTolerance[WETH][0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568] = 400; // uniBTC"
        );
        console.log("");
        console.log("// Low liquidity pairs - 5%");
        console.log(
            "slippageTolerance[WETH][0xE95A203B1a91a908F9B9CE46459d101078c2c3cb] = 500; // ankrETH"
        );
        console.log(
            "slippageTolerance[WETH][0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38] = 500; // osETH"
        );
    }
}
*/