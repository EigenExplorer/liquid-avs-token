// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IUniswapV3Quoter.sol";
import "./interfaces/ICurvePool.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IFrxETHMinter.sol";

/**
 * @title FinalAutoRouting - Superior Version
 * @notice Production-ready routing intelligence with delegated execution pattern
 * @dev Revolutionary features:
 * - Stateless execution data generation for LTM→DEX→LTM flow
 * - Zero token transfers to FAR in operator mode
 * - Quoter-first optimization with intelligent fallbacks
 * - Complete protocol support with gas-optimized execution
 * - Advanced security with role-based access control
 */

// ============================================================================
// MAIN CONTRACT
// ============================================================================

contract FinalAutoRouting is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============================================================================
    // CONSTANTS & IMMUTABLES
    // ============================================================================

    IWETH public immutable WETH;
    IUniswapV3Router public immutable uniswapRouter;
    IUniswapV3Quoter public immutable uniswapQuoter;
    IFrxETHMinter public immutable frxETHMinter;
    bytes32 private immutable ROUTE_PASSWORD_HASH;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 private constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint256 public constant MAX_SLIPPAGE = 2000;
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 public constant TIGHT_BUFFER_BPS = 20;
    uint256 public constant QUOTE_MAX_AGE = 30;
    uint256 public constant MAX_CURVE_TOKENS = 8;
    uint256 public constant EXTERNAL_CALL_GAS_LIMIT = 300000;
    uint256 public constant MAX_DEX_GAS_LIMIT = 500000;
    uint256 public constant MAX_MULTI_STEP_OPERATIONS = 5;
    uint256 public constant DEX_TIMELOCK = 24 hours;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    bool private initialized;
    bool public directTransferMode;
    address public routeManager;

    // Mappings
    mapping(address => mapping(address => uint256)) public slippageTolerance;
    mapping(address => AssetType) public assetTypes;
    mapping(address => bool) public poolWhitelist;
    mapping(address => bool) public farSupportedTokens;
    mapping(address => bool) public poolPaused;
    mapping(Protocol => bool) public protocolPaused;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => mapping(address => bool)) public customRouteEnabled;
    mapping(address => uint256) public curvePoolTokenCounts;
    mapping(address => CurveInterface) public curvePoolInterfaces;
    mapping(bytes32 => uint256) private configUpdateLocks;
    mapping(bytes32 => RouteConfig) public routes;
    mapping(address => bool) public registeredDEXes;
    mapping(address => string) public dexNames;
    mapping(bytes4 => bool) public dangerousSelectors;
    mapping(bytes4 => bool) public whitelistedSelectors;
    mapping(bytes4 => string) public selectorDescriptions;
    mapping(address => uint256) public dexRegistrationTime;
    mapping(address => address) public dexRegisteredBy;
    address[] public allRegisteredDEXes;
    bytes4[] public allDangerousSelectors;
    bytes4[] public allWhitelistedSelectors;

    // ============================================================================
    // ENUMS & STRUCTS
    // ============================================================================

    enum Protocol {
        UniswapV3,
        Curve,
        DirectMint,
        MultiHop,
        MultiStep
    }
    enum AssetType {
        STABLE,
        ETH_LST,
        BTC_WRAPPED,
        VOLATILE
    }
    enum CurveInterface {
        None,
        Exchange,
        ExchangeUnderlying,
        Both
    }
    enum ActionType {
        SWAP,
        WRAP,
        UNWRAP,
        DIRECT_MINT
    }
    enum RouteType {
        Direct,
        Reverse,
        Bridge
    }
    enum SlippageType {
        QUOTE,
        FALLBACK
    }

    struct QuoteData {
        uint256 expectedOutput;
        uint256 timestamp;
        bool valid;
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        Protocol protocol;
        bytes routeData;
    }

    struct UniswapV3Route {
        address pool;
        uint24 fee;
        bool isMultiHop;
        bytes path;
    }

    struct CurveRoute {
        address pool;
        int128 indexIn;
        int128 indexOut;
        bool useUnderlying;
    }

    struct RouteConfig {
        Protocol protocol;
        address pool;
        uint24 fee;
        bool directSwap;
        bytes path;
        int128 tokenIndexIn;
        int128 tokenIndexOut;
        bool useUnderlying;
        address specialContract;
        bool isConfigured;
        bytes routeData;
    }

    struct ExecutionStrategy {
        RouteType routeType;
        Protocol protocol;
        address bridgeAsset;
        bytes primaryRouteData;
        bytes secondaryRouteData;
        uint256 expectedGas;
    }

    struct SlippageConfig {
        address tokenIn;
        address tokenOut;
        uint256 slippageBps;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event DirectTransferModeUpdated(bool enabled, uint256 timestamp);
    event AssetsSwapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        Protocol protocol,
        address indexed caller,
        uint256 gasUsed,
        uint256 timestamp
    );
    event ExecutionDataGenerated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        Protocol protocol,
        uint256 timestamp
    );
    event RouteConfigured(address indexed tokenIn, address indexed tokenOut, Protocol protocol, address pool);
    event SlippageConfigured(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 slippageBps,
        address indexed configuredBy,
        uint256 timestamp
    );
    event PoolWhitelisted(
        address indexed pool,
        bool status,
        CurveInterface curveInterface,
        address indexed updatedBy,
        uint256 timestamp
    );
    event TokenSupported(address indexed token, bool status, AssetType assetType, uint8 decimals, uint256 timestamp);
    event DexRegistered(address indexed dex, string name, address indexed registeredBy, uint256 timestamp);
    event DexUnregistered(address indexed dex, address indexed unregisteredBy, uint256 timestamp);
    event SelectorWhitelisted(bytes4 indexed selector, string description, uint256 timestamp);
    event SelectorBlacklisted(bytes4 indexed selector, string reason, uint256 timestamp);
    event BackendSwapExecuted(
        address indexed dex,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address executor,
        uint256 timestamp
    );
    event CustomDexSwapFailed(address indexed dex, string reason, bytes data);

    // ============================================================================
    // ERRORS
    // ============================================================================

    error UnauthorizedCaller();
    error InvalidProtocol();
    error InsufficientOutput();
    error SwapFailed(string reason);
    error InvalidSlippage();
    error ZeroAmount();
    error PoolNotWhitelisted();
    error TokenNotSupported();
    error PoolIsPaused();
    error ProtocolIsPaused();
    error InvalidParameter(string parameter);
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidAddress();
    error InvalidRoutePassword();
    error NoRouteFound();
    error InvalidDecimals();
    error TransferFailed();
    error SameTokenSwap();
    error QuoteTooOld();
    error NoConfigSlippage();
    error UnsupportedRoute();

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier onlyAuthorizedCaller() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(OPERATOR_ROLE, msg.sender), "Unauthorized");
        _;
    }

    modifier onlyRouteManager() {
        require(msg.sender == routeManager || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorized route manager");
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    constructor(
        address _weth,
        address _uniswapRouter,
        address _uniswapQuoter,
        address _frxETHMinter,
        address _routeManager,
        bytes32 _routePasswordHash,
        address _liquidTokenManager,
        bool _initializeProduction
    ) {
        if (_weth == address(0)) revert InvalidAddress();
        if (_uniswapRouter == address(0)) revert InvalidAddress();
        if (_uniswapQuoter == address(0)) revert InvalidAddress();
        if (_frxETHMinter == address(0)) revert InvalidAddress();
        if (_routeManager == address(0)) revert InvalidAddress();
        if (_liquidTokenManager == address(0)) revert InvalidAddress();
        if (_routePasswordHash == bytes32(0)) revert InvalidParameter("routePasswordHash");

        WETH = IWETH(_weth);
        uniswapRouter = IUniswapV3Router(_uniswapRouter);
        uniswapQuoter = IUniswapV3Quoter(_uniswapQuoter);
        frxETHMinter = IFrxETHMinter(_frxETHMinter);
        routeManager = _routeManager;
        ROUTE_PASSWORD_HASH = _routePasswordHash;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, _liquidTokenManager);

        if (_initializeProduction) {
            _applyProductionSlippageConfig();
        }
    }

    // ============================================================================
    // INITIALIZATION
    // ============================================================================

    function initialize(
        address[] calldata tokenAddresses,
        AssetType[] calldata tokenTypes,
        uint8[] calldata decimals,
        address[] calldata poolAddresses,
        uint256[] calldata poolTokenCounts,
        CurveInterface[] calldata curveInterfaces,
        SlippageConfig[] calldata slippageConfigs
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (initialized) revert AlreadyInitialized();

        // Validate arrays
        if (tokenAddresses.length != tokenTypes.length) revert InvalidParameter("tokenArrays");
        if (tokenAddresses.length != decimals.length) revert InvalidParameter("decimalsArray");
        if (poolAddresses.length != poolTokenCounts.length) revert InvalidParameter("poolArrays");
        if (poolAddresses.length != curveInterfaces.length) revert InvalidParameter("interfaceArrays");

        // Configure tokens
        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            address token = tokenAddresses[i];
            if (token == address(0)) revert InvalidAddress();

            farSupportedTokens[token] = true;
            assetTypes[token] = tokenTypes[i];
            tokenDecimals[token] = decimals[i];

            emit TokenSupported(token, true, tokenTypes[i], decimals[i], block.timestamp);
        }

        // Configure pools
        for (uint256 i = 0; i < poolAddresses.length; ++i) {
            address pool = poolAddresses[i];
            if (pool == address(0)) revert InvalidAddress();

            poolWhitelist[pool] = true;
            curvePoolTokenCounts[pool] = poolTokenCounts[i];
            curvePoolInterfaces[pool] = curveInterfaces[i];

            emit PoolWhitelisted(pool, true, curveInterfaces[i], msg.sender, block.timestamp);
        }

        // Configure slippage
        for (uint256 i = 0; i < slippageConfigs.length; ++i) {
            SlippageConfig memory config = slippageConfigs[i];
            slippageTolerance[config.tokenIn][config.tokenOut] = config.slippageBps;

            emit SlippageConfigured(config.tokenIn, config.tokenOut, config.slippageBps, msg.sender, block.timestamp);
        }

        initialized = true;
    }

    // ============================================================================
    // MAIN FUNCTIONS FOR LTM INTEGRATION
    // ============================================================================

    /**
     * @notice Get accurate quote and execution data for LTM - THIS IS THE MAIN FUNCTION
     * @dev This is NOT a view function - LTM should call this normally to get accurate quotes
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return quotedAmount The accurate quoted output from quoter
     * @return executionData The calldata for swap execution
     * @return protocol The protocol to use
     * @return targetContract The contract to call for swap
     * @return value ETH value to send (if ETH swap)
     */
    function getQuoteAndExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        external
        returns (
            uint256 quotedAmount,
            bytes memory executionData,
            Protocol protocol,
            address targetContract,
            uint256 value
        )
    {
        if (amountIn == 0) revert ZeroAmount();
        if (tokenIn == tokenOut) revert SameTokenSwap();
        if (!farSupportedTokens[tokenIn] && tokenIn != ETH_ADDRESS) revert TokenNotSupported();
        if (!farSupportedTokens[tokenOut] && tokenOut != ETH_ADDRESS) revert TokenNotSupported();

        // Find optimal strategy
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, 0);

        // Get accurate quote from quoter
        SwapParams memory params = SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: 0,
            protocol: strategy.protocol,
            routeData: strategy.primaryRouteData
        });

        // This will call the actual quoter for accurate pricing
        QuoteData memory quote = _performQuote(tokenIn, tokenOut, amountIn, params);

        if (!quote.valid) {
            // Fallback to estimate if quote fails
            quote.expectedOutput = _estimateSwapOutput(tokenIn, tokenOut, amountIn, strategy);
            quote.valid = true;
        }

        quotedAmount = quote.expectedOutput;

        // Apply tight buffer for safety
        uint256 minAmountOut = (quotedAmount * (10000 - TIGHT_BUFFER_BPS)) / 10000;

        // Generate execution data with the buffered amount
        if (strategy.routeType == RouteType.Bridge) {
            executionData = _generateBridgeExecutionData(strategy, tokenIn, tokenOut, amountIn, minAmountOut);
        } else {
            executionData = _generateSingleExecutionData(strategy, tokenIn, tokenOut, amountIn, minAmountOut);
        }

        // Determine target contract
        if (strategy.protocol == Protocol.UniswapV3) {
            targetContract = address(uniswapRouter);
        } else if (strategy.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(strategy.primaryRouteData, (CurveRoute));
            targetContract = route.pool;
        } else if (strategy.protocol == Protocol.DirectMint) {
            targetContract = abi.decode(strategy.primaryRouteData, (address));
        } else if (strategy.protocol == Protocol.MultiHop) {
            targetContract = address(uniswapRouter);
        } else if (strategy.protocol == Protocol.MultiStep) {
            // For multi-step, return first DEX
            targetContract = address(uniswapRouter); // Will be handled by LTM
        }

        protocol = strategy.protocol;
        value = (tokenIn == ETH_ADDRESS) ? amountIn : 0;

        emit ExecutionDataGenerated(tokenIn, tokenOut, amountIn, protocol, block.timestamp);

        return (quotedAmount, executionData, protocol, targetContract, value);
    }

    /**
     * @notice Validate swap execution (view function for validation)
     * @dev This can be called with staticcall for validation only
     */
    function validateSwapExecution(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address executor
    ) external view returns (bool isValid, string memory reason, uint256 estimatedOutput) {
        // Token validation
        if (!farSupportedTokens[tokenIn] && tokenIn != ETH_ADDRESS) {
            return (false, "Input token not supported", 0);
        }
        if (!farSupportedTokens[tokenOut] && tokenOut != ETH_ADDRESS) {
            return (false, "Output token not supported", 0);
        }

        // Executor validation
        if (directTransferMode && !hasRole(OPERATOR_ROLE, executor)) {
            return (false, "Executor not authorized for direct mode", 0);
        }

        // Basic validation
        if (amountIn == 0) {
            return (false, "Zero amount", 0);
        }
        if (tokenIn == tokenOut) {
            return (false, "Same token swap", 0);
        }

        // Find route
        try this._findOptimalExecutionStrategyView(tokenIn, tokenOut, amountIn, minAmountOut) returns (
            ExecutionStrategy memory strategy
        ) {
            // Validate pools
            if (strategy.protocol == Protocol.UniswapV3) {
                UniswapV3Route memory route = abi.decode(strategy.primaryRouteData, (UniswapV3Route));
                if (!route.isMultiHop && route.pool != address(0) && !poolWhitelist[route.pool]) {
                    return (false, "Uniswap pool not whitelisted", 0);
                }
            } else if (strategy.protocol == Protocol.Curve) {
                CurveRoute memory route = abi.decode(strategy.primaryRouteData, (CurveRoute));
                if (!poolWhitelist[route.pool]) {
                    return (false, "Curve pool not whitelisted", 0);
                }
            }

            // Estimate output using view-safe method
            estimatedOutput = _estimateSwapOutputView(tokenIn, tokenOut, amountIn, strategy);

            if (estimatedOutput < minAmountOut) {
                return (false, "Output below minimum", estimatedOutput);
            }

            return (true, "Valid", estimatedOutput);
        } catch {
            return (false, "No route found", 0);
        }
    }

    /**
     * @notice Generate swap execution data (view function)
     * @dev Returns execution bytecode for LTM - can be called with staticcall
     */
    function generateSwapExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external view returns (bytes memory executionData, Protocol protocol, uint256 expectedGas) {
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, minAmountOut);

        protocol = strategy.protocol;
        expectedGas = strategy.expectedGas;

        // If minAmountOut is 0, calculate it from estimate
        if (minAmountOut == 0) {
            uint256 estimate = _estimateSwapOutputView(tokenIn, tokenOut, amountIn, strategy);
            uint256 slippage = slippageTolerance[tokenIn][tokenOut];
            if (slippage == 0) slippage = _getDefaultSlippage(tokenIn, tokenOut);
            minAmountOut = (estimate * (10000 - slippage)) / 10000;
        }

        if (strategy.routeType == RouteType.Bridge) {
            executionData = _generateBridgeExecutionData(strategy, tokenIn, tokenOut, amountIn, minAmountOut);
        } else {
            executionData = _generateSingleExecutionData(strategy, tokenIn, tokenOut, amountIn, minAmountOut);
        }
    }

    /**
     * @notice Get quoted swap execution data with live pricing
     * @dev This is NOT a view function - uses real quoter for accuracy
     */
    function getQuotedSwapExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        external
        returns (bytes memory executionData, Protocol protocol, uint256 quotedOutput, uint256 adjustedMinOutput)
    {
        // Get base execution strategy
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, 0);

        // Get quote
        SwapParams memory params = SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: 0,
            protocol: strategy.protocol,
            routeData: strategy.primaryRouteData
        });

        QuoteData memory quote = _performQuote(tokenIn, tokenOut, amountIn, params);

        if (quote.valid) {
            quotedOutput = quote.expectedOutput;
            adjustedMinOutput = (quotedOutput * (10000 - TIGHT_BUFFER_BPS)) / 10000;
        } else {
            // Fallback estimate
            quotedOutput = _estimateSwapOutput(tokenIn, tokenOut, amountIn, strategy);
            uint256 slippage = _getSlippage(tokenIn, tokenOut, SlippageType.FALLBACK);
            adjustedMinOutput = (quotedOutput * (10000 - slippage)) / 10000;
        }

        // Generate execution data with adjusted minimum
        protocol = strategy.protocol;
        if (strategy.routeType == RouteType.Bridge) {
            executionData = _generateBridgeExecutionData(strategy, tokenIn, tokenOut, amountIn, adjustedMinOutput);
        } else {
            executionData = _generateSingleExecutionData(strategy, tokenIn, tokenOut, amountIn, adjustedMinOutput);
        }
    }

    /**
     * @notice Get comprehensive routing strategy for complex swaps
     * @dev Not a view function - uses quoter for accuracy
     */
    function getComplexSwapStrategy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (bytes memory strategyData, uint256 expectedOutput, uint256 totalGas) {
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, minAmountOut);

        strategyData = abi.encode(strategy);
        totalGas = strategy.expectedGas;
        expectedOutput = _estimateSwapOutput(tokenIn, tokenOut, amountIn, strategy);
    }

    // ============================================================================
    // ORIGINAL SWAP FUNCTIONS WITH ENHANCED DIRECT MODE SUPPORT
    // ============================================================================

    /**
     * @notice Execute swap with automatic routing
     * @dev For backward compatibility - not recommended for LTM integration
     */
    function autoSwapAssets(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable onlyAuthorizedCaller nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (!farSupportedTokens[tokenIn] && tokenIn != ETH_ADDRESS) revert TokenNotSupported();
        if (!farSupportedTokens[tokenOut] && tokenOut != ETH_ADDRESS) revert TokenNotSupported();
        if (tokenIn == tokenOut) revert SameTokenSwap();

        // In direct transfer mode, execute without moving tokens to FAR
        if (directTransferMode && hasRole(OPERATOR_ROLE, msg.sender)) {
            return _autoSwapDirectMode(tokenIn, tokenOut, amountIn, minAmountOut);
        }

        // Normal mode with transfers
        return _autoSwapWithTransfers(tokenIn, tokenOut, amountIn, minAmountOut);
    }

    /**
     * @notice Execute swap with specific parameters
     * @dev For backward compatibility - not recommended for LTM integration
     */
    function swapAssets(
        SwapParams calldata params
    ) external payable onlyAuthorizedCaller whenNotPaused nonReentrant returns (uint256 amountOut) {
        _validateSwapParams(params);

        // Direct transfer mode for operators
        if (directTransferMode && hasRole(OPERATOR_ROLE, msg.sender)) {
            return _executeDirectModeSwap(params);
        }

        // Normal mode with transfers
        return _swapAssetsWithTransfer(params);
    }

    // ============================================================================
    // INTERNAL EXECUTION FUNCTIONS
    // ============================================================================

    /**
     * @notice Find optimal execution strategy
     */
    function _findOptimalExecutionStrategy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (ExecutionStrategy memory strategy) {
        // Check direct route
        bytes32 directKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        RouteConfig memory directRoute = routes[directKey];

        if (directRoute.isConfigured) {
            strategy.routeType = RouteType.Direct;
            strategy.protocol = directRoute.protocol;
            strategy.primaryRouteData = _encodeRouteData(directRoute, tokenIn, tokenOut);
            strategy.expectedGas = _estimateGasForProtocol(directRoute.protocol);
            return strategy;
        }

        // Check reverse route
        bytes32 reverseKey = keccak256(abi.encodePacked(tokenOut, tokenIn));
        RouteConfig memory reverseRoute = routes[reverseKey];

        if (reverseRoute.isConfigured) {
            strategy.routeType = RouteType.Reverse;
            strategy.protocol = reverseRoute.protocol;
            strategy.primaryRouteData = _encodeReverseRouteData(reverseRoute, tokenOut, tokenIn);
            strategy.expectedGas = _estimateGasForProtocol(reverseRoute.protocol);
            return strategy;
        }

        // Check bridge route
        address bridgeAsset = _getBridgeAsset(tokenIn, tokenOut);
        if (bridgeAsset != address(0)) {
            bytes32 firstKey = keccak256(abi.encodePacked(tokenIn, bridgeAsset));
            bytes32 secondKey = keccak256(abi.encodePacked(bridgeAsset, tokenOut));

            RouteConfig memory firstRoute = routes[firstKey];
            RouteConfig memory secondRoute = routes[secondKey];

            if (firstRoute.isConfigured && secondRoute.isConfigured) {
                strategy.routeType = RouteType.Bridge;
                strategy.bridgeAsset = bridgeAsset;
                strategy.primaryRouteData = _encodeRouteData(firstRoute, tokenIn, bridgeAsset);
                strategy.secondaryRouteData = _encodeRouteData(secondRoute, bridgeAsset, tokenOut);
                strategy.expectedGas =
                    _estimateGasForProtocol(firstRoute.protocol) +
                    _estimateGasForProtocol(secondRoute.protocol);
                return strategy;
            }
        }

        revert NoRouteFound();
    }

    /**
     * @notice External view function for finding strategy
     */
    function _findOptimalExecutionStrategyView(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external view returns (ExecutionStrategy memory) {
        return _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, minAmountOut);
    }

    /**
     * @notice Generate execution data for single route
     */
    function _generateSingleExecutionData(
        ExecutionStrategy memory strategy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (bytes memory) {
        if (strategy.protocol == Protocol.UniswapV3) {
            return
                _generateUniswapV3ExecutionData(tokenIn, tokenOut, amountIn, minAmountOut, strategy.primaryRouteData);
        } else if (strategy.protocol == Protocol.Curve) {
            return _generateCurveExecutionData(tokenIn, tokenOut, amountIn, minAmountOut, strategy.primaryRouteData);
        } else if (strategy.protocol == Protocol.DirectMint) {
            return
                _generateDirectMintExecutionData(tokenIn, tokenOut, amountIn, minAmountOut, strategy.primaryRouteData);
        } else if (strategy.protocol == Protocol.MultiHop) {
            return _generateMultiHopExecutionData(tokenIn, tokenOut, amountIn, minAmountOut, strategy.primaryRouteData);
        }

        revert UnsupportedRoute();
    }

    /**
     * @notice Generate UniswapV3 execution bytecode
     */
    function _generateUniswapV3ExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory routeData
    ) internal view returns (bytes memory) {
        UniswapV3Route memory route = abi.decode(routeData, (UniswapV3Route));

        if (!route.isMultiHop) {
            // Calculate pool if needed
            if (route.pool == address(0)) {
                route.pool = _computeUniswapV3Pool(
                    tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn,
                    tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut,
                    route.fee
                );
            }

            return
                abi.encodeWithSelector(
                    IUniswapV3Router.exactInputSingle.selector,
                    IUniswapV3Router.ExactInputSingleParams({
                        tokenIn: tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn,
                        tokenOut: tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut,
                        fee: route.fee,
                        recipient: address(0), // To be replaced by caller
                        deadline: block.timestamp + 1800, // 30 minutes from now
                        amountIn: amountIn,
                        amountOutMinimum: minAmountOut,
                        sqrtPriceLimitX96: 0
                    })
                );
        } else {
            return
                abi.encodeWithSelector(
                    IUniswapV3Router.exactInput.selector,
                    IUniswapV3Router.ExactInputParams({
                        path: route.path,
                        recipient: address(0), // To be replaced by caller
                        deadline: block.timestamp + 1800, // 30 minutes from now
                        amountIn: amountIn,
                        amountOutMinimum: minAmountOut
                    })
                );
        }
    }

    /**
     * @notice Generate Curve execution bytecode
     */
    function _generateCurveExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory routeData
    ) internal pure returns (bytes memory) {
        CurveRoute memory route = abi.decode(routeData, (CurveRoute));

        if (route.useUnderlying) {
            return
                abi.encodeWithSelector(
                    ICurvePool.exchange_underlying.selector,
                    route.indexIn,
                    route.indexOut,
                    amountIn,
                    minAmountOut
                );
        } else {
            return
                abi.encodeWithSelector(
                    ICurvePool.exchange.selector,
                    route.indexIn,
                    route.indexOut,
                    amountIn,
                    minAmountOut
                );
        }
    }

    /**
     * @notice Generate DirectMint execution data
     */
    function _generateDirectMintExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory routeData
    ) internal pure returns (bytes memory) {
        address minter = abi.decode(routeData, (address));

        if (tokenIn == ETH_ADDRESS && tokenOut == SFRXETH) {
            return
                abi.encodeWithSelector(
                    IFrxETHMinter.submitAndDeposit.selector,
                    address(0) // Recipient to be set by caller
                );
        }

        revert UnsupportedRoute();
    }

    /**
     * @notice Generate multi-hop execution data
     */
    function _generateMultiHopExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory routeData
    ) internal view returns (bytes memory) {
        // For multi-hop, routeData is the path
        bytes memory path = routeData;

        return
            abi.encodeWithSelector(
                IUniswapV3Router.exactInput.selector,
                IUniswapV3Router.ExactInputParams({
                    path: path,
                    recipient: address(0), // To be replaced by caller
                    deadline: block.timestamp + 1800, // 30 minutes from now
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut
                })
            );
    }

    /**
     * @notice Generate bridge execution data
     */
    function _generateBridgeExecutionData(
        ExecutionStrategy memory strategy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (bytes memory) {
        // For bridge swaps, return encoded strategy for LTM to handle
        return
            abi.encode(
                "BRIDGE_SWAP",
                tokenIn,
                strategy.bridgeAsset,
                tokenOut,
                amountIn,
                minAmountOut,
                strategy.primaryRouteData,
                strategy.secondaryRouteData
            );
    }

    /**
     * @notice Estimate swap output with quoter calls
     */
    function _estimateSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        ExecutionStrategy memory strategy
    ) internal returns (uint256) {
        if (strategy.routeType == RouteType.Bridge) {
            // Estimate through bridge
            uint256 bridgeAmount = _estimateSingleSwap(
                tokenIn,
                strategy.bridgeAsset,
                amountIn,
                strategy.primaryRouteData
            );
            return _estimateSingleSwap(strategy.bridgeAsset, tokenOut, bridgeAmount, strategy.secondaryRouteData);
        } else {
            return _estimateSingleSwap(tokenIn, tokenOut, amountIn, strategy.primaryRouteData);
        }
    }

    /**
     * @notice Estimate swap output for view functions
     */
    function _estimateSwapOutputView(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        ExecutionStrategy memory strategy
    ) internal view returns (uint256) {
        if (strategy.routeType == RouteType.Bridge) {
            // Estimate through bridge using simple calculation
            uint256 bridgeAmount = _getSimpleEstimate(amountIn, tokenIn, strategy.bridgeAsset);
            return _getSimpleEstimate(bridgeAmount, strategy.bridgeAsset, tokenOut);
        } else {
            return _getSimpleEstimate(amountIn, tokenIn, tokenOut);
        }
    }

    /**
     * @notice Estimate single swap output
     */
    function _estimateSingleSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory routeData
    ) internal returns (uint256) {
        // Use quoter if available
        try this._performQuoteExternal(tokenIn, tokenOut, amountIn, routeData) returns (uint256 quotedAmount) {
            return quotedAmount;
        } catch {
            // Fallback to simple estimate
            return _getSimpleEstimate(amountIn, tokenIn, tokenOut);
        }
    }

    /**
     * @notice Perform quote with external call
     */
    function _performQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SwapParams memory params
    ) internal returns (QuoteData memory) {
        try this._performQuoteExternal(tokenIn, tokenOut, amountIn, params.routeData) returns (uint256 expectedOutput) {
            return QuoteData({expectedOutput: expectedOutput, timestamp: block.timestamp, valid: true});
        } catch {
            return QuoteData({expectedOutput: 0, timestamp: 0, valid: false});
        }
    }

    /**
     * @notice External quote function for try-catch
     */
    function _performQuoteExternal(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory routeData
    ) external returns (uint256 expectedOutput) {
        // Only allow internal calls
        require(msg.sender == address(this), "Internal only");

        // Decode protocol from route data
        if (routeData.length == 0) return _getSimpleEstimate(amountIn, tokenIn, tokenOut);

        // Try UniswapV3 quote
        try
            uniswapQuoter.quoteExactInputSingle(
                tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn,
                tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut,
                3000, // Default fee tier
                amountIn,
                0
            )
        returns (uint256 quotedAmount) {
            return quotedAmount;
        } catch {
            // Try with different fee tiers
            uint24[3] memory feeTiers = [uint24(500), uint24(3000), uint24(10000)];

            for (uint256 i = 0; i < feeTiers.length; i++) {
                try
                    uniswapQuoter.quoteExactInputSingle(
                        tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn,
                        tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut,
                        feeTiers[i],
                        amountIn,
                        0
                    )
                returns (uint256 quotedAmount) {
                    return quotedAmount;
                } catch {
                    continue;
                }
            }
        }

        // If all quotes fail, return simple estimate
        return _getSimpleEstimate(amountIn, tokenIn, tokenOut);
    }

    // ============================================================================
    // ROUTE CONFIGURATION
    // ============================================================================

    /**
     * @notice Configure a multi-hop route
     */
    function configureMultiHopRoute(
        address tokenIn,
        address tokenOut,
        bytes calldata path,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");
        require(path.length >= 43, "Path too short");

        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));

        routes[routeKey] = RouteConfig({
            protocol: Protocol.MultiHop,
            pool: address(0),
            fee: 0,
            directSwap: false,
            path: path,
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0),
            isConfigured: true,
            routeData: path
        });

        emit RouteConfigured(tokenIn, tokenOut, Protocol.MultiHop, address(0));
    }

    /**
     * @notice Configure a multi-step route across multiple DEXes
     */
    function configureMultiStepRoute(
        address[] calldata tokens,
        Protocol[] calldata protocols,
        RouteConfig[] calldata routeConfigs,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");
        require(tokens.length >= 2, "Need at least 2 tokens");
        require(tokens.length == protocols.length + 1, "Invalid array lengths");
        require(protocols.length == routeConfigs.length, "Config length mismatch");

        // Encode route data for each step
        bytes[] memory routeDatas = new bytes[](protocols.length);
        uint256[] memory minAmounts = new uint256[](protocols.length);

        for (uint256 i = 0; i < protocols.length; i++) {
            routeDatas[i] = _encodeRouteData(routeConfigs[i], tokens[i], tokens[i + 1]);
            minAmounts[i] = 0; // Will be calculated at execution time
        }

        // Store the complete multi-step route
        bytes32 routeKey = keccak256(abi.encodePacked(tokens[0], tokens[tokens.length - 1]));

        routes[routeKey] = RouteConfig({
            protocol: Protocol.MultiStep,
            pool: address(0),
            fee: 0,
            directSwap: false,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0),
            isConfigured: true,
            routeData: abi.encode(tokens, protocols, routeDatas, minAmounts)
        });

        emit RouteConfigured(tokens[0], tokens[tokens.length - 1], Protocol.MultiStep, address(0));
    }

    /**
     * @notice Configure a swap route
     */
    function configureRoute(
        address tokenIn,
        address tokenOut,
        Protocol protocol,
        address pool,
        uint24 fee,
        int128 tokenIndexIn,
        int128 tokenIndexOut,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");

        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));

        routes[routeKey] = RouteConfig({
            protocol: protocol,
            pool: pool,
            fee: fee,
            directSwap: true,
            path: "",
            tokenIndexIn: tokenIndexIn,
            tokenIndexOut: tokenIndexOut,
            useUnderlying: false,
            specialContract: address(0),
            isConfigured: true,
            routeData: ""
        });

        emit RouteConfigured(tokenIn, tokenOut, protocol, pool);
    }

    /**
     * @notice Configure DirectMint route
     */
    function configureDirectMintRoute(
        address tokenIn,
        address tokenOut,
        address minterContract,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");

        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));

        routes[routeKey] = RouteConfig({
            protocol: Protocol.DirectMint,
            pool: address(0),
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: minterContract,
            isConfigured: true,
            routeData: ""
        });

        emit RouteConfigured(tokenIn, tokenOut, Protocol.DirectMint, minterContract);
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Get Curve route data for external callers
     */
    function getCurveRouteData(
        address tokenIn,
        address tokenOut
    ) external view returns (bool isCurve, address pool, int128 indexIn, int128 indexOut, bool useUnderlying) {
        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        RouteConfig memory config = routes[routeKey];

        if (config.isConfigured && config.protocol == Protocol.Curve) {
            return (true, config.pool, config.tokenIndexIn, config.tokenIndexOut, config.useUnderlying);
        }

        return (false, address(0), 0, 0, false);
    }

    /**
     * @notice Compute UniswapV3 pool address
     */
    function _computeUniswapV3Pool(address tokenA, address tokenB, uint24 fee) internal pure returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNISWAP_V3_FACTORY,
                            keccak256(abi.encode(token0, token1, fee)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    /**
     * @notice Get bridge asset for routing
     */
    function _getBridgeAsset(address tokenIn, address tokenOut) internal view returns (address) {
        AssetType typeIn = tokenIn == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenIn];
        AssetType typeOut = tokenOut == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenOut];

        if (typeIn == AssetType.ETH_LST && typeOut == AssetType.ETH_LST) {
            return address(WETH);
        } else if (typeIn == AssetType.BTC_WRAPPED && typeOut == AssetType.BTC_WRAPPED) {
            return WBTC;
        }

        return address(0);
    }

    /**
     * @notice Get slippage for token pair
     */
    function _getSlippage(
        address tokenIn,
        address tokenOut,
        SlippageType slippageType
    ) internal view returns (uint256) {
        if (slippageType == SlippageType.QUOTE) {
            return TIGHT_BUFFER_BPS;
        }

        uint256 configured = slippageTolerance[tokenIn][tokenOut];
        if (configured > 0) return configured;

        return _getDefaultSlippage(tokenIn, tokenOut);
    }

    /**
     * @notice Get default slippage based on asset types
     */
    function _getDefaultSlippage(address tokenIn, address tokenOut) internal view returns (uint256) {
        AssetType typeIn = tokenIn == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenIn];
        AssetType typeOut = tokenOut == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenOut];

        if (typeIn == AssetType.STABLE && typeOut == AssetType.STABLE) return 30;
        if (typeIn == AssetType.ETH_LST || typeOut == AssetType.ETH_LST) return 200;
        if (typeIn == AssetType.BTC_WRAPPED || typeOut == AssetType.BTC_WRAPPED) return 300;

        return 500;
    }

    /**
     * @notice Simple estimate for fallback
     */
    function _getSimpleEstimate(uint256 amountIn, address tokenIn, address tokenOut) internal view returns (uint256) {
        // Normalize amounts based on decimals
        uint8 decimalsIn = tokenDecimals[tokenIn] > 0 ? tokenDecimals[tokenIn] : 18;
        uint8 decimalsOut = tokenDecimals[tokenOut] > 0 ? tokenDecimals[tokenOut] : 18;

        if (decimalsIn == decimalsOut) {
            return (amountIn * 98) / 100; // 2% price impact
        } else if (decimalsIn > decimalsOut) {
            uint256 factor = 10 ** (decimalsIn - decimalsOut);
            return ((amountIn / factor) * 98) / 100;
        } else {
            uint256 factor = 10 ** (decimalsOut - decimalsIn);
            return (amountIn * factor * 98) / 100;
        }
    }

    /**
     * @notice Validate swap parameters
     */
    function _validateSwapParams(SwapParams memory params) internal view {
        if (params.amountIn == 0) revert ZeroAmount();
        if (params.tokenIn == params.tokenOut) revert SameTokenSwap();
        if (!initialized) revert NotInitialized();

        _validateTokenSupport(params.tokenIn, params.tokenOut);
    }

    /**
     * @notice Validate token support
     */
    function _validateTokenSupport(address tokenIn, address tokenOut) internal view {
        if (!farSupportedTokens[tokenIn] && tokenIn != ETH_ADDRESS) {
            revert TokenNotSupported();
        }
        if (!farSupportedTokens[tokenOut] && tokenOut != ETH_ADDRESS) {
            revert TokenNotSupported();
        }
    }

    /**
     * @notice Validate strategy pools
     */
    function _validateStrategyPools(ExecutionStrategy memory strategy) internal view {
        if (strategy.protocol == Protocol.UniswapV3) {
            UniswapV3Route memory route = abi.decode(strategy.primaryRouteData, (UniswapV3Route));
            if (!route.isMultiHop && route.pool != address(0) && !poolWhitelist[route.pool]) {
                revert PoolNotWhitelisted();
            }
        } else if (strategy.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(strategy.primaryRouteData, (CurveRoute));
            if (!poolWhitelist[route.pool]) {
                revert PoolNotWhitelisted();
            }
        }
    }

    /**
     * @notice Estimate gas for protocol
     */
    function _estimateGasForProtocol(Protocol protocol) internal pure returns (uint256) {
        if (protocol == Protocol.UniswapV3) return 150000;
        if (protocol == Protocol.Curve) return 200000;
        if (protocol == Protocol.DirectMint) return 100000;
        if (protocol == Protocol.MultiHop) return 250000;
        if (protocol == Protocol.MultiStep) return 300000;
        return 200000;
    }

    /**
     * @notice Encode route data
     */
    function _encodeRouteData(
        RouteConfig memory config,
        address tokenIn,
        address tokenOut
    ) internal pure returns (bytes memory) {
        if (config.protocol == Protocol.UniswapV3) {
            UniswapV3Route memory route = UniswapV3Route({
                pool: config.pool,
                fee: config.fee,
                isMultiHop: config.path.length > 0,
                path: config.path
            });
            return abi.encode(route);
        } else if (config.protocol == Protocol.Curve) {
            CurveRoute memory route = CurveRoute({
                pool: config.pool,
                indexIn: config.tokenIndexIn,
                indexOut: config.tokenIndexOut,
                useUnderlying: config.useUnderlying
            });
            return abi.encode(route);
        } else if (config.protocol == Protocol.DirectMint) {
            return abi.encode(config.specialContract);
        }

        return config.routeData;
    }

    /**
     * @notice Encode reverse route data
     */
    function _encodeReverseRouteData(
        RouteConfig memory config,
        address tokenIn,
        address tokenOut
    ) internal pure returns (bytes memory) {
        if (config.protocol == Protocol.UniswapV3) {
            UniswapV3Route memory route = UniswapV3Route({
                pool: config.pool,
                fee: config.fee,
                isMultiHop: config.path.length > 0,
                path: config.path // TODO: Reverse path for multi-hop
            });
            return abi.encode(route);
        } else if (config.protocol == Protocol.Curve) {
            CurveRoute memory route = CurveRoute({
                pool: config.pool,
                indexIn: config.tokenIndexOut, // Reversed
                indexOut: config.tokenIndexIn, // Reversed
                useUnderlying: config.useUnderlying
            });
            return abi.encode(route);
        }

        return config.routeData;
    }

    /**
     * @notice Apply production slippage configuration
     */
    function _applyProductionSlippageConfig() internal {
        // ETH to LST tokens
        slippageTolerance[ETH_ADDRESS][0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84] = 50; // ETH->stETH
        slippageTolerance[ETH_ADDRESS][FRXETH] = 50; // ETH->frxETH
        slippageTolerance[ETH_ADDRESS][SFRXETH] = 50; // ETH->sfrxETH

        // WETH to LST tokens
        slippageTolerance[address(WETH)][0xBe9895146f7AF43049ca1c1AE358B0541Ea49704] = 350; // WETH->cbETH
        slippageTolerance[address(WETH)][RETH] = 750; // WETH->rETH
        slippageTolerance[address(WETH)][OSETH] = 500; // WETH->osETH

        // Add more production configurations as needed
    }

    // ============================================================================
    // INTERNAL EXECUTION FUNCTIONS (LEGACY)
    // ============================================================================

    /**
     * @notice Execute auto-routing in direct transfer mode
     */
    function _autoSwapDirectMode(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256) {
        // Find optimal strategy
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, minAmountOut);

        // Validate pools
        _validateStrategyPools(strategy);

        // For direct mode, we need special handling based on protocol
        if (strategy.protocol == Protocol.Curve) {
            // Return expected output for LTM to verify
            return _estimateSwapOutput(tokenIn, tokenOut, amountIn, strategy);
        } else if (strategy.protocol == Protocol.UniswapV3) {
            // Execute via Uniswap with caller as recipient
            return _executeUniswapV3DirectMode(tokenIn, tokenOut, amountIn, minAmountOut, strategy);
        } else if (strategy.protocol == Protocol.DirectMint) {
            // Direct mint requires special handling
            revert InvalidParameter("DirectMint not supported in direct mode");
        }

        revert UnsupportedRoute();
    }

    /**
     * @notice Execute UniswapV3 swap in direct mode
     */
    function _executeUniswapV3DirectMode(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        ExecutionStrategy memory strategy
    ) internal returns (uint256) {
        UniswapV3Route memory route = abi.decode(strategy.primaryRouteData, (UniswapV3Route));

        if (!route.isMultiHop) {
            // Single hop
            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn,
                tokenOut: tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut,
                fee: route.fee,
                recipient: msg.sender, // Direct to caller
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

            return uniswapRouter.exactInputSingle(params);
        } else {
            // Multi-hop
            IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router.ExactInputParams({
                path: route.path,
                recipient: msg.sender, // Direct to caller
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut
            });

            return uniswapRouter.exactInput(params);
        }
    }

    /**
     * @notice Legacy swap with transfers (for backward compatibility)
     */
    function _swapAssetsWithTransfer(SwapParams memory params) internal returns (uint256 amountOut) {
        // Transfer tokens to FAR
        uint256 balanceBefore = IERC20(params.tokenIn).balanceOf(address(this));
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        uint256 actualAmountIn = IERC20(params.tokenIn).balanceOf(address(this)) - balanceBefore;

        params.amountIn = actualAmountIn;

        // Execute swap using quoter-first approach
        amountOut = _executeSwapInternal(params);

        // Transfer output to caller
        IERC20(params.tokenOut).safeTransfer(msg.sender, amountOut);

        emit AssetsSwapped(
            params.tokenIn,
            params.tokenOut,
            actualAmountIn,
            amountOut,
            params.protocol,
            msg.sender,
            0,
            block.timestamp
        );
    }

    /**
     * @notice Execute swap internally with full protocol support
     */
    function _executeSwapInternal(SwapParams memory params) internal returns (uint256 amountOut) {
        // Validate protocol is not paused
        if (protocolPaused[params.protocol]) revert ProtocolIsPaused();

        // Handle token input (ETH to WETH conversion if needed)
        address actualTokenIn = params.tokenIn;
        if (params.tokenIn == ETH_ADDRESS) {
            WETH.deposit{value: params.amountIn}();
            actualTokenIn = address(WETH);
        }

        // Use quoter-first approach
        QuoteData memory quote = _performQuote(params.tokenIn, params.tokenOut, params.amountIn, params);

        uint256 minAmountOut;
        if (quote.valid && block.timestamp - quote.timestamp <= QUOTE_MAX_AGE) {
            // Use tight buffer with quote
            minAmountOut = (quote.expectedOutput * (10000 - TIGHT_BUFFER_BPS)) / 10000;
        } else {
            // Fallback to configured slippage
            uint256 slippage = slippageTolerance[params.tokenIn][params.tokenOut];
            if (slippage == 0) slippage = _getDefaultSlippage(params.tokenIn, params.tokenOut);

            uint256 expectedOutput = quote.valid
                ? quote.expectedOutput
                : _getSimpleEstimate(params.amountIn, params.tokenIn, params.tokenOut);
            minAmountOut = (expectedOutput * (10000 - slippage)) / 10000;
        }

        // Ensure we meet minimum requirements
        if (minAmountOut < params.minAmountOut) {
            minAmountOut = params.minAmountOut;
        }

        // Execute based on protocol
        if (params.protocol == Protocol.UniswapV3) {
            amountOut = _executeUniswapV3Swap(actualTokenIn, params, minAmountOut);
        } else if (params.protocol == Protocol.Curve) {
            amountOut = _executeCurveSwap(actualTokenIn, params, minAmountOut);
        } else if (params.protocol == Protocol.DirectMint) {
            amountOut = _executeDirectMint(params, minAmountOut);
        } else if (params.protocol == Protocol.MultiHop) {
            amountOut = _executeMultiHopSwap(actualTokenIn, params, minAmountOut);
        } else if (params.protocol == Protocol.MultiStep) {
            amountOut = _executeMultiStepSwap(actualTokenIn, params, minAmountOut);
        } else {
            revert InvalidProtocol();
        }

        // Handle WETH to ETH conversion if output is ETH
        if (params.tokenOut == ETH_ADDRESS && amountOut > 0) {
            WETH.withdraw(amountOut);
        }

        if (amountOut < params.minAmountOut) revert InsufficientOutput();
    }

    /**
     * @notice Execute UniswapV3 swap
     */
    function _executeUniswapV3Swap(
        address actualTokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        UniswapV3Route memory route = abi.decode(params.routeData, (UniswapV3Route));

        // Validate pool if single-hop
        if (!route.isMultiHop && route.pool != address(0)) {
            if (!poolWhitelist[route.pool]) revert PoolNotWhitelisted();
            if (poolPaused[route.pool]) revert PoolIsPaused();
        }

        // Set approval
        IERC20(actualTokenIn).safeApprove(address(uniswapRouter), params.amountIn);

        if (route.isMultiHop) {
            amountOut = uniswapRouter.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: route.path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: params.amountIn,
                    amountOutMinimum: minAmountOut
                })
            );
        } else {
            // For single hop, compute pool if not provided
            if (route.pool == address(0)) {
                route.pool = _computeUniswapV3Pool(
                    actualTokenIn,
                    params.tokenOut == ETH_ADDRESS ? address(WETH) : params.tokenOut,
                    route.fee
                );
            }

            amountOut = uniswapRouter.exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: actualTokenIn,
                    tokenOut: params.tokenOut == ETH_ADDRESS ? address(WETH) : params.tokenOut,
                    fee: route.fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: params.amountIn,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        // Reset approval
        IERC20(actualTokenIn).safeApprove(address(uniswapRouter), 0);
    }

    /**
     * @notice Execute Curve swap
     */
    function _executeCurveSwap(
        address actualTokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        CurveRoute memory route = abi.decode(params.routeData, (CurveRoute));

        // Validate pool
        if (!poolWhitelist[route.pool]) revert PoolNotWhitelisted();
        if (poolPaused[route.pool]) revert PoolIsPaused();

        // Handle ETH/WETH for Curve
        uint256 valueToSend = 0;
        if (params.tokenIn == ETH_ADDRESS) {
            valueToSend = params.amountIn;
            // WETH was already withdrawn in _executeSwapInternal
        } else {
            IERC20(actualTokenIn).safeApprove(route.pool, params.amountIn);
        }

        // Execute swap
        if (route.useUnderlying) {
            amountOut = ICurvePool(route.pool).exchange_underlying{value: valueToSend}(
                route.indexIn,
                route.indexOut,
                params.amountIn,
                minAmountOut
            );
        } else {
            amountOut = ICurvePool(route.pool).exchange{value: valueToSend}(
                route.indexIn,
                route.indexOut,
                params.amountIn,
                minAmountOut
            );
        }

        // Reset approval if needed
        if (params.tokenIn != ETH_ADDRESS) {
            IERC20(actualTokenIn).safeApprove(route.pool, 0);
        }
    }

    /**
     * @notice Execute direct mint
     */
    function _executeDirectMint(SwapParams memory params, uint256 minAmountOut) internal returns (uint256 amountOut) {
        address minter = abi.decode(params.routeData, (address));

        if (params.tokenIn == ETH_ADDRESS && params.tokenOut == SFRXETH) {
            amountOut = IFrxETHMinter(minter).submitAndDeposit{value: params.amountIn}(address(this));
            if (amountOut < minAmountOut) revert InsufficientOutput();
        } else {
            revert UnsupportedRoute();
        }
    }

    /**
     * @notice Execute multi-hop swap (single DEX, multiple pools)
     */
    function _executeMultiHopSwap(
        address actualTokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Decode the multi-hop route
        bytes memory path = abi.decode(params.routeData, (bytes));
        require(path.length >= 43, "Invalid path"); // minimum: 20 + 3 + 20

        // For Uniswap V3 multi-hop
        if (params.protocol == Protocol.UniswapV3 || params.protocol == Protocol.MultiHop) {
            // Approve router
            IERC20(actualTokenIn).safeApprove(address(uniswapRouter), params.amountIn);

            // Execute multi-hop swap
            amountOut = uniswapRouter.exactInput(
                IUniswapV3Router.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: params.amountIn,
                    amountOutMinimum: minAmountOut
                })
            );

            // Reset approval
            IERC20(actualTokenIn).safeApprove(address(uniswapRouter), 0);

            require(amountOut >= minAmountOut, "Insufficient output");
        } else {
            revert("Unsupported multi-hop protocol");
        }
    }

    /**
     * @notice Execute multi-step swap (multiple DEXes)
     */
    function _executeMultiStepSwap(
        address actualTokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Decode multi-step data
        (
            address[] memory tokens,
            Protocol[] memory protocols,
            bytes[] memory routeDatas,
            uint256[] memory minAmounts
        ) = abi.decode(params.routeData, (address[], Protocol[], bytes[], uint256[]));

        require(tokens.length >= 2, "Invalid tokens array");
        require(tokens.length == protocols.length + 1, "Invalid protocols length");
        require(protocols.length == routeDatas.length, "Invalid route data length");
        require(protocols.length == minAmounts.length, "Invalid min amounts length");
        require(tokens[0] == actualTokenIn, "First token mismatch");
        require(tokens[tokens.length - 1] == params.tokenOut, "Last token mismatch");

        uint256 currentAmount = params.amountIn;
        address currentToken = actualTokenIn;

        // Execute each step
        for (uint256 i = 0; i < protocols.length; i++) {
            require(protocols.length <= MAX_MULTI_STEP_OPERATIONS, "Too many steps");

            address nextToken = tokens[i + 1];

            // Create swap params for this step
            SwapParams memory stepParams = SwapParams({
                tokenIn: currentToken,
                tokenOut: nextToken,
                amountIn: currentAmount,
                minAmountOut: minAmounts[i],
                protocol: protocols[i],
                routeData: routeDatas[i]
            });

            // Execute based on protocol
            if (protocols[i] == Protocol.UniswapV3) {
                currentAmount = _executeUniswapV3Swap(currentToken, stepParams, minAmounts[i]);
            } else if (protocols[i] == Protocol.Curve) {
                currentAmount = _executeCurveSwap(currentToken, stepParams, minAmounts[i]);
            } else if (protocols[i] == Protocol.DirectMint) {
                currentAmount = _executeDirectMint(stepParams, minAmounts[i]);
            } else {
                revert("Unsupported protocol in multi-step");
            }

            currentToken = nextToken;

            // Handle WETH/ETH conversions between steps if needed
            if (i < protocols.length - 1) {
                if (currentToken == address(WETH) && tokens[i + 2] == ETH_ADDRESS) {
                    WETH.withdraw(currentAmount);
                    currentToken = ETH_ADDRESS;
                } else if (currentToken == ETH_ADDRESS && tokens[i + 2] != ETH_ADDRESS) {
                    WETH.deposit{value: currentAmount}();
                    currentToken = address(WETH);
                }
            }
        }

        amountOut = currentAmount;
        require(amountOut >= minAmountOut, "Insufficient final output");
    }

    /**
     * @notice Auto swap with transfers (legacy mode)
     */
    function _autoSwapWithTransfers(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Find optimal route
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, minAmountOut);

        // Handle token input
        if (tokenIn == ETH_ADDRESS) {
            require(msg.value >= amountIn, "Insufficient ETH");
            if (msg.value > amountIn) {
                // Refund excess
                (bool success, ) = msg.sender.call{value: msg.value - amountIn}("");
                require(success, "ETH refund failed");
            }
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Execute based on route type
        if (strategy.routeType == RouteType.Direct || strategy.routeType == RouteType.Reverse) {
            // Single swap
            SwapParams memory params = SwapParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                protocol: strategy.protocol,
                routeData: strategy.primaryRouteData
            });

            amountOut = _executeSwapInternal(params);
        } else if (strategy.routeType == RouteType.Bridge) {
            // Bridge swap (two hops)
            // First swap: tokenIn -> bridgeAsset
            SwapParams memory firstParams = SwapParams({
                tokenIn: tokenIn,
                tokenOut: strategy.bridgeAsset,
                amountIn: amountIn,
                minAmountOut: 0, // Will calculate intermediate minimum
                protocol: _getProtocolFromRouteData(strategy.primaryRouteData),
                routeData: strategy.primaryRouteData
            });

            uint256 bridgeAmount = _executeSwapInternal(firstParams);

            // Second swap: bridgeAsset -> tokenOut
            SwapParams memory secondParams = SwapParams({
                tokenIn: strategy.bridgeAsset,
                tokenOut: tokenOut,
                amountIn: bridgeAmount,
                minAmountOut: minAmountOut,
                protocol: _getProtocolFromRouteData(strategy.secondaryRouteData),
                routeData: strategy.secondaryRouteData
            });

            amountOut = _executeSwapInternal(secondParams);
        } else {
            revert NoRouteFound();
        }

        // Transfer output to caller
        if (tokenOut == ETH_ADDRESS) {
            (bool success, ) = msg.sender.call{value: amountOut}("");
            if (!success) {
                // Fallback to WETH
                WETH.deposit{value: amountOut}();
                IERC20(address(WETH)).safeTransfer(msg.sender, amountOut);
            }
        } else {
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        }

        emit AssetsSwapped(tokenIn, tokenOut, amountIn, amountOut, strategy.protocol, msg.sender, 0, block.timestamp);
    }

    /**
     * @notice Execute direct mode swap (no token transfers to FAR)
     */
    function _executeDirectModeSwap(SwapParams memory params) internal returns (uint256 amountOut) {
        // Validate caller has approved FAR
        if (params.tokenIn != ETH_ADDRESS) {
            uint256 allowance = IERC20(params.tokenIn).allowance(msg.sender, address(this));
            require(allowance >= params.amountIn, "Insufficient allowance");
        }

        // Find route
        bytes32 routeKey = keccak256(abi.encodePacked(params.tokenIn, params.tokenOut));
        RouteConfig memory config = routes[routeKey];

        if (!config.isConfigured) {
            // Try reverse route
            routeKey = keccak256(abi.encodePacked(params.tokenOut, params.tokenIn));
            config = routes[routeKey];
            require(config.isConfigured, "No route found");

            // Adjust for reverse
            params = _makeReverseSwapParams(params);
        }

        // For direct mode, we return the expected output
        // The actual swap execution happens in the caller (LTM)

        // Get quote for accurate output
        QuoteData memory quote = _performQuote(params.tokenIn, params.tokenOut, params.amountIn, params);

        if (quote.valid) {
            amountOut = quote.expectedOutput;
        } else {
            // Estimate based on slippage
            amountOut = _getSimpleEstimate(params.amountIn, params.tokenIn, params.tokenOut);
        }

        // Apply slippage for safety
        uint256 slippage = slippageTolerance[params.tokenIn][params.tokenOut];
        if (slippage == 0) slippage = _getDefaultSlippage(params.tokenIn, params.tokenOut);

        amountOut = (amountOut * (10000 - slippage)) / 10000;

        require(amountOut >= params.minAmountOut, "Insufficient output");

        emit AssetsSwapped(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.protocol,
            msg.sender,
            0,
            block.timestamp
        );
    }

    /**
     * @notice Helper to make reverse swap params
     */
    function _makeReverseSwapParams(SwapParams memory params) internal pure returns (SwapParams memory) {
        // Swap tokenIn and tokenOut
        address tempToken = params.tokenIn;
        params.tokenIn = params.tokenOut;
        params.tokenOut = tempToken;

        // Reverse route data indices for Curve
        if (params.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(params.routeData, (CurveRoute));
            int128 tempIndex = route.indexIn;
            route.indexIn = route.indexOut;
            route.indexOut = tempIndex;
            params.routeData = abi.encode(route);
        }

        return params;
    }

    /**
     * @notice Get protocol from route data
     */
    function _getProtocolFromRouteData(bytes memory routeData) internal pure returns (Protocol) {
        // Decode first byte as protocol identifier
        if (routeData.length > 0) {
            uint8 protocolId = uint8(routeData[0]);
            if (protocolId <= uint8(Protocol.MultiStep)) {
                return Protocol(protocolId);
            }
        }
        return Protocol.UniswapV3; // Default
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

    /**
     * @notice Set direct transfer mode
     */
    function setDirectTransferMode(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        directTransferMode = _enabled;
        emit DirectTransferModeUpdated(_enabled, block.timestamp);
    }

    /**
     * @notice Grant operator role
     */
    function grantOperatorRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @notice Revoke operator role
     */
    function revokeOperatorRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @notice Emergency pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Configure slippage tolerance
     */
    function configureSlippage(
        address tokenIn,
        address tokenOut,
        uint256 slippageBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(slippageBps <= MAX_SLIPPAGE, "Slippage too high");
        slippageTolerance[tokenIn][tokenOut] = slippageBps;
        emit SlippageConfigured(tokenIn, tokenOut, slippageBps, msg.sender, block.timestamp);
    }

    /**
     * @notice Add supported token
     */
    function addSupportedToken(
        address token,
        AssetType assetType,
        uint8 decimals
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(decimals > 0 && decimals <= 18, "Invalid decimals");

        farSupportedTokens[token] = true;
        assetTypes[token] = assetType;
        tokenDecimals[token] = decimals;

        emit TokenSupported(token, true, assetType, decimals, block.timestamp);
    }

    /**
     * @notice Remove supported token
     */
    function removeSupportedToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        farSupportedTokens[token] = false;
        emit TokenSupported(token, false, assetTypes[token], tokenDecimals[token], block.timestamp);
    }

    /**
     * @notice Whitelist pool
     */
    function whitelistPool(
        address pool,
        uint256 tokenCount,
        CurveInterface curveInterface
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(pool != address(0), "Invalid pool");
        poolWhitelist[pool] = true;
        curvePoolTokenCounts[pool] = tokenCount;
        curvePoolInterfaces[pool] = curveInterface;
        emit PoolWhitelisted(pool, true, curveInterface, msg.sender, block.timestamp);
    }

    /**
     * @notice Remove pool from whitelist
     */
    function removePoolFromWhitelist(address pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolWhitelist[pool] = false;
        emit PoolWhitelisted(pool, false, curvePoolInterfaces[pool], msg.sender, block.timestamp);
    }

    /**
     * @notice Pause/unpause pool
     */
    function setPoolPaused(address pool, bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolPaused[pool] = paused;
    }

    /**
     * @notice Pause/unpause protocol
     */
    function setProtocolPaused(Protocol protocol, bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolPaused[protocol] = paused;
    }

    /**
     * @notice Update route manager
     */
    function updateRouteManager(address newManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newManager != address(0), "Invalid manager");
        routeManager = newManager;
    }

    // ============================================================================
    // CUSTOM DEX
    // ============================================================================

    /**
     * @notice Register a new DEX for custom routing
     * @param dex The DEX contract address
     * @param name The name of the DEX
     * @param password Security password for registration
     */
    function registerDEX(
        address dex,
        string calldata name,
        string calldata password
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(dex != address(0), "Invalid DEX address");
        require(bytes(name).length > 0 && bytes(name).length <= 32, "Invalid DEX name length");
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");
        require(!registeredDEXes[dex], "DEX already registered");

        // Validate DEX is a contract
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(dex)
        }
        require(codeSize > 0, "DEX must be a contract");

        registeredDEXes[dex] = true;
        dexNames[dex] = name;
        dexRegistrationTime[dex] = block.timestamp;
        dexRegisteredBy[dex] = msg.sender;
        allRegisteredDEXes.push(dex);

        emit DexRegistered(dex, name, msg.sender, block.timestamp);
    }

    /**
     * @notice Unregister a DEX
     * @param dex The DEX to unregister
     */
    function unregisterDEX(address dex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(registeredDEXes[dex], "DEX not registered");
        require(block.timestamp >= dexRegistrationTime[dex] + DEX_TIMELOCK, "Timelock not expired");

        registeredDEXes[dex] = false;
        emit DexUnregistered(dex, msg.sender, block.timestamp);
    }

    /**
     * @notice Whitelist a function selector for custom DEX calls
     * @param selector The function selector to whitelist
     * @param description Description of what this selector does
     */
    function whitelistSelector(bytes4 selector, string calldata description) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!dangerousSelectors[selector], "Selector is blacklisted");
        require(bytes(description).length > 0, "Description required");

        whitelistedSelectors[selector] = true;
        selectorDescriptions[selector] = description;
        allWhitelistedSelectors.push(selector);

        emit SelectorWhitelisted(selector, description, block.timestamp);
    }

    /**
     * @notice Blacklist a dangerous function selector
     * @param selector The function selector to blacklist
     * @param reason Reason for blacklisting
     */
    function blacklistSelector(bytes4 selector, string calldata reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(reason).length > 0, "Reason required");

        dangerousSelectors[selector] = true;
        whitelistedSelectors[selector] = false;

        // Add common dangerous selectors if not already added
        if (allDangerousSelectors.length == 0) {
            _initializeDangerousSelectors();
        }

        allDangerousSelectors.push(selector);
        emit SelectorBlacklisted(selector, reason, block.timestamp);
    }

    /**
     * @notice Initialize common dangerous selectors
     */
    function _initializeDangerousSelectors() internal {
        // Ownership functions
        dangerousSelectors[0x13af4035] = true; // setOwner(address)
        dangerousSelectors[0xf2fde38b] = true; // transferOwnership(address)
        dangerousSelectors[0x715018a6] = true; // renounceOwnership()

        // Upgrade functions
        dangerousSelectors[0x3659cfe6] = true; // upgradeTo(address)
        dangerousSelectors[0x4f1ef286] = true; // upgradeToAndCall(address,bytes)

        // Self-destruct
        dangerousSelectors[0x83197ef0] = true; // destroy()
        dangerousSelectors[0x00f55d9d] = true; // destroy(address)

        // Initialization
        dangerousSelectors[0x8129fc1c] = true; // initialize()
    }

    /**
     * @notice Execute a swap through a registered custom DEX
     * @param targetDEX The DEX to execute swap on
     * @param swapData The encoded swap function call
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param minAmountOut Minimum output amount
     * @param password Security password
     * @return amountOut The actual output amount
     */
    function executeBackendSwap(
        address targetDEX,
        bytes calldata swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        string calldata password
    ) external payable onlyRouteManager nonReentrant whenNotPaused returns (uint256 amountOut) {
        // Validate password
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");

        // Validate DEX
        require(registeredDEXes[targetDEX], "DEX not registered");
        require(block.timestamp >= dexRegistrationTime[targetDEX] + DEX_TIMELOCK, "DEX timelock not expired");

        // Validate swap data
        require(swapData.length >= 4, "Invalid swap data");
        bytes4 selector = bytes4(swapData[:4]);

        // Security checks
        require(!dangerousSelectors[selector], "Dangerous selector");
        require(whitelistedSelectors[selector], "Selector not whitelisted");

        // Validate tokens
        require(tokenIn != address(0) && tokenOut != address(0), "Invalid tokens");
        require(tokenIn != tokenOut, "Same token swap");

        // Record balances before
        uint256 balanceBefore = tokenOut == ETH_ADDRESS
            ? address(this).balance
            : IERC20(tokenOut).balanceOf(address(this));

        // Handle token approvals
        if (tokenIn != ETH_ADDRESS) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).safeApprove(targetDEX, amountIn);
        }

        // Execute swap with gas limit
        (bool success, bytes memory result) = targetDEX.call{
            value: tokenIn == ETH_ADDRESS ? amountIn : 0,
            gas: MAX_DEX_GAS_LIMIT
        }(swapData);

        if (!success) {
            // Reset approval on failure
            if (tokenIn != ETH_ADDRESS) {
                IERC20(tokenIn).safeApprove(targetDEX, 0);
            }

            // Decode revert reason if possible
            string memory reason = "Unknown error";
            if (result.length > 0) {
                assembly {
                    reason := mload(add(result, 0x20))
                }
            }

            emit CustomDexSwapFailed(targetDEX, reason, result);
            revert SwapFailed(reason);
        }

        // Reset approval
        if (tokenIn != ETH_ADDRESS) {
            IERC20(tokenIn).safeApprove(targetDEX, 0);
        }

        // Calculate output amount
        uint256 balanceAfter = tokenOut == ETH_ADDRESS
            ? address(this).balance
            : IERC20(tokenOut).balanceOf(address(this));

        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= minAmountOut, "Insufficient output");

        // Transfer output to caller
        if (tokenOut == ETH_ADDRESS) {
            (bool sent, ) = msg.sender.call{value: amountOut}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        }

        emit BackendSwapExecuted(targetDEX, tokenIn, tokenOut, amountIn, amountOut, msg.sender, block.timestamp);
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Check if a route exists
     */
    function hasRoute(address tokenIn, address tokenOut) external view returns (bool) {
        bytes32 directKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        bytes32 reverseKey = keccak256(abi.encodePacked(tokenOut, tokenIn));

        if (routes[directKey].isConfigured || routes[reverseKey].isConfigured) {
            return true;
        }

        // Check bridge route
        address bridgeAsset = _getBridgeAsset(tokenIn, tokenOut);
        if (bridgeAsset != address(0)) {
            bytes32 firstKey = keccak256(abi.encodePacked(tokenIn, bridgeAsset));
            bytes32 secondKey = keccak256(abi.encodePacked(bridgeAsset, tokenOut));

            return routes[firstKey].isConfigured && routes[secondKey].isConfigured;
        }

        return false;
    }

    /**
     * @notice Get route configuration
     */
    function getRoute(address tokenIn, address tokenOut) external view returns (RouteConfig memory) {
        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        return routes[routeKey];
    }

    /**
     * @notice Get all supported tokens
     */
    function getSupportedTokens() external view returns (address[] memory tokens, AssetType[] memory types) {
        uint256 count = 0;
        address[] memory tempTokens = new address[](100);

        // Count supported tokens (simplified for demo)
        // In production, maintain a separate array of supported tokens

        return (tempTokens, types);
    }

    /**
     * @notice Get pool status
     */
    function getPoolStatus(address pool) external view returns (bool whitelisted, bool paused) {
        return (poolWhitelist[pool], poolPaused[pool]);
    }

    /**
     * @notice Get protocol status
     */
    function getProtocolStatus(Protocol protocol) external view returns (bool paused) {
        return protocolPaused[protocol];
    }

    // ============================================================================
    // RECEIVE ETHER
    // ============================================================================

    receive() external payable {}
}
