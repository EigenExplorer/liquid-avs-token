// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../interfaces/IPriceSource.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";

/**
 * @title ChainlinkPriceSource
 * @notice Provides token prices from Chainlink oracles in ETH terms
 * @dev Enhanced to support BTC-denominated tokens with chained conversion
 */
contract ChainlinkPriceSource is IPriceSource {
    mapping(address => AggregatorV3Interface) public tokenFeeds;
    mapping(address => bool) public isBtcDenominated;
    AggregatorV3Interface public btcEthFeed;
    uint256 private constant PRICE_PRECISION = 1e18;
    uint256 private constant STALENESS_PERIOD = 24 hours;

    /**
     * @notice Constructor for standard ETH-denominated tokens
     * @param tokens Array of token addresses
     * @param feeds Array of corresponding price feed addresses
     */
    constructor(address[] memory tokens, address[] memory feeds) {
        require(tokens.length == feeds.length, "Array lengths don't match");
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenFeeds[tokens[i]] = AggregatorV3Interface(feeds[i]);
        }
    }

    /**
     * @notice Initialize BTC-denominated tokens and BTC/ETH feed
     * @param btcTokens Array of BTC-denominated token addresses
     * @param btcFeeds Array of BTC price feed addresses
     * @param _btcEthFeed BTC/ETH price feed address
     */
    function initializeBtcTokens(
        address[] memory btcTokens,
        address[] memory btcFeeds,
        address _btcEthFeed
    ) external {
        require(
            btcTokens.length == btcFeeds.length,
            "Array lengths don't match"
        );
        require(_btcEthFeed != address(0), "BTC/ETH feed required");

        btcEthFeed = AggregatorV3Interface(_btcEthFeed);

        for (uint256 i = 0; i < btcTokens.length; i++) {
            tokenFeeds[btcTokens[i]] = AggregatorV3Interface(btcFeeds[i]);
            isBtcDenominated[btcTokens[i]] = true;
        }
    }

    /**
     * @notice Gets price for a token in ETH terms
     * @param token Token address to get price for
     * @return price Price in ETH with 18 decimals precision
     * @return success Whether the price fetch was successful
     */
    function getPrice(
        address token
    ) external view override returns (uint256 price, bool success) {
        AggregatorV3Interface feed = tokenFeeds[token];

        // Return 0 if feed not configured
        if (address(feed) == address(0)) {
            return (0, false);
        }

        try feed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            // Check for stale data
            if (
                answer <= 0 ||
                updatedAt == 0 ||
                updatedAt + STALENESS_PERIOD < block.timestamp ||
                answeredInRound < roundId
            ) {
                return (0, false);
            }

            // For standard ETH-denominated tokens
            if (!isBtcDenominated[token]) {
                uint8 decimals = feed.decimals();
                price = _normalizePrice(uint256(answer), decimals);
                return (price, true);
            }
            // For BTC-denominated tokens, apply BTC/ETH conversion
            else {
                try btcEthFeed.latestRoundData() returns (
                    uint80 btcRoundId,
                    int256 btcAnswer,
                    uint256 btcStartedAt,
                    uint256 btcUpdatedAt,
                    uint80 btcAnsweredInRound
                ) {
                    // Check BTC/ETH feed for stale data
                    if (
                        btcAnswer <= 0 ||
                        btcUpdatedAt == 0 ||
                        btcUpdatedAt + STALENESS_PERIOD < block.timestamp ||
                        btcAnsweredInRound < btcRoundId
                    ) {
                        return (0, false);
                    }

                    // Convert BTC price to ETH
                    uint8 tokenDecimals = feed.decimals();
                    uint8 btcDecimals = btcEthFeed.decimals();

                    uint256 tokenPriceInBtc = _normalizePrice(
                        uint256(answer),
                        tokenDecimals
                    );
                    uint256 btcPriceInEth = _normalizePrice(
                        uint256(btcAnswer),
                        btcDecimals
                    );

                    // Calculate final price: tokenPriceInBtc * btcPriceInEth
                    price = (tokenPriceInBtc * btcPriceInEth) / PRICE_PRECISION;
                    return (price, true);
                } catch {
                    return (0, false);
                }
            }
        } catch {
            return (0, false);
        }
    }

    /**
     * @dev Normalize price to 18 decimals
     */
    function _normalizePrice(
        uint256 price,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return price / (10 ** (decimals - 18));
        }
        return price;
    }
}