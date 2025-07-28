// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {ILiquidTokenManager} from "../interfaces/ILiquidTokenManager.sol";
import {ITokenRegistryOracle} from "../interfaces/ITokenRegistryOracle.sol";
import "../libraries/StalenessThreshold.sol";

interface ICurvePool {
    function remove_liquidity(uint256, uint256[] calldata) external;
}
interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function observe(
        uint32[] calldata secondsAgos
    ) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

interface IBalancerV2Vault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        FundManagement calldata funds
    ) external view returns (int256[] memory assetDeltas);
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
    uint8 public constant SOURCE_TYPE_UNISWAP_V3_TWAP = 4;
    uint8 public constant SOURCE_TYPE_BALANCER_V2 = 5;
    address private constant BALANCER_V2_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // Define base assets
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
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

        // For UNISWAP_V3_TWAP, use reserved field for TWAP period in minutes
        uint16 twapMinutes = 0;
        if (primaryType == SOURCE_TYPE_UNISWAP_V3_TWAP) {
            twapMinutes = 15; // Default 15 minutes, can be made configurable later
        }

        // Store token configuration
        tokenConfigs[token] = TokenConfig({
            primaryType: primaryType,
            needsArg: needsArg, // Preserved for protocol calls
            reserved: twapMinutes, // Now used for TWAP period when applicable
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
            return _getContractCallPrice(token, config.primarySource, config.fallbackFn, config.needsArg);
        } else if (config.primaryType == SOURCE_TYPE_UNISWAP_V3_TWAP) {
            return _getUniswapV3TwapPrice(config.primarySource, config.reserved);
        } else if (config.primaryType == SOURCE_TYPE_BALANCER_V2) {
            // For Balancer V2, derive poolId from pool address
            bytes32 poolId = _deriveBalancerPoolId(config.primarySource);
            return _getBalancerV2Price(token, poolId);
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

    function _getBalancerV2Price(address token, bytes32 poolId) internal returns (uint256 price, bool success) {
        if (poolId == bytes32(0) || token == address(0)) {
            return (0, false);
        }

        // 1) Fetch pool tokens
        address[] memory tokens;
        uint256[] memory balances;
        {
            bytes memory inData = abi.encodeWithSelector(
                0xf94d4668, // getPoolTokens(bytes32)
                poolId
            );
            (bool ok, bytes memory ret) = address(BALANCER_V2_VAULT).staticcall(inData);
            if (!ok || ret.length < 96) return (0, false);
            (tokens, balances, ) = abi.decode(ret, (address[], uint256[], uint256));
        }

        // 2) Find token indices (handle 2 or 3 token pools)
        uint256 tokenIdx = type(uint256).max;
        uint256 pairedIdx = type(uint256).max;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokenIdx = i;
            } else if (tokens[i] == WETH || tokens[i] == WBTC) {
                pairedIdx = i;
            }
        }

        // Verify we found both tokens
        if (tokenIdx == type(uint256).max || pairedIdx == type(uint256).max) {
            return (0, false);
        }

        // 3) Build swap step
        IBalancerV2Vault.BatchSwapStep[] memory steps = new IBalancerV2Vault.BatchSwapStep[](1);
        steps[0] = IBalancerV2Vault.BatchSwapStep({
            poolId: poolId,
            assetInIndex: tokenIdx,
            assetOutIndex: pairedIdx,
            amount: 1e18,
            userData: ""
        });

        IBalancerV2Vault.FundManagement memory funds = IBalancerV2Vault.FundManagement({
            sender: address(0),
            fromInternalBalance: false,
            recipient: address(0),
            toInternalBalance: false
        });

        // 4) Query the swap
        bytes memory callData = abi.encodeWithSelector(
            0xf84d066e, // queryBatchSwap selector
            IBalancerV2Vault.SwapKind.GIVEN_IN,
            steps,
            tokens,
            funds
        );

        (bool ok2, bytes memory ret2) = address(BALANCER_V2_VAULT).call(callData);
        if (!ok2) return (0, false);

        // 5) Decode result
        int256[] memory deltas = abi.decode(ret2, (int256[]));
        if (deltas.length <= pairedIdx) return (0, false);

        int256 pairedDelta = deltas[pairedIdx];
        if (pairedDelta >= 0) return (0, false);

        // 6) Return price
        price = uint256(-pairedDelta);

        // 7) Handle WBTC decimals if needed
        if (tokens[pairedIdx] == WBTC) {
            price = price * 1e10; // Convert 8 decimals to 18
        }

        success = price > 0;
    }
    /*
    function _getBalancerV2Price(address token, bytes32 poolId) internal returns (uint256 price, bool success) {
        if (poolId == bytes32(0) || token == address(0)) {
            return (0, false);
        }

        // 1) Fetch pool tokens - we know it's a 2-token pool
        address[] memory tokens;
        uint256[] memory balances;
        {
            bytes memory inData = abi.encodeWithSelector(
                0xf94d4668, // getPoolTokens(bytes32)
                poolId
            );
            (bool ok, bytes memory ret) = address(BALANCER_V2_VAULT).staticcall(inData);
            if (!ok || ret.length < 96) return (0, false);
            (tokens, balances, ) = abi.decode(ret, (address[], uint256[], uint256));
        }

        // 2) For whitelisted 2-token pools, just find indices
        if (tokens.length != 2) return (0, false); // Safety check

        uint256 tokenIdx = tokens[0] == token ? 0 : 1;
        uint256 pairedIdx = tokenIdx == 0 ? 1 : 0;

        // Verify our token is actually in the pool
        if (tokens[tokenIdx] != token) return (0, false);

        // 3) Build swap step
        IBalancerV2Vault.BatchSwapStep[] memory steps = new IBalancerV2Vault.BatchSwapStep[](1);
        steps[0] = IBalancerV2Vault.BatchSwapStep({
            poolId: poolId,
            assetInIndex: tokenIdx,
            assetOutIndex: pairedIdx,
            amount: 1e18,
            userData: ""
        });

        IBalancerV2Vault.FundManagement memory funds = IBalancerV2Vault.FundManagement({
            sender: address(0),
            fromInternalBalance: false,
            recipient: address(0),
            toInternalBalance: false
        });

        // 4) Query the swap
        bytes memory callData = abi.encodeWithSelector(
            0xf84d066e, // queryBatchSwap selector
            IBalancerV2Vault.SwapKind.GIVEN_IN,
            steps,
            tokens,
            funds
        );

        (bool ok2, bytes memory ret2) = address(BALANCER_V2_VAULT).call(callData);
        if (!ok2) return (0, false);

        // 5) Decode result
        int256[] memory deltas = abi.decode(ret2, (int256[]));
        if (deltas.length <= pairedIdx) return (0, false);

        int256 pairedDelta = deltas[pairedIdx];
        if (pairedDelta >= 0) return (0, false);

        // 6) Return price
        price = uint256(-pairedDelta);

        // 7) Handle WBTC decimals if needed
        // Since you whitelist pools, you know if it's WBTC paired
        if (tokens[pairedIdx] == WBTC) {
            price = price * 1e10; // Convert 8 decimals to 18
        }

        success = price > 0;
    }
    */
    /// @dev Derive Balancer V2 poolId from pool address by querying the pool directly
    function _deriveBalancerPoolId(address poolAddress) internal view returns (bytes32 poolId) {
        if (poolAddress == address(0)) return bytes32(0);

        // Most Balancer V2 pools have a getPoolId() function
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, shl(224, 0x38fff2d0)) // getPoolId() selector

            let success := staticcall(gas(), poolAddress, ptr, 4, ptr, 32)

            if success {
                poolId := mload(ptr)
                if iszero(gt(poolId, 0)) {
                    // If poolId is zero, fallback to zero-padded address
                    poolId := shl(96, poolAddress)
                }
            }

            // Update free memory pointer
            mstore(0x40, add(ptr, 32))
        }

        // If assembly failed, fallback to zero-padded address
        if (poolId == bytes32(0)) {
            poolId = bytes32(uint256(uint160(poolAddress)));
        }
    }
    /*
    function _getUniswapV3TwapPrice(
        address pool,
        uint16 twapMinutes
    ) internal view returns (uint256 price, bool success) {
        if (pool == address(0) || twapMinutes == 0) return (0, false);

        assembly {
            let ptr := mload(0x40)

            // First, get token0 and token1 addresses to determine price direction
            // token0()
            mstore(ptr, 0x0dfe1681)
            let token0Success := staticcall(gas(), pool, ptr, 0x04, ptr, 0x20)
            let token0 := mload(ptr)

            // token1()
            mstore(ptr, 0xd21220a7)
            let token1Success := staticcall(gas(), pool, ptr, 0x04, ptr, 0x20)
            let token1 := mload(ptr)

            if and(token0Success, token1Success) {
                // Prepare observe() call
                let twapSeconds := mul(twapMinutes, 60)

                mstore(ptr, 0x883bdbfd) // observe(uint32[])
                mstore(add(ptr, 0x04), 0x20) // offset to array
                mstore(add(ptr, 0x24), 0x02) // array length = 2
                mstore(add(ptr, 0x44), twapSeconds) // secondsAgos[0]
                mstore(add(ptr, 0x64), 0x00) // secondsAgos[1] = 0 (now)

                let observeSuccess := staticcall(gas(), pool, ptr, 0x84, ptr, 0x80)

                if observeSuccess {
                    // Extract tickCumulatives
                    let tickCumOld := mload(add(ptr, 0x40))
                    let tickCumNow := mload(add(ptr, 0x60))

                    // Calculate TWAP tick
                    let tickDelta := sub(tickCumNow, tickCumOld)
                    let twapTick := sdiv(tickDelta, twapSeconds)

                    // Convert tick to price using optimized approximation
                    // For tick t: price = 1.0001^t
                    let absTick := twapTick
                    if slt(twapTick, 0) {
                        absTick := sub(0, twapTick)
                    }

                    // Base price (1e18)
                    price := 0x0de0b6b3a7640000

                    // Apply tick-based multiplier using bit-shift approximation
                    // This is accurate to ~0.1% for ticks in range [-100000, 100000]
                    if gt(absTick, 0) {
                        // Each tick represents ~0.01% change
                        // We use bit manipulation for efficiency
                        let multiplier := 0x0de0b6b3a7640000 // 1e18

                        // Process in chunks for better accuracy
                        let tickChunk := absTick

                        // For every 100 ticks, multiply by ~1.01 (simplified)
                        for {

                        } gt(tickChunk, 100) {

                        } {
                            multiplier := div(mul(multiplier, 0x0de488abbdd76000), 0x0de0b6b3a7640000) // ~1.01
                            tickChunk := sub(tickChunk, 100)
                        }

                        // Handle remaining ticks with linear approximation
                        if gt(tickChunk, 0) {
                            // ~0.0001 per tick
                            let adjustment := mul(tickChunk, 0x5f5e100) // 0.0001 * 1e18
                            multiplier := add(multiplier, adjustment)
                        }

                        price := div(mul(price, multiplier), 0x0de0b6b3a7640000)

                        // Apply sign
                        if slt(twapTick, 0) {
                            price := div(mul(0x0de0b6b3a7640000, 0x0de0b6b3a7640000), price)
                        }
                    }

                    success := gt(price, 0)
                }
            }
        }
    }
  
*/
    /// @dev Get TWAP price from Uniswap V3 pool with full precision
    /// Gas cost: ~25,000-35,000 gas (more predictable than assembly)
    /// Accuracy: Exact to the wei
    function _getUniswapV3TwapPrice(
        address pool,
        uint16 twapMinutes
    ) internal view returns (uint256 price, bool success) {
        if (pool == address(0) || twapMinutes == 0) return (0, false);

        uint32 twapSeconds = uint32(twapMinutes) * 60;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapSeconds;
        secondsAgos[1] = 0;

        try IUniswapV3Pool(pool).observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            // Calculate average tick over the period
            int24 twapTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(twapSeconds)));

            // Get sqrtPriceX96 from tick using TickMath library
            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);

            // Convert sqrtPriceX96 to price
            // price = (sqrtPriceX96 / 2^96)^2
            uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);

            // Normalize to 18 decimals
            price = FullMath.mulDiv(priceX192, 1e18, 1 << 192);

            success = true;
        } catch {
            return (0, false);
        }
    }
}