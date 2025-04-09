// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IPriceSource} from "../../interfaces/IPriceSource.sol";

/**
 * @title ProtocolRateSource
 * @notice Gets ETH-denominated prices from protocol-specific rate functions
 */
contract ProtocolRateSource is IPriceSource {
    mapping(address => bytes4) public tokenToSelector;
    mapping(address => address) public tokenToTarget;

    uint256 private constant PRECISION = 1e18;

    /**
     * @notice Constructor to set up token to function mappings
     * @param tokens Array of token addresses
     * @param selectors Array of corresponding function selectors
     * @param targets Array of target contracts to call
     */
    constructor(
        address[] memory tokens,
        bytes4[] memory selectors,
        address[] memory targets
    ) {
        require(
            tokens.length == selectors.length &&
                selectors.length == targets.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            tokenToSelector[tokens[i]] = selectors[i];
            tokenToTarget[tokens[i]] = targets[i];
        }
    }

    /**
     * @notice Gets the ETH price for a token from protocol-specific function
     * @param token The token address to get the price for
     * @return price The price with 18 decimals
     * @return success Whether the price retrieval was successful
     */
    function getPrice(
        address token
    ) external view override returns (uint256 price, bool success) {
        bytes4 selector = tokenToSelector[token];
        address target = tokenToTarget[token];

        if (selector == bytes4(0) || target == address(0)) {
            return (0, false);
        }

        // Call the protocol-specific function
        (bool callSuccess, bytes memory data) = target.staticcall(
            abi.encodeWithSelector(selector)
        );

        if (callSuccess && data.length >= 32) {
            price = abi.decode(data, (uint256));
            return (price, price > 0);
        }

        return (0, false);
    }
}