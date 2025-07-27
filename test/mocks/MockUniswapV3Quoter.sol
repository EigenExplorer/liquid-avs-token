// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUniswapV3Quoter} from "../../src/interfaces/IUniswapV3Quoter.sol";

contract MockUniswapV3Quoter is IUniswapV3Quoter {
    uint256 public mockQuoteAmount = 1000e18;

    function setMockQuote(uint256 _amount) external {
        mockQuoteAmount = _amount;
    }

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external override returns (uint256 amountOut) {
        return mockQuoteAmount;
    }

    function quoteExactInput(bytes memory path, uint256 amountIn) external override returns (uint256 amountOut) {
        return mockQuoteAmount;
    }

    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external override returns (uint256 amountIn) {
        return mockQuoteAmount;
    }

    function quoteExactOutput(bytes memory path, uint256 amountOut) external override returns (uint256 amountIn) {
        return mockQuoteAmount;
    }
}