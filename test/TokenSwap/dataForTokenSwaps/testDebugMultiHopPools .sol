/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../../src/AssetSwapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MultiHopDebugTest is Test {
    AssetSwapper public swapper;

    address constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant ROUTE_MANAGER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant stBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;

    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function setUp() public {
        vm.startPrank(OWNER);
        vm.deal(OWNER, 1000 ether);

        address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        address frxETHMinter = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

        swapper = new AssetSwapper(
            WETH,
            uniswapRouter,
            frxETHMinter,
            ROUTE_MANAGER
        );

        // Minimal initialization for this test
        address[] memory tokens = new address[](3);
        tokens[0] = WETH;
        tokens[1] = WBTC;
        tokens[2] = stBTC;

        AssetSwapper.AssetType[] memory types = new AssetSwapper.AssetType[](3);
        types[0] = AssetSwapper.AssetType.ETH_LST;
        types[1] = AssetSwapper.AssetType.BTC_WRAPPED;
        types[2] = AssetSwapper.AssetType.BTC_WRAPPED;

        uint8[] memory decimals = new uint8[](3);
        decimals[0] = 18;
        decimals[1] = 8;
        decimals[2] = 18;

        address[] memory pools = new address[](0); // Empty for now
        AssetSwapper.SlippageConfig[]
            memory slippageConfigs = new AssetSwapper.SlippageConfig[](1);
        slippageConfigs[0] = AssetSwapper.SlippageConfig(WETH, stBTC, 400);

        swapper.initialize(tokens, types, decimals, pools, slippageConfigs);

        vm.stopPrank();
    }

    function testDebugMultiHopPools() public {
        console.log("=== DEBUGGING MULTI-HOP POOL ADDRESSES ===");

        // Compute the actual pool addresses that Uniswap V3 will use
        address wethWbtcPool3000 = computeUniV3Pool(WETH, WBTC, 3000);
        address wbtcStBtcPool500 = computeUniV3Pool(WBTC, stBTC, 500);

        console.log("WETH->WBTC pool (3000 fee):", wethWbtcPool3000);
        console.log("WBTC->stBTC pool (500 fee):", wbtcStBtcPool500);

        // Check if these pools exist on mainnet
        console.log("WETH->WBTC pool exists:", poolExists(wethWbtcPool3000));
        console.log("WBTC->stBTC pool exists:", poolExists(wbtcStBtcPool500));

        // Test different fee tiers
        console.log("\n=== TRYING DIFFERENT FEE TIERS ===");

        address wethWbtcPool500 = computeUniV3Pool(WETH, WBTC, 500);
        address wethWbtcPool10000 = computeUniV3Pool(WETH, WBTC, 10000);

        console.log("WETH->WBTC pool (500 fee):", wethWbtcPool500);
        console.log(
            "WETH->WBTC pool (500 fee) exists:",
            poolExists(wethWbtcPool500)
        );
        console.log("WETH->WBTC pool (10000 fee):", wethWbtcPool10000);
        console.log(
            "WETH->WBTC pool (10000 fee) exists:",
            poolExists(wethWbtcPool10000)
        );

        // Test stBTC pools
        address wbtcStBtcPool3000 = computeUniV3Pool(WBTC, stBTC, 3000);
        address wbtcStBtcPool10000 = computeUniV3Pool(WBTC, stBTC, 10000);

        console.log("WBTC->stBTC pool (3000 fee):", wbtcStBtcPool3000);
        console.log(
            "WBTC->stBTC pool (3000 fee) exists:",
            poolExists(wbtcStBtcPool3000)
        );
        console.log("WBTC->stBTC pool (10000 fee):", wbtcStBtcPool10000);
        console.log(
            "WBTC->stBTC pool (10000 fee) exists:",
            poolExists(wbtcStBtcPool10000)
        );
    }

    function testActualMultiHopWithCorrectPools() public {
        console.log("=== TESTING WITH CORRECT POOL ADDRESSES ===");

        vm.startPrank(OWNER);
        deal(address(WETH), OWNER, 100 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        // Find the correct pools
        address wethWbtcPool = computeUniV3Pool(WETH, WBTC, 500); // Try 500 fee
        address wbtcStBtcPool = computeUniV3Pool(WBTC, stBTC, 500); // Try 500 fee

        console.log("Using WETH->WBTC pool:", wethWbtcPool);
        console.log("Using WBTC->stBTC pool:", wbtcStBtcPool);

        // Whitelist the correct pools
        swapper.whitelistPool(wethWbtcPool, true);
        swapper.whitelistPool(wbtcStBtcPool, true);

        // Test with correct fee tiers
        bytes memory multiHopPath = abi.encodePacked(
            WETH,
            uint24(500), // Changed from 3000 to 500
            WBTC,
            uint24(500), // Keep as 500
            stBTC
        );

        bytes memory routeData = abi.encode(
            AssetSwapper.UniswapV3Route({
                pool: address(0),
                fee: 0,
                isMultiHop: true,
                path: multiHopPath
            })
        );

        try
            swapper.swapAssets(
                AssetSwapper.SwapParams({
                    tokenIn: WETH,
                    tokenOut: stBTC,
                    amountIn: 1 ether,
                    minAmountOut: 0.001 ether, // Very low minimum for testing
                    protocol: AssetSwapper.Protocol.UniswapV3,
                    routeData: routeData
                })
            )
        returns (uint256 amountOut) {
            console.log(" Multi-hop swap successful! Output:", amountOut);
        } catch Error(string memory reason) {
            console.log(" Multi-hop swap failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(" Multi-hop swap failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }

    // Helper function to compute Uniswap V3 pool address
    function computeUniV3Pool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (address) {
        // Sort tokens
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        // Compute pool address using CREATE2
        bytes32 salt = keccak256(abi.encode(token0, token1, fee));
        bytes32 initCodeHash = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                UNISWAP_V3_FACTORY,
                                salt,
                                initCodeHash
                            )
                        )
                    )
                )
            );
    }

    // Helper function to check if pool exists
    function poolExists(address pool) internal view returns (bool) {
        // Check if contract has code
        uint256 size;
        assembly {
            size := extcodesize(pool)
        }
        return size > 0;
    }
}
*/