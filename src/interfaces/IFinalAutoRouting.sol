// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IFinalAutoRouting {
    enum Protocol {
        UniswapV3,
        Curve,
        DirectMint,
        MultiHop,
        MultiStep
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        Protocol protocol;
        bytes routeData;
    }

    function swapAssets(SwapParams memory params) external payable returns (uint256 amountOut);
    function autoSwapAssets(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable returns (uint256 amountOut);
}