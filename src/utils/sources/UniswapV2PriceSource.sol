// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceSource} from "../../interfaces/IPriceSource.sol";

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/**
 * @title UniswapV2PriceSource
 * @notice Gets ETH-denominated prices from Uniswap V2 pairs
 */
contract UniswapV2PriceSource is IPriceSource {
    mapping(address => address) public pairAddresses;

    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Constructor to set up token to pair mappings
     * @param tokens Array of token addresses
     * @param pairs Array of corresponding UniswapV2 pair addresses
     */
    constructor(address[] memory tokens, address[] memory pairs) {
        require(tokens.length == pairs.length, "Array length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            pairAddresses[tokens[i]] = pairs[i];
        }
    }

    /**
     * @notice Gets the ETH price for a token from UniswapV2 pair
     * @param token The token address to get the price for
     * @return price The price with 18 decimals
     * @return success Whether the price retrieval was successful
     */
    function getPrice(
        address token
    ) external view override returns (uint256 price, bool success) {
        address pairAddress = pairAddresses[token];

        if (pairAddress == address(0)) {
            return (0, false);
        }

        try IUniswapV2Pair(pairAddress).getReserves() returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32
        ) {
            if (reserve0 == 0 || reserve1 == 0) {
                return (0, false);
            }

            address token0;
            address token1;

            try IUniswapV2Pair(pairAddress).token0() returns (address _token0) {
                token0 = _token0;
            } catch {
                return (0, false);
            }

            try IUniswapV2Pair(pairAddress).token1() returns (address _token1) {
                token1 = _token1;
            } catch {
                return (0, false);
            }

            // Determine if token is token0 or token1
            bool isToken0 = token == token0;

            if (isToken0) {
                // Token is token0, price = reserve1/reserve0
                price = (uint256(reserve1) * PRECISION) / uint256(reserve0);
            } else {
                // Token is token1, price = reserve0/reserve1
                price = (uint256(reserve0) * PRECISION) / uint256(reserve1);
            }

            return (price, true);
        } catch {
            return (0, false);
        }
    }
}