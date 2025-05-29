// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/StalenessThreshold.sol";

interface ICurvePool {
    function remove_liquidity(uint256, uint256[] calldata) external;
}
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
    mapping(address => bool) public isConfigured;
    mapping(address => bool) public requiresReentrancyLock;
    // List of all configured tokens - for batch updates
    address[] public configuredTokens;

    /// @dev Prevents the implementation contract from being initialized
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     */
    function initialize(
        Init memory init,
        uint256 stalenessSalt
    ) public initializer {
        __AccessControl_init();

        if (
            init.initialOwner == address(0) ||
            init.priceUpdater == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            init.liquidToken == address(0)
        ) {
            revert InvalidZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(ORACLE_ADMIN_ROLE, init.initialOwner);

        // Grant RATE_UPDATER_ROLE to both priceUpdater and LiquidToken
        _grantRole(RATE_UPDATER_ROLE, init.priceUpdater);
        _grantRole(RATE_UPDATER_ROLE, init.liquidToken);

        _grantRole(TOKEN_CONFIGURATOR_ROLE, address(init.liquidTokenManager));

        liquidTokenManager = init.liquidTokenManager;
        lastGlobalPriceUpdate = uint64(block.timestamp);
        _stalenessSalt = stalenessSalt;
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
        if (token == address(0)) revert TokenCannotBeZeroAddress();
        if (primaryType == 0 && primarySource == address(0))
            revert NativeTokensNotConfigurable();

        if (primarySource == address(0)) revert PrimarySourceCannotBeZero();

        if (fallbackFn != bytes4(0)) {
            if (fallbackSource == address(0)) revert FallbackSourceRequired();
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
        if (tokens.length != newRates.length) revert ArrayLengthMismatch();

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
        if (interval == 0) revert IntervalCannotBeZero();
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
    ) internal returns (uint256 price, bool success) {
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

        // Compute staleness threshold (as in your model)
        uint256 staleness = _emergencyMode
            ? _emergencyInterval
            : StalenessThreshold.getHiddenThreshold(_stalenessSalt);

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, shl(224, 0xfeaf968c)) // left-align selector // latestRoundData()

            let callSuccess := staticcall(gas(), feed, ptr, 4, ptr, 160)

            if callSuccess {
                let roundId := mload(ptr)
                let answer := mload(add(ptr, 32))
                let updatedAt := mload(add(ptr, 96))
                let answeredInRound := mload(add(ptr, 128))

                // Check validity
                if and(
                    and(gt(answer, 0), gt(updatedAt, 0)),
                    iszero(lt(answeredInRound, roundId))
                ) {
                    // Check staleness: block.timestamp > updatedAt + staleness
                    // If NOT stale, proceed
                    if iszero(gt(timestamp(), add(updatedAt, staleness))) {
                        // Call decimals()
                        mstore(ptr, shl(224, 0x313ce567)) // selector for decimals()
                        let decSuccess := staticcall(
                            gas(),
                            feed,
                            ptr,
                            4,
                            ptr,
                            32
                        )
                        let decimals := 8
                        if decSuccess {
                            decimals := and(mload(ptr), 0xff)
                        }

                        switch lt(decimals, 18)
                        case 1 {
                            price := mul(answer, exp(10, sub(18, decimals)))
                        }
                        case 0 {
                            switch gt(decimals, 18)
                            case 1 {
                                price := div(answer, exp(10, sub(decimals, 18)))
                            }
                            default {
                                price := answer
                            }
                        }

                        success := 1
                    }
                    // If stale, success remains 0
                }
            }
        }
    }

    /**
     * @notice Get price from Curve with maximum gas efficiency
     * @dev If requiresReentrancyLock[pool] is true, first trigger remove_liquidity(0, [0,0])
     *      to engage Curve’s nonReentrant lock, then fall back to three staticcalls:
     *      1) get_virtual_price()
     *      2) price_oracle()
     *      3) get_dy(0,1,1e18)
     */
    function _getCurvePrice(
        address pool
    ) internal returns (uint256 price, bool success) {
        if (pool == address(0)) return (0, false);

        // Engage nonReentrant lock if required
        if (requiresReentrancyLock[pool]) {
            // Zero-liquidity call to check reentrancy context
            try ICurvePool(pool).remove_liquidity(0, new uint256[](2)) {
                // If this succeeds, we're not in a reentrancy context -> safe to proceed
            } catch {
                // Revert means we're in a reentrancy context -> unsafe
                revert("CurveOracle: pool re-entrancy");
            }
        }

        assembly {
            let ptr := mload(0x40)

            // Try get_virtual_price
            mstore(ptr, shl(224, 0xbb7b8b80))
            let ok := staticcall(gas(), pool, ptr, 4, ptr, 32)
            if and(ok, gt(mload(ptr), 0)) {
                price := mload(ptr)
                success := 1
            }

            // Try price_oracle
            if iszero(success) {
                mstore(ptr, shl(224, 0x86fc88d3))
                ok := staticcall(gas(), pool, ptr, 4, ptr, 32)
                if and(ok, gt(mload(ptr), 0)) {
                    price := mload(ptr)
                    success := 1
                }
            }

            // Try get_dy(0,1,1e18)
            if iszero(success) {
                mstore(ptr, shl(224, 0x5e0d443f))
                mstore(add(ptr, 4), 0)
                mstore(add(ptr, 36), 1)
                mstore(add(ptr, 68), 0x0DE0B6B3A7640000)
                ok := staticcall(gas(), pool, ptr, 100, ptr, 32)
                if and(ok, gt(mload(ptr), 0)) {
                    price := mload(ptr)
                    success := 1
                }
            }
        }
        return (price, success);
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
    ) external override(ITokenRegistryOracle) returns (uint256) {
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
    ) external returns (uint256 price, bool success) {
        return _getTokenPrice(token);
    }

    //EXPOSED xposed one only for testing it should be removed for prouction
    /**
     * @notice Get price from Curve pool directly (for testing/external calls)
     * @dev This function exposes the internal _getCurvePrice for testing purposes
     * @param pool The Curve pool address to get the price from
     * @return price The price in ETH terms (18 decimals)
     * @return success Whether the price fetch was successful
     */
    function getCurvePrice(
        address pool
    ) external returns (uint256 price, bool success) {
        return _getCurvePrice(pool);
    }
    //FINISHED

    /**
     * @notice Set reentrancy lock requirements for multiple pools in one transaction
     * @param pools Array of Curve pool addresses
     * @param settings Array of boolean values indicating if each pool requires the lock
     */
    function batchSetRequiresLock(
        address[] calldata pools,
        bool[] calldata settings
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        if (pools.length != settings.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < pools.length; i++) {
            requiresReentrancyLock[pools[i]] = settings[i];
        }

        emit BatchPoolsConfigured(pools, settings);
    }
}