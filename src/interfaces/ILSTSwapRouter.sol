// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ILSTSwapRouter {
    enum Protocol {
        UniswapV3, // 0
        Curve, // 1
        DirectMint, // 2
        MultiHop, // 3
        MultiStep // 4
    }

    enum RouteType {
        Direct, // 0
        Reverse, // 1
        Bridge // 2
    }

    struct UniswapV3Route {
        address pool;
        uint24 fee;
        bool isMultiHop;
        bytes path;
    }

    struct CurveRoute {
        address pool;
        int128 indexIn;
        int128 indexOut;
        bool useUnderlying;
    }

    struct ExecutionStrategy {
        RouteType routeType;
        Protocol protocol;
        address bridgeAsset;
        bytes primaryRouteData;
        bytes secondaryRouteData;
        uint256 expectedGas;
    }

    struct SwapStep {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address target;
        bytes data;
        uint256 value;
        Protocol protocol;
    }

    struct MultiStepExecutionPlan {
        SwapStep[] steps;
        uint256 expectedFinalAmount;
    }

    function ETH_ADDRESS() external view returns (address);
    function uniswapRouter() external view returns (address);

    function getWETHRequirements(
        address tokenIn,
        address tokenOut,
        Protocol protocol
    ) external view returns (bool needsWrap, bool needsUnwrap, address wethAddress);

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
        );

    function decodeComplexExecutionData(
        bytes calldata complexData
    )
        external
        pure
        returns (uint8 routeType, address firstTarget, bytes memory firstCalldata, bytes memory additionalData);

    function getBridgeSecondLegData(
        address bridgeAsset,
        address finalToken,
        uint256 bridgeAmount,
        uint256 originalMinOut,
        address recipient
    ) external view returns (bytes memory executionData, address targetContract, bool requiresApproval);

    function getNextStepExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata fullRouteData,
        uint256 stepIndex,
        address recipient
    ) external view returns (bytes memory executionData, address targetContract, bool isFinalStep);

    function getCompleteMultiStepPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) external returns (uint256 quotedOutput, MultiStepExecutionPlan memory plan);
}