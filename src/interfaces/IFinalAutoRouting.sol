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

    enum CurveInterface {
        None,
        Exchange,
        ExchangeUnderlying,
        Both
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

    function getCurveRouteData(
        address tokenIn,
        address tokenOut
    ) external view returns (bool isCurve, address pool, int128 i, int128 j, bool useUnderlying);

    function directTransferMode() external view returns (bool);
}