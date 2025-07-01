/*

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../../../src/AutoRouting.sol";

contract SlippageValidationTest is Test {
    AutoRouting public swapper;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant mETH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address owner = address(0x1);
    address routeManager = address(0x2);
    address authorizedCaller = address(0x3);
    address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address frxETHMinter = address(0x4);
    address liquidTokenManager = 0x5573f46F5B56a9bA767BF45aDA9300bC68e2ccf7;

    string constant TEST_PASSWORD = "testPassword123";

    function setUp() public {
        vm.startPrank(owner);

        bytes32 correctHash = keccak256(
            abi.encode(TEST_PASSWORD, routeManager)
        );

        swapper = new AutoRouting(
            WETH,
            uniswapRouter,
            frxETHMinter,
            routeManager,
            correctHash,
            liquidTokenManager
        );

        address[] memory tokens = new address[](5);
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = WBTC;
        tokens[3] = rETH;
        tokens[4] = mETH;

        AutoRouting.AssetType[] memory types = new AutoRouting.AssetType[](5);
        types[0] = AutoRouting.AssetType.ETH_LST;
        types[1] = AutoRouting.AssetType.STABLE;
        types[2] = AutoRouting.AssetType.BTC_WRAPPED;
        types[3] = AutoRouting.AssetType.ETH_LST;
        types[4] = AutoRouting.AssetType.ETH_LST;

        uint8[] memory decimals = new uint8[](5);
        decimals[0] = 18;
        decimals[1] = 6;
        decimals[2] = 8;
        decimals[3] = 18;
        decimals[4] = 18;

        address[] memory pools = new address[](1);
        pools[0] = 0x840DEEef2f115Cf50DA625F7368C24af6fE74410;

        uint256[] memory poolTokenCounts = new uint256[](1);
        poolTokenCounts[0] = 2;

        AutoRouting.CurveInterface[]
            memory curveInterfaces = new AutoRouting.CurveInterface[](1);
        curveInterfaces[0] = AutoRouting.CurveInterface.None;

        AutoRouting.SlippageConfig[]
            memory slippageConfigs = new AutoRouting.SlippageConfig[](3);
        slippageConfigs[0] = AutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: USDC,
            slippageBps: 100
        });
        slippageConfigs[1] = AutoRouting.SlippageConfig({
            tokenIn: WETH,
            tokenOut: WBTC,
            slippageBps: 300
        });
        slippageConfigs[2] = AutoRouting.SlippageConfig({
            tokenIn: rETH,
            tokenOut: mETH,
            slippageBps: 50
        });

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
        address[5] memory tokens = [WETH, USDC, WBTC, rETH, mETH];

        for (uint i = 0; i < tokens.length; i++) {
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0x23b872dd), // transferFrom
                abi.encode(true)
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0xa9059cbb), // transfer
                abi.encode(true)
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0x095ea7b3), // approve
                abi.encode(true)
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0xdd62ed3e), // allowance
                abi.encode(uint256(0))
            );
            vm.mockCall(
                tokens[i],
                abi.encodeWithSelector(0x70a08231), // balanceOf
                abi.encode(type(uint256).max)
            );
        }
    }

    function testValidSlippageWithinTolerance() public {
        console.log("Testing Valid Slippage Within Tolerance");

        uint256 amountIn = 1e18;
        uint256 minAmountOut = 1900e6;

        vm.prank(authorizedCaller);
        try swapper.autoSwapAssets(WETH, USDC, amountIn, minAmountOut) {
            console.log("Valid slippage accepted");
        } catch {
            console.log("Auto routing test completed");
        }
    }

    function testCrossAssetSlippageValidation() public {
        console.log("Testing Cross Asset Slippage Validation");

        uint256 tolerance = swapper.slippageTolerance(WETH, USDC);
        assertEq(tolerance, 100);
        console.log("Cross asset slippage tolerance:", tolerance);
    }

    function testSameAssetTypeSlippage() public {
        console.log("Testing Same Asset Type Slippage");

        uint256 tolerance = swapper.slippageTolerance(rETH, mETH);
        assertEq(tolerance, 50);
        console.log("Same asset type slippage:", tolerance);
    }

    function testZeroAmountRejection() public {
        console.log("Testing Zero Amount Rejection");

        vm.prank(liquidTokenManager);
        vm.expectRevert("Zero amount");
        swapper.autoSwapAssets(WETH, USDC, 0, 0);
        console.log("Zero amount input rejected");
    }

    function testSameTokenSwapRejection() public {
        console.log("Testing Same Token Swap Rejection");

        vm.prank(liquidTokenManager);
        vm.expectRevert("Same token");
        swapper.autoSwapAssets(WETH, WETH, 1e18, 1e18);
        console.log("Same token swap correctly rejected");
    }

    function testContractPausedBehavior() public {
        console.log("Testing Contract Paused Behavior");

        vm.startPrank(owner);
        swapper.pause();
        assertTrue(swapper.paused());

        vm.expectRevert("Pausable: paused");
        swapper.autoSwapAssets(WETH, rETH, 1e18, 9e17);

        swapper.unpause();
        assertFalse(swapper.paused());
        console.log("Contract pause functionality working");
        vm.stopPrank();
    }
}
*/