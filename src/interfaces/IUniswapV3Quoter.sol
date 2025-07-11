// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IUniswapV3Quoter
 * @notice Interface for the Uniswap V3 Quoter contract
 * @dev Used for getting swap quotes without executing trades
 */
interface IUniswapV3Quoter {
    /**
     * @notice Returns the amount out received for a given exact input swap without executing the swap
     * @param tokenIn The token being swapped in
     * @param tokenOut The token being swapped out
     * @param fee The fee of the pool
     * @param amountIn The desired input amount
     * @param sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
     * @return amountOut The amount of `tokenOut` that would be received
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    /**
     * @notice Returns the amount out received for a given exact input but for a swap of a single pool
     * @param path The path of the swap, i.e. each token pair and the pool fee
     * @param amountIn The desired input amount
     * @return amountOut The amount of the final output token that would be received
     */
    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    ) external returns (uint256 amountOut);

    /**
     * @notice Returns the amount in required for a given exact output swap without executing the swap
     * @param tokenIn The token being swapped in
     * @param tokenOut The token being swapped out
     * @param fee The fee of the pool
     * @param amountOut The desired output amount
     * @param sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
     * @return amountIn The amount of `tokenIn` that would be required
     */
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);

    /**
     * @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
     * @param path The path of the swap, i.e. each token pair and the pool fee. Path must be provided in reverse order
     * @param amountOut The desired output amount
     * @return amountIn The amount of the first input token that would be required
     */
    function quoteExactOutput(
        bytes memory path,
        uint256 amountOut
    ) external returns (uint256 amountIn);

    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
    }
}
