// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../../src/FinalAutoRouting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FinalAutoRoutingComprehensiveTest is Test {
    using Strings for uint256;

    FinalAutoRouting public finalAutoRouting;

    // Test configuration
    uint256 constant FORK_BLOCK = 19500000;
    uint256 constant TEST_AMOUNT_ETH = 1e18; // 1 ETH
    uint256 constant TEST_AMOUNT_TOKEN = 1000e18; // 1000 tokens

    // Asset addresses (matching your contract's constants)
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address constant ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address constant LSETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    address constant STBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address constant UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Contract addresses
    address constant UNISWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_QUOTER =
        0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant FRXETH_MINTER = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    // Test users
    address constant WHALE = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;

    // Test result tracking
    struct ComprehensiveTestResult {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedOut;
        uint256 actualOut;
        uint256 gasUsed;
        bool swapSuccessful;
        bool quoterUsed;
        bool fallbackUsed;
        string routeType;
        string testType;
        string failureReason;
        uint256 actualSlippageBps;
        uint256 configuredSlippageBps;
    }

    ComprehensiveTestResult[] private testResults;
    uint256 public totalTests;
    uint256 public successfulTests;
    uint256 public quoterSuccesses;
    uint256 public fallbackSuccesses;

    function setUp() public {
        vm.createSelectFork("https://core.gashawk.io/rpc", FORK_BLOCK);

        console.log("=== finalAutoRouting Comprehensive Test Setup ===");
        console.log("Fork Block:", FORK_BLOCK);
        console.log("Test User:", WHALE);

        _deployfinalAutoRouting();
        _fundTestUser();
        _setupProductionConfiguration();

        console.log("Setup completed successfully");
        console.log("---");
    }

    function _setupProductionConfiguration() internal {
        console.log("Initializing contract with production data...");

        // Step 1: Initialize the contract with supported tokens and pools
        _initializeContract();

        // Step 2: Configure specific routes
        _configureRoutes();

        console.log("Production configuration completed");
    }

    function _initializeContract() internal {
        // Prepare initialization data based on your config
        address[] memory tokenAddresses = new address[](17);
        FinalAutoRouting.AssetType[]
            memory tokenTypes = new FinalAutoRouting.AssetType[](17);
        uint8[] memory decimals = new uint8[](17);

        // Add all supported tokens
        tokenAddresses[0] = ETH_ADDRESS;
        tokenTypes[0] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[0] = 18;

        tokenAddresses[1] = WETH;
        tokenTypes[1] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[1] = 18;

        tokenAddresses[2] = WBTC;
        tokenTypes[2] = FinalAutoRouting.AssetType.BTC_WRAPPED;
        decimals[2] = 8;

        tokenAddresses[3] = ANKRETH;
        tokenTypes[3] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[3] = 18;

        tokenAddresses[4] = CBETH;
        tokenTypes[4] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[4] = 18;

        tokenAddresses[5] = ETHX;
        tokenTypes[5] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[5] = 18;

        tokenAddresses[6] = FRXETH;
        tokenTypes[6] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[6] = 18;

        tokenAddresses[7] = LSETH;
        tokenTypes[7] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[7] = 18;

        tokenAddresses[8] = METH;
        tokenTypes[8] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[8] = 18;

        tokenAddresses[9] = OETH;
        tokenTypes[9] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[9] = 18;

        tokenAddresses[10] = OSETH;
        tokenTypes[10] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[10] = 18;

        tokenAddresses[11] = RETH;
        tokenTypes[11] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[11] = 18;

        tokenAddresses[12] = SFRXETH;
        tokenTypes[12] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[12] = 18;

        tokenAddresses[13] = STBTC;
        tokenTypes[13] = FinalAutoRouting.AssetType.BTC_WRAPPED;
        decimals[13] = 18;

        tokenAddresses[14] = STETH;
        tokenTypes[14] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[14] = 18;

        tokenAddresses[15] = SWETH;
        tokenTypes[15] = FinalAutoRouting.AssetType.ETH_LST;
        decimals[15] = 18;

        tokenAddresses[16] = UNIBTC;
        tokenTypes[16] = FinalAutoRouting.AssetType.BTC_WRAPPED;
        decimals[16] = 8;

        // Prepare pool data
        address[] memory poolAddresses = new address[](17);
        uint256[] memory poolTokenCounts = new uint256[](17);
        FinalAutoRouting.CurveInterface[]
            memory curveInterfaces = new FinalAutoRouting.CurveInterface[](17);

        // Uniswap V3 pools
        poolAddresses[0] = 0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E; // WETH/ankrETH
        poolTokenCounts[0] = 2;
        curveInterfaces[0] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[1] = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410; // WETH/cbETH
        poolTokenCounts[1] = 2;
        curveInterfaces[1] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[2] = 0x5d811a9d059dDAB0C18B385ad3b752f734f011cB; // WETH/lsETH
        poolTokenCounts[2] = 2;
        curveInterfaces[2] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[3] = 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14; // WETH/mETH
        poolTokenCounts[3] = 2;
        curveInterfaces[3] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[4] = 0x52299416C469843F4e0d54688099966a6c7d720f; // WETH/OETH
        poolTokenCounts[4] = 2;
        curveInterfaces[4] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[5] = 0x553e9C493678d8606d6a5ba284643dB2110Df823; // WETH/rETH
        poolTokenCounts[5] = 2;
        curveInterfaces[5] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[6] = 0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D; // WETH/stETH
        poolTokenCounts[6] = 2;
        curveInterfaces[6] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[7] = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2; // WETH/swETH
        poolTokenCounts[7] = 2;
        curveInterfaces[7] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[8] = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD; // WETH/WBTC
        poolTokenCounts[8] = 2;
        curveInterfaces[8] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[9] = 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0; // WBTC/stBTC
        poolTokenCounts[9] = 2;
        curveInterfaces[9] = FinalAutoRouting.CurveInterface.None;

        poolAddresses[10] = 0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0; // WBTC/uniBTC
        poolTokenCounts[10] = 2;
        curveInterfaces[10] = FinalAutoRouting.CurveInterface.None;

        // Curve pools
        poolAddresses[11] = 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2; // ETH/ankrETH
        poolTokenCounts[11] = 2;
        curveInterfaces[11] = FinalAutoRouting.CurveInterface.Exchange;

        poolAddresses[12] = 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492; // ETH/ETHx
        poolTokenCounts[12] = 2;
        curveInterfaces[12] = FinalAutoRouting.CurveInterface.Exchange;

        poolAddresses[13] = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577; // ETH/frxETH
        poolTokenCounts[13] = 2;
        curveInterfaces[13] = FinalAutoRouting.CurveInterface.Exchange;

        poolAddresses[14] = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; // ETH/stETH
        poolTokenCounts[14] = 2;
        curveInterfaces[14] = FinalAutoRouting.CurveInterface.Exchange;

        poolAddresses[15] = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d; // rETH/osETH curve
        poolTokenCounts[15] = 2;
        curveInterfaces[15] = FinalAutoRouting.CurveInterface.Exchange;

        poolAddresses[16] = FRXETH_MINTER; // frxETH minter
        poolTokenCounts[16] = 2;
        curveInterfaces[16] = FinalAutoRouting.CurveInterface.None;

        // Prepare slippage configs (using production optimized values)
        FinalAutoRouting.SlippageConfig[]
            memory slippageConfigs = new FinalAutoRouting.SlippageConfig[](10);

        slippageConfigs[0] = FinalAutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: CBETH,
            slippageBps: 350
        });

        slippageConfigs[1] = FinalAutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: RETH,
            slippageBps: 750
        });

        slippageConfigs[2] = FinalAutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: STETH,
            slippageBps: 100
        });

        slippageConfigs[3] = FinalAutoRouting.SlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: STETH,
            slippageBps: 50
        });

        slippageConfigs[4] = FinalAutoRouting.SlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: ANKRETH,
            slippageBps: 50
        });

        slippageConfigs[5] = FinalAutoRouting.SlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: FRXETH,
            slippageBps: 50
        });

        slippageConfigs[6] = FinalAutoRouting.SlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: SFRXETH,
            slippageBps: 50
        });

        slippageConfigs[7] = FinalAutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: METH,
            slippageBps: 100
        });

        slippageConfigs[8] = FinalAutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: OETH,
            slippageBps: 100
        });

        slippageConfigs[9] = FinalAutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: SWETH,
            slippageBps: 250
        });

        // Initialize the contract
        finalAutoRouting.initialize(
            tokenAddresses,
            tokenTypes,
            decimals,
            poolAddresses,
            poolTokenCounts,
            curveInterfaces,
            slippageConfigs
        );

        console.log("Contract initialized successfully");
    }

    function _configureRoutes() internal {
        // Configure routes based on your JSON config
        string memory password = "testPassword123";

        // WETH -> LST tokens (UniswapV3)
        finalAutoRouting.configureRoute(
            WETH,
            CBETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            500,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            METH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
            500,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            OETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x52299416C469843F4e0d54688099966a6c7d720f,
            500,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            RETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x553e9C493678d8606d6a5ba284643dB2110Df823,
            100,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            STETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D,
            10000,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            SWETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x30eA22C879628514f1494d4BBFEF79D21A6B49A2,
            500,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            ANKRETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E,
            3000,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            WETH,
            LSETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x5d811a9d059dDAB0C18B385ad3b752f734f011cB,
            500,
            0,
            0,
            password
        );

        // ETH -> LST tokens (Curve)
        finalAutoRouting.configureRoute(
            ETH_ADDRESS,
            ANKRETH,
            FinalAutoRouting.Protocol.Curve,
            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
            0,
            0,
            1,
            password
        );
        finalAutoRouting.configureRoute(
            ETH_ADDRESS,
            ETHX,
            FinalAutoRouting.Protocol.Curve,
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
            0,
            0,
            1,
            password
        );
        finalAutoRouting.configureRoute(
            ETH_ADDRESS,
            FRXETH,
            FinalAutoRouting.Protocol.Curve,
            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
            0,
            0,
            1,
            password
        );
        finalAutoRouting.configureRoute(
            ETH_ADDRESS,
            STETH,
            FinalAutoRouting.Protocol.Curve,
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            0,
            0,
            1,
            password
        );

        // ✅ CONFIGURE REVERSE ROUTES FOR AUTO ROUTING
        finalAutoRouting.configureRoute(
            CBETH,
            WETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            500,
            0,
            0,
            password
        );
        finalAutoRouting.configureRoute(
            STETH,
            WETH,
            FinalAutoRouting.Protocol.UniswapV3,
            0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D,
            10000,
            0,
            0,
            password
        );

        // ✅ CONFIGURE DIRECT MINT ROUTE
        finalAutoRouting.configureRoute(
            ETH_ADDRESS,
            SFRXETH,
            FinalAutoRouting.Protocol.DirectMint,
            FRXETH_MINTER,
            0,
            0,
            0,
            password
        );

        console.log("Routes configured successfully");
    }

    function _fundTestUser() internal {
        vm.deal(WHALE, 1000e18); // 1000 ETH

        // Wrap ETH to WETH for testing
        vm.startPrank(WHALE);
        IWETH(WETH).deposit{value: 500e18}(); // Wrap 500 ETH to WETH

        // Approve finalAutoRouting to use WETH and ETH
        IERC20(WETH).approve(address(finalAutoRouting), type(uint256).max);

        console.log("WETH Balance:", IWETH(WETH).balanceOf(WHALE));
        console.log("ETH Balance:", WHALE.balance);
        vm.stopPrank();

        console.log("Test user funded with ETH and WETH");
    }

    function testComprehensivefinalAutoRoutingFunctionality() public {
        console.log("=== COMPREHENSIVE finalAutoRouting TEST SUITE ===");
        console.log("Testing all swap types with quoter-first approach");
        console.log("---");

        // Test Category 1: Direct Swaps (Uniswap V3) - WETH based
        _testDirectUniswapSwaps();

        // Test Category 2: Direct Swaps (Curve) - ETH based
        _testDirectCurveSwaps();

        // Test Category 3: Direct Mint Operations
        _testDirectMintSwaps();

        // Test Category 4: Auto Routing Tests
        _testAutoRoutingSwaps();

        // Test Category 5: Error Handling
        _testErrorScenarios();

        _generateFinalReport();
    }

    function _testDirectUniswapSwaps() internal {
        console.log("=== Testing Direct Uniswap V3 Swaps ===");

        // ✅ FIXED: Use autoSwapAssets() to let contract build route data
        _testAutoSwap(
            WETH,
            CBETH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->cbETH"
        );
        _testAutoSwap(
            WETH,
            METH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->mETH"
        );
        _testAutoSwap(
            WETH,
            OETH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->OETH"
        );
        _testAutoSwap(
            WETH,
            RETH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->rETH"
        );
        _testAutoSwap(
            WETH,
            STETH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->stETH"
        );
        _testAutoSwap(
            WETH,
            SWETH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->swETH"
        );
        _testAutoSwap(
            WETH,
            LSETH,
            TEST_AMOUNT_ETH,
            "Direct Uniswap",
            "WETH->lsETH"
        );

        console.log("Direct Uniswap swaps completed");
        console.log("---");
    }

    function _testDirectCurveSwaps() internal {
        console.log("=== Testing Direct Curve Swaps ===");

        // ✅ FIXED: Use autoSwapAssets() to let contract build route data
        _testAutoSwap(
            ETH_ADDRESS,
            ANKRETH,
            TEST_AMOUNT_ETH,
            "Direct Curve",
            "ETH->ankrETH"
        );
        _testAutoSwap(
            ETH_ADDRESS,
            ETHX,
            TEST_AMOUNT_ETH,
            "Direct Curve",
            "ETH->ETHx"
        );
        _testAutoSwap(
            ETH_ADDRESS,
            FRXETH,
            TEST_AMOUNT_ETH,
            "Direct Curve",
            "ETH->frxETH"
        );
        _testAutoSwap(
            ETH_ADDRESS,
            STETH,
            TEST_AMOUNT_ETH,
            "Direct Curve",
            "ETH->stETH"
        );

        console.log("Direct Curve swaps completed");
        console.log("---");
    }

    function _testDirectMintSwaps() internal {
        console.log("=== Testing Direct Mint Operations ===");

        // ✅ FIXED: Use autoSwapAssets() to let contract build route data
        _testAutoSwap(
            ETH_ADDRESS,
            SFRXETH,
            TEST_AMOUNT_ETH,
            "Direct Mint",
            "ETH->sfrxETH"
        );

        console.log("Direct Mint swaps completed");
        console.log("---");
    }

    function _testAutoRoutingSwaps() internal {
        console.log("=== Testing Auto Routing ===");

        // First acquire some tokens to test auto routing between them
        console.log("Acquiring tokens for auto routing tests...");

        // Get some cbETH first
        _acquireTokenForAutoRouting(CBETH, 2e18);

        // Get some stETH
        _acquireTokenForAutoRouting(STETH, 2e18);

        // Test auto routing between acquired tokens
        _testAutoSwap(CBETH, STETH, 1e18, "Auto Routing", "cbETH->stETH");
        _testAutoSwap(STETH, CBETH, 1e18, "Auto Routing", "stETH->cbETH");

        console.log("Auto routing swaps completed");
        console.log("---");
    }

    function _testErrorScenarios() internal {
        console.log("=== Testing Error Scenarios ===");

        // Test cross-category swap (should fail)
        _testErrorCase(
            WETH,
            WBTC,
            TEST_AMOUNT_ETH,
            "Cross-category swap not supported"
        );

        // Test zero amount (should fail)
        _testErrorCase(WETH, CBETH, 0, "Zero amount");

        // Test same token swap (should fail)
        _testErrorCase(WETH, WETH, TEST_AMOUNT_ETH, "Same token");

        console.log("Error scenario tests completed");
        console.log("---");
    }

    // ✅ FIXED: Unified test function using autoSwapAssets()
    function _testAutoSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        string memory routeType,
        string memory testType
    ) internal {
        totalTests++;

        console.log("Testing auto swap:");
        console.log("  From: %s", _getTokenSymbol(tokenIn));
        console.log("  To: %s", _getTokenSymbol(tokenOut));
        console.log("  Amount: %s", amountIn.toString());
        console.log("  Route Type: %s", routeType);

        uint256 gasStart = gasleft();
        bool success = false;
        uint256 actualOut = 0;
        string memory failureReason = "";

        vm.startPrank(WHALE);

        // Check balance for non-ETH tokens
        if (tokenIn != ETH_ADDRESS) {
            uint256 balance = IERC20(tokenIn).balanceOf(WHALE);
            if (balance < amountIn) {
                console.log(
                    "  Insufficient balance: %s, needed: %s",
                    balance.toString(),
                    amountIn.toString()
                );
                vm.stopPrank();
                _recordTestResult(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    0,
                    0,
                    false,
                    routeType,
                    testType,
                    "Insufficient balance"
                );
                return;
            }
        }

        try
            finalAutoRouting.autoSwapAssets{
                value: tokenIn == ETH_ADDRESS ? amountIn : 0
            }(tokenIn, tokenOut, amountIn, 0)
        returns (uint256 result) {
            actualOut = result;
            success = true;
            successfulTests++;
        } catch Error(string memory reason) {
            failureReason = reason;
        } catch (bytes memory) {
            failureReason = "Low-level revert";
        }

        vm.stopPrank();

        uint256 gasUsed = gasStart - gasleft();
        _recordTestResult(
            tokenIn,
            tokenOut,
            amountIn,
            actualOut,
            gasUsed,
            success,
            routeType,
            testType,
            failureReason
        );
    }

    function _acquireTokenForAutoRouting(
        address token,
        uint256 amount
    ) internal {
        console.log(
            "  Acquiring %s %s...",
            (amount / 1e18).toString(),
            _getTokenSymbol(token)
        );

        vm.startPrank(WHALE);

        try
            finalAutoRouting.autoSwapAssets(
                WETH,
                token,
                (amount * 11) / 10,
                0 // 10% buffer for slippage
            )
        returns (uint256 amountOut) {
            console.log(
                "  Successfully acquired %s %s",
                (amountOut / 1e18).toString(),
                _getTokenSymbol(token)
            );
            // Approve for auto routing tests
            IERC20(token).approve(address(finalAutoRouting), type(uint256).max);
        } catch Error(string memory reason) {
            console.log(
                "  Failed to acquire %s: %s",
                _getTokenSymbol(token),
                reason
            );
        } catch {
            console.log(
                "  Failed to acquire %s: Low-level error",
                _getTokenSymbol(token)
            );
        }

        vm.stopPrank();
    }

    function _testErrorCase(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        string memory expectedError
    ) internal {
        totalTests++;

        console.log("Testing expected error:");
        console.log("  From: %s", _getTokenSymbol(tokenIn));
        console.log("  To: %s", _getTokenSymbol(tokenOut));
        console.log("  Amount: %s", amountIn.toString());
        console.log("  Expected: %s", expectedError);

        bool success = false;
        string memory failureReason = "";

        vm.startPrank(WHALE);

        try
            finalAutoRouting.autoSwapAssets{
                value: tokenIn == ETH_ADDRESS ? amountIn : 0
            }(tokenIn, tokenOut, amountIn, 0)
        returns (uint256) {
            success = true;
        } catch Error(string memory reason) {
            failureReason = reason;
        } catch (bytes memory) {
            failureReason = "Low-level revert";
        }

        vm.stopPrank();

        // For error cases, success means the test passed (error occurred as expected)
        if (!success) {
            successfulTests++;
        }

        console.log(
            "  Result: %s",
            success ? "UNEXPECTED SUCCESS" : "EXPECTED FAILURE"
        );
        console.log("  Reason: %s", failureReason);
    }

    function _recordTestResult(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 actualOut,
        uint256 gasUsed,
        bool success,
        string memory routeType,
        string memory testType,
        string memory failureReason
    ) internal {
        ComprehensiveTestResult memory result = ComprehensiveTestResult({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            expectedOut: 0,
            actualOut: actualOut,
            gasUsed: gasUsed,
            swapSuccessful: success,
            quoterUsed: false, // Could be enhanced with event parsing
            fallbackUsed: false,
            routeType: routeType,
            testType: testType,
            failureReason: failureReason,
            actualSlippageBps: 0,
            configuredSlippageBps: 0
        });

        testResults.push(result);

        console.log("Test Result:");
        console.log(
            "  Route: %s -> %s",
            _getTokenSymbol(tokenIn),
            _getTokenSymbol(tokenOut)
        );
        console.log("  Amount In: %s", amountIn.toString());
        console.log("  Actual Out: %s", actualOut.toString());
        console.log("  Success: %s", success ? "YES" : "NO");
        console.log("  Gas Used: %s", gasUsed.toString());
        if (bytes(failureReason).length > 0) {
            console.log("  Failure Reason: %s", failureReason);
        }
        console.log("---");
    }

    function _generateFinalReport() internal view {
        console.log("=== COMPREHENSIVE TEST SUITE FINAL REPORT ===");
        console.log("Total Tests: %s", totalTests.toString());
        console.log("Successful Tests: %s", successfulTests.toString());
        console.log(
            "Success Rate: %s%%",
            totalTests > 0
                ? ((successfulTests * 100) / totalTests).toString()
                : "0"
        );

        console.log("");
        console.log("=== ROUTE TYPE BREAKDOWN ===");
        _printRouteTypeBreakdown();

        console.log("");
        console.log("=== TEST SUITE COMPLETED ===");
    }

    function testDirectMinterCall() public {
        vm.deal(address(this), 1 ether);

        IFrxETHMinter minter = IFrxETHMinter(FRXETH_MINTER);
        uint256 sharesBefore = IERC20(SFRXETH).balanceOf(address(this));

        uint256 shares = minter.submitAndDeposit{value: 1 ether}(address(this));

        uint256 sharesAfter = IERC20(SFRXETH).balanceOf(address(this));

        console.log("Shares returned:", shares);
        console.log("Balance increase:", sharesAfter - sharesBefore);

        require(shares > 0, "No shares returned");
        require(sharesAfter > sharesBefore, "No balance increase");
    }

    function _printRouteTypeBreakdown() internal view {
        string[5] memory routeTypes = [
            "Direct Uniswap",
            "Direct Curve",
            "Direct Mint",
            "Auto Routing",
            "Error Cases"
        ];

        for (uint256 i = 0; i < routeTypes.length; i++) {
            uint256 total = 0;
            uint256 successful = 0;

            for (uint256 j = 0; j < testResults.length; j++) {
                if (
                    keccak256(bytes(testResults[j].routeType)) ==
                    keccak256(bytes(routeTypes[i]))
                ) {
                    total++;
                    if (testResults[j].swapSuccessful) {
                        successful++;
                    }
                }
            }

            if (total > 0) {
                console.log(
                    "  %s: %s/%s (%s%%)",
                    routeTypes[i],
                    successful.toString()
                );
                console.log(
                    total.toString(),
                    ((successful * 100) / total).toString()
                );
            }
        }
    }

    // Helper functions
    function _deployfinalAutoRouting() internal {
        finalAutoRouting = new FinalAutoRouting(
            WETH,
            UNISWAP_ROUTER,
            UNISWAP_QUOTER,
            FRXETH_MINTER,
            address(this), // Route manager
            keccak256(abi.encode("testPassword123", address(this))),
            WHALE, // Authorized caller
            true // Apply production config
        );

        console.log("finalAutoRouting deployed at:", address(finalAutoRouting));
    }

    function _getTokenSymbol(
        address token
    ) internal pure returns (string memory) {
        if (token == ETH_ADDRESS) return "ETH";
        if (token == WETH) return "WETH";
        if (token == WBTC) return "WBTC";
        if (token == RETH) return "rETH";
        if (token == CBETH) return "cbETH";
        if (token == STETH) return "stETH";
        if (token == METH) return "mETH";
        if (token == OETH) return "OETH";
        if (token == ANKRETH) return "ankrETH";
        if (token == FRXETH) return "frxETH";
        if (token == SWETH) return "swETH";
        if (token == LSETH) return "lsETH";
        if (token == STBTC) return "stBTC";
        if (token == UNIBTC) return "uniBTC";
        if (token == SFRXETH) return "sfrxETH";
        if (token == OSETH) return "osETH";
        if (token == ETHX) return "ETHx";
        return "UNKNOWN";
    }
}
