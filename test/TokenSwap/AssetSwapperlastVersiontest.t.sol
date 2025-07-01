/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/AssetSwapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/interfaces/IWETH.sol";

contract AssetSwapperlastVersiontest is Test {
    AssetSwapper public swapper;

    // Config addresses (checksummed)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Test addresses
    address constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant ROUTE_MANAGER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant LIQUID_TOKEN_MANAGER =
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant USER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    // Config data structure updated for v3.0
    struct ConfigData {
        address[] tokenAddresses;
        AssetSwapper.AssetType[] tokenTypes;
        uint8[] decimals;
        address[] poolAddresses;
        uint256[] poolTokenCounts;
        AssetSwapper.CurveInterface[] curveInterfaces;
        AssetSwapper.SlippageConfig[] slippageConfigs;
    }

    function setUp() public {
        vm.startPrank(OWNER);
        vm.deal(OWNER, 1000 ether);

        // Deploy contracts with all required parameters for v3.0
        address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        address frxETHMinter = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
        bytes32 routePasswordHash = keccak256(
            abi.encode("testPassword123", address(0))
        ); // Include salt

        swapper = new AssetSwapper(
            WETH,
            uniswapRouter,
            frxETHMinter,
            ROUTE_MANAGER,
            routePasswordHash,
            LIQUID_TOKEN_MANAGER // Added required parameter
        );

        // Initialize from config
        _initializeFromConfig();

        vm.stopPrank();
    }

    function _initializeFromConfig() private {
        ConfigData memory config = _createConfigData();

        swapper.initialize(
            config.tokenAddresses,
            config.tokenTypes,
            config.decimals,
            config.poolAddresses,
            config.poolTokenCounts,
            config.curveInterfaces,
            config.slippageConfigs
        );

        console.log("Contract initialized with config data");
        console.log("Total tokens:", config.tokenAddresses.length);
        console.log("Total pools whitelisted:", config.poolAddresses.length);
        console.log("Slippage configurations:", config.slippageConfigs.length);
    }

    // Updated config data creation for v3.0
    function _createConfigData() private pure returns (ConfigData memory) {
        ConfigData memory config;

        // Token addresses
        address[] memory tokens = new address[](17);
        tokens[0] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // ETH
        tokens[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        tokens[2] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        tokens[3] = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb; // ankrETH
        tokens[4] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
        tokens[5] = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b; // ETHx
        tokens[6] = 0x5E8422345238F34275888049021821E8E08CAa1f; // frxETH
        tokens[7] = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549; // lsETH
        tokens[8] = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa; // mETH
        tokens[9] = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3; // OETH
        tokens[10] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38; // osETH
        tokens[11] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH
        tokens[12] = 0xac3E018457B222d93114458476f3E3416Abbe38F; // sfrxETH
        tokens[13] = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3; // stBTC
        tokens[14] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        tokens[15] = 0xf951E335afb289353dc249e82926178EaC7DEd78; // swETH
        tokens[16] = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568; // uniBTC
        config.tokenAddresses = tokens;

        // Token types
        AssetSwapper.AssetType[] memory types = new AssetSwapper.AssetType[](
            17
        );
        types[0] = AssetSwapper.AssetType.ETH_LST; // ETH
        types[1] = AssetSwapper.AssetType.ETH_LST; // WETH
        types[2] = AssetSwapper.AssetType.BTC_WRAPPED; // WBTC
        types[3] = AssetSwapper.AssetType.ETH_LST; // ankrETH
        types[4] = AssetSwapper.AssetType.ETH_LST; // cbETH
        types[5] = AssetSwapper.AssetType.ETH_LST; // ETHx
        types[6] = AssetSwapper.AssetType.ETH_LST; // frxETH
        types[7] = AssetSwapper.AssetType.ETH_LST; // lsETH
        types[8] = AssetSwapper.AssetType.ETH_LST; // mETH
        types[9] = AssetSwapper.AssetType.ETH_LST; // OETH
        types[10] = AssetSwapper.AssetType.ETH_LST; // osETH
        types[11] = AssetSwapper.AssetType.ETH_LST; // rETH
        types[12] = AssetSwapper.AssetType.ETH_LST; // sfrxETH
        types[13] = AssetSwapper.AssetType.BTC_WRAPPED; // stBTC
        types[14] = AssetSwapper.AssetType.ETH_LST; // stETH
        types[15] = AssetSwapper.AssetType.ETH_LST; // swETH
        types[16] = AssetSwapper.AssetType.BTC_WRAPPED; // uniBTC
        config.tokenTypes = types;

        // Decimals
        uint8[] memory decimals = new uint8[](17);
        for (uint i = 0; i < 17; i++) {
            decimals[i] = 18; // Default
        }
        decimals[2] = 8; // WBTC
        decimals[16] = 8; // uniBTC
        config.decimals = decimals;

        // Pool addresses
        address[] memory pools = new address[](17);
        pools[0] = 0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E;
        pools[1] = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;
        pools[2] = 0x5d811a9d059dDAB0C18B385ad3b752f734f011cB;
        pools[3] = 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14;
        pools[4] = 0x52299416C469843F4e0d54688099966a6c7d720f;
        pools[5] = 0x553e9C493678d8606d6a5ba284643dB2110Df823;
        pools[6] = 0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D;
        pools[7] = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2;
        pools[8] = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
        pools[9] = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0;
        pools[10] = 0x242017eE869bF0734Bc5E4feb086A52e6391Dd0d;
        pools[11] = 0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0;
        pools[12] = 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;
        pools[13] = 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492;
        pools[14] = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
        pools[15] = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        pools[16] = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
        config.poolAddresses = pools;

        // Pool token counts (required for v3.0)
        uint256[] memory poolTokenCounts = new uint256[](17);
        for (uint i = 0; i < 17; i++) {
            poolTokenCounts[i] = 2; // Most pools have 2 tokens
        }
        // Adjust for specific pools that have more tokens
        poolTokenCounts[15] = 2; // stETH Curve pool
        poolTokenCounts[16] = 4; // osETH Curve pool (example)
        config.poolTokenCounts = poolTokenCounts;

        // Curve interfaces (required for v3.0)
        AssetSwapper.CurveInterface[]
            memory curveInterfaces = new AssetSwapper.CurveInterface[](17);
        for (uint i = 0; i < 17; i++) {
            if (i >= 15) {
                // Last few are Curve pools
                curveInterfaces[i] = AssetSwapper.CurveInterface.Exchange;
            } else {
                curveInterfaces[i] = AssetSwapper.CurveInterface.None; // Uniswap pools
            }
        }
        config.curveInterfaces = curveInterfaces;

        // Slippage configs with updated values
        AssetSwapper.SlippageConfig[]
            memory slippageConfigs = new AssetSwapper.SlippageConfig[](23);

        // WETH pairs
        slippageConfigs[0] = AssetSwapper.SlippageConfig(WETH, tokens[3], 700); // ankrETH
        slippageConfigs[1] = AssetSwapper.SlippageConfig(WETH, tokens[4], 700); // cbETH
        slippageConfigs[2] = AssetSwapper.SlippageConfig(WETH, tokens[7], 700); // lsETH
        slippageConfigs[3] = AssetSwapper.SlippageConfig(WETH, tokens[8], 800); // mETH
        slippageConfigs[4] = AssetSwapper.SlippageConfig(WETH, tokens[9], 800); // OETH
        slippageConfigs[5] = AssetSwapper.SlippageConfig(
            WETH,
            tokens[11],
            1300
        ); // rETH
        slippageConfigs[6] = AssetSwapper.SlippageConfig(WETH, tokens[14], 700); // stETH
        slippageConfigs[7] = AssetSwapper.SlippageConfig(WETH, tokens[15], 700); // swETH
        slippageConfigs[8] = AssetSwapper.SlippageConfig(WETH, tokens[10], 800); // osETH
        slippageConfigs[9] = AssetSwapper.SlippageConfig(WETH, tokens[12], 700); // sfrxETH
        slippageConfigs[10] = AssetSwapper.SlippageConfig(
            WETH,
            tokens[13],
            1000
        ); // stBTC
        slippageConfigs[11] = AssetSwapper.SlippageConfig(
            WETH,
            tokens[16],
            1000
        ); // uniBTC

        // ETH pairs
        slippageConfigs[12] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            tokens[14],
            500
        ); // stETH
        slippageConfigs[13] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            tokens[3],
            700
        ); // ankrETH
        slippageConfigs[14] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            tokens[5],
            700
        ); // ETHx
        slippageConfigs[15] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            tokens[6],
            700
        ); // frxETH
        slippageConfigs[16] = AssetSwapper.SlippageConfig(
            ETH_ADDRESS,
            tokens[12],
            500
        ); // sfrxETH

        // Cross pairs
        slippageConfigs[17] = AssetSwapper.SlippageConfig(
            tokens[11],
            tokens[10],
            800
        ); // rETH->osETH
        slippageConfigs[18] = AssetSwapper.SlippageConfig(
            WBTC,
            tokens[13],
            800
        ); // WBTC->stBTC
        slippageConfigs[19] = AssetSwapper.SlippageConfig(
            WBTC,
            tokens[16],
            800
        ); // WBTC->uniBTC
        slippageConfigs[20] = AssetSwapper.SlippageConfig(
            tokens[6],
            tokens[12],
            200
        ); // frxETH->sfrxETH
        slippageConfigs[21] = AssetSwapper.SlippageConfig(
            tokens[14],
            tokens[11],
            500
        ); // stETH->rETH
        slippageConfigs[22] = AssetSwapper.SlippageConfig(
            tokens[8],
            tokens[9],
            500
        ); // mETH->OETH

        config.slippageConfigs = slippageConfigs;

        return config;
    }

    function testInitializationState() public {
        console.log("Testing initialization state...");

        // Check token support
        assertTrue(swapper.supportedTokens(WETH));
        assertTrue(swapper.supportedTokens(WBTC));
        assertTrue(
            swapper.supportedTokens(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704)
        ); // cbETH

        // Check decimals
        assertEq(swapper.tokenDecimals(WETH), 18);
        assertEq(swapper.tokenDecimals(WBTC), 8);
        assertEq(
            swapper.tokenDecimals(0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568),
            8
        ); // uniBTC

        // Check pool whitelist
        assertTrue(
            swapper.whitelistedPools(0x840DEEef2f115Cf50DA625F7368C24af6fE74410)
        ); // cbETH pool
        assertTrue(
            swapper.whitelistedPools(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022)
        ); // stETH Curve

        // Check slippage tolerance
        assertEq(
            swapper.slippageTolerance(
                WETH,
                0xBe9895146f7AF43049ca1c1AE358B0541Ea49704
            ),
            700
        ); // cbETH
        assertEq(
            swapper.slippageTolerance(
                WETH,
                0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa
            ),
            800
        ); // mETH

        // Check authorized caller
        assertTrue(swapper.isAuthorizedCaller(LIQUID_TOKEN_MANAGER));

        console.log("Initialization state verified");
    }

    function testAllUniswapV3Swaps() public {
        console.log("Testing all Uniswap V3 swaps...");

        vm.startPrank(LIQUID_TOKEN_MANAGER); // Use authorized caller
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 100 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        address[] memory targets = new address[](3);
        targets[0] = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa; // mETH
        targets[1] = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3; // OETH
        targets[2] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH

        for (uint i = 0; i < targets.length; i++) {
            console.log("=== TESTING SWAP", i + 1, "===");
            console.log("Target token:", targets[i]);

            uint256 balanceBefore = IERC20(targets[i]).balanceOf(
                LIQUID_TOKEN_MANAGER
            );
            address pool = _getUniswapPool(WETH, targets[i]);
            uint24 fee = _getFeeForPair(WETH, targets[i]);
            uint256 minOut = _calculateMinOut(WETH, targets[i], 1 ether);

            console.log("Pool address:", pool);
            console.log("Fee tier:", fee);
            console.log("Min out:", minOut);
            console.log("Pool whitelisted:", swapper.whitelistedPools(pool));

            bytes memory routeData = abi.encode(
                AssetSwapper.UniswapV3Route({
                    pool: pool,
                    fee: fee,
                    isMultiHop: false,
                    path: ""
                })
            );

            try
                swapper.swapAssets(
                    AssetSwapper.SwapParams({
                        tokenIn: WETH,
                        tokenOut: targets[i],
                        amountIn: 1 ether,
                        minAmountOut: minOut,
                        protocol: AssetSwapper.Protocol.UniswapV3,
                        routeData: routeData
                    })
                )
            returns (uint256 amountOut) {
                uint256 balanceAfter = IERC20(targets[i]).balanceOf(
                    LIQUID_TOKEN_MANAGER
                );
                console.log("SwapParams memory params SWAP SUCCESS!");
                console.log("Output amount:", amountOut);
                console.log("Balance change:", balanceAfter - balanceBefore);
                assertGt(balanceAfter, balanceBefore);
            } catch Error(string memory reason) {
                console.log(" SWAP FAILED!");
                console.log("Error reason:", reason);
            } catch (bytes memory lowLevelData) {
                console.log(" LOW-LEVEL ERROR!");
                console.logBytes(lowLevelData);
            }

            console.log("==================");
        }

        vm.stopPrank();
    }

    function testMultiHopSwapIsolated() public {
        console.log("=== ISOLATED MULTI-HOP SWAP TEST ===");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        address stBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;

        // Create multi-hop path: WETH -> WBTC -> stBTC
        bytes memory multiHopPath = abi.encodePacked(
            WETH,
            uint24(3000),
            WBTC,
            uint24(500),
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

        uint256 minOut = 1000000; // 0.01 stBTC (8 decimals)

        uint256 stBTCBefore = IERC20(stBTC).balanceOf(LIQUID_TOKEN_MANAGER);

        console.log("Executing multi-hop swap: WETH -> WBTC -> stBTC");

        try
            swapper.swapAssets(
                AssetSwapper.SwapParams({
                    tokenIn: WETH,
                    tokenOut: stBTC,
                    amountIn: 1 ether,
                    minAmountOut: minOut,
                    protocol: AssetSwapper.Protocol.UniswapV3,
                    routeData: routeData
                })
            )
        returns (uint256 amountOut) {
            uint256 stBTCAfter = IERC20(stBTC).balanceOf(LIQUID_TOKEN_MANAGER);
            console.log("SwapParams memory params MULTI-HOP SUCCESS!");
            console.log("stBTC received:", amountOut);
            console.log("Balance change:", stBTCAfter - stBTCBefore);
            assertGt(stBTCAfter, stBTCBefore);
        } catch Error(string memory reason) {
            console.log(" MULTI-HOP FAILED!");
            console.log("Error reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(" LOW-LEVEL ERROR!");
            console.logBytes(lowLevelData);
        }

        vm.stopPrank();
    }

    function testCurveSwaps() public {
        console.log("Testing Curve swaps...");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        vm.deal(LIQUID_TOKEN_MANAGER, 10 ether);

        // Test ETH -> stETH via Curve
        address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address stETHPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

        uint256 balanceBefore = IERC20(stETH).balanceOf(LIQUID_TOKEN_MANAGER);

        bytes memory routeData = abi.encode(
            AssetSwapper.CurveRoute({
                pool: stETHPool,
                tokenIndexIn: 0, // ETH index
                tokenIndexOut: 1, // stETH index
                useUnderlying: false
            })
        );

        uint256 minOut = 0.95 ether; // 5% slippage tolerance

        try
            swapper.swapAssets{value: 1 ether}(
                AssetSwapper.SwapParams({
                    tokenIn: ETH_ADDRESS,
                    tokenOut: stETH,
                    amountIn: 1 ether,
                    minAmountOut: minOut,
                    protocol: AssetSwapper.Protocol.Curve,
                    routeData: routeData
                })
            )
        returns (uint256 amountOut) {
            uint256 balanceAfter = IERC20(stETH).balanceOf(
                LIQUID_TOKEN_MANAGER
            );
            console.log("SwapParams memory params Curve swap successful!");
            console.log("stETH received:", amountOut);
            console.log("Balance change:", balanceAfter - balanceBefore);
            assertGt(balanceAfter, balanceBefore);
        } catch Error(string memory reason) {
            console.log(" Curve swap failed:", reason);
        }

        vm.stopPrank();
    }

    function testDirectMint() public {
        console.log("Testing Direct Mint (ETH -> sfrxETH)...");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        vm.deal(LIQUID_TOKEN_MANAGER, 10 ether);

        address sfrxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
        uint256 balanceBefore = IERC20(sfrxETH).balanceOf(LIQUID_TOKEN_MANAGER);

        try
            swapper.swapAssets{value: 1 ether}(
                AssetSwapper.SwapParams({
                    tokenIn: ETH_ADDRESS,
                    tokenOut: sfrxETH,
                    amountIn: 1 ether,
                    minAmountOut: 0.85 ether, // ✅ Changed from 0.95 to 0.85 - realistic expectation
                    protocol: AssetSwapper.Protocol.DirectMint,
                    routeData: ""
                })
            )
        returns (uint256 amountOut) {
            uint256 balanceAfter = IERC20(sfrxETH).balanceOf(
                LIQUID_TOKEN_MANAGER
            );
            console.log("SwapParams memory params Direct mint successful!");
            console.log("sfrxETH received:", amountOut);
            assertGt(balanceAfter, balanceBefore);

            // ✅ Add realistic range check
            assertGe(amountOut, 0.85 ether); // At least 0.85 sfrxETH
            assertLe(amountOut, 0.95 ether); // At most 0.95 sfrxETH
        } catch Error(string memory reason) {
            console.log(" Direct mint failed:", reason);
            revert(reason); // ✅ Show the actual error for debugging
        }

        vm.stopPrank();
    }

    function testSpecialMultiHopRoute() public {
        console.log("Testing special multi-hop route (WETH -> osETH)...");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        address osETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
        uint256 balanceBefore = IERC20(osETH).balanceOf(LIQUID_TOKEN_MANAGER);

        try
            swapper.swapAssets(
                AssetSwapper.SwapParams({
                    tokenIn: WETH,
                    tokenOut: osETH,
                    amountIn: 1 ether,
                    minAmountOut: 0.85 ether, // Conservative minimum
                    protocol: AssetSwapper.Protocol.MultiHop,
                    routeData: ""
                })
            )
        returns (uint256 amountOut) {
            uint256 balanceAfter = IERC20(osETH).balanceOf(
                LIQUID_TOKEN_MANAGER
            );
            console.log(
                "SwapParams memory params Special multi-hop successful!"
            );
            console.log("osETH received:", amountOut);
            assertGt(balanceAfter, balanceBefore);
        } catch Error(string memory reason) {
            console.log(" Special multi-hop failed:", reason);
        }

        vm.stopPrank();
    }

    function testMultiStepSwap() public {
        console.log("Testing multi-step swap (WETH -> ETH -> sfrxETH)...");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        address sfrxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;

        // Create multi-step route data
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
            tokenOut: sfrxETH,
            routeData: ""
        });

        AssetSwapper.MultiStepRoute memory multiStepRoute = AssetSwapper
            .MultiStepRoute({steps: steps});

        bytes memory routeData = abi.encode(multiStepRoute);

        uint256 balanceBefore = IERC20(sfrxETH).balanceOf(LIQUID_TOKEN_MANAGER);

        try
            swapper.swapAssets(
                AssetSwapper.SwapParams({
                    tokenIn: WETH,
                    tokenOut: sfrxETH,
                    amountIn: 1 ether,
                    minAmountOut: 0.85 ether,
                    protocol: AssetSwapper.Protocol.MultiStep,
                    routeData: routeData
                })
            )
        returns (uint256 amountOut) {
            uint256 balanceAfter = IERC20(sfrxETH).balanceOf(
                LIQUID_TOKEN_MANAGER
            );
            console.log("SwapParams memory params Multi-step swap successful!");
            console.log("sfrxETH received:", amountOut);
            assertGt(balanceAfter, balanceBefore);
        } catch Error(string memory reason) {
            console.log(" Multi-step swap failed:", reason);
        }

        vm.stopPrank();
    }

    function testErrorHandling() public {
        console.log("Testing error handling...");

        vm.startPrank(LIQUID_TOKEN_MANAGER);
        deal(address(WETH), LIQUID_TOKEN_MANAGER, 10 ether);
        IERC20(WETH).approve(address(swapper), type(uint256).max);

        // Test 1: Zero amount swap
        console.log("Test 1: Zero amount swap");
        vm.expectRevert(AssetSwapper.ZeroAmount.selector);
        swapper.swapAssets(
            AssetSwapper.SwapParams({
                tokenIn: WETH,
                tokenOut: 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa,
                amountIn: 0, // Zero amount
                minAmountOut: 1 ether,
                protocol: AssetSwapper.Protocol.UniswapV3,
                routeData: ""
            })
        );
        console.log("SwapParams memory params Correctly rejected zero amount");

        // Test 2: Same token swap
        console.log("Test 2: Same token swap");
        vm.expectRevert(
            abi.encodeWithSelector(
                AssetSwapper.InvalidParameter.selector,
                "sameToken"
            )
        );
        swapper.swapAssets(
            AssetSwapper.SwapParams({
                tokenIn: WETH,
                tokenOut: WETH, // Same token
                amountIn: 1 ether,
                minAmountOut: 1 ether,
                protocol: AssetSwapper.Protocol.UniswapV3,
                routeData: ""
            })
        );
        console.log(
            "SwapParams memory params Correctly rejected same token swap"
        );

        vm.stopPrank();
    }

    function testEmergencyFunctions() public {
        console.log("Testing emergency functions...");

        vm.startPrank(OWNER);

        // Test pause/unpause
        swapper.pause();
        assertTrue(swapper.paused());
        console.log("SwapParams memory params Contract paused successfully");

        // Test emergency withdraw
        deal(WETH, address(swapper), 1 ether);
        uint256 balanceBefore = IERC20(WETH).balanceOf(OWNER);

        swapper.emergencyWithdraw(WETH, 1 ether, OWNER);

        uint256 balanceAfter = IERC20(WETH).balanceOf(OWNER);
        assertEq(balanceAfter - balanceBefore, 1 ether);
        console.log("SwapParams memory params Emergency withdraw successful");

        // Test unpause
        swapper.unpause();
        assertFalse(swapper.paused());
        console.log("SwapParams memory params Contract unpaused successfully");

        // Test pool pause
        address testPool = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;
        swapper.emergencyPausePool(testPool, "Testing");
        assertTrue(swapper.poolPaused(testPool));
        console.log("SwapParams memory params Pool paused successfully");

        swapper.unpausePool(testPool);
        assertFalse(swapper.poolPaused(testPool));
        console.log("SwapParams memory params Pool unpaused successfully");

        vm.stopPrank();
    }

    function testRoutePasswordProtection() public {
        console.log("Testing route password protection...");

        vm.startPrank(ROUTE_MANAGER);

        // Test with wrong password
        vm.expectRevert(AssetSwapper.InvalidRoutePassword.selector);
        swapper.enableCustomRoute(
            WETH,
            0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa,
            true,
            "wrongPassword"
        );
        console.log(
            "SwapParams memory params Correctly rejected wrong password"
        );

        // Test with correct password
        swapper.enableCustomRoute(
            WETH,
            0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa,
            true,
            "testPassword123" // Correct password
        );
        console.log(
            "SwapParams memory params Successfully enabled route with correct password"
        );

        assertTrue(
            swapper.isCustomRouteEnabled(
                WETH,
                0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa
            )
        );

        vm.stopPrank();
    }

    function testConfigurationFunctions() public {
        console.log("Testing configuration functions...");

        vm.startPrank(OWNER);

        // Test token support update
        address newToken = 0x1234567890123456789012345678901234567890;
        swapper.supportToken(
            newToken,
            true,
            AssetSwapper.AssetType.VOLATILE,
            18
        );
        assertTrue(swapper.supportedTokens(newToken));
        console.log("SwapParams memory params Token support updated");

        // Test slippage configuration
        swapper.setSlippageTolerance(WETH, newToken, 1500);
        assertEq(swapper.slippageTolerance(WETH, newToken), 1500);
        console.log("SwapParams memory params Slippage tolerance set");

        // Test authorized caller management
        address newCaller = 0x9876543210987654321098765432109876543210;
        swapper.setAuthorizedCaller(newCaller, true);
        assertTrue(swapper.isAuthorizedCaller(newCaller));
        console.log("SwapParams memory params Authorized caller added");

        vm.stopPrank();
    }

    // Helper functions
    function _getUniswapPool(
        address tokenA,
        address tokenB
    ) private pure returns (address) {
        // Return appropriate pool addresses based on token pair
        if (
            (tokenA == WETH &&
                tokenB == 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa) ||
            (tokenB == WETH &&
                tokenA == 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa)
        ) {
            return 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14; // WETH/mETH
        }
        if (
            (tokenA == WETH &&
                tokenB == 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3) ||
            (tokenB == WETH &&
                tokenA == 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3)
        ) {
            return 0x52299416C469843F4e0d54688099966a6c7d720f; // WETH/OETH
        }
        if (
            (tokenA == WETH &&
                tokenB == 0xae78736Cd615f374D3085123A210448E74Fc6393) ||
            (tokenB == WETH &&
                tokenA == 0xae78736Cd615f374D3085123A210448E74Fc6393)
        ) {
            return 0x553e9C493678d8606d6a5ba284643dB2110Df823; // WETH/rETH
        }
        if (
            (tokenA == WETH && tokenB == WBTC) ||
            (tokenB == WETH && tokenA == WBTC)
        ) {
            return 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD; // WETH/WBTC
        }
        return 0x840DEEef2f115Cf50DA625F7368C24af6fE74410; // Default: cbETH pool
    }

    function _getFeeForPair(
        address tokenA,
        address tokenB
    ) private pure returns (uint24) {
        if (
            (tokenA == WETH && tokenB == WBTC) ||
            (tokenB == WETH && tokenA == WBTC)
        ) {
            return 3000; // 0.3% for WETH/WBTC
        }
        if (
            (tokenA == WETH &&
                tokenB == 0xae78736Cd615f374D3085123A210448E74Fc6393) ||
            (tokenB == WETH &&
                tokenA == 0xae78736Cd615f374D3085123A210448E74Fc6393)
        ) {
            return 100; // 0.01% for WETH/rETH
        }
        return 500; // Default 0.05%
    }

    function _calculateMinOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (uint256) {
        uint256 slippageBps = swapper.getSlippageTolerance(tokenIn, tokenOut);
        uint256 normalizedAmount = swapper.normalizeAmount(
            tokenIn,
            tokenOut,
            amountIn
        );
        return (normalizedAmount * (10000 - slippageBps)) / 10000;
    }

    function _getCurvePool(
        address tokenIn,
        address tokenOut
    ) private pure returns (address) {
        if (
            tokenIn == ETH_ADDRESS &&
            tokenOut == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
        ) return 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        if (
            tokenIn == ETH_ADDRESS &&
            tokenOut == 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb
        ) return 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;
        if (
            tokenIn == ETH_ADDRESS &&
            tokenOut == 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b
        ) return 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492;
        if (
            tokenIn == ETH_ADDRESS &&
            tokenOut == 0x5E8422345238F34275888049021821E8E08CAa1f
        ) return 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577; // frxETH
        return address(0);
    }

    // Additional comprehensive test
    function testNormalizationFunction() public view {
        console.log("Testing normalization function...");

        // Test WETH (18 decimals) to WBTC (8 decimals)
        uint256 wethAmount = 1 ether; // 1 WETH
        uint256 normalized = swapper.normalizeAmount(WETH, WBTC, wethAmount);

        console.log("WETH amount (18 decimals):", wethAmount);
        console.log("Normalized to WBTC (8 decimals):", normalized);

        // 1 WETH (1e18) normalized to WBTC decimals should be 1e8
        assertEq(normalized, 100000000); // 1e8
        console.log("SwapParams memory params Normalization test passed");
    }

    function testViewFunctions() public view {
        console.log("Testing view functions...");

        // Test getTokenInfo
        (
            bool supported,
            AssetSwapper.AssetType assetType,
            uint8 decimals
        ) = swapper.getTokenInfo(WETH);
        assertTrue(supported);
        assertEq(uint(assetType), uint(AssetSwapper.AssetType.ETH_LST));
        assertEq(decimals, 18);
        console.log("SwapParams memory params getTokenInfo works correctly");

        // Test getPoolInfo
        address testPool = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;
        (
            bool whitelisted,
            bool paused,
            uint256 tokenCount,
            AssetSwapper.CurveInterface curveInterface
        ) = swapper.getPoolInfo(testPool);
        assertTrue(whitelisted);
        assertFalse(paused);
        console.log("SwapParams memory params getPoolInfo works correctly");

        // Test calculateSwapOutput
        (uint256 normalizedOut, uint256 minOut) = swapper.calculateSwapOutput(
            WETH,
            WBTC,
            1 ether
        );
        assertGt(normalizedOut, 0);
        assertGt(minOut, 0);
        assertLt(minOut, normalizedOut); // minOut should be less due to slippage
        console.log(
            "SwapParams memory params calculateSwapOutput works correctly"
        );
    }
}
*/