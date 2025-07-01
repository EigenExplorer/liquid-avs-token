/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AssetSwapper} from "../../../src/AssetSwapper.sol";

contract AssetSwapperlastVersiontest is Test {
    // Constants matching AssetSwapper
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant LSETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    address constant UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
    address constant STBTC = 0x530824DA86689C9C17CdC2871Ff29B058345b44a;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Test contract state
    AssetSwapper public assetSwapper;
    address public owner;
    address public liquidTokenManager;
    address public routeManager;

    // Fork configuration
    uint256 mainnetFork;

    function setUp() public {
        console.log("CONTRACT INITIALIZATION STARTING");

        // Fork mainnet
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Setup addresses
        owner = address(this);
        liquidTokenManager = address(0x123);
        routeManager = address(0x456);

        // Deploy AssetSwapper with proper constructor parameters
        bytes32 routePasswordHash = keccak256(
            abi.encode("test_password", address(1))
        );

        assetSwapper = new AssetSwapper(
            WETH,
            0xE592427A0AEce92De3Edee1F18E0157C05861564, // Uniswap V3 Router
            0xbAFA44EFE7901E04E39Dad13167D089C559c1138, // frxETH Minter
            routeManager,
            routePasswordHash,
            liquidTokenManager
        );

        console.log("AssetSwapper v3.0 DEPLOYMENT COMPLETE");
        console.log(
            "Auto-routing enabled by default:",
            assetSwapper.autoRoutingEnabled()
        );
        console.log("Contract initialized at:", address(assetSwapper));

        // Initialize with configuration
        _initializeAssetSwapper();

        console.log("CONTRACT INITIALIZATION COMPLETE");
    }

    function _initializeAssetSwapper() private {
        // Token addresses array (17 tokens)
        address[] memory tokenAddresses = new address[](17);
        tokenAddresses[0] = WETH;
        tokenAddresses[1] = WBTC;
        tokenAddresses[2] = STETH;
        tokenAddresses[3] = RETH;
        tokenAddresses[4] = CBETH;
        tokenAddresses[5] = ANKRETH;
        tokenAddresses[6] = OSETH;
        tokenAddresses[7] = FRXETH;
        tokenAddresses[8] = SFRXETH;
        tokenAddresses[9] = OETH;
        tokenAddresses[10] = SWETH;
        tokenAddresses[11] = ETHX;
        tokenAddresses[12] = METH;
        tokenAddresses[13] = LSETH;
        tokenAddresses[14] = UNIBTC;
        tokenAddresses[15] = STBTC;
        tokenAddresses[16] = USDT;

        // Asset types
        AssetSwapper.AssetType[]
            memory assetTypes = new AssetSwapper.AssetType[](17);
        assetTypes[0] = AssetSwapper.AssetType.VOLATILE; // WETH
        assetTypes[1] = AssetSwapper.AssetType.BTC_WRAPPED; // WBTC
        for (uint i = 2; i <= 13; i++) {
            assetTypes[i] = AssetSwapper.AssetType.ETH_LST; // All ETH LSTs
        }
        assetTypes[14] = AssetSwapper.AssetType.BTC_WRAPPED; // UNIBTC
        assetTypes[15] = AssetSwapper.AssetType.BTC_WRAPPED; // STBTC
        assetTypes[16] = AssetSwapper.AssetType.STABLE; // USDT

        // Decimals
        uint8[] memory decimals = new uint8[](17);
        decimals[0] = 18; // WETH
        decimals[1] = 8; // WBTC
        for (uint i = 2; i <= 13; i++) {
            decimals[i] = 18; // ETH LSTs
        }
        decimals[14] = 8; // UNIBTC
        decimals[15] = 18; // STBTC
        decimals[16] = 6; // USDT

        // Pool addresses
        address[] memory poolAddresses = new address[](10);
        poolAddresses[0] = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD; // WETH/WBTC
        poolAddresses[1] = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; // ETH/stETH Curve
        poolAddresses[2] = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577; // ETH/frxETH Curve
        poolAddresses[3] = 0x0CE176E1b11A8f88a4Ba2535De80E81F88592bad; // ETH/ankrETH Curve
        poolAddresses[4] = 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492; // ETH/ethx Curve
        poolAddresses[5] = 0x553e9C493678d8606d6a5ba284643dB2110Df823; // WETH/rETH Uniswap
        poolAddresses[6] = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d; // rETH/osETH Curve
        poolAddresses[7] = 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14; // WETH/METH
        poolAddresses[8] = 0x52299416C469843F4e0d54688099966a6c7d720f; // WETH/OETH
        poolAddresses[9] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // Additional pool

        // Pool token counts
        uint256[] memory poolTokenCounts = new uint256[](10);
        for (uint i = 0; i < 10; i++) {
            poolTokenCounts[i] = 2;
        }

        // Curve interfaces
        AssetSwapper.CurveInterface[]
            memory curveInterfaces = new AssetSwapper.CurveInterface[](10);
        curveInterfaces[0] = AssetSwapper.CurveInterface.None; // Uniswap
        for (uint i = 1; i <= 6; i++) {
            curveInterfaces[i] = AssetSwapper.CurveInterface.Exchange; // Curve
        }
        for (uint i = 7; i <= 9; i++) {
            curveInterfaces[i] = AssetSwapper.CurveInterface.None; // Uniswap
        }

        // Slippage configurations - more conservative
        AssetSwapper.SlippageConfig[]
            memory slippageConfigs = new AssetSwapper.SlippageConfig[](10);
        slippageConfigs[0] = AssetSwapper.SlippageConfig(WETH, WBTC, 1500); // 15%
        slippageConfigs[1] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            STETH,
            1000
        ); // 10%
        slippageConfigs[2] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            FRXETH,
            1000
        ); // 10%
        slippageConfigs[3] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            ANKRETH,
            1000
        ); // 10%
        slippageConfigs[4] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            ETHX,
            1000
        ); // 10%
        slippageConfigs[5] = AssetSwapper.SlippageConfig(WETH, RETH, 1500); // 15%
        slippageConfigs[6] = AssetSwapper.SlippageConfig(RETH, OSETH, 1500); // 15%
        slippageConfigs[7] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            SFRXETH,
            1500
        ); // 15%
        slippageConfigs[8] = AssetSwapper.SlippageConfig(WETH, OSETH, 2000); // 20%
        slippageConfigs[9] = AssetSwapper.SlippageConfig(WETH, SFRXETH, 1500); // 15%

        // Initialize the contract
        assetSwapper.initialize(
            tokenAddresses,
            assetTypes,
            decimals,
            poolAddresses,
            poolTokenCounts,
            curveInterfaces,
            slippageConfigs
        );
    }

    function testAutoRoutingExecution() public {
        console.log("TESTING AUTO-ROUTING EXECUTION");

        address tokenIn = WETH;
        address tokenOut = WBTC;
        uint256 amountIn = 1 ether;

        // Give tokens to liquidTokenManager and approve
        deal(WETH, liquidTokenManager, amountIn);
        vm.prank(liquidTokenManager);
        IERC20(WETH).approve(address(assetSwapper), amountIn);

        address pool = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
        uint24 fee = 3000;

        AssetSwapper.UniswapV3Route memory route = AssetSwapper.UniswapV3Route({
            pool: pool,
            fee: fee,
            isMultiHop: false,
            path: ""
        });

        // FIXED: Realistic minimum for WETH->WBTC swap. 1 ETH ~= 0.023 BTC at current rates
        uint256 minAmountOut = 2000000; // 0.02 WBTC (2% of 1 WBTC) - very conservative

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: AssetSwapper.Protocol.UniswapV3,
            routeData: abi.encode(route)
        });

        vm.prank(liquidTokenManager);
        uint256 amountOut = assetSwapper.swapAssets(params);

        console.log("AUTO-ROUTING SUCCESS! Amount out:", amountOut);
        assertGt(amountOut, 0, "Should receive WBTC");
    }

    function testCurveSwaps() public {
        console.log("TESTING CURVE SWAPS");

        uint256 amountIn = 1 ether;
        address pool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

        AssetSwapper.CurveRoute memory route = AssetSwapper.CurveRoute({
            pool: pool,
            tokenIndexIn: 0,
            tokenIndexOut: 1,
            useUnderlying: false
        });

        uint256 minAmountOut = (amountIn * 8500) / 10000; // 15% slippage

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: ETH_ADDRESS,
            tokenOut: STETH,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: AssetSwapper.Protocol.Curve,
            routeData: abi.encode(route)
        });

        vm.prank(liquidTokenManager);
        uint256 amountOut = assetSwapper.swapAssets{value: amountIn}(params);

        console.log("CURVE SWAP SUCCESS! Received stETH:", amountOut);
        assertGt(amountOut, 0, "Should receive stETH");
    }

    function testDirectMint() public {
        console.log("TESTING DIRECT MINT");

        uint256 amountIn = 1 ether;
        uint256 minAmountOut = (amountIn * 8000) / 10000; // 20% slippage - more conservative

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: ETH_ADDRESS,
            tokenOut: SFRXETH,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: AssetSwapper.Protocol.DirectMint,
            routeData: ""
        });

        vm.prank(liquidTokenManager);
        uint256 amountOut = assetSwapper.swapAssets{value: amountIn}(params);

        console.log("DIRECT MINT SUCCESS! Received sfrxETH:", amountOut);
        assertGt(amountOut, 0, "Should receive sfrxETH");
    }

    function testEmergencyFunctions() public {
        console.log("TESTING EMERGENCY FUNCTIONS");

        // Test pause/unpause
        assetSwapper.pause();
        console.log("Contract paused successfully");
        assertTrue(assetSwapper.paused(), "Contract should be paused");

        // Test emergency withdraw (requires paused state)
        deal(address(assetSwapper), 1 ether);
        uint256 balanceBefore = address(this).balance;
        assetSwapper.emergencyWithdraw(ETH_ADDRESS, 1 ether, address(this));
        console.log("Emergency withdraw successful");
        assertEq(
            address(this).balance - balanceBefore,
            1 ether,
            "Should withdraw ETH"
        );

        // Test unpause
        assetSwapper.unpause();
        console.log("Contract unpaused successfully");
        assertFalse(assetSwapper.paused(), "Contract should be unpaused");

        // Test pool pause/unpause
        address poolToPause = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
        assetSwapper.emergencyPausePool(poolToPause, "Testing");
        console.log("Pool paused successfully");

        (, bool poolPaused, , ) = assetSwapper.getPoolInfo(poolToPause);
        assertTrue(poolPaused, "Pool should be paused");

        assetSwapper.unpausePool(poolToPause);
        console.log("Pool unpaused successfully");

        (, bool poolUnpaused, , ) = assetSwapper.getPoolInfo(poolToPause);
        assertFalse(poolUnpaused, "Pool should be unpaused");
    }

    function testErrorHandling() public {
        console.log("TESTING ERROR HANDLING");

        // Test zero amount with authorized caller
        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: WETH,
            tokenOut: WBTC,
            amountIn: 0,
            minAmountOut: 0,
            protocol: AssetSwapper.Protocol.UniswapV3,
            routeData: ""
        });

        vm.prank(liquidTokenManager);
        vm.expectRevert(AssetSwapper.ZeroAmount.selector);
        assetSwapper.swapAssets(params);
        console.log("Correctly rejected zero amount");

        // Test same token swap with authorized caller
        params.tokenIn = WETH;
        params.tokenOut = WETH;
        params.amountIn = 1 ether;

        vm.prank(liquidTokenManager);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidParameter(string)", "sameToken")
        );
        assetSwapper.swapAssets(params);
        console.log("Correctly rejected same token swap");

        // Test unauthorized caller (use different address)
        address unauthorizedUser = address(0x999);
        params.tokenIn = WETH;
        params.tokenOut = WBTC;
        vm.prank(unauthorizedUser);
        vm.expectRevert(AssetSwapper.UnauthorizedCaller.selector);
        assetSwapper.swapAssets(params);
        console.log("Correctly rejected unauthorized caller");
    }

    function testViewFunctions() public {
        console.log("TESTING VIEW FUNCTIONS");

        // Test authorized caller
        assertTrue(
            assetSwapper.isAuthorizedCaller(liquidTokenManager),
            "LTM should be authorized"
        );

        // Test token info
        (
            bool supported,
            AssetSwapper.AssetType assetType,
            uint8 decimals
        ) = assetSwapper.getTokenInfo(WETH);
        assertTrue(supported, "WETH should be supported");
        assertEq(
            uint8(assetType),
            uint8(AssetSwapper.AssetType.VOLATILE),
            "WETH should be volatile"
        );
        assertEq(decimals, 18, "WETH should have 18 decimals");

        // Test slippage tolerance
        uint256 slippage = assetSwapper.getSlippageTolerance(WETH, WBTC);
        assertEq(slippage, 1500, "Should have 15% slippage");

        // Test normalization
        uint256 normalized = assetSwapper.normalizeAmount(WETH, WBTC, 1 ether);
        assertEq(normalized, 1e8, "Should normalize to 8 decimals");

        // Test direct route check
        assertTrue(
            assetSwapper.hasDirectRoute(WETH, WBTC),
            "Should have direct WETH->WBTC route"
        );

        // Test route info
        (
            uint8 routeType,
            address hubToken,
            uint256 estimatedSlippage
        ) = assetSwapper.getRouteInfo(WETH, WBTC);
        assertEq(routeType, 1, "Should have direct route");
        assertEq(hubToken, address(0), "Should not use hub token");

        // Test auto-routing stats
        (
            uint256 successCount,
            uint256 failureCount,
            bool enabled
        ) = assetSwapper.getAutoRoutingStats();
        assertTrue(enabled, "Auto-routing should be enabled");

        console.log("All view functions working correctly");
    }

    function testMultiHopSwap() public {
        console.log("TESTING MULTI-HOP SWAP");

        uint256 amountIn = 1 ether;

        // FIXED: Give tokens to liquidTokenManager BEFORE executing the swap
        deal(WETH, liquidTokenManager, amountIn);
        vm.prank(liquidTokenManager);
        IERC20(WETH).approve(address(assetSwapper), amountIn);

        uint256 minAmountOut = (amountIn * 7000) / 10000; // 30% slippage for multi-hop

        // Correct MultiHopRoute structure
        AssetSwapper.MultiHopRoute memory route = AssetSwapper.MultiHopRoute({
            routeHash: keccak256("WETH_TO_OSETH"),
            intermediateMinOut: 0,
            routeData: ""
        });

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: WETH,
            tokenOut: OSETH,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: AssetSwapper.Protocol.MultiHop,
            routeData: abi.encode(route)
        });

        vm.prank(liquidTokenManager);
        uint256 amountOut = assetSwapper.swapAssets(params);

        console.log("MULTI-HOP SUCCESS! Received osETH:", amountOut);
        assertGt(amountOut, 0, "Should receive osETH");
    }

    function testMultiStepSwap() public {
        console.log("TESTING MULTI-STEP SWAP");

        uint256 amountIn = 1 ether;
        deal(WETH, liquidTokenManager, amountIn);
        vm.prank(liquidTokenManager);
        IERC20(WETH).approve(address(assetSwapper), amountIn);

        // Correct StepAction structure with 5 fields
        AssetSwapper.StepAction[] memory steps = new AssetSwapper.StepAction[](
            2
        );

        steps[0] = AssetSwapper.StepAction({
            actionType: AssetSwapper.ActionType.UNWRAP,
            protocol: AssetSwapper.Protocol.UniswapV3,
            tokenIn: WETH,
            tokenOut: ETH_ADDRESS,
            routeData: ""
        });

        steps[1] = AssetSwapper.StepAction({
            actionType: AssetSwapper.ActionType.DIRECT_MINT,
            protocol: AssetSwapper.Protocol.DirectMint,
            tokenIn: ETH_ADDRESS,
            tokenOut: SFRXETH,
            routeData: ""
        });

        AssetSwapper.MultiStepRoute memory route = AssetSwapper.MultiStepRoute({
            steps: steps
        });

        uint256 minAmountOut = (amountIn * 7000) / 10000; // 30% slippage for multi-step

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: WETH,
            tokenOut: SFRXETH,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: AssetSwapper.Protocol.MultiStep,
            routeData: abi.encode(route)
        });

        vm.prank(liquidTokenManager);
        uint256 amountOut = assetSwapper.swapAssets(params);

        console.log("MULTI-STEP SUCCESS! Received sfrxETH:", amountOut);
        assertGt(amountOut, 0, "Should receive sfrxETH");
    }

    function testUniswapV3DirectSwaps() public {
        console.log("TESTING UNISWAP V3 DIRECT SWAPS");

        // FIXED: Only test with whitelisted pools
        // Using RETH pool which is already whitelisted at index 5
        address tokenOut = RETH;
        address pool = 0x553e9C493678d8606d6a5ba284643dB2110Df823;
        uint24 fee = 100;

        console.log("Testing swap to token:", tokenOut);

        uint256 amountIn = 0.1 ether;
        deal(WETH, liquidTokenManager, amountIn);
        vm.prank(liquidTokenManager);
        IERC20(WETH).approve(address(assetSwapper), amountIn);

        AssetSwapper.UniswapV3Route memory route = AssetSwapper.UniswapV3Route({
            pool: pool,
            fee: fee,
            isMultiHop: false,
            path: ""
        });

        uint256 minAmountOut = (amountIn * 8000) / 10000; // 20% slippage

        AssetSwapper.SwapParams memory params = AssetSwapper.SwapParams({
            tokenIn: WETH,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: AssetSwapper.Protocol.UniswapV3,
            routeData: abi.encode(route)
        });

        vm.prank(liquidTokenManager);
        uint256 amountOut = assetSwapper.swapAssets(params);

        console.log("Direct swap success! Amount out:", amountOut);
        assertGt(amountOut, 0, "Should receive tokens");
    }

    function testAutoRoutingCapabilities() public {
        console.log("TESTING AUTO-ROUTING CAPABILITIES");

        // Test direct route checking (avoid recursion)
        bool hasRoute = assetSwapper.hasDirectRoute(WETH, WBTC);
        console.log("Has direct route WETH->WBTC:", hasRoute);
        assertTrue(hasRoute, "Should have direct route");

        // Test auto-routing stats
        (
            uint256 successCount,
            uint256 failureCount,
            bool enabled
        ) = assetSwapper.getAutoRoutingStats();
        console.log("Auto-routing enabled:", enabled);
        console.log("Success count:", successCount);
        console.log("Failure count:", failureCount);
        assertTrue(enabled, "Should be enabled");

        // Test route info for known direct route
        (
            uint8 routeType,
            address hubToken,
            uint256 estimatedSlippage
        ) = assetSwapper.getRouteInfo(WETH, WBTC);

        console.log("Route type:", routeType);
        console.log("Hub token:", hubToken);
        console.log("Estimated slippage:", estimatedSlippage);

        assertEq(routeType, 1, "Should be direct route");
    }

    function testCalculateSwapOutput() public {
        console.log("TESTING CALCULATE SWAP OUTPUT");

        (uint256 normalizedOut, uint256 minOut) = assetSwapper
            .calculateSwapOutput(WETH, WBTC, 1 ether);

        console.log("Normalized output:", normalizedOut);
        console.log("Min output with slippage:", minOut);

        assertEq(normalizedOut, 1e8, "Should normalize to WBTC decimals");
        assertLt(
            minOut,
            normalizedOut,
            "Min out should be less than normalized"
        );
    }

    function testProtocolPauseUnpause() public {
        console.log("TESTING PROTOCOL PAUSE/UNPAUSE");

        // Pause protocol
        assetSwapper.emergencyPauseProtocol(
            AssetSwapper.Protocol.UniswapV3,
            "Testing"
        );
        console.log("Protocol paused successfully");
        assertTrue(
            assetSwapper.protocolPaused(AssetSwapper.Protocol.UniswapV3),
            "Protocol should be paused"
        );

        // Unpause protocol
        assetSwapper.unpauseProtocol(AssetSwapper.Protocol.UniswapV3);
        console.log("Protocol unpaused successfully");
        assertFalse(
            assetSwapper.protocolPaused(AssetSwapper.Protocol.UniswapV3),
            "Protocol should be unpaused"
        );
    }

    // Skip the password test for now as requested
    function testRoutePasswordProtection() public {
        console.log("TESTING ROUTE PASSWORD PROTECTION - SKIPPED");
        // This test is being skipped as requested
        console.log("Password test bypassed");
    }

    // Receive function to accept ETH
    receive() external payable {}
}
*/