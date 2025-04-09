// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../interfaces/IPriceSource.sol";

/**
 * @title FallbackPriceSource
 * @notice Price source that tries multiple sources in sequence until a valid price is found
 */
contract FallbackPriceSource is IPriceSource {
    // Array of price sources in priority order for a token
    mapping(address => address[]) public sources;

    // Maximum sources allowed per token
    uint8 public constant MAX_SOURCES = 5;

    // Events
    event SourcesConfigured(address indexed token, address[] sources);
    event PriceObtained(
        address indexed token,
        uint8 sourceIndex,
        uint256 price
    );
    event AllSourcesFailed(address indexed token);

    /**
     * @notice Configure price sources for a specific token
     * @param token Token address
     * @param _sources Array of price source contracts in priority order
     */
    function configureSources(
        address token,
        address[] calldata _sources
    ) external {
        require(_sources.length > 0, "At least one source required");
        require(_sources.length <= MAX_SOURCES, "Too many sources");

        delete sources[token];
        for (uint8 i = 0; i < _sources.length; i++) {
            require(_sources[i] != address(0), "Invalid source address");
            sources[token].push(_sources[i]);
        }

        emit SourcesConfigured(token, _sources);
    }

    /**
     * @notice Get price from the first working source
     * @param token Token address
     * @return price Token price in ETH terms (18 decimals)
     * @return success Whether any source provided a valid price
     */
    function getPrice(
        address token
    ) external view override returns (uint256 price, bool success) {
        address[] memory tokenSources = sources[token];

        if (tokenSources.length == 0) {
            return (0, false);
        }

        // Try each source in order until one succeeds
        for (uint8 i = 0; i < tokenSources.length; i++) {
            try IPriceSource(tokenSources[i]).getPrice(token) returns (
                uint256 _price,
                bool _success
            ) {
                if (_success && _price > 0) {
                    return (_price, true);
                }
            } catch {
                // This source failed, try the next one
                continue;
            }
        }

        // All sources failed
        return (0, false);
    }

    /**
     * @notice Get the number of sources for a token
     */
    function getSourceCount(address token) external view returns (uint256) {
        return sources[token].length;
    }

    /**
     * @notice Get source at specific index
     */
    function getSourceAt(
        address token,
        uint8 index
    ) external view returns (address) {
        require(index < sources[token].length, "Index out of bounds");
        return sources[token][index];
    }

    /**
     * @notice Get all sources for a token
     */
    function getAllSources(
        address token
    ) external view returns (address[] memory) {
        return sources[token];
    }
}