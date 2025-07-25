// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IUniswapV3Router} from "../../src/interfaces/IUniswapV3Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockUniswapV3Router is IUniswapV3Router {
    uint256 public mockAmountOut = 1000e18; // Default mock output

    function setMockAmountOut(uint256 _amount) external {
        mockAmountOut = _amount;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable override returns (uint256 amountOut) {
        // Simple mock: mint output tokens to recipient instead of real swap
        MockERC20(params.tokenOut).mint(params.recipient, mockAmountOut);
        return mockAmountOut;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
        // Simple mock - just return mockAmountOut
        return mockAmountOut;
    }
}