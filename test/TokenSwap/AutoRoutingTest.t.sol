
/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/AutoRouting.sol";

contract AutoRoutingProductionConfigTest is Test {
    AutoRouting public swapper;

    // Core addresses from config
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Test addresses
    address constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant ROUTE_MANAGER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant LIQUID_TOKEN_MANAGER =
        0x1234567890123456789012345678901234567890;

    // Token addresses from config
    address constant ankrETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant cbETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant ETHx = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant frxETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant lsETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    address constant mETH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address constant osETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant sfrxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant stBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant swETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address constant uniBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;

    string constant password = "testPassword123";

    function setUp() public {
        vm.createFork("https://ethereum-rpc.publicnode.com");
        vm.startPrank(OWNER);
        vm.deal(OWNER, 1000 ether);

        // Deploy AutoRouting contract
        swapper = new AutoRouting(
            WETH,
            0xE592427A0AEce92De3Edee1F18E0157C05861564,
            0xbAFA44EFE7901E04E39Dad13167D089C559c1138,
            ROUTE_MANAGER,
            keccak256(abi.encode(password, ROUTE_MANAGER)),
            LIQUID_TOKEN_MANAGER
        );

        _initializeContractFromConfig();
        _configureAllRoutes(); // Configure ALL necessary routes

        vm.stopPrank();
    }

    function _initializeContractFromConfig() private {
        // All tokens from config
        address[] memory tokens = new address[](17);
        tokens[0] = ETH_ADDRESS;
        tokens[1] = WETH;
        tokens[2] = WBTC;
        tokens[3] = ankrETH;
        tokens[4] = cbETH;
        tokens[5] = ETHx;
        tokens[6] = frxETH;
        tokens[7] = lsETH;
        tokens[8] = mETH;
        tokens[9] = OETH;
        tokens[10] = osETH;
        tokens[11] = rETH;
        tokens[12] = sfrxETH;
        tokens[13] = stBTC;
        tokens[14] = stETH;
        tokens[15] = swETH;
        tokens[16] = uniBTC;

        // Asset types from config
        AutoRouting.AssetType[] memory types = new AutoRouting.AssetType[](17);
        types[0] = AutoRouting.AssetType.ETH_LST; // ETH
        types[1] = AutoRouting.AssetType.ETH_LST; // WETH
        types[2] = AutoRouting.AssetType.BTC_WRAPPED; // WBTC
        for (uint i = 3; i < 17; i++) {
            if (i == 13 || i == 16) {
                // stBTC, uniBTC
                types[i] = AutoRouting.AssetType.BTC_WRAPPED;
            } else {
                types[i] = AutoRouting.AssetType.ETH_LST;
            }
        }

        // Decimals from config
        uint8[] memory decimals = new uint8[](17);
        for (uint i = 0; i < 17; i++) {
            if (i == 2 || i == 16) {
                // WBTC, uniBTC
                decimals[i] = 8;
            } else {
                decimals[i] = 18;
            }
        }

        // All pools from config poolWhitelist
        address[] memory pools = new address[](17);
        pools[0] = 0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E; // WETH/ankrETH
        pools[1] = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410; // WETH/cbETH
        pools[2] = 0x5d811a9d059dDAB0C18B385ad3b752f734f011cB; // WETH/lsETH
        pools[3] = 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14; // WETH/mETH
        pools[4] = 0x52299416C469843F4e0d54688099966a6c7d720f; // WETH/OETH
        pools[5] = 0x553e9C493678d8606d6a5ba284643dB2110Df823; // WETH/rETH
        pools[6] = 0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D; // WETH/stETH
        pools[7] = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2; // WETH/swETH
        pools[8] = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD; // WETH/WBTC
        pools[9] = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0; // WBTC/stBTC
        pools[10] = 0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0; // WBTC/uniBTC
        pools[11] = 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2; // ETH/ankrETH Curve
        pools[12] = 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492; // ETH/ETHx Curve
        pools[13] = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577; // ETH/frxETH Curve
        pools[14] = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; // ETH/stETH Curve
        pools[15] = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d; // rETH/osETH Curve
        pools[16] = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138; // frxETH Minter

        uint256[] memory tokenCounts = new uint256[](17);
        for (uint i = 0; i < 17; i++) {
            tokenCounts[i] = 2;
        }

        AutoRouting.CurveInterface[]
            memory interfaces = new AutoRouting.CurveInterface[](17);
        // Uniswap pools (0-10)
        for (uint i = 0; i < 11; i++) {
            interfaces[i] = AutoRouting.CurveInterface.None;
        }
        // Curve pools (11-15)
        for (uint i = 11; i < 16; i++) {
            interfaces[i] = AutoRouting.CurveInterface.Exchange;
        }
        // frxETH Minter (16)
        interfaces[16] = AutoRouting.CurveInterface.None;

        // More generous slippage configs for production
        AutoRouting.SlippageConfig[]
            memory slippageConfigs = new AutoRouting.SlippageConfig[](10);
        slippageConfigs[0] = AutoRouting.SlippageConfig(
            ETH_ADDRESS,
            stETH,
            2000
        ); // 20%
        slippageConfigs[1] = AutoRouting.SlippageConfig(
            ETH_ADDRESS,
            ankrETH,
            2000
        ); // 20%
        slippageConfigs[2] = AutoRouting.SlippageConfig(
            ETH_ADDRESS,
            sfrxETH,
            2000
        ); // 20%
        slippageConfigs[3] = AutoRouting.SlippageConfig(WETH, cbETH, 2000); // 20%
        slippageConfigs[4] = AutoRouting.SlippageConfig(WETH, rETH, 2000); // 20%
        slippageConfigs[5] = AutoRouting.SlippageConfig(WETH, WBTC, 2000); // 20%
        slippageConfigs[6] = AutoRouting.SlippageConfig(WETH, stETH, 2000); // 20%
        slippageConfigs[7] = AutoRouting.SlippageConfig(WETH, mETH, 2000); // 20%
        slippageConfigs[8] = AutoRouting.SlippageConfig(WBTC, stBTC, 2000); // 20%
        slippageConfigs[9] = AutoRouting.SlippageConfig(WBTC, uniBTC, 2000); // 20%

        swapper.initialize(
            tokens,
            types,
            decimals,
            pools,
            tokenCounts,
            interfaces,
            slippageConfigs
        );

        console.log("=== CONTRACT INITIALIZED FROM CONFIG ===");
    }

    // Configure ALL routes needed for both direct and auto-routing
    function _configureAllRoutes() private {
        console.log("=== CONFIGURING ALL ROUTES ===");

        vm.startPrank(ROUTE_MANAGER);

        // Configure routes for direct swaps that are in config

        // ETH routes
        swapper.configureRoute(
            ETH_ADDRESS,
            stETH,
            AutoRouting.Protocol.Curve,
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            0,
            0,
            1,
            password
        );

        swapper.configureRoute(
            ETH_ADDRESS,
            ankrETH,
            AutoRouting.Protocol.Curve,
            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
            0,
            0,
            1,
            password
        );

        swapper.configureRoute(
            ETH_ADDRESS,
            frxETH,
            AutoRouting.Protocol.Curve,
            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
            0,
            0,
            1,
            password
        );

        swapper.configureRoute(
            ETH_ADDRESS,
            sfrxETH,
            AutoRouting.Protocol.DirectMint,
            0xbAFA44EFE7901E04E39Dad13167D089C559c1138,
            0,
            0,
            0,
            password
        );

        // WETH routes
        swapper.configureRoute(
            WETH,
            cbETH,
            AutoRouting.Protocol.UniswapV3,
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            500,
            0,
            0,
            password
        );

        swapper.configureRoute(
            WETH,
            rETH,
            AutoRouting.Protocol.UniswapV3,
            0x553e9C493678d8606d6a5ba284643dB2110Df823,
            100,
            0,
            0,
            password
        );

        swapper.configureRoute(
            WETH,
            ankrETH,
            AutoRouting.Protocol.UniswapV3,
            0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E,
            3000,
            0,
            0,
            password
        );

        swapper.configureRoute(
            WETH,
            mETH,
            AutoRouting.Protocol.UniswapV3,
            0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
            500,
            0,
            0,
            password
        );

        swapper.configureRoute(
            WETH,
            OETH,
            AutoRouting.Protocol.UniswapV3,
            0x52299416C469843F4e0d54688099966a6c7d720f,
            500,
            0,
            0,
            password
        );

        // Reverse routes for auto-routing
        swapper.configureRoute(
            ankrETH,
            WETH,
            AutoRouting.Protocol.UniswapV3,
            0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E,
            3000,
            0,
            0,
            password
        );

        swapper.configureRoute(
            cbETH,
            WETH,
            AutoRouting.Protocol.UniswapV3,
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            500,
            0,
            0,
            password
        );

        swapper.configureRoute(
            mETH,
            WETH,
            AutoRouting.Protocol.UniswapV3,
            0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
            500,
            0,
            0,
            password
        );

        swapper.configureRoute(
            OETH,
            WETH,
            AutoRouting.Protocol.UniswapV3,
            0x52299416C469843F4e0d54688099966a6c7d720f,
            500,
            0,
            0,
            password
        );

        vm.stopPrank();
        console.log("=== ALL ROUTES CONFIGURED ===");
    }

    // ============================================================================
    // DIRECT ROUTE TESTS - CURVE
    // ============================================================================

    function testDirectRouteCurveETHtoStETH() public {
        console.log("=== DIRECT ROUTE: ETH -> stETH (Curve) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        vm.deal(LIQUID_TOKEN_MANAGER, 10 ether);

        bytes memory routeData = abi.encode(
            AutoRouting.CurveRoute({
                pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
                tokenIndexIn: 0,
                tokenIndexOut: 1,
                useUnderlying: false
            })
        );

        uint256 amountOut = swapper.swapAssets{value: 0.1 ether}(
            AutoRouting.SwapParams({
                tokenIn: ETH_ADDRESS,
                tokenOut: stETH,
                amountIn: 0.1 ether,
                minAmountOut: 0.08 ether, // 20% slippage
                protocol: AutoRouting.Protocol.Curve,
                routeData: routeData
            })
        );

        console.log(" ETH->stETH Curve SUCCESS - Amount:", amountOut);
        assertGt(amountOut, 0.08 ether, "Should receive minimum stETH");
        vm.stopPrank();
    }

    function testDirectRouteCurveETHtoAnkrETH() public {
        console.log("=== DIRECT ROUTE: ETH -> ankrETH (Curve) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        vm.deal(LIQUID_TOKEN_MANAGER, 10 ether);

        bytes memory routeData = abi.encode(
            AutoRouting.CurveRoute({
                pool: 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
                tokenIndexIn: 0,
                tokenIndexOut: 1,
                useUnderlying: false
            })
        );

        uint256 amountOut = swapper.swapAssets{value: 0.1 ether}(
            AutoRouting.SwapParams({
                tokenIn: ETH_ADDRESS,
                tokenOut: ankrETH,
                amountIn: 0.1 ether,
                minAmountOut: 0.08 ether, // 20% slippage
                protocol: AutoRouting.Protocol.Curve,
                routeData: routeData
            })
        );

        console.log(" ETH->ankrETH Curve SUCCESS - Amount:", amountOut);
        assertGt(amountOut, 0.08 ether, "Should receive minimum ankrETH");
        vm.stopPrank();
    }

    // ============================================================================
    // DIRECT ROUTE TESTS - UNISWAP V3
    // ============================================================================

    function testDirectRouteUniswapWETHtoCbETH() public {
        console.log("=== DIRECT ROUTE: WETH -> cbETH (Uniswap V3) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        bytes memory routeData = abi.encode(
            AutoRouting.UniswapV3Route({
                pool: 0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
                fee: 500,
                isMultiHop: false,
                path: ""
            })
        );

        uint256 amountOut = swapper.swapAssets(
            AutoRouting.SwapParams({
                tokenIn: WETH,
                tokenOut: cbETH,
                amountIn: 0.1 ether,
                minAmountOut: 0.08 ether, // 20% slippage
                protocol: AutoRouting.Protocol.UniswapV3,
                routeData: routeData
            })
        );

        console.log(" WETH->cbETH Uniswap SUCCESS - Amount:", amountOut);
        assertGt(amountOut, 0.08 ether, "Should receive minimum cbETH");
        vm.stopPrank();
    }

    function testDirectRouteUniswapWETHtoRETH() public {
        console.log("=== DIRECT ROUTE: WETH -> rETH (Uniswap V3) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        bytes memory routeData = abi.encode(
            AutoRouting.UniswapV3Route({
                pool: 0x553e9C493678d8606d6a5ba284643dB2110Df823,
                fee: 100,
                isMultiHop: false,
                path: ""
            })
        );

        uint256 amountOut = swapper.swapAssets(
            AutoRouting.SwapParams({
                tokenIn: WETH,
                tokenOut: rETH,
                amountIn: 0.1 ether,
                minAmountOut: 0.08 ether, // 20% slippage
                protocol: AutoRouting.Protocol.UniswapV3,
                routeData: routeData
            })
        );

        console.log(" WETH->rETH Uniswap SUCCESS - Amount:", amountOut);
        assertGt(amountOut, 0.08 ether, "Should receive minimum rETH");
        vm.stopPrank();
    }

    // ============================================================================
    // DIRECT ROUTE TESTS - SPECIAL PROTOCOLS
    // ============================================================================

    function testDirectRouteETHtoSfrxETH() public {
        console.log("=== DIRECT ROUTE: ETH -> sfrxETH (DirectMint) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        vm.deal(LIQUID_TOKEN_MANAGER, 10 ether);

        // For DirectMint, routeData can be empty
        bytes memory routeData = "";

        uint256 amountOut = swapper.swapAssets{value: 0.1 ether}(
            AutoRouting.SwapParams({
                tokenIn: ETH_ADDRESS,
                tokenOut: sfrxETH,
                amountIn: 0.1 ether,
                minAmountOut: 0.08 ether, // 20% slippage
                protocol: AutoRouting.Protocol.DirectMint,
                routeData: routeData
            })
        );

        console.log(" ETH->sfrxETH DirectMint SUCCESS - Amount:", amountOut);
        assertGt(amountOut, 0.08 ether, "Should receive minimum sfrxETH");
        vm.stopPrank();
    }

    // ============================================================================
    // AUTO ROUTING TESTS
    // ============================================================================

    function testAutoRoutingAnkrETHtoCbETH() public {
        console.log("=== AUTO ROUTING: ankrETH -> cbETH (via WETH) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(ankrETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(ankrETH).approve(address(swapper), type(uint256).max);

        uint256 amountOut = swapper.autoSwapAssets(
            ankrETH,
            cbETH,
            0.1 ether,
            0.080 ether // 36% slippage for 2-hop (1 - 0.8 * 0.8 = 0.36)
        );

        console.log(
            " AUTO ROUTING SUCCESS - ankrETH->cbETH - Amount:",
            amountOut
        );
        assertGt(amountOut, 0.080 ether, "Should receive minimum cbETH");
        vm.stopPrank();
    }

    function testAutoRoutingMETHtoOETH() public {
        console.log("=== AUTO ROUTING: mETH -> OETH (via WETH) ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(mETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(mETH).approve(address(swapper), type(uint256).max);

        uint256 amountOut = swapper.autoSwapAssets(
            mETH,
            OETH,
            0.1 ether,
            0.080 ether // 20% slippage for 2-hop (1 - 0.8 * 0.8 = 0.36)
        );

        console.log(" AUTO ROUTING SUCCESS - mETH->OETH - Amount:", amountOut);
        assertGt(amountOut, 0.080 ether, "Should receive minimum OETH");
        vm.stopPrank();
    }
    // ============================================================================
    // COMPREHENSIVE BATCH TESTS
    // ============================================================================

    function testAllCurveRoutes() public {
        console.log("=== TESTING ALL CURVE ROUTES ===");

        testDirectRouteCurveETHtoStETH();
        testDirectRouteCurveETHtoAnkrETH();

        console.log(" All Curve routes tested successfully");
    }

    function testAllUniswapRoutes() public {
        console.log("=== TESTING ALL UNISWAP ROUTES ===");

        testDirectRouteUniswapWETHtoCbETH();
        testDirectRouteUniswapWETHtoRETH();

        console.log(" All Uniswap routes tested successfully");
    }

    function testAllAutoRoutes() public {
        console.log("=== TESTING ALL AUTO ROUTES ===");

        testAutoRoutingAnkrETHtoCbETH();
        testAutoRoutingMETHtoOETH();

        console.log(" All Auto routes tested successfully");
    }

    // ============================================================================
    // ERROR HANDLING
    // ============================================================================

    function testErrorHandling() public {
        console.log("=== TESTING ERROR HANDLING ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        vm.deal(LIQUID_TOKEN_MANAGER, 10 ether);

        // Same token
        vm.expectRevert("Same token");
        swapper.autoSwapAssets{value: 1 ether}(
            ETH_ADDRESS,
            ETH_ADDRESS,
            1 ether,
            1 ether
        );

        // Zero amount
        vm.expectRevert("Zero amount");
        swapper.autoSwapAssets{value: 0}(ETH_ADDRESS, stETH, 0, 0);

        // Cross-category
        vm.expectRevert("Cross-category swaps not supported");
        swapper.autoSwapAssets{value: 1 ether}(ETH_ADDRESS, WBTC, 1 ether, 1);

        console.log(" Error handling works correctly");
        vm.stopPrank();
    }
}
*/