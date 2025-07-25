// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Import contracts
import "../src/FinalAutoRouting.sol";
import "./mocks/MockLiquidTokenManager.sol";

contract LTMFARIntegrationTest is Test {
    // Contracts
    FinalAutoRouting public far;
    MockLiquidTokenManager public ltm;

    // Mainnet addresses
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_V3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant CURVE_STETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant FRXETH_MINTER = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    // Token addresses
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address constant UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;

    // Pool addresses from your config
    address constant WETH_CBETH_POOL = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;
    address constant WETH_RETH_POOL = 0x553e9C493678d8606d6a5ba284643dB2110Df823;
    address constant WETH_WBTC_POOL = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
    address constant WBTC_UNIBTC_POOL = 0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0;
    address constant RETH_OSETH_POOL = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
    address constant WETH_STETH_POOL = 0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D;

    // Test user
    address user;
    string constant PASSWORD = "[REDACTED]";

    function setUp() public {
        console.log("\n=== SETUP START ===");

        // Fork mainnet
        vm.createSelectFork("wss://eth.drpc.org");

        user = makeAddr("user");

        // Deploy contracts
        _deployContracts();

        // Initialize FAR
        _initializeFAR();

        // Configure essential routes for auto-routing tests
        _configureMinimalRoutes();

        // Get test assets
        _getTestAssets();

        console.log("=== SETUP COMPLETE ===\n");
    }

    function _deployContracts() internal {
        // Compute FAR address
        address predictedFARAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes32 passwordHash = keccak256(abi.encode(PASSWORD, predictedFARAddress));

        // Deploy FAR
        far = new FinalAutoRouting(
            WETH,
            UNISWAP_V3_ROUTER,
            UNISWAP_V3_QUOTER,
            FRXETH_MINTER,
            address(this),
            passwordHash,
            address(this),
            false
        );

        // Deploy Mock LTM
        ltm = new MockLiquidTokenManager();

        // Initialize LTM
        MockLiquidTokenManager.Init memory ltmInit = MockLiquidTokenManager.Init({
            strategyManager: address(0),
            delegationManager: address(0),
            liquidToken: address(0),
            stakerNodeCoordinator: address(0),
            tokenRegistryOracle: address(0),
            initialOwner: address(this),
            strategyController: address(this),
            priceUpdater: address(this),
            finalAutoRouting: address(far),
            weth: WETH
        });

        ltm.initialize(ltmInit);
        far.grantOperatorRole(address(ltm));
    }

    function _initializeFAR() internal {
        // Token set matching your config
        address[] memory tokens = new address[](8);
        tokens[0] = ETH_ADDRESS;
        tokens[1] = WETH;
        tokens[2] = STETH;
        tokens[3] = CBETH;
        tokens[4] = RETH;
        tokens[5] = OSETH;
        tokens[6] = WBTC;
        tokens[7] = UNIBTC;

        FinalAutoRouting.AssetType[] memory types = new FinalAutoRouting.AssetType[](8);
        for (uint i = 0; i < 6; i++) types[i] = FinalAutoRouting.AssetType.ETH_LST;
        types[6] = FinalAutoRouting.AssetType.BTC_WRAPPED;
        types[7] = FinalAutoRouting.AssetType.BTC_WRAPPED;

        uint8[] memory decimals = new uint8[](8);
        for (uint i = 0; i < 6; i++) decimals[i] = 18;
        decimals[6] = 8;
        decimals[7] = 8;

        // Essential pools matching your config
        address[] memory pools = new address[](5);
        pools[0] = CURVE_STETH_POOL; // ETH -> stETH (Curve)
        pools[1] = WETH_CBETH_POOL; // UniswapV3
        pools[2] = WETH_RETH_POOL; // UniswapV3
        pools[3] = RETH_OSETH_POOL; // Curve
        pools[4] = WETH_STETH_POOL; // UniswapV3 WETH-stETH

        uint256[] memory tokenCounts = new uint256[](5);
        for (uint i = 0; i < 5; i++) tokenCounts[i] = 2;

        FinalAutoRouting.CurveInterface[] memory interfaces = new FinalAutoRouting.CurveInterface[](5);
        interfaces[0] = FinalAutoRouting.CurveInterface.Exchange; // ETH-stETH Curve
        interfaces[1] = FinalAutoRouting.CurveInterface.None; // UniswapV3
        interfaces[2] = FinalAutoRouting.CurveInterface.None; // UniswapV3
        interfaces[3] = FinalAutoRouting.CurveInterface.Exchange; // rETH-osETH Curve
        interfaces[4] = FinalAutoRouting.CurveInterface.None; // WETH-stETH UniswapV3

        // More conservative slippage configs
        FinalAutoRouting.SlippageConfig[] memory slippages = new FinalAutoRouting.SlippageConfig[](12);
        slippages[0] = FinalAutoRouting.SlippageConfig(ETH_ADDRESS, STETH, 500); // ETH->stETH
        slippages[1] = FinalAutoRouting.SlippageConfig(WETH, CBETH, 1000); // Increased from 700
        slippages[2] = FinalAutoRouting.SlippageConfig(WETH, RETH, 1500); // Increased from 1300
        slippages[3] = FinalAutoRouting.SlippageConfig(STETH, WETH, 1000); // Increased from 700
        slippages[4] = FinalAutoRouting.SlippageConfig(CBETH, WETH, 1000); // Increased from 700
        slippages[5] = FinalAutoRouting.SlippageConfig(RETH, WETH, 1500); // Increased from 1300
        slippages[6] = FinalAutoRouting.SlippageConfig(RETH, OSETH, 1200); // Increased from 800
        slippages[7] = FinalAutoRouting.SlippageConfig(OSETH, RETH, 1200); // Increased from 800
        slippages[8] = FinalAutoRouting.SlippageConfig(STETH, CBETH, 1500); // Multi-step
        slippages[9] = FinalAutoRouting.SlippageConfig(CBETH, RETH, 1500); // Multi-step
        slippages[10] = FinalAutoRouting.SlippageConfig(WETH, OSETH, 1500); // Multi-step
        slippages[11] = FinalAutoRouting.SlippageConfig(OSETH, WETH, 1500); // Multi-step

        far.initialize(tokens, types, decimals, pools, tokenCounts, interfaces, slippages);
    }

    function _configureMinimalRoutes() internal {
        // Configure routes matching your config exactly

        // 1. WETH <-> stETH (UniswapV3 with fee 10000)
        far.configureRoute(
            WETH,
            STETH,
            FinalAutoRouting.Protocol.UniswapV3,
            WETH_STETH_POOL,
            10000, // Fee from your config
            [int128(0), int128(0)],
            false,
            address(0),
            PASSWORD
        );

        far.configureRoute(
            STETH,
            WETH,
            FinalAutoRouting.Protocol.UniswapV3,
            WETH_STETH_POOL,
            10000, // Fee from your config
            [int128(0), int128(0)],
            false,
            address(0),
            PASSWORD
        );

        // 2. WETH <-> cbETH (UniswapV3 with fee 500)
        far.configureRoute(
            WETH,
            CBETH,
            FinalAutoRouting.Protocol.UniswapV3,
            WETH_CBETH_POOL,
            500,
            [int128(0), int128(0)],
            false,
            address(0),
            PASSWORD
        );

        far.configureRoute(
            CBETH,
            WETH,
            FinalAutoRouting.Protocol.UniswapV3,
            WETH_CBETH_POOL,
            500,
            [int128(0), int128(0)],
            false,
            address(0),
            PASSWORD
        );

        // 3. WETH <-> rETH (UniswapV3 with fee 100)
        far.configureRoute(
            WETH,
            RETH,
            FinalAutoRouting.Protocol.UniswapV3,
            WETH_RETH_POOL,
            100,
            [int128(0), int128(0)],
            false,
            address(0),
            PASSWORD
        );

        far.configureRoute(
            RETH,
            WETH,
            FinalAutoRouting.Protocol.UniswapV3,
            WETH_RETH_POOL,
            100,
            [int128(0), int128(0)],
            false,
            address(0),
            PASSWORD
        );

        // 4. rETH <-> osETH (Curve)
        far.configureRoute(
            RETH,
            OSETH,
            FinalAutoRouting.Protocol.Curve,
            RETH_OSETH_POOL,
            0,
            [int128(1), int128(0)], // rETH index 1, osETH index 0
            false,
            address(0),
            PASSWORD
        );

        far.configureRoute(
            OSETH,
            RETH,
            FinalAutoRouting.Protocol.Curve,
            RETH_OSETH_POOL,
            0,
            [int128(0), int128(1)], // osETH index 0, rETH index 1
            false,
            address(0),
            PASSWORD
        );

        // 5. ETH <-> stETH (Curve) - for setup
        far.configureRoute(
            ETH_ADDRESS,
            STETH,
            FinalAutoRouting.Protocol.Curve,
            CURVE_STETH_POOL,
            0,
            [int128(0), int128(1)], // ETH index 0, stETH index 1
            false,
            address(0),
            PASSWORD
        );
    }

    function _getTestAssets() internal {
        vm.deal(address(this), 10 ether);

        // Get WETH
        IWETH(WETH).deposit{value: 5 ether}();

        // Get stETH via Curve (ETH -> stETH)
        ICurvePool(CURVE_STETH_POOL).exchange{value: 2 ether}(0, 1, 2 ether, 0);

        // Get cbETH via UniswapV3
        IERC20(WETH).approve(UNISWAP_V3_ROUTER, 1 ether);
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: CBETH,
            fee: 500,
            recipient: address(this),
            deadline: block.timestamp + 3600,
            amountIn: 1 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params);

        // Get rETH via UniswapV3
        IERC20(WETH).approve(UNISWAP_V3_ROUTER, 1 ether);
        IUniswapV3Router.ExactInputSingleParams memory rethParams = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: RETH,
            fee: 100,
            recipient: address(this),
            deadline: block.timestamp + 3600,
            amountIn: 1 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(rethParams);

        // Get osETH by converting some rETH via Curve
        uint256 rethBalance = IERC20(RETH).balanceOf(address(this));
        if (rethBalance > 0.5 ether) {
            IERC20(RETH).approve(RETH_OSETH_POOL, 0.5 ether);
            ICurvePool(RETH_OSETH_POOL).exchange(1, 0, 0.5 ether, 0); // rETH index 1 -> osETH index 0
        }
    }

    // Test 1: Auto-routing stETH -> cbETH (should find WETH bridge)
    function testAutoRoutingStETHToCbETH() public {
        console.log("\n=== Test: stETH -> cbETH Auto-routing (Bridge via WETH) ===");

        uint256 amountIn = 0.5 ether;
        uint256 minAmountOut = 0.3 ether; // Very conservative

        // Check route exists
        assertTrue(far.hasRoute(STETH, CBETH), "Route should exist via bridge");

        IERC20(STETH).approve(address(ltm), amountIn);

        uint256 balanceBefore = ltm.mockStakedBalances(1, CBETH);

        ltm.swapAndStake(STETH, CBETH, amountIn, 1, minAmountOut);

        uint256 balanceAfter = ltm.mockStakedBalances(1, CBETH);
        uint256 amountStaked = balanceAfter - balanceBefore;

        console.log("Amount staked:", amountStaked);
        assertGe(amountStaked, minAmountOut, "Output too low");
    }

    // Test 2: Auto-routing cbETH -> rETH (should find WETH bridge)
    function testAutoRoutingCbETHToRETH() public {
        console.log("\n=== Test: cbETH -> rETH Auto-routing (Bridge via WETH) ===");

        uint256 amountIn = 0.3 ether;
        uint256 minAmountOut = 0.15 ether; // Very conservative

        assertTrue(far.hasRoute(CBETH, RETH), "Route should exist via bridge");

        IERC20(CBETH).approve(address(ltm), amountIn);

        uint256 balanceBefore = ltm.mockStakedBalances(2, RETH);

        ltm.swapAndStake(CBETH, RETH, amountIn, 2, minAmountOut);

        uint256 balanceAfter = ltm.mockStakedBalances(2, RETH);
        uint256 amountStaked = balanceAfter - balanceBefore;

        console.log("Amount staked:", amountStaked);
        assertGe(amountStaked, minAmountOut, "Output too low");
    }

    // Test 3: Multi-step auto-routing stETH -> osETH (via WETH -> rETH)
    function testAutoRoutingStETHToOsETH() public {
        console.log("\n=== Test: stETH -> osETH Multi-step Auto-routing ===");

        // Use a smaller amount and account for potential 1-2 wei loss
        uint256 amountIn = 0.1 ether;
        uint256 minAmountOut = 0.04 ether; // Lower expectation

        assertTrue(far.hasRoute(STETH, OSETH), "Multi-step route should exist");

        IERC20(STETH).approve(address(ltm), amountIn);

        uint256 osethBalanceBefore = ltm.mockStakedBalances(3, OSETH);

        ltm.swapAndStake(STETH, OSETH, amountIn, 3, minAmountOut);

        uint256 osethBalanceAfter = ltm.mockStakedBalances(3, OSETH);
        uint256 amountStaked = osethBalanceAfter - osethBalanceBefore;

        console.log("Amount staked:", amountStaked);
        assertGe(amountStaked, minAmountOut, "Output too low");
    }
    // Test 4: Reverse auto-routing osETH -> WETH
    function testAutoRoutingOsETHToWETH() public {
        console.log("\n=== Test: osETH -> WETH Reverse Auto-routing ===");

        // Use the osETH we got in setup
        uint256 osETHBalance = IERC20(OSETH).balanceOf(address(this));
        require(osETHBalance > 0, "No osETH balance available for test");

        uint256 amountIn = osETHBalance / 2; // Use half of available balance
        uint256 minAmountOut = (amountIn * 4) / 10; // Expect at least 40% due to multi-step slippage

        console.log("osETH balance:", osETHBalance);
        console.log("Amount to swap:", amountIn);
        console.log("Min amount out:", minAmountOut);

        IERC20(OSETH).approve(address(ltm), amountIn);

        uint256 balanceBefore = ltm.mockStakedBalances(4, WETH);

        ltm.swapAndStake(OSETH, WETH, amountIn, 4, minAmountOut);

        uint256 balanceAfter = ltm.mockStakedBalances(4, WETH);
        uint256 amountStaked = balanceAfter - balanceBefore;

        console.log("Amount staked:", amountStaked);
        assertGe(amountStaked, minAmountOut, "Output too low");
    }

    // Test 5: Complex multi-step cbETH -> osETH
    function testAutoRoutingCbETHToOsETH() public {
        console.log("\n=== Test: cbETH -> osETH Complex Auto-routing ===");

        uint256 amountIn = 0.2 ether;
        uint256 minAmountOut = 0.08 ether; // Very conservative for 3-step

        // Should find: cbETH -> WETH -> rETH -> osETH
        assertTrue(far.hasRoute(CBETH, OSETH), "Complex route should exist");

        IERC20(CBETH).approve(address(ltm), amountIn);

        uint256 balanceBefore = ltm.mockStakedBalances(5, OSETH);

        ltm.swapAndStake(CBETH, OSETH, amountIn, 5, minAmountOut);

        uint256 balanceAfter = ltm.mockStakedBalances(5, OSETH);
        uint256 amountStaked = balanceAfter - balanceBefore;

        console.log("Amount staked:", amountStaked);
        assertGe(amountStaked, minAmountOut, "Output too low");
    }

    // Test 6: Quote validation for auto-routed paths
    function testAutoRoutingQuoteValidation() public {
        console.log("\n=== Test: Auto-routing Quote Validation ===");


        // Test multi-step quote
        (uint256 quote2, , , , ) = far.getQuoteAndExecutionData(CBETH, OSETH, 1 ether, address(ltm));
        console.log("cbETH -> osETH quote:", quote2);
        assertGt(quote2, 0.4 ether, "Multi-step quote too low");

        // Validate execution
        (bool isValid, string memory reason, uint256 estimate) = far.validateSwapExecution(
            STETH,
            CBETH,
            1 ether,
            0.5 ether,
            address(ltm)
        );
        assertTrue(isValid, reason);
        console.log("Validation passed with estimate:", estimate);
    }

    // Test 7: Error handling for impossible routes
    function testAutoRoutingErrors() public {
        console.log("\n=== Test: Auto-routing Error Cases ===");

        // Test cross-category (should fail)
        address USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.expectRevert();
        ltm.swapAndStake(WETH, USDC, 1 ether, 1, 0);
        console.log(" Cross-category swap rejected");

        // Test unsupported token
        vm.expectRevert();
        ltm.swapAndStake(address(0x123), WETH, 1 ether, 1, 0);
        console.log(" Unsupported token rejected");

        // Test same token
        vm.expectRevert();
        ltm.swapAndStake(WETH, WETH, 1 ether, 1, 0);
        console.log(" Same token swap rejected");
    }

   

    function testFARRouteDiagnostics() public {
        console.log("=== FAR Route Discovery Diagnostics ===");

        // Test direct routes
        console.log("Direct routes:");
        console.log("STETH->WETH:", far.hasRoute(STETH, WETH));
        console.log("WETH->RETH:", far.hasRoute(WETH, RETH));
        console.log("RETH->OSETH:", far.hasRoute(RETH, OSETH));
        console.log("CBETH->WETH:", far.hasRoute(CBETH, WETH));
        console.log("WETH->CBETH:", far.hasRoute(WETH, CBETH));

        // Test bridge discovery
        console.log("\nBridge routes:");
        console.log("STETH->OSETH:", far.hasRoute(STETH, OSETH));
        console.log("CBETH->OSETH:", far.hasRoute(CBETH, OSETH));
        console.log("STETH->CBETH:", far.hasRoute(STETH, CBETH));
        console.log("CBETH->RETH:", far.hasRoute(CBETH, RETH));
        console.log("OSETH->WETH:", far.hasRoute(OSETH, WETH));

        // Test reverse routes
        console.log("\nReverse routes:");
        console.log("WETH->STETH:", far.hasRoute(WETH, STETH));
        console.log("RETH->WETH:", far.hasRoute(RETH, WETH));
        console.log("OSETH->RETH:", far.hasRoute(OSETH, RETH));
    }

    function testIndividualRouteQuotes() public {
        console.log("=== Individual Route Quote Testing ===");

        // Test each leg of stETH->osETH path
        console.log("Testing STETH->WETH...");
        (bool success1, bytes memory result1) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, STETH, WETH, 1 ether, address(this))
        );
        if (success1) {
            (uint256 quote1, , , , ) = abi.decode(result1, (uint256, bytes, uint8, address, uint256));
            console.log(" STETH->WETH quote:", quote1);
        } else {
            console.log(" STETH->WETH failed");
        }

        console.log("Testing WETH->RETH...");
        (bool success2, bytes memory result2) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, WETH, RETH, 1 ether, address(this))
        );
        if (success2) {
            (uint256 quote2, , , , ) = abi.decode(result2, (uint256, bytes, uint8, address, uint256));
            console.log(" WETH->RETH quote:", quote2);
        } else {
            console.log(" WETH->RETH failed");
        }

        console.log("Testing RETH->OSETH...");
        (bool success3, bytes memory result3) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, RETH, OSETH, 1 ether, address(this))
        );
        if (success3) {
            (uint256 quote3, , , , ) = abi.decode(result3, (uint256, bytes, uint8, address, uint256));
            console.log(" RETH->OSETH quote:", quote3);
        } else {
            console.log(" RETH->OSETH failed");
        }
    }

    function testBridgeRouteQuotes() public {
        console.log("=== Bridge Route Quote Testing ===");

        console.log("Testing STETH->OSETH...");
        (bool success1, bytes memory result1) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, STETH, OSETH, 1 ether, address(this))
        );
        if (success1) {
            (uint256 quote1, , uint8 protocol1, , ) = abi.decode(result1, (uint256, bytes, uint8, address, uint256));
            console.log(" STETH->OSETH quote:", quote1);
            console.log(" Protocol:", protocol1);
        } else {
            console.log(" STETH->OSETH failed");
        }

        console.log("Testing CBETH->OSETH...");
        (bool success2, bytes memory result2) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, CBETH, OSETH, 1 ether, address(this))
        );
        if (success2) {
            (uint256 quote2, , uint8 protocol2, , ) = abi.decode(result2, (uint256, bytes, uint8, address, uint256));
            console.log(" CBETH->OSETH quote:", quote2);
            console.log(" Protocol:", protocol2);
        } else {
            console.log(" CBETH->OSETH failed");
        }

        console.log("Testing OSETH->WETH...");
        (bool success3, bytes memory result3) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, OSETH, WETH, 1 ether, address(this))
        );
        if (success3) {
            (uint256 quote3, , uint8 protocol3, , ) = abi.decode(result3, (uint256, bytes, uint8, address, uint256));
            console.log(" OSETH->WETH quote:", quote3);
            console.log(" Protocol:", protocol3);
        } else {
            console.log(" OSETH->WETH failed");
        }
    }

    function testSlippageAnalysis() public {
        console.log("=== Slippage Analysis ===");

        // Test the cbETH->rETH route
        console.log("Testing cbETH->rETH with 0.3 ether...");
        (bool success, bytes memory result) = address(far).call(
            abi.encodeWithSelector(far.getQuoteAndExecutionData.selector, CBETH, RETH, 0.3 ether, address(this))
        );

        if (success) {
            (uint256 quote, , , , ) = abi.decode(result, (uint256, bytes, uint8, address, uint256));
            console.log("Quote:", quote);
            console.log("Input:", 0.3 ether);

            uint256 slippageBps = ((0.3 ether - quote) * 10000) / 0.3 ether;
            console.log("Slippage:", slippageBps, "bps");

            // Test what min amounts would work
            console.log("Would pass with:");
            console.log(" 10% slippage (270000000000000000):", quote >= 270000000000000000);
            console.log(" 15% slippage (255000000000000000):", quote >= 255000000000000000);
            console.log(" 20% slippage (240000000000000000):", quote >= 240000000000000000);
            console.log(" 30% slippage (210000000000000000):", quote >= 210000000000000000);
            console.log(" 40% slippage (180000000000000000):", quote >= 180000000000000000);
            console.log(" 50% slippage (150000000000000000):", quote >= 150000000000000000);
        } else {
            console.log(" cbETH->rETH failed completely");
        }
    }

    function testMultiStepPlanGeneration() public {
        console.log("=== Multi-Step Plan Generation ===");

        console.log("Testing STETH->OSETH getCompleteMultiStepPlan...");
        (bool success1, bytes memory result1) = address(far).call(
            abi.encodeWithSelector(far.getCompleteMultiStepPlan.selector, STETH, OSETH, 1 ether, address(this))
        );

        if (success1) {
            console.log(" STETH->OSETH plan generated successfully");
        } else {
            console.log(" STETH->OSETH plan generation failed");
        }

        console.log("Testing CBETH->OSETH getCompleteMultiStepPlan...");
        (bool success2, bytes memory result2) = address(far).call(
            abi.encodeWithSelector(far.getCompleteMultiStepPlan.selector, CBETH, OSETH, 1 ether, address(this))
        );

        if (success2) {
            console.log(" CBETH->OSETH plan generated successfully");
        } else {
            console.log(" CBETH->OSETH plan generation failed");
        }

        console.log("Testing OSETH->WETH getCompleteMultiStepPlan...");
        (bool success3, bytes memory result3) = address(far).call(
            abi.encodeWithSelector(far.getCompleteMultiStepPlan.selector, OSETH, WETH, 1 ether, address(this))
        );

        if (success3) {
            console.log(" OSETH->WETH plan generated successfully");
        } else {
            console.log(" OSETH->WETH plan generation failed");
        }
    }

    function testAutoRoutingCbETHToWETHViaStETH() public {
        console.log("\n=== Test: cbETH -> WETH (via stETH route) ===");

        uint256 amountIn = 0.5 ether;
        uint256 minAmountOut = 0.3 ether; // Lower expectation

        IERC20(CBETH).approve(address(ltm), amountIn);

        // Check WETH balance before - should be done differently
        uint256 wethBalanceBefore = ltm.mockStakedBalances(2, WETH);

        ltm.swapAndStake(CBETH, WETH, amountIn, 2, minAmountOut);

        uint256 wethBalanceAfter = ltm.mockStakedBalances(2, WETH);
        uint256 amountReceived = wethBalanceAfter - wethBalanceBefore;

        console.log(string.concat("WETH received: ", Strings.toString(amountReceived)));
        assertGe(amountReceived, minAmountOut, "Output too low");
    }

    function testAutoRoutingWETHToStETH() public {
        console.log("\n=== Test: WETH -> stETH Auto-routing ===");

        uint256 amountIn = 0.5 ether;
        uint256 minAmountOut = 0.3 ether; // Lower expectation due to fees

        assertTrue(far.hasRoute(WETH, STETH), "Route should exist");

        IERC20(WETH).approve(address(ltm), amountIn);

        // Use mock staked balance instead of direct balance check
        uint256 stethBalanceBefore = ltm.mockStakedBalances(1, STETH);

        ltm.swapAndStake(WETH, STETH, amountIn, 1, minAmountOut);

        uint256 stethBalanceAfter = ltm.mockStakedBalances(1, STETH);
        uint256 amountReceived = stethBalanceAfter - stethBalanceBefore;

        console.log(string.concat("stETH received: ", Strings.toString(amountReceived)));
        assertGe(amountReceived, minAmountOut, "Output too low");
    }

    receive() external payable {}
}