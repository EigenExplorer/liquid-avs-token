// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {IPriceConstants} from "../interfaces/IPriceConstants.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceConstants} from "./sources/PriceConstants.sol";
/**
 * @title TokenRegistryOracle
 * @notice Gas-optimized price oracle with primary/fallback lookup
 * @dev Uses static lookup tables for maximum gas efficiency
 */
contract TokenRegistryOracle is
    ITokenRegistryOracle,
    IPriceOracle,
    Initializable,
    AccessControlUpgradeable
{
    // Constants
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    uint256 private constant PRECISION = 1e18;
    uint256 private constant STALENESS_PERIOD = 24 hours;

    // Core dependencies
    ILiquidTokenManager public liquidTokenManager;
    IPriceConstants public priceConstants;

    // Price staleness controls
    uint64 private _priceUpdateInterval = 12 hours;
    uint64 public lastGlobalPriceUpdate;

    // Gas-optimized token configuration: packed into single storage slot
    struct TokenConfig {
        uint8 primaryType; // 1=Chainlink, 2=Curve, 3=BTC-chained, 4=Protocol
        uint8 needsArg; // 0=No arg, 1=Needs arg
        uint16 reserved; // For future use
        address primarySource; // Primary price source address
        bytes4 fallbackFn; // Function selector for fallback
    }

    // Token configuration mapping
    mapping(address => TokenConfig) public tokenConfigs;

    // List of all configured tokens - for batch updates
    address[] public configuredTokens;
    mapping(address => bool) public isConfigured;

    // Chainlink specific storage
    mapping(address => address) public btcTokenPairs; // For BTC-denominated tokens
    address public BTCETHFEED;

    /**
     * @notice Initialize the contract
     */
    function initialize(Init memory init) public initializer {
        __AccessControl_init();

        require(
            init.initialOwner != address(0) &&
                init.priceUpdater != address(0) &&
                address(init.liquidTokenManager) != address(0),
            "Invalid zero address"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(ORACLE_ADMIN_ROLE, init.initialOwner);
        _grantRole(RATE_UPDATER_ROLE, init.priceUpdater);

        liquidTokenManager = init.liquidTokenManager;
        priceConstants = IPriceConstants(address(new PriceConstants()));
        lastGlobalPriceUpdate = uint64(block.timestamp);

        // Set up BTC price feed for BTC-denominated tokens
        BTCETHFEED = priceConstants.CHAINLINK_BTC_ETH();
    }

    /**
     * @notice Configure a token with its primary and fallback sources
     * @param token Token address
     * @param primaryType Source type (1=Chainlink, 2=Curve, 3=BTC-chained, 4=Protocol)
     * @param primarySource Primary source address
     * @param needsArg Whether fallback fn needs args
     * @param fallbackFn Function selector for fallback
     */
    function configureToken(
        address token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        bytes4 fallbackFn
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(token != address(0), "Token cannot be zero address");

        // Store token configuration
        tokenConfigs[token] = TokenConfig({
            primaryType: primaryType,
            needsArg: needsArg,
            reserved: 0,
            primarySource: primarySource,
            fallbackFn: fallbackFn
        });

        // Add to configured tokens list if new
        if (!isConfigured[token]) {
            configuredTokens.push(token);
            isConfigured[token] = true;
        }

        emit TokenSourceSet(token, primarySource);
    }

    /**
     * @notice Configure BTC-denominated token with chained feeds
     * @param token BTC-denominated token
     * @param btcFeed Token/BTC price feed
     * @param fallbackFn Fallback function selector
     */
    function configureBtcToken(
        address token,
        address btcFeed,
        bytes4 fallbackFn
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(
            token != address(0) && btcFeed != address(0),
            "Invalid address"
        );
        require(BTCETHFEED != address(0), "BTC/ETH feed not set");

        // Set up token configuration as BTC-chained
        tokenConfigs[token] = TokenConfig({
            primaryType: uint8(priceConstants.SOURCE_TYPE_BTC_CHAINED()),
            needsArg: 0,
            reserved: 0,
            primarySource: btcFeed,
            fallbackFn: fallbackFn
        });

        // Store BTC pair for lookup
        btcTokenPairs[token] = btcFeed;

        // Add to configured tokens
        if (!isConfigured[token]) {
            configuredTokens.push(token);
            isConfigured[token] = true;
        }

        emit TokenSourceSet(token, btcFeed);
    }

    /**
     * @notice Sets up all tokens with their primary/fallback sources
     * @dev Call after initialization to configure all tokens at once
     */
    function configureAllTokens() external onlyRole(ORACLE_ADMIN_ROLE) {
        // Configure Chainlink-primary tokens
        _configureToken(
            priceConstants.RETH(),
            priceConstants.SOURCE_TYPE_CHAINLINK(),
            priceConstants.CHAINLINK_RETH_ETH(),
            0, // No arg
            priceConstants.SELECTOR_GET_EXCHANGE_RATE()
        );

        _configureToken(
            priceConstants.STETH(),
            priceConstants.SOURCE_TYPE_CHAINLINK(),
            priceConstants.CHAINLINK_STETH_ETH(),
            1, // Needs arg
            priceConstants.SELECTOR_GET_POOLED_ETH_BY_SHARES()
        );

        _configureToken(
            priceConstants.CBETH(),
            priceConstants.SOURCE_TYPE_CHAINLINK(),
            priceConstants.CHAINLINK_CBETH_ETH(),
            0, // No arg
            priceConstants.SELECTOR_EXCHANGE_RATE()
        );

        _configureToken(
            priceConstants.METH(),
            priceConstants.SOURCE_TYPE_CHAINLINK(),
            priceConstants.CHAINLINK_METH_ETH(),
            1, // Needs arg
            priceConstants.SELECTOR_METH_TO_ETH()
        );

        _configureToken(
            priceConstants.OETH(),
            priceConstants.SOURCE_TYPE_CHAINLINK(),
            priceConstants.CHAINLINK_OETH_ETH(),
            1, // Needs arg
            priceConstants.SELECTOR_CONVERT_TO_ASSETS()
        );

        // Configure BTC-denominated tokens
        _configureBtcToken(
            priceConstants.UNIBTC(),
            priceConstants.CHAINLINK_UNIBTC_BTC(),
            priceConstants.SELECTOR_GET_RATE()
        );

        _configureBtcToken(
            priceConstants.STBTC(),
            priceConstants.CHAINLINK_STBTC_BTC(),
            priceConstants.SELECTOR_GET_RATE()
        );

        // Configure Curve-primary tokens
        _configureToken(
            priceConstants.LSETH(),
            priceConstants.SOURCE_TYPE_CURVE(),
            priceConstants.LSETH_CURVE_POOL(),
            1, // Needs arg
            priceConstants.SELECTOR_UNDERLYING_BALANCE_FROM_SHARES()
        );

        _configureToken(
            priceConstants.ETHx(),
            priceConstants.SOURCE_TYPE_CURVE(),
            priceConstants.ETHx_CURVE_POOL(),
            0, // No arg
            priceConstants.SELECTOR_GET_EXCHANGE_RATE()
        );

        _configureToken(
            priceConstants.SFRxETH(),
            priceConstants.SOURCE_TYPE_PROTOCOL(), // Direct contract call
            priceConstants.SFRxETH_CONTRACT(),
            1, // Needs arg
            priceConstants.SELECTOR_CONVERT_TO_ASSETS()
        );

        _configureToken(
            priceConstants.ANKR_ETH(),
            priceConstants.SOURCE_TYPE_CURVE(),
            priceConstants.ANKR_ETH_CURVE_POOL(),
            0, // No arg
            priceConstants.SELECTOR_RATIO()
        );

        _configureToken(
            priceConstants.OSETH(),
            priceConstants.SOURCE_TYPE_CURVE(),
            priceConstants.OSETH_CURVE_POOL(),
            1, // Needs arg
            priceConstants.SELECTOR_CONVERT_TO_ASSETS()
        );

        _configureToken(
            priceConstants.SWETH(),
            priceConstants.SOURCE_TYPE_CURVE(),
            priceConstants.SWETH_CURVE_POOL(),
            0, // No arg
            priceConstants.SELECTOR_SWETH_TO_ETH_RATE()
        );

        _configureToken(
            priceConstants.WSTETH(),
            priceConstants.SOURCE_TYPE_CURVE(),
            priceConstants.WSTETH_CONTRACT(),
            0, // No arg
            priceConstants.SELECTOR_STETH_PER_TOKEN()
        );
        _configureToken(
            priceConstants.WBETH(),
            priceConstants.SOURCE_TYPE_PROTOCOL(), // Direct contract call
            priceConstants.WBETH_CONTRACT(),
            0, // No arg needed
            priceConstants.SELECTOR_EXCHANGE_RATE()
        );
    }

    /**
     * @notice Internal helper for configuring tokens
     */
    function _configureToken(
        address token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        bytes4 fallbackFn
    ) internal {
        tokenConfigs[token] = TokenConfig({
            primaryType: primaryType,
            needsArg: needsArg,
            reserved: 0,
            primarySource: primarySource,
            fallbackFn: fallbackFn
        });

        if (!isConfigured[token]) {
            configuredTokens.push(token);
            isConfigured[token] = true;
        }
    }

    /**
     * @notice Internal helper for configuring BTC-denominated tokens
     */
    function _configureBtcToken(
        address token,
        address btcFeed,
        bytes4 fallbackFn
    ) internal {
        tokenConfigs[token] = TokenConfig({
            primaryType: uint8(priceConstants.SOURCE_TYPE_BTC_CHAINED()),
            needsArg: 0,
            reserved: 0,
            primarySource: btcFeed,
            fallbackFn: fallbackFn
        });

        btcTokenPairs[token] = btcFeed;

        if (!isConfigured[token]) {
            configuredTokens.push(token);
            isConfigured[token] = true;
        }
    }

    /**
     * @notice Updates a token's rate manually
     */
    function updateRate(
        IERC20 token,
        uint256 newRate
    ) external onlyRole(RATE_UPDATER_ROLE) {
        _updateTokenRate(token, newRate);
    }

    /**
     * @notice Updates rates for multiple tokens manually
     */
    function batchUpdateRates(
        IERC20[] calldata tokens,
        uint256[] calldata newRates
    ) external onlyRole(RATE_UPDATER_ROLE) {
        require(tokens.length == newRates.length, "Array length mismatch");

        uint256 len = tokens.length;
        unchecked {
            for (uint256 i = 0; i < len; i++) {
                _updateTokenRate(tokens[i], newRates[i]);
            }
        }
    }

    /**
     * @notice Sets price update interval
     */
    function setPriceUpdateInterval(
        uint256 interval
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(interval > 0, "Interval cannot be zero");
        uint256 oldInterval = _priceUpdateInterval;
        _priceUpdateInterval = uint64(interval);
        emit UpdateIntervalChanged(oldInterval, interval);
    }

    /**
     * @notice Get current token rate
     */
    function getRate(IERC20 token) external view returns (uint256) {
        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager
            .getTokenInfo(token);
        return tokenInfo.pricePerUnit;
    }

    /**
     * @notice Gets configured update interval
     * @return Interval in seconds
     */
    function priceUpdateInterval() external view override returns (uint256) {
        return _priceUpdateInterval;
    }

    /**
     * @notice Check if prices are stale
     */
    function arePricesStale()
        public
        view
        override(IPriceOracle, ITokenRegistryOracle)
        returns (bool)
    {
        return (block.timestamp >
            uint256(lastGlobalPriceUpdate) + uint256(_priceUpdateInterval));
    }

    /**
     * @notice Get last price update timestamp
     */
    function lastPriceUpdate() external view returns (uint256) {
        return lastGlobalPriceUpdate;
    }

    /**
     * @notice Update all token prices if stale
     */
    function updateAllPricesIfNeeded()
        external
        override(IPriceOracle, ITokenRegistryOracle)
        returns (bool)
    {
        // Skip if prices are fresh
        if (!arePricesStale()) {
            return false;
        }

        // Check authorization
        if (
            !hasRole(RATE_UPDATER_ROLE, msg.sender) &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender) &&
            !hasRole(ORACLE_ADMIN_ROLE, msg.sender)
        ) {
            revert InvalidUpdater(msg.sender);
        }

        // Process all token prices
        _updateAllPrices();

        // Update timestamp
        lastGlobalPriceUpdate = uint64(block.timestamp);
        emit GlobalPricesUpdated(msg.sender, block.timestamp);

        return true;
    }

    /**
     * @notice Fetch and update prices for all configured tokens
     */
    function _updateAllPrices() internal {
        uint256 len = configuredTokens.length;

        for (uint256 i = 0; i < len; i++) {
            address token = configuredTokens[i];
            (uint256 price, bool success) = _getTokenPrice(token);

            if (success && price > 0) {
                _updateTokenRate(IERC20(token), price);
            } else {
                // Try fallback if available
                (
                    uint256 fallbackPrice,
                    bool fallbackSuccess
                ) = _getFallbackPrice(token);
                if (fallbackSuccess && fallbackPrice > 0) {
                    _updateTokenRate(IERC20(token), fallbackPrice);
                }
                // Otherwise, keep existing price
            }
        }
    }

    /**
     * @notice Internal function to update token rate
     */
    function _updateTokenRate(IERC20 token, uint256 newRate) internal {
        ILiquidTokenManager manager = liquidTokenManager;
        uint256 oldRate = manager.getTokenInfo(token).pricePerUnit;
        manager.updatePrice(token, newRate);
        emit TokenRateUpdated(token, oldRate, newRate, msg.sender);
    }

    /**
     * @notice Get token price from primary source
     */
    function _getTokenPrice(
        address token
    ) internal view returns (uint256 price, bool success) {
        TokenConfig memory config = tokenConfigs[token];

        // Skip if not configured
        if (config.primarySource == address(0)) {
            return (0, false);
        }

        // Get price based on source type
        if (
            config.primaryType == uint8(priceConstants.SOURCE_TYPE_CHAINLINK())
        ) {
            return _getChainlinkPrice(config.primarySource);
        } else if (
            config.primaryType == uint8(priceConstants.SOURCE_TYPE_CURVE())
        ) {
            return _getCurvePrice(config.primarySource);
        } else if (
            config.primaryType ==
            uint8(priceConstants.SOURCE_TYPE_BTC_CHAINED())
        ) {
            return _getBtcChainedPrice(token, config.primarySource);
        } else if (
            config.primaryType == uint8(priceConstants.SOURCE_TYPE_PROTOCOL())
        ) {
            // Use protocol rate directly
            return
                _getContractCallPrice(
                    token,
                    config.primarySource,
                    config.fallbackFn,
                    config.needsArg
                );
        }

        return (0, false);
    }

    /**
     * @notice Get token price from fallback source (protocol call)
     */
    function _getFallbackPrice(
        address token
    ) internal view returns (uint256 price, bool success) {
        TokenConfig memory config = tokenConfigs[token];

        // Skip if no fallback
        if (config.fallbackFn == bytes4(0)) {
            return (0, false);
        }

        // Get token contract from constants
        address contractAddr;

        if (token == priceConstants.RETH())
            contractAddr = priceConstants.RETH_CONTRACT();
        else if (token == priceConstants.STETH())
            contractAddr = priceConstants.STETH_CONTRACT();
        else if (token == priceConstants.CBETH())
            contractAddr = priceConstants.CBETH_CONTRACT();
        else if (token == priceConstants.ETHx())
            contractAddr = priceConstants.ETHx_CONTRACT();
        else if (token == priceConstants.OSETH())
            contractAddr = priceConstants.OSETH_CONTRACT();
        else if (token == priceConstants.SFRxETH())
            contractAddr = priceConstants.SFRxETH_CONTRACT();
        else if (token == priceConstants.SWETH())
            contractAddr = priceConstants.SWETH_CONTRACT();
        else if (token == priceConstants.WSTETH())
            contractAddr = priceConstants.WSTETH_CONTRACT();
        else if (token == priceConstants.ANKR_ETH())
            contractAddr = priceConstants.ANKR_ETH_CONTRACT();
        else if (token == priceConstants.LSETH())
            contractAddr = priceConstants.LSETH_CONTRACT();
        else if (token == priceConstants.OETH())
            contractAddr = priceConstants.OETH_CONTRACT();
        else if (token == priceConstants.METH())
            contractAddr = priceConstants.METH_CONTRACT();
        else if (token == priceConstants.UNIBTC())
            contractAddr = priceConstants.UNIBTC_CONTRACT();
        else if (token == priceConstants.WBETH())
            contractAddr = priceConstants.WBETH_CONTRACT();
        else if (token == priceConstants.STBTC())
            contractAddr = priceConstants.STBTC_ACCOUNTANT_CONTRACT();
        else return (0, false);

        return
            _getContractCallPrice(
                token,
                contractAddr,
                config.fallbackFn,
                config.needsArg
            );
    }

    /**
     * @notice Get price from Chainlink with maximum gas efficiency
     */
    function _getChainlinkPrice(
        address feed
    ) internal view returns (uint256 price, bool success) {
        if (feed == address(0)) return (0, false);

        // Use assembly for Chainlink calls
        assembly {
            // Free memory pointer
            let ptr := mload(0x40)

            // Call latestRoundData() - 0xfeaf968c
            mstore(ptr, 0xfeaf968c)
            let callSuccess := staticcall(
                gas(), // Gas
                feed, // Target
                ptr, // Input
                4, // Input size
                ptr, // Output
                160 // 5 return values: uint80,int256,uint256,uint256,uint80
            )

            // Process result
            if callSuccess {
                let roundId := mload(ptr)
                let answer := mload(add(ptr, 32))
                // Skip startedAt at ptr+64
                let updatedAt := mload(add(ptr, 96))
                let answeredInRound := mload(add(ptr, 128))

                // Check validity
                if and(
                    and(gt(answer, 0), gt(updatedAt, 0)),
                    iszero(lt(answeredInRound, roundId))
                ) {
                    // Check staleness - invert the condition to handle fresh prices first
                    if iszero(lt(add(updatedAt, 86400), timestamp())) {
                        // Call decimals() - 0x313ce567
                        mstore(ptr, 0x313ce567)
                        let decSuccess := staticcall(
                            gas(),
                            feed,
                            ptr,
                            4, // Input size
                            ptr,
                            32 // Output size
                        )

                        let decimals := 8 // Default
                        if decSuccess {
                            decimals := and(mload(ptr), 0xff) // uint8
                        }

                        // Convert to 18 decimals
                        switch lt(decimals, 18)
                        case 1 {
                            // dec < 18: multiply
                            price := mul(answer, exp(10, sub(18, decimals)))
                        }
                        case 0 {
                            switch gt(decimals, 18)
                            case 1 {
                                // dec > 18: divide
                                price := div(answer, exp(10, sub(decimals, 18)))
                            }
                            default {
                                // dec == 18: no adjustment
                                price := answer
                            }
                        }

                        success := 1
                    }
                    // Handle stale prices in a separate condition
                    if lt(add(updatedAt, 86400), timestamp()) {
                        success := 0
                    }
                }
            }
        }
    }

    /**
     * @notice Get price from Curve with maximum gas efficiency
     */
    function _getCurvePrice(
        address pool
    ) internal view returns (uint256 price, bool success) {
        if (pool == address(0)) return (0, false);

        assembly {
            // Free memory pointer
            let ptr := mload(0x40)

            // Try get_virtual_price() - 0xbb7b8b80
            mstore(ptr, 0xbb7b8b80)
            let callSuccess := staticcall(gas(), pool, ptr, 4, ptr, 32)

            if and(callSuccess, gt(mload(ptr), 0)) {
                price := mload(ptr)
                success := 1
            }
            // If we didn't get a price yet, try the next method
            if iszero(success) {
                // Try price_oracle() - 0x2df9529b
                mstore(ptr, 0x2df9529b)
                callSuccess := staticcall(gas(), pool, ptr, 4, ptr, 32)

                if and(callSuccess, gt(mload(ptr), 0)) {
                    price := mload(ptr)
                    success := 1
                }
            }

            // If we still don't have a price, try the final method
            if iszero(success) {
                // Try get_dy(0,1,1e18) - 0x5e0d443f
                mstore(ptr, 0x5e0d443f) // Function selector
                mstore(add(ptr, 4), 0) // i = 0 (int128)
                mstore(add(ptr, 36), 1) // j = 1 (int128)
                // Correct hex for 1e18 (use full 32 bytes)
                mstore(add(ptr, 68), 0xDE0B6B3A7640000)

                callSuccess := staticcall(
                    gas(),
                    pool,
                    ptr,
                    100, // Input size
                    ptr,
                    32 // Output size
                )

                if and(callSuccess, gt(mload(ptr), 0)) {
                    price := mload(ptr)
                    success := 1
                }
            }
        }
    }
    /**
     * @notice Get price from BTC-chained feeds
     */
    function _getBtcChainedPrice(
        address token,
        address btcFeed
    ) internal view returns (uint256 price, bool success) {
        if (btcFeed == address(0) || BTCETHFEED == address(0)) {
            return (0, false);
        }

        // Get token-BTC price
        (uint256 tokenBtcPrice, bool success1) = _getChainlinkPrice(btcFeed);
        if (!success1 || tokenBtcPrice == 0) {
            return (0, false);
        }

        // Get BTC-ETH price
        (uint256 btcEthPrice, bool success2) = _getChainlinkPrice(BTCETHFEED);
        if (!success2 || btcEthPrice == 0) {
            return (0, false);
        }

        // Calculate: tokenBtcPrice * btcEthPrice / PRECISION
        price = (tokenBtcPrice * btcEthPrice) / PRECISION;
        return (price, true);
    }
    /**
     * @notice Get price from contract call with maximum gas efficiency
     */
    function _getContractCallPrice(
        address token,
        address contractAddr,
        bytes4 selector,
        uint8 needsArg
    ) internal view returns (uint256 price, bool success) {
        if (contractAddr == address(0) || selector == bytes4(0)) {
            return (0, false);
        }

        // Use assembly for maximum gas efficiency
        assembly {
            // Free memory pointer
            let ptr := mload(0x40)

            // Store function selector at memory position ptr
            mstore(ptr, selector)

            // Prepare call data parameters
            let callSize := 4 // Selector size

            // If the function requires an argument (1e18)
            if needsArg {
                // Correct hex for 1e18
                mstore(add(ptr, 4), 0xDE0B6B3A7640000)
                callSize := 36 // Selector (4) + argument (32)
            }

            // Make the static call
            success := staticcall(
                gas(), // Forward all available gas
                contractAddr, // Target contract
                ptr, // Call data pointer
                callSize, // Call data size
                ptr, // Output location (reuse memory)
                32 // Output size (single uint256)
            )

            // Process the result
            if success {
                // Load the returned value
                price := mload(ptr)
                // Update success: true only if price > 0
                success := gt(price, 0)
            }
        }
    }
    /**
     * @notice Get token price directly (for external calls)
     */
    function getTokenPrice(
        address token
    ) external view override(IPriceOracle, ITokenRegistryOracle) returns (uint256) {
        (uint256 price, bool success) = _getTokenPrice(token);

        if (success && price > 0) {
            return price;
        }

        // Try fallback
        (uint256 fallbackPrice, bool fallbackSuccess) = _getFallbackPrice(
            token
        );
        if (fallbackSuccess && fallbackPrice > 0) {
            return fallbackPrice;
        }

        // Return stored price if available
        return liquidTokenManager.getTokenInfo(IERC20(token)).pricePerUnit;
    }

    // =========================================================================
    // TESTING FUNCTIONS - COMMENT OUT FOR PRODUCTION
    // =========================================================================

    /**
     * @notice TEST ONLY: Get token price from primary source
     * @dev This function exposes the internal _getTokenPrice for testing purposes
     * @param token The token address to get the price for
     * @return price The price in ETH terms (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function _getTokenPrice_exposed(
        address token
    ) external view returns (uint256 price, bool success) {
        return _getTokenPrice(token);
    }

    /**
     * @notice TEST ONLY: Get token price from fallback source
     * @dev This function exposes the internal _getFallbackPrice for testing purposes
     * @param token The token address to get the fallback price for
     * @return price The fallback price in ETH terms (18 decimals)
     * @return success Whether the fallback price fetch was successful
     */
    function _getFallbackPrice_exposed(
        address token
    ) external view returns (uint256 price, bool success) {
        return _getFallbackPrice(token);
    }

    /**
     * @notice TEST ONLY: Get price for BTC-denominated token
     * @dev This function exposes the internal _getBtcChainedPrice for testing purposes
     * @param token The BTC-denominated token address
     * @param btcFeed The BTC price feed address
     * @return price The price in ETH terms (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function _getBtcChainedPrice_exposed(
        address token,
        address btcFeed
    ) external view returns (uint256 price, bool success) {
        return _getBtcChainedPrice(token, btcFeed);
    }

    /**
     * @notice TEST ONLY: Get Chainlink price
     * @dev This function exposes the internal _getChainlinkPrice for testing purposes
     * @param feed The Chainlink price feed address
     * @return price The price from Chainlink (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function _getChainlinkPrice_exposed(
        address feed
    ) external view returns (uint256 price, bool success) {
        return _getChainlinkPrice(feed);
    }

    /**
     * @notice TEST ONLY: Get Curve price
     * @dev This function exposes the internal _getCurvePrice for testing purposes
     * @param pool The Curve pool address
     * @return price The price from Curve (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function _getCurvePrice_exposed(
        address pool
    ) external view returns (uint256 price, bool success) {
        return _getCurvePrice(pool);
    }

    /**
     * @notice TEST ONLY: Get price from contract call
     * @dev This function exposes the internal _getContractCallPrice for testing purposes
     * @param token The token address
     * @param contractAddr The contract to call
     * @param selector The function selector
     * @param needsArg Whether the function needs an argument
     * @return price The price from the contract call (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function _getContractCallPrice_exposed(
        address token,
        address contractAddr,
        bytes4 selector,
        uint8 needsArg
    ) external view returns (uint256 price, bool success) {
        return _getContractCallPrice(token, contractAddr, selector, needsArg);
    }
}