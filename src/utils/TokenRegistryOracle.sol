// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import "../libraries/StalenessThreshold.sol";

interface ICurvePool {
    function remove_liquidity(uint256, uint256[] calldata) external;
}

/**
 * @title TokenRegistryOracle
 * @notice Gas-optimized price oracle with primary/fallback static lookup
 */
contract TokenRegistryOracle is ITokenRegistryOracle, Initializable, AccessControlUpgradeable {
    // ------------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------------

    /// @notice Constants
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    bytes32 public constant TOKEN_CONFIGURATOR_ROLE = keccak256("TOKEN_CONFIGURATOR_ROLE");
    uint256 private constant PRECISION = 1e18;

    /// @notice Source types
    uint8 public constant SOURCE_TYPE_CHAINLINK = 1;
    uint8 public constant SOURCE_TYPE_CURVE = 2;
    uint8 public constant SOURCE_TYPE_PROTOCOL = 3;

    /// @notice Core dependencies
    ILiquidTokenManager public liquidTokenManager;

    /// @notice Price staleness controls
    uint256 private _stalenessSalt;
    uint64 private _emergencyInterval;
    uint64 public lastGlobalPriceUpdate;
    bool private _emergencyMode;

    /// @notice Mapping of assets to their corresponding token configuration
    mapping(address => TokenConfig) public tokenConfigs;

    /// @notice Mapping of assets to whether their config status
    mapping(address => bool) public isConfigured;

    /// @notice Mapping of Curve pools to whether they need a re-entrancy lock
    mapping(address => bool) public requiresReentrancyLock;

    /// @notice List of all configured tokens
    address[] public configuredTokens;

    // ------------------------------------------------------------------------------
    // Init functions
    // ------------------------------------------------------------------------------

    /// @dev Prevents the implementation contract from being initialized
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ITokenRegistryOracle
    function initialize(Init memory init, uint256 stalenessSalt) public initializer {
        __AccessControl_init();

        if (
            address(init.initialOwner) == address(0) ||
            address(init.priceUpdater) == address(0) ||
            address(init.liquidTokenManager) == address(0) ||
            address(init.liquidToken) == address(0)
        ) {
            revert ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, init.initialOwner);
        _grantRole(ORACLE_ADMIN_ROLE, init.initialOwner);
        _grantRole(RATE_UPDATER_ROLE, init.priceUpdater);
        _grantRole(RATE_UPDATER_ROLE, init.liquidToken);
        _grantRole(TOKEN_CONFIGURATOR_ROLE, address(init.liquidTokenManager));

        liquidTokenManager = init.liquidTokenManager;
        lastGlobalPriceUpdate = uint64(block.timestamp);
        _stalenessSalt = stalenessSalt;
        _emergencyMode = false;
    }

    // ------------------------------------------------------------------------------
    // Core functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ITokenRegistryOracle
    function configureToken(
        address token,
        uint8 primaryType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackFn
    ) external onlyRole(TOKEN_CONFIGURATOR_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (primaryType == 0 && primarySource == address(0)) revert NativeTokensNotConfigurable();
        if (primarySource == address(0)) revert ZeroAddress();
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

    /// @inheritdoc ITokenRegistryOracle
    function removeToken(address token) external onlyRole(TOKEN_CONFIGURATOR_ROLE) {
        // Check if token is configured
        if (!isConfigured[token]) {
            return;
        }

        // Clear token configuration
        delete tokenConfigs[token];

        // Remove from configured tokens array
        uint256 len = configuredTokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (configuredTokens[i] == token) {
                configuredTokens[i] = configuredTokens[len - 1];
                configuredTokens.pop();
                break;
            }
        }

        // Mark token as not configured
        isConfigured[token] = false;

        emit TokenRemoved(token);
    }

    /// @inheritdoc ITokenRegistryOracle
    function updateRate(IERC20 token, uint256 newRate) external onlyRole(RATE_UPDATER_ROLE) {
        _updateTokenRate(token, newRate);
    }

    /// @inheritdoc ITokenRegistryOracle
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

    /// @inheritdoc ITokenRegistryOracle
    function updateAllPricesIfNeeded() external override(ITokenRegistryOracle) returns (bool) {
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

    /// @dev Called by `updateAllPricesIfNeeded`
    function _updateAllPrices() internal {
        uint256 len = configuredTokens.length;

        for (uint256 i = 0; i < len; i++) {
            address token = configuredTokens[i];
            (uint256 price, bool success) = _getTokenPrice(token);

            if (success && price > 0) {
                _updateTokenRate(IERC20(token), price);
            } else {
                // Try fallback if available
                (uint256 fallbackPrice, bool fallbackSuccess) = _getFallbackPrice(token);
                if (fallbackSuccess && fallbackPrice > 0) {
                    _updateTokenRate(IERC20(token), fallbackPrice);
                } else {
                    // Revert if both fail
                    revert NoFreshPrice(token);
                }
            }
        }
    }

    /// @dev Called by `updateRate`, `batchUpdateRates` and `_updateAllPrices`
    function _updateTokenRate(IERC20 token, uint256 newRate) internal {
        ILiquidTokenManager manager = liquidTokenManager;
        uint256 oldRate = manager.getTokenInfo(token).pricePerUnit;
        manager.updatePrice(token, newRate);
        emit TokenRateUpdated(token, oldRate, newRate, msg.sender);
    }

    /// @inheritdoc ITokenRegistryOracle
    function setPriceUpdateInterval(uint256 interval) external onlyRole(ORACLE_ADMIN_ROLE) {
        if (interval == 0) revert IntervalCannotBeZero();
        _emergencyInterval = uint64(interval);
        _emergencyMode = true;
        emit UpdateIntervalChanged(_emergencyInterval, interval);
    }

    /// @inheritdoc ITokenRegistryOracle
    function disableEmergencyInterval() external onlyRole(ORACLE_ADMIN_ROLE) {
        _emergencyMode = false;
        emit EmergencyIntervalDisabled();
    }

    /// @inheritdoc ITokenRegistryOracle
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

    // ------------------------------------------------------------------------------
    // Getter functions
    // ------------------------------------------------------------------------------

    /// @inheritdoc ITokenRegistryOracle
    function getRate(IERC20 token) external view returns (uint256) {
        ILiquidTokenManager.TokenInfo memory tokenInfo = liquidTokenManager.getTokenInfo(token);
        return tokenInfo.pricePerUnit;
    }

    /// @inheritdoc ITokenRegistryOracle
    function arePricesStale() public view override(ITokenRegistryOracle) returns (bool) {
        return (block.timestamp > uint256(lastGlobalPriceUpdate) + _getDynamicInterval());
    }

    /// @dev Called by `arePricesStale`
    function _getDynamicInterval() internal view returns (uint256) {
        if (_emergencyMode) return _emergencyInterval;
        return StalenessThreshold.getHiddenThreshold(_stalenessSalt);
    }

    /// @inheritdoc ITokenRegistryOracle
    function lastPriceUpdate() external view returns (uint256) {
        return lastGlobalPriceUpdate;
    }

    /// @inheritdoc ITokenRegistryOracle
    function getTokenPrice(address token) external override(ITokenRegistryOracle) returns (uint256) {
        (uint256 price, bool success) = _getTokenPrice(token);

        if (success && price > 0) {
            return price;
        }

        // Try fallback
        (uint256 fallbackPrice, bool fallbackSuccess) = _getFallbackPrice(token);
        if (fallbackSuccess && fallbackPrice > 0) {
            return fallbackPrice;
        }

        // Return stored price if available
        return liquidTokenManager.getTokenInfo(IERC20(token)).pricePerUnit;
    }

    /// @inheritdoc ITokenRegistryOracle
    function _getTokenPrice_getter(address token) external returns (uint256 price, bool success) {
        return _getTokenPrice(token);
    }

    /// @dev Called by `getTokenPrice` and `_getTokenPrice_getter`
    function _getTokenPrice(address token) internal returns (uint256 price, bool success) {
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
            return _getContractCallPrice(token, config.primarySource, config.fallbackFn, config.needsArg);
        }

        return (0, false);
    }

    /// @dev Called by `_getTokenPrice`
    function _getChainlinkPrice(address feed) internal view returns (uint256 price, bool success) {
        if (feed == address(0)) return (0, false);

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
                if and(and(gt(answer, 0), gt(updatedAt, 0)), iszero(lt(answeredInRound, roundId))) {
                    // Call decimals()
                    mstore(ptr, shl(224, 0x313ce567)) // selector for decimals()
                    let decSuccess := staticcall(gas(), feed, ptr, 4, ptr, 32)
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
            }
        }
    }

    /// @dev Called by `_updateAllPrices` and `getTokenPrice`
    function _getFallbackPrice(address token) internal view returns (uint256 price, bool success) {
        TokenConfig memory config = tokenConfigs[token];

        // Skip if no fallback
        if (config.fallbackFn == bytes4(0) || config.fallbackSource == address(0)) {
            return (0, false);
        }

        return _getContractCallPrice(token, config.fallbackSource, config.fallbackFn, config.needsArg);
    }

    /// @dev Called by `_getTokenPrice`
    /// @dev If requiresReentrancyLock[pool] is true, first trigger remove_liquidity(0, [0,0])
    ///      to engage Curve’s nonReentrant lock, then fall back to three staticcalls:
    ///       1) get_virtual_price()
    ///       2) price_oracle()
    ///       3) get_dy(0,1,1e18)
    function _getCurvePrice(address pool) internal returns (uint256 price, bool success) {
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

    /// @dev Called by `_getTokenPrice` and `_getFallbackPrice`
    function _getContractCallPrice(
        address token,
        address contractAddr,
        bytes4 selector,
        uint8 needsArg
    ) internal view returns (uint256 price, bool success) {
        if (contractAddr == address(0) || selector == bytes4(0)) {
            return (0, false);
        }

        assembly {
            // Free memory pointer
            let ptr := mload(0x40)

            // Store function selector at memory position ptr
            mstore(ptr, selector)

            // Prepare call data parameters
            let callSize := 4 // Selector size

            // If the function requires an argument (1e18)
            if needsArg {
                mstore(add(ptr, 4), 0xDE0B6B3A7640000) // Hex for 1e18
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

            if success {
                // Load the returned value
                price := mload(ptr)

                // Update success: true only if price > 0
                success := gt(price, 0)
            }
        }
    }
}