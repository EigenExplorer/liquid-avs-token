// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceSource} from "../../interfaces/IPriceSource.sol";
import {IUniswapV3Pool} from "../../interfaces/IUniswapV3Pool.sol";
import {TickMath} from "../../libraries/TickMath.sol";
import {FixedPoint96} from "../../libraries/FixedPoint96.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";

/**
 * @title UniswapV3PriceSource
 * @notice Gets ETH-denominated prices from Uniswap V3 pools
 */
contract UniswapV3PriceSource is IPriceSource {
    address public immutable ethUsdFeed;
    mapping(address => address) public poolAddresses;
    mapping(address => bool) public isToken0;
    mapping(address => bool) public needsUsdConversion;

    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Constructor to set up token to pool mappings
     * @param _ethUsdFeed ETH/USD Chainlink feed address
     * @param tokens Array of token addresses
     * @param pools Array of corresponding UniswapV3 pool addresses
     * @param _isToken0 Whether each token is token0 in its pool
     * @param _needsUsdConversion Whether USD price needs conversion to ETH
     */
    constructor(
        address _ethUsdFeed,
        address[] memory tokens,
        address[] memory pools,
        bool[] memory _isToken0,
        bool[] memory _needsUsdConversion
    ) {
        require(
            tokens.length == pools.length &&
                pools.length == _isToken0.length &&
                _isToken0.length == _needsUsdConversion.length,
            "Array length mismatch"
        );

        ethUsdFeed = _ethUsdFeed;

        for (uint256 i = 0; i < tokens.length; i++) {
            poolAddresses[tokens[i]] = pools[i];
            isToken0[tokens[i]] = _isToken0[i];
            needsUsdConversion[tokens[i]] = _needsUsdConversion[i];
        }
    }

    /**
     * @notice Gets the ETH price for a token from UniswapV3 pool
     * @param token The token address to get the price for
     * @return price The price with 18 decimals
     * @return success Whether the price retrieval was successful
     */
    function getPrice(
        address token
    ) external view override returns (uint256 price, bool success) {
        address poolAddress = poolAddresses[token];

        if (poolAddress == address(0)) {
            return (0, false);
        }

        try this.fetchUniswapV3Price(token, poolAddress) returns (
            uint256 rawPrice,
            bool rawSuccess
        ) {
            if (!rawSuccess) {
                return (0, false);
            }

            if (needsUsdConversion[token]) {
                // Convert USD price to ETH price
                try this.getEthUsdPrice() returns (
                    uint256 ethUsdPrice,
                    bool priceSuccess
                ) {
                    if (!priceSuccess || ethUsdPrice == 0) {
                        return (0, false);
                    }

                    // rawPrice is USD price, divide by ETH/USD to get ETH price
                    price = (rawPrice * PRECISION) / ethUsdPrice;
                    return (price, true);
                } catch {
                    return (0, false);
                }
            } else {
                // Already in ETH terms
                return (rawPrice, true);
            }
        } catch {
            return (0, false);
        }
    }

    /**
     * @notice Helper function to get the ETH/USD price
     * @return price ETH/USD price with 18 decimals
     * @return success Whether the price retrieval was successful
     */
    function getEthUsdPrice()
        external
        view
        returns (uint256 price, bool success)
    {
        try AggregatorV3Interface(ethUsdFeed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0 || updatedAt == 0 || roundId == 0) {
                return (0, false);
            }

            uint8 decimals;
            try AggregatorV3Interface(ethUsdFeed).decimals() returns (
                uint8 dec
            ) {
                decimals = dec;
            } catch {
                decimals = 8; // Default for ETH/USD
            }

            // Convert to 18 decimals
            if (decimals == 18) {
                price = uint256(answer);
            } else if (decimals < 18) {
                price = uint256(answer) * (10 ** (18 - decimals));
            } else {
                price = uint256(answer) / (10 ** (decimals - 18));
            }

            return (price, true);
        } catch {
            return (0, false);
        }
    }

    /**
     * @notice Fetches the price from a Uniswap V3 pool
     * @param token The token address
     * @param poolAddress The Uniswap V3 pool address
     * @return price The price with 18 decimals
     * @return success Whether the price retrieval was successful
     */
    function fetchUniswapV3Price(
        address token,
        address poolAddress
    ) external view returns (uint256 price, bool success) {
        try IUniswapV3Pool(poolAddress).slot0() returns (
            uint160 sqrtPriceX96,
            int24,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            if (sqrtPriceX96 == 0) {
                return (0, false);
            }

            // Calculate the price from sqrtPriceX96
            uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
            uint256 Q192 = 1 << 192;
            uint256 rawPrice = (priceX96 * PRECISION) / Q192;

            // Adjust based on token position (token0 or token1)
            if (isToken0[token]) {
                // If token is token0, price = 1/rawPrice
                if (rawPrice == 0) return (0, false);
                price = (PRECISION * PRECISION) / rawPrice;
            } else {
                price = rawPrice;
            }

            return (price, true);
        } catch {
            return (0, false);
        }
    }
}