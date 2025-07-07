// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IUniswapV3Router.sol";
import "../src/interfaces/ICurvePool.sol";
import "../src/interfaces/IFrxETHMinter.sol";
import "../src/interfaces/IWETH.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ProgressiveSlippageAnalysisTest is Test {
    // ============================================================================
    // ASSETS & CONSTANTS
    // ============================================================================

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant LSETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    address constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant STBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address constant UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;

    IUniswapV3Router constant uniswapRouter =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IFrxETHMinter constant frxETHMinter =
        IFrxETHMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138);

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct SlippageTestResult {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedOut;
        uint256 actualOut;
        uint256 actualSlippageBps;
        uint256 configuredSlippageBps;
        bool swapSuccessful;
        string routeType;
        string assetCategory;
        uint256 gasUsed;
        string failureReason;
        uint256 successfulSlippageBps; // New field to track at what slippage it succeeded
    }

    struct RouteConfig {
        address pool;
        uint24 fee;
        int128 tokenIndexIn;
        int128 tokenIndexOut;
        address specialContract;
        address[] pathTokens;
        uint24[] pathFees;
        string routeType;
    }

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    mapping(address => mapping(address => RouteConfig)) public routes;
    SlippageTestResult[] private testResults;

    address testAccount = address(0x1337);
    uint256 constant INITIAL_ETH = 10000 ether;

    // Progressive slippage levels to test for failing swaps
    uint256[] progressiveSlippages = [
        1500, // 15%
        2000, // 20%
        3000, // 30%
        5000, // 50%
        7500, // 75%
        10000 // 100%
    ];

    // ============================================================================
    // SETUP
    // ============================================================================

    function setUp() public {
        vm.createFork("https://ethereum-rpc.publicnode.com");
        vm.deal(testAccount, INITIAL_ETH);
        vm.startPrank(testAccount);
        IWETH(WETH).deposit{value: 8000 ether}();

        _setupAllRouteConfigurations();
        vm.stopPrank();
    }

    function _setupAllRouteConfigurations() internal {
        // === WETH ROUTES (Direct Uniswap V3) ===
        routes[WETH][WBTC] = RouteConfig(
            0xCBCdF9626bC03E24f779434178A73a0B4bad62eD,
            3000,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][ANKRETH] = RouteConfig(
            0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E,
            3000,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][CBETH] = RouteConfig(
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            500,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][LSETH] = RouteConfig(
            0x5d811a9d059dDAB0C18B385ad3b752f734f011cB,
            500,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][METH] = RouteConfig(
            0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
            500,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][OETH] = RouteConfig(
            0x52299416C469843F4e0d54688099966a6c7d720f,
            500,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][RETH] = RouteConfig(
            0x553e9C493678d8606d6a5ba284643dB2110Df823,
            100,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][STETH] = RouteConfig(
            0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D,
            10000,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );
        routes[WETH][SWETH] = RouteConfig(
            0x30eA22C879628514f1494d4BBFEF79D21A6B49A2,
            500,
            0,
            0,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct UniswapV3"
        );

        // === ETH ROUTES (Direct Curve) ===
        routes[ETH_ADDRESS][ANKRETH] = RouteConfig(
            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
            0,
            0,
            1,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct Curve"
        );
        routes[ETH_ADDRESS][ETHX] = RouteConfig(
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
            0,
            0,
            1,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct Curve"
        );
        routes[ETH_ADDRESS][FRXETH] = RouteConfig(
            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
            0,
            0,
            1,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct Curve"
        );
        routes[ETH_ADDRESS][STETH] = RouteConfig(
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            0,
            0,
            1,
            address(0),
            new address[](0),
            new uint24[](0),
            "Direct Curve"
        );

        // === DIRECT MINT ===
        routes[ETH_ADDRESS][SFRXETH] = RouteConfig(
            address(0),
            0,
            0,
            0,
            address(frxETHMinter),
            new address[](0),
            new uint24[](0),
            "Direct Mint"
        );

        // === MULTI-PATH ROUTES ===
        address[] memory stBTCPath = new address[](3);
        stBTCPath[0] = WETH;
        stBTCPath[1] = WBTC;
        stBTCPath[2] = STBTC;
        uint24[] memory stBTCFees = new uint24[](2);
        stBTCFees[0] = 3000;
        stBTCFees[1] = 500;
        routes[WETH][STBTC] = RouteConfig(
            address(0),
            0,
            0,
            0,
            address(0),
            stBTCPath,
            stBTCFees,
            "Multi-Path"
        );

        address[] memory uniBTCPath = new address[](3);
        uniBTCPath[0] = WETH;
        uniBTCPath[1] = WBTC;
        uniBTCPath[2] = UNIBTC;
        uint24[] memory uniBTCFees = new uint24[](2);
        uniBTCFees[0] = 3000;
        uniBTCFees[1] = 3000;
        routes[WETH][UNIBTC] = RouteConfig(
            address(0),
            0,
            0,
            0,
            address(0),
            uniBTCPath,
            uniBTCFees,
            "Multi-Path"
        );
    }

    // ============================================================================
    // MAIN TEST FUNCTION
    // ============================================================================

    function testProgressiveSlippageAnalysis() public {
        console.log("=== PROGRESSIVE SLIPPAGE ANALYSIS ===");
        console.log("Testing production routes with optimized slippage...\n");

        _testProductionRecommendedSlippages();
        _testFailingRoutesWithProgressiveSlippage();
        _generateDetailedProductionReport();
    }

    function _testProductionRecommendedSlippages() internal {
        console.log("--- Testing with PRODUCTION RECOMMENDED Slippages ---");

        // Test successful routes with recommended production slippages
        _testSingleRouteWithSlippage(WETH, CBETH, 0.1 ether, 600); // Recommended: 600 bps
        _testSingleRouteWithSlippage(WETH, LSETH, 0.1 ether, 500); // Recommended: 500 bps
        _testSingleRouteWithSlippage(WETH, METH, 0.1 ether, 300); // Recommended: 300 bps
        _testSingleRouteWithSlippage(WETH, OETH, 0.1 ether, 200); // Recommended: 200 bps
        _testSingleRouteWithSlippage(WETH, RETH, 0.1 ether, 1000); // Recommended: 1000 bps
        _testSingleRouteWithSlippage(WETH, STETH, 0.1 ether, 200); // Recommended: 200 bps
        _testSingleRouteWithSlippage(WETH, SWETH, 0.1 ether, 500); // Recommended: 500 bps

        _testSingleCurveRouteWithSlippage(ETH_ADDRESS, ANKRETH, 0.1 ether, 100); // Recommended: 100 bps
        _testSingleCurveRouteWithSlippage(ETH_ADDRESS, ETHX, 0.1 ether, 100); // Recommended: 100 bps
        _testSingleCurveRouteWithSlippage(ETH_ADDRESS, FRXETH, 0.1 ether, 100); // Recommended: 100 bps
        _testSingleCurveRouteWithSlippage(ETH_ADDRESS, STETH, 0.1 ether, 100); // Recommended: 100 bps
        _testDirectMintWithSlippage(ETH_ADDRESS, SFRXETH, 0.1 ether, 100); // Recommended: 100 bps
    }

    function _testFailingRoutesWithProgressiveSlippage() internal {
        console.log("--- Testing FAILING Routes with Progressive Slippage ---");

        // Test the routes that failed in the original test
        address[] memory failingTokensIn = new address[](4);
        address[] memory failingTokensOut = new address[](4);

        failingTokensIn[0] = WETH;
        failingTokensOut[0] = WBTC; // Cross-category
        failingTokensIn[1] = WETH;
        failingTokensOut[1] = ANKRETH; // Same category but failed
        failingTokensIn[2] = WETH;
        failingTokensOut[2] = STBTC; // Multi-path cross-category
        failingTokensIn[3] = WETH;
        failingTokensOut[3] = UNIBTC; // Multi-path cross-category

        for (uint i = 0; i < failingTokensIn.length; i++) {
            _testRouteWithProgressiveSlippage(
                failingTokensIn[i],
                failingTokensOut[i],
                0.1 ether
            );
        }
    }

    function _testRouteWithProgressiveSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal {
        console.log(
            "Testing %s -> %s with progressive slippage:",
            _getTokenSymbol(tokenIn),
            _getTokenSymbol(tokenOut)
        );

        for (uint i = 0; i < progressiveSlippages.length; i++) {
            uint256 slippageBps = progressiveSlippages[i];
            console.log(
                "  Trying slippage: %s bps (%s%%)",
                Strings.toString(slippageBps),
                Strings.toString(slippageBps / 100)
            );

            bool success = false;

            if (
                keccak256(bytes(routes[tokenIn][tokenOut].routeType)) ==
                keccak256(bytes("Multi-Path"))
            ) {
                success = _testMultiPathRouteWithSlippage(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    slippageBps
                );
            } else {
                success = _testSingleRouteWithSlippage(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    slippageBps
                );
            }

            if (success) {
                console.log(
                    "   SUCCESS at %s bps!",
                    Strings.toString(slippageBps)
                );
                break;
            } else {
                console.log(
                    "   Failed at %s bps",
                    Strings.toString(slippageBps)
                );
            }
        }
        console.log("");
    }

    function _testSingleRouteWithSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (bool) {
        vm.startPrank(testAccount);

        if (tokenIn == WETH && IERC20(WETH).balanceOf(testAccount) < amountIn) {
            vm.stopPrank();
            return false;
        }

        RouteConfig memory route = routes[tokenIn][tokenOut];
        if (route.pool == address(0)) {
            vm.stopPrank();
            return false;
        }

        uint256 expectedOut = _getExpectedOutputUniswap(
            tokenIn,
            tokenOut,
            amountIn
        );
        uint256 minAmountOut = (expectedOut * (10000 - slippageBps)) / 10000;

        IERC20(tokenIn).approve(address(uniswapRouter), amountIn);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testAccount);
        uint256 gasStart = gasleft();

        try
            uniswapRouter.exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: route.fee,
                    recipient: testAccount,
                    deadline: block.timestamp + 300,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            )
        returns (uint256) {
            uint256 gasUsed = gasStart - gasleft();
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(testAccount);
            uint256 actualOut = balanceAfter - balanceBefore;

            uint256 actualSlippageBps = expectedOut > actualOut
                ? ((expectedOut - actualOut) * 10000) / expectedOut
                : 0;

            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: actualOut,
                    actualSlippageBps: actualSlippageBps,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: true,
                    routeType: route.routeType,
                    assetCategory: _getCategoryString(tokenIn, tokenOut),
                    gasUsed: gasUsed,
                    failureReason: "",
                    successfulSlippageBps: slippageBps
                })
            );

            vm.stopPrank();
            return true;
        } catch Error(string memory reason) {
            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: 0,
                    actualSlippageBps: 10000,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: false,
                    routeType: route.routeType,
                    assetCategory: _getCategoryString(tokenIn, tokenOut),
                    gasUsed: 0,
                    failureReason: reason,
                    successfulSlippageBps: 0
                })
            );

            vm.stopPrank();
            return false;
        }
    }

    function _testSingleCurveRouteWithSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (bool) {
        vm.startPrank(testAccount);

        if (tokenIn == ETH_ADDRESS && testAccount.balance < amountIn) {
            vm.stopPrank();
            return false;
        }

        RouteConfig memory route = routes[tokenIn][tokenOut];
        if (route.pool == address(0)) {
            vm.stopPrank();
            return false;
        }

        uint256 expectedOut = _getCurveQuote(
            route.pool,
            route.tokenIndexIn,
            route.tokenIndexOut,
            amountIn
        );
        if (expectedOut == 0) {
            expectedOut = (amountIn * 98) / 100;
        }

        uint256 minAmountOut = (expectedOut * (10000 - slippageBps)) / 10000;

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testAccount);
        uint256 gasStart = gasleft();

        try
            ICurvePool(route.pool).exchange{
                value: tokenIn == ETH_ADDRESS ? amountIn : 0
            }(route.tokenIndexIn, route.tokenIndexOut, amountIn, minAmountOut)
        {
            uint256 gasUsed = gasStart - gasleft();
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(testAccount);
            uint256 actualOut = balanceAfter - balanceBefore;

            uint256 actualSlippageBps = expectedOut > actualOut
                ? ((expectedOut - actualOut) * 10000) / expectedOut
                : 0;

            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: actualOut,
                    actualSlippageBps: actualSlippageBps,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: true,
                    routeType: route.routeType,
                    assetCategory: "ETH_LST",
                    gasUsed: gasUsed,
                    failureReason: "",
                    successfulSlippageBps: slippageBps
                })
            );

            vm.stopPrank();
            return true;
        } catch Error(string memory reason) {
            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: 0,
                    actualSlippageBps: 10000,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: false,
                    routeType: route.routeType,
                    assetCategory: "ETH_LST",
                    gasUsed: 0,
                    failureReason: reason,
                    successfulSlippageBps: 0
                })
            );

            vm.stopPrank();
            return false;
        }
    }

    function _testDirectMintWithSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (bool) {
        vm.startPrank(testAccount);

        if (testAccount.balance < amountIn) {
            vm.stopPrank();
            return false;
        }

        uint256 expectedOut = (amountIn * 89) / 100;
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testAccount);
        uint256 gasStart = gasleft();

        try
            frxETHMinter.submitAndDeposit{value: amountIn}(testAccount)
        returns (uint256) {
            uint256 gasUsed = gasStart - gasleft();
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(testAccount);
            uint256 actualOut = balanceAfter - balanceBefore;

            uint256 actualSlippageBps = expectedOut > actualOut
                ? ((expectedOut - actualOut) * 10000) / expectedOut
                : 0;

            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: actualOut,
                    actualSlippageBps: actualSlippageBps,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: true,
                    routeType: "Direct Mint",
                    assetCategory: "ETH_LST",
                    gasUsed: gasUsed,
                    failureReason: "",
                    successfulSlippageBps: slippageBps
                })
            );

            vm.stopPrank();
            return true;
        } catch Error(string memory reason) {
            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: 0,
                    actualSlippageBps: 10000,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: false,
                    routeType: "Direct Mint",
                    assetCategory: "ETH_LST",
                    gasUsed: 0,
                    failureReason: reason,
                    successfulSlippageBps: 0
                })
            );

            vm.stopPrank();
            return false;
        }
    }

    function _testMultiPathRouteWithSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippageBps
    ) internal returns (bool) {
        vm.startPrank(testAccount);

        if (IERC20(tokenIn).balanceOf(testAccount) < amountIn) {
            vm.stopPrank();
            return false;
        }

        RouteConfig memory route = routes[tokenIn][tokenOut];
        if (route.pathTokens.length == 0) {
            vm.stopPrank();
            return false;
        }

        uint256 expectedOut = (amountIn * 80) / 100;
        IERC20(tokenIn).approve(address(uniswapRouter), amountIn);

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(testAccount);
        uint256 gasStart = gasleft();

        bytes memory path = abi.encodePacked(route.pathTokens[0]);
        for (uint i = 0; i < route.pathFees.length; i++) {
            path = abi.encodePacked(
                path,
                route.pathFees[i],
                route.pathTokens[i + 1]
            );
        }

        try
            uniswapRouter.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: path,
                    recipient: testAccount,
                    deadline: block.timestamp + 300,
                    amountIn: amountIn,
                    amountOutMinimum: (expectedOut * (10000 - slippageBps)) /
                        10000
                })
            )
        returns (uint256) {
            uint256 gasUsed = gasStart - gasleft();
            uint256 balanceAfter = IERC20(tokenOut).balanceOf(testAccount);
            uint256 actualOut = balanceAfter - balanceBefore;

            uint256 actualSlippageBps = expectedOut > actualOut
                ? ((expectedOut - actualOut) * 10000) / expectedOut
                : 0;

            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: actualOut,
                    actualSlippageBps: actualSlippageBps,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: true,
                    routeType: route.routeType,
                    assetCategory: "CROSS_CATEGORY",
                    gasUsed: gasUsed,
                    failureReason: "",
                    successfulSlippageBps: slippageBps
                })
            );

            vm.stopPrank();
            return true;
        } catch Error(string memory reason) {
            _recordTestResult(
                SlippageTestResult({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    expectedOut: expectedOut,
                    actualOut: 0,
                    actualSlippageBps: 10000,
                    configuredSlippageBps: slippageBps,
                    swapSuccessful: false,
                    routeType: route.routeType,
                    assetCategory: "CROSS_CATEGORY",
                    gasUsed: 0,
                    failureReason: reason,
                    successfulSlippageBps: 0
                })
            );

            vm.stopPrank();
            return false;
        }
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    function _getExpectedOutputUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal pure returns (uint256) {
        return (amountIn * 93) / 100; // Conservative 7% estimate
    }

    function _getCategoryString(
        address tokenIn,
        address tokenOut
    ) internal pure returns (string memory) {
        if (
            (tokenIn == WETH || tokenIn == ETH_ADDRESS) &&
            (tokenOut == ANKRETH ||
                tokenOut == CBETH ||
                tokenOut == ETHX ||
                tokenOut == FRXETH ||
                tokenOut == LSETH ||
                tokenOut == METH ||
                tokenOut == OETH ||
                tokenOut == OSETH ||
                tokenOut == RETH ||
                tokenOut == SFRXETH ||
                tokenOut == STETH ||
                tokenOut == SWETH)
        ) {
            return "ETH_LST";
        } else if (
            (tokenIn == WETH) &&
            (tokenOut == WBTC || tokenOut == STBTC || tokenOut == UNIBTC)
        ) {
            return "CROSS_CATEGORY";
        }
        return "MIXED";
    }

    function _getCurveQuote(
        address pool,
        int128 tokenIndexIn,
        int128 tokenIndexOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        try
            ICurvePool(pool).get_dy(tokenIndexIn, tokenIndexOut, amountIn)
        returns (uint256 dy) {
            return dy;
        } catch {
            return 0;
        }
    }

    function _recordTestResult(SlippageTestResult memory result) internal {
        testResults.push(result);

        console.log("Test Result:");
        console.log(
            "  Route: %s -> %s",
            _getTokenSymbol(result.tokenIn),
            _getTokenSymbol(result.tokenOut)
        );
        console.log(
            "  Amount In: %s ETH",
            Strings.toString(result.amountIn / 1e18)
        );
        console.log(
            "  Expected Out (wei): %s",
            Strings.toString(result.expectedOut)
        );
        console.log(
            "  Actual Out (wei): %s",
            Strings.toString(result.actualOut)
        );
        console.log(
            "  Actual Slippage: %s bps",
            Strings.toString(result.actualSlippageBps)
        );
        console.log(
            "  Configured Slippage: %s bps",
            Strings.toString(result.configuredSlippageBps)
        );
        console.log("  Route Type: %s", result.routeType);
        console.log("  Success: %s", result.swapSuccessful ? "YES" : "NO");
        console.log("  Gas Used: %s", Strings.toString(result.gasUsed));
        if (result.successfulSlippageBps > 0) {
            console.log(
                "  Successful at: %s bps",
                Strings.toString(result.successfulSlippageBps)
            );
        }
        if (bytes(result.failureReason).length > 0) {
            console.log("  Failure Reason: %s", result.failureReason);
        }
        console.log("---");
    }

    function _getTokenSymbol(
        address token
    ) internal pure returns (string memory) {
        if (token == ETH_ADDRESS) return "ETH";
        if (token == WETH) return "WETH";
        if (token == WBTC) return "WBTC";
        if (token == ANKRETH) return "ankrETH";
        if (token == CBETH) return "cbETH";
        if (token == ETHX) return "ETHx";
        if (token == FRXETH) return "frxETH";
        if (token == LSETH) return "lsETH";
        if (token == METH) return "mETH";
        if (token == OETH) return "OETH";
        if (token == OSETH) return "osETH";
        if (token == RETH) return "rETH";
        if (token == SFRXETH) return "sfrxETH";
        if (token == STBTC) return "stBTC";
        if (token == STETH) return "stETH";
        if (token == SWETH) return "swETH";
        if (token == UNIBTC) return "uniBTC";
        return "UNKNOWN";
    }

    function _generateDetailedProductionReport() internal view {
        console.log("\n=== DETAILED PRODUCTION CONFIGURATION REPORT ===\n");

        uint256 totalTests = testResults.length;
        uint256 successfulTests = 0;

        console.log("=== PRODUCTION SLIPPAGE CONFIGURATION ===");
        console.log("");

        for (uint i = 0; i < totalTests; i++) {
            SlippageTestResult memory result = testResults[i];

            if (result.swapSuccessful) {
                successfulTests++;

                console.log(
                    " %s -> %s:",
                    _getTokenSymbol(result.tokenIn),
                    _getTokenSymbol(result.tokenOut)
                );
                console.log(
                    "   Actual Slippage: %s bps",
                    Strings.toString(result.actualSlippageBps)
                );
                console.log(
                    "   Tested Slippage: %s bps",
                    Strings.toString(result.configuredSlippageBps)
                );
                console.log("   Route Type: %s", result.routeType);
                console.log("   Category: %s", result.assetCategory);
                console.log(
                    "   RECOMMENDED: %s bps",
                    Strings.toString(result.configuredSlippageBps)
                );
                console.log("");
            } else {
                console.log(
                    " %s -> %s:",
                    _getTokenSymbol(result.tokenIn),
                    _getTokenSymbol(result.tokenOut)
                );
                console.log(
                    "   Failed at: %s bps",
                    Strings.toString(result.configuredSlippageBps)
                );
                console.log("   Reason: %s", result.failureReason);
                console.log("   Route Type: %s", result.routeType);
                console.log("");
            }
        }

        console.log("=== SUMMARY ===");
        console.log("Total Tests: %s", Strings.toString(totalTests));
        console.log("Successful: %s", Strings.toString(successfulTests));
        console.log(
            "Success Rate: %s%%",
            Strings.toString((successfulTests * 100) / totalTests)
        );
        console.log("\n=== END REPORT ===");
    }

    receive() external payable {}
}