// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/StalenessThreshold.sol";
/**
 * @title TokenRegistryOracle
 * @notice Gas-optimized price oracle with primary/fallback lookup
 * @dev Uses static lookup tables for maximum gas efficiency
 */
contract TokenRegistryOracle is
    ITokenRegistryOracle,
    Initializable,
    AccessControlUpgradeable
{
    // Constants
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    bytes32 public constant TOKEN_CONFIGURATOR_ROLE =
        keccak256("TOKEN_CONFIGURATOR_ROLE");
    uint256 private constant PRECISION = 1e18;
    //uint256 private constant STALENESS_PERIOD = 24 hours;

    // Source types
    uint8 public constant SOURCE_TYPE_CHAINLINK = 1;
    uint8 public constant SOURCE_TYPE_CURVE = 2;
    uint8 public constant SOURCE_TYPE_PROTOCOL = 3;

    // Core dependencies
    ILiquidTokenManager public liquidTokenManager;

    // Price staleness controls
    uint256 private _stalenessSalt;
    uint64 private _emergencyInterval;
    uint64 public lastGlobalPriceUpdate;
    bool private _emergencyMode;

    // Gas-optimized token configuration: packed into single storage slot
    struct TokenConfig {
        uint8 primaryType; // 1=Chainlink, 2=Curve, , 3=Protocol
        uint8 needsArg; // 0=No arg, 1=Needs arg
        uint16 reserved; // For future use
        address primarySource; // Primary price source address
        address fallbackSource; // Fallback source contract address
        bytes4 fallbackFn; // Function selector for fallback
    }

    // Token configuration mapping
    mapping(address => TokenConfig) public tokenConfigs;

    // List of all configured tokens - for batch updates
    address[] public configuredTokens;
    mapping(address => bool) public isConfigured;

    /**
     * @notice Initialize the contract
     */
    function initialize(
        Init memory init,
        uint256 stalenessSalt
    ) public initializer {
        __AccessControl_init();

        require(
            init.initialOwner != address(0) &&
                init.priceUpdater != address(0) &&
                address(init.liquidTokenManager) != address(0) &&
                init.liquidToken != address(0), // <-- add this check to double check new role managnemnt
            "Invalid zero address"
        );

        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(ORACLE_ADMIN_ROLE, init.initialOwner);

        // Grant RATE_UPDATER_ROLE to both priceUpdater and LiquidToken
        _grantRole(RATE_UPDATER_ROLE, init.priceUpdater);
        _grantRole(RATE_UPDATER_ROLE, init.liquidToken);

        _grantRole(TOKEN_CONFIGURATOR_ROLE, address(init.liquidTokenManager));

        liquidTokenManager = init.liquidTokenManager;
        lastGlobalPriceUpdate = uint64(block.timestamp);
        _stalenessSalt = stalenessSalt;
        _emergencyInterval = 12 hours;
        _emergencyMode = false;
    }

    /**
     * @notice Configure a token with its primary and fallback sources
     * @param token Token address
     * @param primaryType Source type (1=Chainlink, 2=Curve, 3=Protocol)
     * @param primarySource Primary source address
     * @param needsArg Whether fallback fn needs args
     * @param fallbackSource Address of the fallback source contract
     * @param fallbackFn Function selector for fallback
     */
    function configureToken(
        address token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn
    ) external onlyRole(TOKEN_CONFIGURATOR_ROLE) {
        require(token != address(0), "Token cannot be zero address");
        require(
            !(primaryType == 0 && primarySource == address(0)),
            "Native tokens must not be configured in Oracle"
        );

        require(
            primarySource != address(0),
            "Primary source cannot be zero address"
        );

        if (fallbackFn != bytes4(0)) {
            require(
                fallbackSource != address(0),
                "Fallback source required when fallback function provided"
            );
        }

        // Store token configuration
        tokenConfigs[token] = TokenConfig({
            primaryType: primaryType,
            needsArg: needsArg,
            reserved: 0,
            primarySource: primarySource,
            fallbackSource: fallbackSource,
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
     * @notice Remove a token configuration from the registry
     * @param token Address of the token to remove
     */
    function removeToken(
        address token
    ) external onlyRole(TOKEN_CONFIGURATOR_ROLE) {
        // Check if token is configured
        if (!isConfigured[token]) {
            return; // Not configured, nothing to remove
        }

        // Clear token configuration
        delete tokenConfigs[token];
        //delete btcTokenPairs[token];

        // Remove from configured tokens array
        uint256 len = configuredTokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (configuredTokens[i] == token) {
                // Swap with last element and pop
                configuredTokens[i] = configuredTokens[len - 1];
                configuredTokens.pop();
                break;
            }
        }

        // Mark token as not configured
        isConfigured[token] = false;

        emit TokenRemoved(token);
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

    function _getDynamicInterval() internal view returns (uint256) {
        if (_emergencyMode) return _emergencyInterval;
        return StalenessThreshold.getHiddenThreshold(_stalenessSalt);
    }
    /**
     * @notice Sets price update interval
     */
    function setPriceUpdateInterval(
        uint256 interval
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        require(interval > 0, "Interval cannot be zero");
        _emergencyInterval = uint64(interval);
        _emergencyMode = true;
        emit UpdateIntervalChanged(_emergencyInterval, interval);
    }

    function disableEmergencyInterval() external onlyRole(ORACLE_ADMIN_ROLE) {
        _emergencyMode = false;
        emit EmergencyIntervalDisabled();
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
     * @notice Check if prices are stale
     */
    function arePricesStale()
        public
        view
        override(ITokenRegistryOracle)
        returns (bool)
    {
        return (block.timestamp >
            uint256(lastGlobalPriceUpdate) + _getDynamicInterval());
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
        override(ITokenRegistryOracle)
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
                } else {
                    // Revert if both fail
                    revert NoFreshPrice(token);
                }
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
        if (config.primaryType == SOURCE_TYPE_CHAINLINK) {
            return _getChainlinkPrice(config.primarySource);
        } else if (config.primaryType == SOURCE_TYPE_CURVE) {
            return _getCurvePrice(config.primarySource);
        } else if (config.primaryType == SOURCE_TYPE_PROTOCOL) {
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
        if (
            config.fallbackFn == bytes4(0) ||
            config.fallbackSource == address(0)
        ) {
            return (0, false);
        }

        return
            _getContractCallPrice(
                token,
                config.fallbackSource,
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
            mstore(ptr, shl(224, 0xfeaf968c))
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
                        mstore(ptr, shl(224, 0x313ce567))
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
            mstore(ptr, shl(224, 0xbb7b8b80))
            let callSuccess := staticcall(gas(), pool, ptr, 4, ptr, 32)

            if and(callSuccess, gt(mload(ptr), 0)) {
                price := mload(ptr)
                success := 1
            }
            // If we didn't get a price yet, try the next method
            if iszero(success) {
                // Try price_oracle() - 0x2df9529b
                mstore(ptr, shl(224, 0x2df9529b))
                callSuccess := staticcall(gas(), pool, ptr, 4, ptr, 32)

                if and(callSuccess, gt(mload(ptr), 0)) {
                    price := mload(ptr)
                    success := 1
                }
            }

            // If we still don't have a price, try the final method
            if iszero(success) {
                // Try get_dy(0,1,1e18) - 0x5e0d443f
                mstore(ptr, shl(224, 0x5e0d443f))
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
    ) external view override(ITokenRegistryOracle) returns (uint256) {
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

    /**
     * @notice helper for addtoken: Get token price from primary source
     * @dev This function exposes the internal _getTokenPrice for testing/setting purposes
     * @param token The token address to get the price for
     * @return price The price in based terms (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function _getTokenPrice_getter(
        address token
    ) external view returns (uint256 price, bool success) {
        return _getTokenPrice(token);
    }

    // =========================================================================
    // TESTING FUNCTIONS - COMMENT OUT FOR PRODUCTION
    // =========================================================================

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
