/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../../../src/AutoRouting.sol";

contract DecimalNormalizationTest is Test {
    AutoRouting public swapper;

    // Test tokens with various decimals
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant GUSD = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;
    address constant RAI = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;
    address constant CUSTOM = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;

    address owner = address(0xA);
    address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address routeManager = address(0xD);
    address liquidTokenManager = address(0xE);

    function setUp() public {
        vm.startPrank(owner);

        bytes32 pwHash = keccak256(
            abi.encode("testPassword123", address(this))
        );
        swapper = new AutoRouting(
            WETH,
            uniswapRouter,
            address(0xC),
            routeManager,
            pwHash,
            liquidTokenManager
        );

        address[] memory tokens = new address[](6);
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = WBTC;
        tokens[3] = GUSD;
        tokens[4] = RAI;
        tokens[5] = CUSTOM;

        AutoRouting.AssetType[] memory types = new AutoRouting.AssetType[](
            6
        );
        types[0] = AutoRouting.AssetType.ETH_LST;
        types[1] = AutoRouting.AssetType.STABLE;
        types[2] = AutoRouting.AssetType.BTC_WRAPPED;
        types[3] = AutoRouting.AssetType.STABLE;
        types[4] = AutoRouting.AssetType.ETH_LST;
        types[5] = AutoRouting.AssetType.ETH_LST;

        uint8[] memory decimals = new uint8[](6);
        decimals[0] = 18;
        decimals[1] = 6;
        decimals[2] = 8;
        decimals[3] = 2;
        decimals[4] = 18;
        decimals[5] = 18;

        address[] memory pools = new address[](1);
        pools[0] = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;

        uint256[] memory poolTokenCounts = new uint256[](1);
        poolTokenCounts[0] = 2;

        AutoRouting.CurveInterface[]
            memory curveInterfaces = new AutoRouting.CurveInterface[](1);
        curveInterfaces[0] = AutoRouting.CurveInterface.None;

        AutoRouting.SlippageConfig[]
            memory slippageConfigs = new AutoRouting.SlippageConfig[](0);

        swapper.initialize(
            tokens,
            types,
            decimals,
            pools,
            poolTokenCounts,
            curveInterfaces,
            slippageConfigs
        );

        vm.stopPrank();
        _mockTokenContracts();
    }

    function _mockTokenContracts() internal {
        address[6] memory tokens = [WETH, USDC, WBTC, GUSD, RAI, CUSTOM];

        for (uint i = 0; i < tokens.length; i++) {
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0x23b872dd),
                abi.encode(true)
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0xa9059cbb),
                abi.encode(true)
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0x095ea7b3),
                abi.encode(true)
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0xdd62ed3e),
                abi.encode(uint256(0))
            );
        }
    }

    function testBasicNormalization18To6() public {
        console.log("Testing 18 to 6 Decimal Normalization");

        uint256 amountIn = 1e18;
        uint256 normalized = swapper.normalizeAmount(WETH, USDC, amountIn);

        // 18 decimals to 6 decimals: divide by 1e12
        assertEq(normalized, 1e6);
        console.log("18 to 6 decimal normalization:", normalized);
    }

    function testNormalization6To18() public {
        console.log("Testing 6 to 18 Decimal Normalization");

        uint256 amountIn = 1000000; // 1 USDC
        uint256 normalized = swapper.normalizeAmount(USDC, WETH, amountIn);

        // 6 decimals to 18 decimals: multiply by 1e12
        assertEq(normalized, 1e18);
        console.log("6 to 18 decimal normalization:", normalized);
    }

    function testExtremeLowDecimals() public {
        console.log("Testing Extreme Low Decimals (2)");

        uint256 amountIn = 100; // 1.00 GUSD
        uint256 normalized = swapper.normalizeAmount(GUSD, USDC, amountIn);

        // 2 decimals to 6 decimals: multiply by 1e4
        assertEq(normalized, 1000000);
        console.log("2 to 6 decimal normalization:", normalized);
    }

    function testHighDecimalsNormalization() public {
        console.log("Testing High Decimals Normalization");

        uint256 amountIn = 1e18;
        uint256 normalized = swapper.normalizeAmount(CUSTOM, USDC, amountIn);

        // 18 decimals to 6 decimals
        assertEq(normalized, 1e6);
        console.log("18 to 6 decimal normalization:", normalized);
    }

    function testSameDecimalNormalization() public {
        console.log("Testing Same Decimal Normalization");

        uint256 amountIn = 1e18;
        uint256 normalized = swapper.normalizeAmount(WETH, RAI, amountIn);

        // Both 18 decimals: no change
        assertEq(normalized, amountIn);
        console.log("Same decimal normalization:", normalized);
    }

    function testBTCDecimalHandling() public {
        console.log("Testing BTC Decimal Handling");

        uint256 amountIn = 1e8; // 1 WBTC
        uint256 normalized = swapper.normalizeAmount(WBTC, WETH, amountIn);

        // 8 decimals to 18 decimals: multiply by 1e10
        assertEq(normalized, 1e18);
        console.log("BTC to ETH decimal normalization:", normalized);
    }

    function testReverseNormalization() public {
        console.log("Testing Reverse Normalization");

        uint256 amountIn = 1e18; // 1 WETH
        uint256 normalized = swapper.normalizeAmount(WETH, WBTC, amountIn);

        // 18 decimals to 8 decimals: divide by 1e10
        assertEq(normalized, 1e8);
        console.log("WETH to WBTC normalization:", normalized);
    }

    function testOverflowProtection() public {
        console.log("Testing Overflow Protection");

        // Test with max safe amount
        uint256 maxSafeAmount = type(uint256).max / 1e18;
        uint256 normalized = swapper.normalizeAmount(GUSD, WETH, maxSafeAmount);

        assertTrue(normalized > 0);
        console.log("Overflow protection working");
    }
}
*/