// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILSTSwapRouter} from "../../src/interfaces/ILSTSwapRouter.sol";

// Mock LSTSwapRouter contract for testing
contract MockLSTSwapRouter is ILSTSwapRouter {
    using SafeERC20 for IERC20;

    // Mock storage for routes and rates
    mapping(address => mapping(address => uint256)) public mockRates;
    mapping(address => mapping(address => bool)) public routeExists;
    mapping(address => mapping(address => Protocol)) public routeProtocols;
    mapping(address => mapping(address => address)) public routeTargets;

    // Constants
    address public constant ETH_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor() {
        // Common token addresses
        address STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        address CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;

        // Set up default supported routes with 1:1 rates for testing
        _setMockRoute(ETH_ADDR, WETH, 1e18, Protocol.DirectMint, WETH);
        _setMockRoute(WETH, ETH_ADDR, 1e18, Protocol.DirectMint, WETH);
        _setMockRoute(WETH, STETH, 1e18, Protocol.Curve, STETH);
        _setMockRoute(STETH, WETH, 1e18, Protocol.Curve, WETH);
        _setMockRoute(ETH_ADDR, STETH, 1e18, Protocol.Curve, STETH);
        _setMockRoute(STETH, ETH_ADDR, 1e18, Protocol.Curve, ETH_ADDR);
        _setMockRoute(WETH, RETH, 1e18, Protocol.UniswapV3, RETH);
        _setMockRoute(RETH, WETH, 1e18, Protocol.UniswapV3, WETH);
        _setMockRoute(WETH, CBETH, 1e18, Protocol.UniswapV3, CBETH);
        _setMockRoute(CBETH, WETH, 1e18, Protocol.UniswapV3, WETH);
    }

    function _setMockRoute(
        address tokenIn,
        address tokenOut,
        uint256 rate,
        Protocol protocol,
        address target
    ) internal {
        mockRates[tokenIn][tokenOut] = rate;
        routeExists[tokenIn][tokenOut] = true;
        routeProtocols[tokenIn][tokenOut] = protocol;
        routeTargets[tokenIn][tokenOut] = target;
    }

    // ILSTSwapRouter implementation
    function ETH_ADDRESS() external pure returns (address) {
        return ETH_ADDR;
    }

    function uniswapRouter() external pure returns (address) {
        return 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    }

    function getWETHRequirements(
        address tokenIn,
        address tokenOut,
        Protocol protocol
    ) external pure returns (bool needsWrap, bool needsUnwrap, address wethAddress) {
        wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        needsWrap = tokenIn == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        needsUnwrap = tokenOut == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

    function getQuoteAndExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        returns (
            uint256 quotedAmount,
            bytes memory executionData,
            uint8 protocol,
            address targetContract,
            uint256 value
        )
    {
        require(routeExists[tokenIn][tokenOut], "Route not found");

        quotedAmount = (amountIn * mockRates[tokenIn][tokenOut]) / 1e18;
        protocol = uint8(routeProtocols[tokenIn][tokenOut]);
        targetContract = routeTargets[tokenIn][tokenOut];
        value = tokenIn == ETH_ADDR ? amountIn : 0;

        // Simple mock execution data
        executionData = abi.encodeWithSignature("transfer(address,uint256)", recipient, quotedAmount);
    }

    function decodeComplexExecutionData(
        bytes calldata complexData
    )
        external
        pure
        returns (uint8 routeType, address firstTarget, bytes memory firstCalldata, bytes memory additionalData)
    {
        routeType = 0;
        firstTarget = address(0);
        firstCalldata = "";
        additionalData = "";
    }

    function getBridgeSecondLegData(
        address bridgeAsset,
        address finalToken,
        uint256 bridgeAmount,
        uint256 originalMinOut,
        address recipient
    ) external view returns (bytes memory executionData, address targetContract, bool requiresApproval) {
        executionData = abi.encodeWithSignature("transfer(address,uint256)", recipient, bridgeAmount);
        targetContract = bridgeAsset;
        requiresApproval = true;
    }

    function getNextStepExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata fullRouteData,
        uint256 stepIndex,
        address recipient
    ) external view returns (bytes memory executionData, address targetContract, bool isFinalStep) {
        executionData = abi.encodeWithSignature("transfer(address,uint256)", recipient, amountIn);
        targetContract = tokenOut;
        isFinalStep = true;
    }

    function getCompleteMultiStepPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) external returns (uint256 totalQuotedAmount, MultiStepExecutionPlan memory plan) {
        require(routeExists[tokenIn][tokenOut], "Route not found");

        totalQuotedAmount = (amountIn * mockRates[tokenIn][tokenOut]) / 1e18;

        SwapStep[] memory steps = new SwapStep[](1);
        steps[0] = SwapStep({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: (totalQuotedAmount * 95) / 100, // 5% slippage
            target: routeTargets[tokenIn][tokenOut],
            data: abi.encodeWithSignature("transfer(address,uint256)", recipient, totalQuotedAmount),
            value: tokenIn == ETH_ADDR ? amountIn : 0,
            protocol: routeProtocols[tokenIn][tokenOut]
        });

        plan = MultiStepExecutionPlan({steps: steps, expectedFinalAmount: totalQuotedAmount});
    }

    // Mock execution function for testing
    function executeSwap(address tokenIn, address tokenOut, uint256 amountIn, address recipient) external payable {
        require(routeExists[tokenIn][tokenOut], "Route not found");

        uint256 amountOut = (amountIn * mockRates[tokenIn][tokenOut]) / 1e18;

        // Handle input tokens
        if (tokenIn == ETH_ADDR) {
            require(msg.value >= amountIn, "Insufficient ETH");
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Handle output tokens
        if (tokenOut == ETH_ADDR) {
            (bool success, ) = payable(recipient).call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenOut).safeTransfer(recipient, amountOut);
        }
    }

    receive() external payable {}
}

// Type alias for backward compatibility
contract MockLSR is MockLSTSwapRouter {}
