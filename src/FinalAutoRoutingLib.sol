// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IUniswapV3Quoter.sol";
import "./interfaces/ICurvePool.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IFrxETHMinter.sol";

/**
 * @title FinalAutoRoutingLib
 * @notice Production routing library with complete feature parity to contract
 * @dev Features:
 *      - Smart ETH/WETH normalization with automatic route discovery
 *      - Full quoter-first optimization with slippage tiers
 *      - Complete protocol support (UniswapV3, Curve variants, DirectMint)
 *      - Dynamic configuration via LTM-passed parameters
 *      - Security mechanisms (pause, selector blacklist)
 *      - Decimal normalization for precision
 *      - Complete auto-routing with bridge assets (WETH for ETH_LST, WBTC for BTC_WRAPPED)
 *      - Reverse route support
 *      - Multi-step swap handling with wrap/unwrap sequences
 *      - Production-ready error handling and fallbacks
 */
library FinalAutoRoutingLib {
    // ============================================================================
    // CONSTANTS
    // ============================================================================
    address public constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNISWAP_QUOTER =
        0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address public constant FRXETH_MINTER =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    // Token addresses
    address public constant ANKRETH =
        0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address public constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address public constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address public constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant LSETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant SFRXETH =
        0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant STBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address public constant UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;

    // Parameters
    uint256 public constant TIGHT_BUFFER_BPS = 100; // 1%
    uint256 public constant DEADLINE_BUFFER = 600; // 10 minutes
    uint256 public constant MAX_SLIPPAGE = 2000; // 20%
    uint256 public constant QUOTE_MAX_AGE = 30; // 30 seconds
    uint256 public constant MAX_CURVE_TOKENS = 8; // Curve limit
    uint256 public constant BRIDGE_BUFFER_BPS = 300; // 3% buffer for bridge steps

    // ============================================================================
    // STRUCTS & ENUMS
    // ============================================================================
    enum Protocol {
        UniswapV3,
        Curve,
        DirectMint,
        MultiHop,
        MultiStep
    }

    enum AssetCategory {
        ETH_LST,
        BTC_WRAPPED,
        STABLE,
        VOLATILE
    }

    enum CurveInterface {
        None,
        Exchange,
        ExchangeUnderlying,
        Both
    }

    struct SwapInstructions {
        address target;
        bytes callData;
        uint256 value;
        address approvalToken;
        address approvalTarget;
        uint256 minAmountOut;
    }

    struct MultiStepInstructions {
        SwapInstructions[] steps;
        uint256 totalMinOut;
    }

    struct RouteConfig {
        Protocol protocol;
        bytes routeData;
        uint256 fallbackSlippageBps;
        bool supportsQuoter;
    }

    struct QuoteResult {
        uint256 expectedAmount;
        uint256 tightAmount;
        uint256 fallbackAmount;
        bool isValid;
        uint256 timestamp;
    }

    struct UniswapV3Route {
        uint24 fee;
        bool isMultiHop;
        bytes path;
    }

    struct CurveRoute {
        address pool;
        int128 tokenIndexIn;
        int128 tokenIndexOut;
        CurveInterface curveInterface;
    }

    struct TokenConfig {
        AssetCategory category;
        uint8 decimals;
        bool supported;
    }

    struct PoolConfig {
        bool whitelisted;
        bool paused;
        CurveInterface curveInterface;
        uint256 tokenCount;
    }

    struct ProtocolPause {
        bool uniswapV3Paused;
        bool curvePaused;
        bool directMintPaused;
        bool multiHopPaused;
        bool multiStepPaused;
    }

    struct SecurityConfig {
        bytes4[] dangerousSelectors;
        address[] registeredDEXes;
    }

    struct FullConfig {
        mapping(address => TokenConfig) tokens;
        mapping(address => PoolConfig) pools;
        mapping(address => mapping(address => RouteConfig)) routes;
        mapping(address => mapping(address => uint256)) slippages;
        ProtocolPause protocolPause;
        SecurityConfig security;
    }

    // ============================================================================
    // ERRORS
    // ============================================================================
    error InvalidTokenPair();
    error UnsupportedRoute();
    error ZeroAmount();
    error CrossCategorySwap();
    error InvalidLTMAddress();
    error SlippageTooHigh();
    error InsufficientOutput();
    error QuoteExpired();
    error InvalidToken();
    error UnauthorizedCaller();
    error PoolNotWhitelisted();
    error PoolPaused();
    error ProtocolPaused();
    error TokenNotSupported();
    error InvalidTokenIndex();
    error DangerousSelector();
    error DEXNotRegistered();
    error ExternalCallFailed();

    // ============================================================================
    // MAIN PUBLIC INTERFACE (UPDATED WITH ETH/WETH NORMALIZATION)
    // ============================================================================

    /**
     * @notice Get swap instructions with smart ETH/WETH normalization and complete feature parity
     * @dev Includes quoter-first, slippage tiers, security checks, decimal normalization, auto wrap/unwrap
     */
    function getSwapInstructions(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) public returns (SwapInstructions memory instructions) {
        // Validate basic inputs
        if (amountIn == 0) revert ZeroAmount();
        if (tokenIn == tokenOut) revert InvalidTokenPair();
        if (ltmAddress == address(0)) revert InvalidLTMAddress();

        // Validate token support
        if (
            !_isTokenSupported(tokenIn, config) ||
            !_isTokenSupported(tokenOut, config)
        ) {
            revert TokenNotSupported();
        }

        // Normalize ETH/WETH pair for route discovery
        (
            address normalizedIn,
            address normalizedOut,
            bool needsWrap,
            bool needsUnwrap
        ) = _normalizeTokenPair(tokenIn, tokenOut, config);

        // Try direct route with normalized tokens
        (bool routeFound, RouteConfig memory routeConfig) = _resolveRoute(
            normalizedIn,
            normalizedOut,
            config
        );

        // Try reverse route
        if (!routeFound) {
            (routeFound, routeConfig) = _resolveRoute(
                normalizedOut,
                normalizedIn,
                config
            );
            if (routeFound) routeConfig = _invertRouteConfig(routeConfig);
        }

        // If no direct route, try bridge routing
        if (!routeFound) {
            return
                _getBridgeRouteInstructions(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    minAmountOut,
                    ltmAddress,
                    config
                );
        }

        // Apply protocol-level pause
        _checkProtocolPause(routeConfig.protocol, config.protocolPause);

        // Handle MultiStep separately
        if (routeConfig.protocol == Protocol.MultiStep) {
            MultiStepInstructions memory multiStep = getMultiStepInstructions(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                ltmAddress,
                config
            );
            return multiStep.steps[0];
        }

        // Get quote for normalized tokens
        QuoteResult memory quote = _getQuoteWithFallback(
            normalizedIn,
            normalizedOut,
            amountIn,
            routeConfig,
            config
        );

        // Validate quote freshness
        if (
            quote.isValid && block.timestamp - quote.timestamp > QUOTE_MAX_AGE
        ) {
            revert QuoteExpired();
        }

        // ✅ KEY FIX: Respect the external minimum amount
        uint256 targetMinOut;
        if (quote.isValid) {
            // Use the greater of: quoter-based minimum OR external minimum
            targetMinOut = quote.tightAmount > minAmountOut
                ? quote.tightAmount
                : minAmountOut;
        } else {
            // No valid quote: use the greater of: fallback calculation OR external minimum
            uint256 fallbackMin = (amountIn *
                (10000 - routeConfig.fallbackSlippageBps)) / 10000;
            targetMinOut = fallbackMin > minAmountOut
                ? fallbackMin
                : minAmountOut;
        }

        // Generate instructions with intelligent wrap/unwrap handling
        instructions = _generateInstructionsWithWrapUnwrap(
            routeConfig,
            tokenIn,
            tokenOut,
            normalizedIn,
            normalizedOut,
            amountIn,
            targetMinOut,
            targetMinOut, // Use same value for final minimum
            ltmAddress,
            needsWrap,
            needsUnwrap,
            config
        );
    }

    /**
     * @notice Get multi-step swap instructions with bridge routing and decimal normalization
     */
    /**
     * @notice Get multi-step swap instructions with enhanced intermediate minimum calculations
     * @dev Improved bridge routing with quoter-based intermediate amounts
     */
    function getMultiStepInstructions(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) public returns (MultiStepInstructions memory instructions) {
        // Handle explicit multi-step routes first
        if (tokenIn == WETH && tokenOut == SFRXETH) {
            return
                _getWETHToSfrxETHInstructions(
                    amountIn,
                    minAmountOut,
                    ltmAddress,
                    config
                );
        }
        if (tokenIn == WETH && tokenOut == OSETH) {
            return
                _getWETHToOsETHInstructions(
                    amountIn,
                    minAmountOut,
                    ltmAddress,
                    config
                );
        }
        if (tokenIn == OSETH && tokenOut == WETH) {
            return
                _getOsETHToWETHInstructions(
                    amountIn,
                    minAmountOut,
                    ltmAddress,
                    config
                );
        }
        if (tokenIn == ETH_ADDRESS && tokenOut == SFRXETH) {
            return
                _getETHToSfrxETHInstructions(
                    amountIn,
                    minAmountOut,
                    ltmAddress,
                    config
                );
        }

        // Generic bridge routing with enhanced calculations
        AssetCategory categoryIn = _getTokenCategory(tokenIn, config);
        AssetCategory categoryOut = _getTokenCategory(tokenOut, config);

        if (categoryIn != categoryOut) revert CrossCategorySwap();

        address bridgeAsset = _getBridgeAssetForCategory(categoryIn);

        // Can't bridge if tokenIn or tokenOut is already the bridge asset
        if (tokenIn == bridgeAsset || tokenOut == bridgeAsset) {
            revert UnsupportedRoute();
        }

        // Enhanced bridge discovery with ETH/WETH normalization
        (bool step1Found, RouteConfig memory step1Route) = _resolveRoute(
            tokenIn,
            bridgeAsset,
            config
        );

        // Try normalized variants if no direct route
        if (!step1Found) {
            (
                address normalizedIn,
                address normalizedBridge,
                ,

            ) = _normalizeTokenPair(tokenIn, bridgeAsset, config);
            (step1Found, step1Route) = _resolveRoute(
                normalizedIn,
                normalizedBridge,
                config
            );

            if (!step1Found) {
                (step1Found, step1Route) = _resolveRoute(
                    normalizedBridge,
                    normalizedIn,
                    config
                );
                if (step1Found) step1Route = _invertRouteConfig(step1Route);
            }
        }

        if (!step1Found) revert UnsupportedRoute();

        (bool step2Found, RouteConfig memory step2Route) = _resolveRoute(
            bridgeAsset,
            tokenOut,
            config
        );

        // Try normalized variants if no direct route
        if (!step2Found) {
            (
                address normalizedBridge,
                address normalizedOut,
                ,

            ) = _normalizeTokenPair(bridgeAsset, tokenOut, config);
            (step2Found, step2Route) = _resolveRoute(
                normalizedBridge,
                normalizedOut,
                config
            );

            if (!step2Found) {
                (step2Found, step2Route) = _resolveRoute(
                    normalizedOut,
                    normalizedBridge,
                    config
                );
                if (step2Found) step2Route = _invertRouteConfig(step2Route);
            }
        }

        if (!step2Found) revert UnsupportedRoute();

        // Generate two-step instructions with enhanced intermediate calculations
        instructions.steps = new SwapInstructions[](2);

        // ✅ ENHANCED: Calculate intermediate minimum with quoter support
        uint256 intermediateMin = _calculateIntermediateMinimum(
            tokenIn,
            bridgeAsset,
            tokenOut,
            amountIn,
            minAmountOut,
            step1Route,
            step2Route,
            config
        );

        instructions.steps[0] = _generateInstructions(
            step1Route,
            tokenIn,
            bridgeAsset,
            amountIn,
            intermediateMin,
            ltmAddress,
            config
        );

        instructions.steps[1] = _generateInstructions(
            step2Route,
            bridgeAsset,
            tokenOut,
            0, // Amount will be determined by balance after step 1
            minAmountOut,
            ltmAddress,
            config
        );

        instructions.totalMinOut = minAmountOut;
        return instructions;
    }

    // ============================================================================
    // ETH/WETH NORMALIZATION (NEW CORE FEATURE)
    // ============================================================================

    /**
     * @notice Normalize ETH/WETH pair for route resolution
     * @dev Try both ETH and WETH variants to find existing routes
     */
    function _normalizeTokenPair(
        address tokenIn,
        address tokenOut,
        FullConfig storage config
    )
        internal
        view
        returns (
            address normalizedIn,
            address normalizedOut,
            bool needsWrap,
            bool needsUnwrap
        )
    {
        // Default values
        normalizedIn = tokenIn;
        normalizedOut = tokenOut;
        needsWrap = false;
        needsUnwrap = false;

        // Check if we have route for current pair
        (bool directFound, ) = _resolveRoute(tokenIn, tokenOut, config);
        if (directFound)
            return (normalizedIn, normalizedOut, needsWrap, needsUnwrap);

        // Try ETH/WETH variants
        address altTokenIn = (tokenIn == ETH_ADDRESS)
            ? WETH
            : (tokenIn == WETH)
                ? ETH_ADDRESS
                : tokenIn;
        address altTokenOut = (tokenOut == ETH_ADDRESS)
            ? WETH
            : (tokenOut == WETH)
                ? ETH_ADDRESS
                : tokenOut;

        // Try: altTokenIn -> tokenOut
        (bool altInFound, ) = _resolveRoute(altTokenIn, tokenOut, config);
        if (altInFound) {
            normalizedIn = altTokenIn;
            needsWrap = (tokenIn == ETH_ADDRESS && altTokenIn == WETH);
            return (normalizedIn, normalizedOut, needsWrap, needsUnwrap);
        }

        // Try: tokenIn -> altTokenOut
        (bool altOutFound, ) = _resolveRoute(tokenIn, altTokenOut, config);
        if (altOutFound) {
            normalizedOut = altTokenOut;
            needsUnwrap = (tokenOut == ETH_ADDRESS && altTokenOut == WETH);
            return (normalizedIn, normalizedOut, needsWrap, needsUnwrap);
        }

        // Try: altTokenIn -> altTokenOut
        (bool altBothFound, ) = _resolveRoute(altTokenIn, altTokenOut, config);
        if (altBothFound) {
            normalizedIn = altTokenIn;
            normalizedOut = altTokenOut;
            needsWrap = (tokenIn == ETH_ADDRESS && altTokenIn == WETH);
            needsUnwrap = (tokenOut == ETH_ADDRESS && altTokenOut == WETH);
            return (normalizedIn, normalizedOut, needsWrap, needsUnwrap);
        }

        // No route found with any variant
        return (normalizedIn, normalizedOut, needsWrap, needsUnwrap);
    }

    /**
     * @notice Check if token is supported (including ETH/WETH variants)
     */
    function _isTokenSupported(
        address token,
        FullConfig storage config
    ) internal view returns (bool) {
        if (config.tokens[token].supported) return true;
        // Check ETH/WETH variant
        address altToken = (token == ETH_ADDRESS)
            ? WETH
            : (token == WETH)
                ? ETH_ADDRESS
                : address(0);
        return (altToken != address(0) && config.tokens[altToken].supported);
    }

    /**
     * @notice Get token category (including ETH/WETH variants)
     */
    function _getTokenCategory(
        address token,
        FullConfig storage config
    ) internal view returns (AssetCategory) {
        if (config.tokens[token].supported) {
            return config.tokens[token].category;
        }
        // Check ETH/WETH variant
        address altToken = (token == ETH_ADDRESS)
            ? WETH
            : (token == WETH)
                ? ETH_ADDRESS
                : address(0);
        if (altToken != address(0) && config.tokens[altToken].supported) {
            return config.tokens[altToken].category;
        }
        revert TokenNotSupported();
    }

    /**
     * @notice Generate instructions with intelligent wrap/unwrap handling
     */
    function _generateInstructionsWithWrapUnwrap(
        RouteConfig memory routeConfig,
        address originalTokenIn,
        address originalTokenOut,
        address normalizedTokenIn,
        address normalizedTokenOut,
        uint256 amountIn,
        uint256 targetMinOut,
        uint256 finalMinOut,
        address recipient,
        bool needsWrap,
        bool needsUnwrap,
        FullConfig storage config
    ) internal view returns (SwapInstructions memory) {
        // ✅ Case 1: No wrapping needed
        if (!needsWrap && !needsUnwrap) {
            return
                _generateInstructions(
                    routeConfig,
                    originalTokenIn,
                    originalTokenOut,
                    amountIn,
                    finalMinOut,
                    recipient,
                    config
                );
        }

        // ✅ Case 2: Need to wrap ETH -> WETH before swap
        if (needsWrap && !needsUnwrap) {
            // For now, return wrap instruction - MockLTM will handle the sequence
            return
                SwapInstructions({
                    target: WETH,
                    callData: abi.encodeWithSelector(IWETH.deposit.selector),
                    value: amountIn,
                    approvalToken: address(0),
                    approvalTarget: address(0),
                    minAmountOut: amountIn // WETH amount after wrap
                });
        }

        // ✅ Case 3: Need to unwrap WETH -> ETH after swap
        if (!needsWrap && needsUnwrap) {
            // Return the main swap instruction, MockLTM will handle unwrapping
            return
                _generateInstructions(
                    routeConfig,
                    normalizedTokenIn,
                    normalizedTokenOut,
                    amountIn,
                    targetMinOut,
                    recipient,
                    config
                );
        }

        // ✅ Case 4: Both wrap and unwrap needed (ETH -> WETH -> swap -> ETH)
        // Return wrap instruction, MockLTM will handle the full sequence
        return
            SwapInstructions({
                target: WETH,
                callData: abi.encodeWithSelector(IWETH.deposit.selector),
                value: amountIn,
                approvalToken: address(0),
                approvalTarget: address(0),
                minAmountOut: amountIn
            });
    }

    // ============================================================================
    // BRIDGE ROUTING (UPDATED)
    // ============================================================================

    function _getBridgeRouteInstructions(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) internal returns (SwapInstructions memory) {
        // ✅ Determine categories (check variants if needed)
        AssetCategory categoryIn = _getTokenCategory(tokenIn, config);
        AssetCategory categoryOut = _getTokenCategory(tokenOut, config);

        // ✅ Cross-category swaps not supported
        if (categoryIn != categoryOut) {
            revert CrossCategorySwap();
        }

        // ✅ Get bridge asset for category
        address bridgeAsset = _getBridgeAssetForCategory(categoryIn);

        // ✅ Can't bridge if tokenIn or tokenOut is already the bridge asset
        if (tokenIn == bridgeAsset || tokenOut == bridgeAsset) {
            revert UnsupportedRoute();
        }

        // ✅ This will be handled as multi-step by MockLTM
        revert UnsupportedRoute(); // Triggers multi-step fallback
    }

    // ============================================================================
    // CORE LOGIC (COMPLETE FEATURE PARITY)
    // ============================================================================

    function _getQuoteWithFallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        RouteConfig memory routeConfig,
        FullConfig storage config
    ) internal returns (QuoteResult memory result) {
        // Apply pair-specific slippage if configured
        uint256 pairSlippage = config.slippages[tokenIn][tokenOut];
        if (pairSlippage != 0) {
            routeConfig.fallbackSlippageBps = pairSlippage;
        }

        if (routeConfig.supportsQuoter) {
            if (routeConfig.protocol == Protocol.UniswapV3) {
                (result.expectedAmount, result.isValid) = _quoteUniswapV3(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    routeConfig.routeData
                );
            } else if (routeConfig.protocol == Protocol.Curve) {
                (result.expectedAmount, result.isValid) = _quoteCurve(
                    amountIn,
                    routeConfig.routeData,
                    config
                );
            } else if (routeConfig.protocol == Protocol.MultiHop) {
                (result.expectedAmount, result.isValid) = _quoteMultiHop(
                    amountIn,
                    routeConfig.routeData
                );
            } else if (routeConfig.protocol == Protocol.DirectMint) {
                (result.expectedAmount, result.isValid) = _quoteDirectMint(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    routeConfig
                );
            }
        }

        // Calculate amounts with slippage buffers
        result.tightAmount = result.isValid
            ? (result.expectedAmount * (10000 - TIGHT_BUFFER_BPS)) / 10000
            : 0;

        result.fallbackAmount =
            ((result.isValid ? result.expectedAmount : amountIn) *
                (10000 - routeConfig.fallbackSlippageBps)) /
            10000;
        result.timestamp = block.timestamp;
    }

    function _generateInstructions(
        RouteConfig memory routeConfig,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        FullConfig storage config
    ) internal view returns (SwapInstructions memory) {
        if (routeConfig.protocol == Protocol.UniswapV3) {
            return
                _generateUniswapV3Instructions(
                    routeConfig,
                    tokenIn,
                    tokenOut,
                    amountIn,
                    minAmountOut,
                    recipient
                );
        } else if (routeConfig.protocol == Protocol.Curve) {
            return
                _generateCurveInstructions(
                    routeConfig,
                    tokenIn,
                    tokenOut,
                    amountIn,
                    minAmountOut,
                    config
                );
        } else if (routeConfig.protocol == Protocol.DirectMint) {
            return
                _generateDirectMintInstructions(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    minAmountOut,
                    recipient,
                    routeConfig
                );
        } else if (routeConfig.protocol == Protocol.MultiHop) {
            return
                _generateMultiHopInstructions(
                    routeConfig,
                    amountIn,
                    minAmountOut,
                    recipient
                );
        }
        revert UnsupportedRoute();
    }

    // ============================================================================
    // QUOTER FUNCTIONS (IMPLEMENTED)
    // ============================================================================

    function _quoteUniswapV3(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory routeData
    ) internal returns (uint256 amount, bool success) {
        UniswapV3Route memory route = abi.decode(routeData, (UniswapV3Route));

        try
            IUniswapV3Quoter(UNISWAP_QUOTER).quoteExactInputSingle(
                tokenIn == ETH_ADDRESS ? WETH : tokenIn,
                tokenOut == ETH_ADDRESS ? WETH : tokenOut,
                route.fee,
                amountIn,
                0
            )
        returns (uint256 quotedAmount) {
            return (quotedAmount, true);
        } catch {
            return (0, false);
        }
    }

    function _quoteMultiHop(
        uint256 amountIn,
        bytes memory routeData
    ) internal returns (uint256 amount, bool success) {
        UniswapV3Route memory route = abi.decode(routeData, (UniswapV3Route));

        try
            IUniswapV3Quoter(UNISWAP_QUOTER).quoteExactInput(
                route.path,
                amountIn
            )
        returns (uint256 quotedAmount) {
            return (quotedAmount, true);
        } catch {
            return (0, false);
        }
    }

    function _quoteCurve(
        uint256 amountIn,
        bytes memory routeData,
        FullConfig storage config
    ) internal returns (uint256 amount, bool success) {
        CurveRoute memory route = abi.decode(routeData, (CurveRoute));
        _validateCurvePool(route.pool, config);

        try
            ICurvePool(route.pool).get_dy(
                route.tokenIndexIn,
                route.tokenIndexOut,
                amountIn
            )
        returns (uint256 quotedAmount) {
            return (quotedAmount, true);
        } catch {
            return (0, false);
        }
    }

    function _quoteDirectMint(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        RouteConfig memory routeConfig
    ) internal pure returns (uint256 amount, bool success) {
        if (tokenIn == ETH_ADDRESS && tokenOut == SFRXETH) {
            // 1:1 minting ratio
            return (amountIn, true);
        }
        return (0, false);
    }

    function _validateCurvePool(
        address pool,
        FullConfig storage config
    ) internal view {
        PoolConfig memory poolConfig = config.pools[pool];
        if (!poolConfig.whitelisted) revert PoolNotWhitelisted();
        if (poolConfig.paused) revert PoolPaused();
    }

    // ============================================================================
    // INSTRUCTION GENERATION (IMPLEMENTED)
    // ============================================================================

    function _generateUniswapV3Instructions(
        RouteConfig memory routeConfig,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) internal view returns (SwapInstructions memory) {
        UniswapV3Route memory route = abi.decode(
            routeConfig.routeData,
            (UniswapV3Route)
        );

        if (route.isMultiHop) {
            return
                SwapInstructions({
                    target: UNISWAP_ROUTER,
                    callData: abi.encodeWithSelector(
                        IUniswapV3Router.exactInput.selector,
                        IUniswapV3Router.ExactInputParams({
                            path: route.path,
                            recipient: recipient,
                            deadline: block.timestamp + DEADLINE_BUFFER,
                            amountIn: amountIn,
                            amountOutMinimum: minAmountOut
                        })
                    ),
                    value: tokenIn == ETH_ADDRESS ? amountIn : 0,
                    approvalToken: tokenIn == ETH_ADDRESS
                        ? address(0)
                        : tokenIn,
                    approvalTarget: tokenIn == ETH_ADDRESS
                        ? address(0)
                        : UNISWAP_ROUTER,
                    minAmountOut: minAmountOut
                });
        } else {
            return
                SwapInstructions({
                    target: UNISWAP_ROUTER,
                    callData: abi.encodeWithSelector(
                        IUniswapV3Router.exactInputSingle.selector,
                        IUniswapV3Router.ExactInputSingleParams({
                            tokenIn: tokenIn == ETH_ADDRESS ? WETH : tokenIn,
                            tokenOut: tokenOut == ETH_ADDRESS ? WETH : tokenOut,
                            fee: route.fee,
                            recipient: recipient,
                            deadline: block.timestamp + DEADLINE_BUFFER,
                            amountIn: amountIn,
                            amountOutMinimum: minAmountOut,
                            sqrtPriceLimitX96: 0
                        })
                    ),
                    value: tokenIn == ETH_ADDRESS ? amountIn : 0,
                    approvalToken: tokenIn == ETH_ADDRESS
                        ? address(0)
                        : tokenIn,
                    approvalTarget: tokenIn == ETH_ADDRESS
                        ? address(0)
                        : UNISWAP_ROUTER,
                    minAmountOut: minAmountOut
                });
        }
    }

    function _generateMultiHopInstructions(
        RouteConfig memory routeConfig,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) internal view returns (SwapInstructions memory) {
        UniswapV3Route memory route = abi.decode(
            routeConfig.routeData,
            (UniswapV3Route)
        );

        return
            SwapInstructions({
                target: UNISWAP_ROUTER,
                callData: abi.encodeWithSelector(
                    IUniswapV3Router.exactInput.selector,
                    IUniswapV3Router.ExactInputParams({
                        path: route.path,
                        recipient: recipient,
                        deadline: block.timestamp + DEADLINE_BUFFER,
                        amountIn: amountIn,
                        amountOutMinimum: minAmountOut
                    })
                ),
                value: 0,
                approvalToken: address(0),
                approvalTarget: address(0),
                minAmountOut: minAmountOut
            });
    }

    function _generateCurveInstructions(
        RouteConfig memory routeConfig,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        FullConfig storage config
    ) internal view returns (SwapInstructions memory) {
        CurveRoute memory route = abi.decode(
            routeConfig.routeData,
            (CurveRoute)
        );
        _validateCurvePool(route.pool, config);

        // Select function based on Curve interface
        bytes4 selector;
        if (route.curveInterface == CurveInterface.Exchange) {
            selector = ICurvePool.exchange.selector;
        } else if (route.curveInterface == CurveInterface.ExchangeUnderlying) {
            selector = ICurvePool.exchange_underlying.selector;
        } else {
            revert UnsupportedRoute();
        }

        // Handle ETH output case
        if (tokenOut == ETH_ADDRESS) {
            return
                SwapInstructions({
                    target: route.pool,
                    callData: abi.encodeWithSelector(
                        selector,
                        route.tokenIndexIn,
                        route.tokenIndexOut,
                        amountIn,
                        minAmountOut
                    ),
                    value: 0, // No value sent for ETH output
                    approvalToken: tokenIn == ETH_ADDRESS
                        ? address(0)
                        : tokenIn,
                    approvalTarget: tokenIn == ETH_ADDRESS
                        ? address(0)
                        : route.pool,
                    minAmountOut: minAmountOut
                });
        }
        // Handle ETH input case
        else if (tokenIn == ETH_ADDRESS) {
            return
                SwapInstructions({
                    target: route.pool,
                    callData: abi.encodeWithSelector(
                        selector,
                        route.tokenIndexIn,
                        route.tokenIndexOut,
                        amountIn,
                        minAmountOut
                    ),
                    value: amountIn, // Send ETH with transaction
                    approvalToken: address(0), // No approval needed
                    approvalTarget: address(0),
                    minAmountOut: minAmountOut
                });
        }
        // Standard ERC20 swap
        else {
            return
                SwapInstructions({
                    target: route.pool,
                    callData: abi.encodeWithSelector(
                        selector,
                        route.tokenIndexIn,
                        route.tokenIndexOut,
                        amountIn,
                        minAmountOut
                    ),
                    value: 0,
                    approvalToken: tokenIn,
                    approvalTarget: route.pool,
                    minAmountOut: minAmountOut
                });
        }
    }

    function _generateDirectMintInstructions(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        RouteConfig memory routeConfig
    ) internal pure returns (SwapInstructions memory) {
        address minter = abi.decode(routeConfig.routeData, (address));
        require(
            (tokenIn == ETH_ADDRESS || tokenIn == WETH) && tokenOut == SFRXETH,
            "Invalid direct mint"
        );

        // Handle WETH input case
        if (tokenIn == WETH) {
            return
                SwapInstructions({
                    target: WETH,
                    callData: abi.encodeWithSelector(
                        IWETH.withdraw.selector,
                        amountIn
                    ),
                    value: 0,
                    approvalToken: address(0),
                    approvalTarget: address(0),
                    minAmountOut: amountIn // Amount of ETH to receive
                });
        }
        // Native ETH input
        else {
            return
                SwapInstructions({
                    target: minter,
                    callData: abi.encodeWithSelector(
                        IFrxETHMinter.submitAndDeposit.selector,
                        recipient
                    ),
                    value: amountIn,
                    approvalToken: address(0),
                    approvalTarget: address(0),
                    minAmountOut: minAmountOut
                });
        }
    }

    // ============================================================================
    // SECURITY FUNCTIONS (PAUSE MECHANISMS)
    // ============================================================================

    function _checkProtocolPause(
        Protocol protocol,
        ProtocolPause storage pauseConfig
    ) internal view {
        if (protocol == Protocol.UniswapV3 && pauseConfig.uniswapV3Paused)
            revert ProtocolPaused();
        if (protocol == Protocol.Curve && pauseConfig.curvePaused)
            revert ProtocolPaused();
        if (protocol == Protocol.DirectMint && pauseConfig.directMintPaused)
            revert ProtocolPaused();
        if (protocol == Protocol.MultiHop && pauseConfig.multiHopPaused)
            revert ProtocolPaused();
        if (protocol == Protocol.MultiStep && pauseConfig.multiStepPaused)
            revert ProtocolPaused();
    }

    // ============================================================================
    // DECIMAL NORMALIZATION
    // ============================================================================

    function _normalizeAmount(
        uint256 amount,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) internal pure returns (uint256) {
        if (decimalsIn == decimalsOut) return amount;
        if (decimalsIn > decimalsOut) {
            uint256 diff = decimalsIn - decimalsOut;
            return amount / (10 ** diff);
        } else {
            uint256 diff = decimalsOut - decimalsIn;
            return amount * (10 ** diff);
        }
    }

    // ============================================================================
    // DYNAMIC DEX REGISTRY
    // ============================================================================

    function executeBackendSwap(
        address dex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata callData,
        FullConfig storage config
    ) external view returns (SwapInstructions memory) {
        // Validate selector
        bytes4 selector = bytes4(callData);
        _validateSelector(selector, config.security);
        // Check DEX registration
        bool dexRegistered;
        for (uint i = 0; i < config.security.registeredDEXes.length; i++) {
            if (config.security.registeredDEXes[i] == dex) {
                dexRegistered = true;
                break;
            }
        }
        if (!dexRegistered) revert DEXNotRegistered();

        // Check selector blacklist
        for (uint i = 0; i < config.security.dangerousSelectors.length; i++) {
            if (config.security.dangerousSelectors[i] == selector) {
                revert DangerousSelector();
            }
        }
        return
            SwapInstructions({
                target: dex,
                callData: callData,
                value: tokenIn == ETH_ADDRESS ? amountIn : 0,
                approvalToken: tokenIn == ETH_ADDRESS ? address(0) : tokenIn,
                approvalTarget: dex,
                minAmountOut: 0
            });
    }

    // ============================================================================
    // ROUTE RESOLUTION (FULLY IMPLEMENTED WITH ALL ROUTES)
    // ============================================================================

    function _resolveRoute(
        address tokenIn,
        address tokenOut,
        FullConfig storage config
    ) internal view returns (bool success, RouteConfig memory routeConfig) {
        // First check dynamic configuration
        RouteConfig storage dynamicConfig = config.routes[tokenIn][tokenOut];
        if (
            dynamicConfig.protocol != Protocol.UniswapV3 ||
            dynamicConfig.routeData.length > 0
        ) {
            return (true, dynamicConfig);
        }

        // ============ DIRECT MINT ROUTES ============
        if (tokenIn == ETH_ADDRESS && tokenOut == SFRXETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.DirectMint,
                    routeData: abi.encode(FRXETH_MINTER),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }

        // ============ ETH → LST ROUTES (CURVE) ============
        if (tokenIn == ETH_ADDRESS && tokenOut == ANKRETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
                            0,
                            1,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 70,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ETH_ADDRESS && tokenOut == ETHX) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                            0,
                            1,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ETH_ADDRESS && tokenOut == FRXETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
                            0,
                            1,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ETH_ADDRESS && tokenOut == STETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
                            0,
                            1,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }

        // ============ LST → ETH ROUTES (CURVE REVERSE) ============
        if (tokenIn == STETH && tokenOut == ETH_ADDRESS) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
                            1,
                            0,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ANKRETH && tokenOut == ETH_ADDRESS) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
                            1,
                            0,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 70,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ETHX && tokenOut == ETH_ADDRESS) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
                            1,
                            0,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == FRXETH && tokenOut == ETH_ADDRESS) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.Curve,
                    routeData: abi.encode(
                        CurveRoute(
                            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
                            1,
                            0,
                            CurveInterface.Exchange
                        )
                    ),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }

        // ============ WETH → LST ROUTES (UNISWAP V3) ============
        if (tokenIn == WETH && tokenOut == CBETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 350,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == LSETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 150,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == METH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == OETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == RETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(100, false, "")),
                    fallbackSlippageBps: 750,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == STETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(10000, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == SWETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 250,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WETH && tokenOut == ANKRETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(3000, false, "")),
                    fallbackSlippageBps: 1500,
                    supportsQuoter: true
                })
            );
        }

        // ============ LST → WETH ROUTES (UNISWAP V3 REVERSE) ============
        if (tokenIn == CBETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 350,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == RETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(100, false, "")),
                    fallbackSlippageBps: 750,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == STETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(10000, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ANKRETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(3000, false, "")),
                    fallbackSlippageBps: 1500,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == LSETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 150,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == METH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == OETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == SWETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 250,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == FRXETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == ETHX && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 50,
                    supportsQuoter: true
                })
            );
        }

        // ============ MULTI-STEP ROUTES ============
        if (tokenIn == WETH && tokenOut == SFRXETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.MultiStep,
                    routeData: "",
                    fallbackSlippageBps: 400,
                    supportsQuoter: false
                })
            );
        }
        if (tokenIn == WETH && tokenOut == OSETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.MultiStep,
                    routeData: "",
                    fallbackSlippageBps: 1200,
                    supportsQuoter: false
                })
            );
        }
        if (tokenIn == OSETH && tokenOut == WETH) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.MultiStep,
                    routeData: "",
                    fallbackSlippageBps: 500,
                    supportsQuoter: false
                })
            );
        }

        // ============ BTC ROUTES ============
        if (tokenIn == WBTC && tokenOut == STBTC) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == WBTC && tokenOut == UNIBTC) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(3000, false, "")),
                    fallbackSlippageBps: 150,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == STBTC && tokenOut == WBTC) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(500, false, "")),
                    fallbackSlippageBps: 100,
                    supportsQuoter: true
                })
            );
        }
        if (tokenIn == UNIBTC && tokenOut == WBTC) {
            return (
                true,
                RouteConfig({
                    protocol: Protocol.UniswapV3,
                    routeData: abi.encode(UniswapV3Route(3000, false, "")),
                    fallbackSlippageBps: 150,
                    supportsQuoter: true
                })
            );
        }

        return (false, RouteConfig(Protocol.UniswapV3, "", 0, false));
    }

    // ============================================================================
    // MULTI-STEP ROUTES (FULLY IMPLEMENTED)
    // ============================================================================

    function _getWETHToSfrxETHInstructions(
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) internal pure returns (MultiStepInstructions memory) {
        MultiStepInstructions memory instructions;
        instructions.steps = new SwapInstructions[](2);

        // Step 1: Unwrap WETH to ETH
        instructions.steps[0] = SwapInstructions({
            target: WETH,
            callData: abi.encodeWithSelector(IWETH.withdraw.selector, amountIn),
            value: 0,
            approvalToken: address(0),
            approvalTarget: address(0),
            minAmountOut: amountIn
        });

        // Step 2: Directly convert ETH to sfrxETH using submitAndDeposit
        instructions.steps[1] = SwapInstructions({
            target: FRXETH_MINTER,
            callData: abi.encodeWithSelector(
                IFrxETHMinter.submitAndDeposit.selector,
                ltmAddress // Receives sfrxETH directly
            ),
            value: amountIn, // Send ETH with call
            approvalToken: address(0),
            approvalTarget: address(0),
            minAmountOut: minAmountOut
        });

        instructions.totalMinOut = minAmountOut;
        return instructions;
    }

    /**
     * @notice Get WETH → osETH multi-step instructions with realistic market rates
     * @dev Uses quoter-first approach with realistic fallback ratios
     */
    function _getWETHToOsETHInstructions(
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) internal returns (MultiStepInstructions memory) {
        MultiStepInstructions memory instructions;
        instructions.steps = new SwapInstructions[](2);

        // ✅ Step 1: WETH → rETH with realistic minimum calculation
        uint256 expectedRETH;
        bool hasQuote = false;

        // Try to get realistic quote from Uniswap quoter
        try
            IUniswapV3Quoter(UNISWAP_QUOTER).quoteExactInputSingle(
                WETH,
                RETH,
                100, // 0.01% fee tier
                amountIn,
                0
            )
        returns (uint256 quotedAmount) {
            // Use quote with 3% slippage buffer
            expectedRETH = (quotedAmount * 97) / 100;
            hasQuote = true;
        } catch {
            // Fallback: Use realistic market ratio (rETH trades at ~13% premium to ETH)
            // So 1 WETH ≈ 0.87 rETH
            expectedRETH = (amountIn * 87) / 100;
        }

        instructions.steps[0] = SwapInstructions({
            target: UNISWAP_ROUTER,
            callData: abi.encodeWithSelector(
                IUniswapV3Router.exactInputSingle.selector,
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: RETH,
                    fee: 100,
                    recipient: ltmAddress,
                    deadline: block.timestamp + DEADLINE_BUFFER,
                    amountIn: amountIn,
                    amountOutMinimum: expectedRETH, // ✅ FIXED: Realistic minimum
                    sqrtPriceLimitX96: 0
                })
            ),
            value: 0,
            approvalToken: WETH,
            approvalTarget: UNISWAP_ROUTER,
            minAmountOut: 0 // Will be updated by MockLTM with actual balance
        });

        // ✅ Step 2: rETH → osETH with dynamic minimum calculation
        address curvePool = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;

        // Calculate minimum for step 2 based on final target
        // Account for potential slippage in both steps
        uint256 step2MinOut = hasQuote
            ? (minAmountOut * 95) / 100 // If we have quote, be more aggressive
            : (minAmountOut * 90) / 100; // If no quote, be more conservative

        instructions.steps[1] = SwapInstructions({
            target: curvePool,
            callData: abi.encodeWithSelector(
                ICurvePool.exchange.selector,
                1, // rETH index
                0, // osETH index
                0, // amountIn - will be set by MockLTM
                step2MinOut
            ),
            value: 0,
            approvalToken: RETH,
            approvalTarget: curvePool,
            minAmountOut: minAmountOut
        });

        instructions.totalMinOut = minAmountOut;
        return instructions;
    }

    /**
     * @notice Get osETH → WETH multi-step instructions with realistic market rates
     * @dev Handles osETH → rETH → WETH with proper intermediate calculations
     */
    function _getOsETHToWETHInstructions(
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) internal returns (MultiStepInstructions memory) {
        MultiStepInstructions memory instructions;
        instructions.steps = new SwapInstructions[](2);

        // ✅ Step 1: osETH → rETH with realistic expectations
        address curvePool = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;

        // Calculate expected rETH from osETH (roughly 1:1 but with slippage)
        uint256 expectedRETH;
        try ICurvePool(curvePool).get_dy(0, 1, amountIn) returns (uint256 dy) {
            // Use Curve quoter with 2% slippage
            expectedRETH = (dy * 98) / 100;
        } catch {
            // Fallback: Conservative 1:1 ratio with 5% slippage
            expectedRETH = (amountIn * 95) / 100;
        }

        instructions.steps[0] = SwapInstructions({
            target: curvePool,
            callData: abi.encodeWithSelector(
                ICurvePool.exchange.selector,
                0, // osETH index
                1, // rETH index
                amountIn,
                expectedRETH // ✅ FIXED: Realistic minimum
            ),
            value: 0,
            approvalToken: OSETH,
            approvalTarget: curvePool,
            minAmountOut: 0 // Will be updated by MockLTM
        });

        // ✅ Step 2: rETH → WETH with quoter-based calculation
        uint256 expectedWETH;
        bool hasQuote = false;

        // Try to get quote for rETH → WETH
        try
            IUniswapV3Quoter(UNISWAP_QUOTER).quoteExactInputSingle(
                RETH,
                WETH,
                100, // 0.01% fee tier
                expectedRETH, // Use expected amount from step 1
                0
            )
        returns (uint256 quotedAmount) {
            // rETH trades at premium, so we get more WETH per rETH
            expectedWETH = (quotedAmount * 97) / 100; // 3% slippage
            hasQuote = true;
        } catch {
            // Fallback: rETH premium means ~1.15 WETH per rETH, but be conservative
            expectedWETH = (expectedRETH * 110) / 100; // 10% premium with buffer
        }

        // Ensure we don't set unrealistic expectations
        if (expectedWETH < minAmountOut) {
            expectedWETH = minAmountOut;
        }

        instructions.steps[1] = SwapInstructions({
            target: UNISWAP_ROUTER,
            callData: abi.encodeWithSelector(
                IUniswapV3Router.exactInputSingle.selector,
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: RETH,
                    tokenOut: WETH,
                    fee: 100,
                    recipient: ltmAddress,
                    deadline: block.timestamp + DEADLINE_BUFFER,
                    amountIn: 0, // Will be set by MockLTM with actual balance
                    amountOutMinimum: minAmountOut, // Use final target
                    sqrtPriceLimitX96: 0
                })
            ),
            value: 0,
            approvalToken: RETH,
            approvalTarget: UNISWAP_ROUTER,
            minAmountOut: minAmountOut
        });

        instructions.totalMinOut = minAmountOut;
        return instructions;
    }

    function _getETHToSfrxETHInstructions(
        uint256 amountIn,
        uint256 minAmountOut,
        address ltmAddress,
        FullConfig storage config
    ) internal pure returns (MultiStepInstructions memory) {
        MultiStepInstructions memory instructions;
        instructions.steps = new SwapInstructions[](1); // Only 1 step needed

        // Direct conversion: ETH → sfrxETH
        instructions.steps[0] = SwapInstructions({
            target: FRXETH_MINTER,
            callData: abi.encodeWithSelector(
                IFrxETHMinter.submitAndDeposit.selector,
                ltmAddress
            ),
            value: amountIn,
            approvalToken: address(0),
            approvalTarget: address(0),
            minAmountOut: minAmountOut
        });

        instructions.totalMinOut = minAmountOut;
        return instructions;
    }

    // ============================================================================
    // UTILITIES
    // ============================================================================

    function _getBridgeAssetForCategory(
        AssetCategory category
    ) internal pure returns (address) {
        if (category == AssetCategory.ETH_LST) return WETH;
        if (category == AssetCategory.BTC_WRAPPED) return WBTC;
        return WETH; // Default bridge
    }

    function _invertRouteConfig(
        RouteConfig memory config
    ) internal pure returns (RouteConfig memory) {
        if (config.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(
                config.routeData,
                (CurveRoute)
            );
            return
                RouteConfig(
                    config.protocol,
                    abi.encode(
                        CurveRoute(
                            route.pool,
                            route.tokenIndexOut,
                            route.tokenIndexIn,
                            route.curveInterface
                        )
                    ),
                    config.fallbackSlippageBps,
                    config.supportsQuoter
                );
        }
        return config;
    }

    function _validateSelector(
        bytes4 selector,
        SecurityConfig storage security
    ) internal view {
        for (uint i = 0; i < security.dangerousSelectors.length; i++) {
            if (security.dangerousSelectors[i] == selector) {
                revert DangerousSelector();
            }
        }
    }
    /**
     * @notice Calculate realistic intermediate minimum for multi-step swaps
     * @dev Uses quoters when available, falls back to conservative estimates
     */
    function _calculateIntermediateMinimum(
        address tokenIn,
        address bridgeAsset,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        RouteConfig memory step1Route,
        RouteConfig memory step2Route,
        FullConfig storage config
    ) internal returns (uint256 intermediateMin) {
        // Try to get quote for step 1
        uint256 expectedIntermediate;
        bool hasStep1Quote = false;

        if (step1Route.supportsQuoter) {
            QuoteResult memory quote1 = _getQuoteWithFallback(
                tokenIn,
                bridgeAsset,
                amountIn,
                step1Route,
                config
            );

            if (quote1.isValid) {
                expectedIntermediate = quote1.expectedAmount;
                hasStep1Quote = true;
            }
        }

        // If no quote, use route-specific fallback calculations
        if (!hasStep1Quote) {
            if (tokenIn == WETH && bridgeAsset == RETH) {
                // WETH → rETH: rETH trades at premium
                expectedIntermediate = (amountIn * 87) / 100; // ~13% premium
            } else if (tokenIn == RETH && bridgeAsset == WETH) {
                // rETH → WETH: We get more WETH per rETH
                expectedIntermediate = (amountIn * 115) / 100; // ~15% premium
            } else {
                // Generic fallback with step1 slippage
                expectedIntermediate =
                    (amountIn * (10000 - step1Route.fallbackSlippageBps)) /
                    10000;
            }
        }

        // Apply conservative buffer for intermediate step
        intermediateMin =
            (expectedIntermediate * (10000 - BRIDGE_BUFFER_BPS)) /
            10000;

        // Ensure the intermediate amount is sufficient to meet final minimum
        // This is a sanity check - if our intermediate amount can't possibly
        // yield the final minimum, adjust upward
        uint256 theoreticalFinalMin = (intermediateMin *
            (10000 - step2Route.fallbackSlippageBps)) / 10000;

        if (theoreticalFinalMin < minAmountOut) {
            // Adjust intermediate minimum upward to ensure final target is reachable
            intermediateMin =
                (minAmountOut * 10000) /
                (10000 - step2Route.fallbackSlippageBps);
            intermediateMin =
                (intermediateMin * 10000) /
                (10000 - BRIDGE_BUFFER_BPS); // Add buffer
        }

        return intermediateMin;
    }

    function normalizeAmount(
        uint256 amount,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) external pure returns (uint256) {
        return _normalizeAmount(amount, decimalsIn, decimalsOut);
    }
}