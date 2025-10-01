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

    function getCompleteMultiStepPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) external returns (uint256 totalQuotedAmount, MultiStepExecutionPlan memory plan);
}
