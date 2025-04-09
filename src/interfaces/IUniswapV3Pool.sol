// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

/// @title The interface for a Uniswap V3 Pool
interface IUniswapV3Pool {
    /// @notice The first of the two tokens of the pool, sorted by address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    function token1() external view returns (address);

    /// @notice The pool's fee in hundredths of a bip, i.e. 1e-6
    function fee() external view returns (uint24);

    /// @notice The 0th storage slot in the pool stores many values
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice The currently in-range liquidity available to the pool
    function liquidity() external view returns (uint128);
}