// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceSource} from "../../interfaces/IPriceSource.sol";

/**
 * @title CurvePriceSource
 * @notice Gets ETH-denominated prices from Curve pools
 */
contract CurvePriceSource is IPriceSource {
    mapping(address => address) public poolAddresses;

    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Constructor to set up token to pool mappings
     * @param tokens Array of token addresses
     * @param pools Array of corresponding Curve pool addresses
     */
    constructor(address[] memory tokens, address[] memory pools) {
        require(tokens.length == pools.length, "Array length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            poolAddresses[tokens[i]] = pools[i];
        }
    }

    /**
     * @notice Gets the ETH price for a token from Curve pool
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

        // For Curve pools that directly involve ETH
        try this.getCurveExchangeRate(poolAddress) returns (uint256 rate) {
            if (rate == 0) {
                return (0, false);
            }

            return (rate, true);
        } catch {
            return (0, false);
        }
    }

    /**
     * @notice Gets the exchange rate from a Curve pool
     * @param poolAddress The Curve pool address
     * @return The exchange rate with 18 decimals
     */
    function getCurveExchangeRate(
        address poolAddress
    ) external view returns (uint256) {
        // Try various Curve pool interfaces for price

        // First attempt: get_virtual_price
        (bool success1, bytes memory data1) = poolAddress.staticcall(
            abi.encodeWithSignature("get_virtual_price()")
        );

        if (success1 && data1.length >= 32) {
            return abi.decode(data1, (uint256));
        }

        // Second attempt: price_oracle
        (bool success2, bytes memory data2) = poolAddress.staticcall(
            abi.encodeWithSignature("price_oracle()")
        );

        if (success2 && data2.length >= 32) {
            return abi.decode(data2, (uint256));
        }

        // Third attempt: get_dy with common indices
        (bool success3, bytes memory data3) = poolAddress.staticcall(
            abi.encodeWithSignature(
                "get_dy(int128,int128,uint256)",
                0,
                1,
                PRECISION
            )
        );

        if (success3 && data3.length >= 32) {
            return abi.decode(data3, (uint256));
        }

        return 0;
    }
}