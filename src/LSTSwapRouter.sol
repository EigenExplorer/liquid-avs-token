// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; //below 5 path (LSR PRODUCT is 5)
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interfaces
import "./interfaces/ICurvePool.sol";
import "./interfaces/IFrxETHMinter.sol";
import "./interfaces/IUniswapV3Quoter.sol";
import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IWETH.sol";

/**
 * @title LSTSwapRouter
 * @notice Intelligent routing system that provides execution data without holding assets
 * @dev LSTSwapRouter acts as a guide for Executor, never touching tokens directly
 */
contract LSTSwapRouter is AccessControl, ReentrancyGuard, Pausable {
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
    address public routeManager;

    // Mappings
    mapping(address => mapping(address => uint256)) public slippageTolerance;
    mapping(address => AssetType) public assetTypes;
    mapping(address => bool) public poolWhitelist;
    mapping(address => bool) public farSupportedTokens;
    mapping(address => bool) public poolPaused;
    mapping(Protocol => bool) public protocolPaused;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => uint256) public curvePoolTokenCounts;
    mapping(address => CurveInterface) public curvePoolInterfaces;
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

    struct ExecutionStep {
        address target;
        uint256 value;
        bytes data;
        address tokenIn;
        address tokenOut;
        bool requiresApproval;
        bool isCurvePool;
    }

    struct SlippageConfig {
        address tokenIn;
        address tokenOut;
        uint256 slippageBps;
    }

    struct SwapStep {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address target;
        bytes data;
        uint256 value;
        Protocol protocol;
    }

    struct MultiStepExecutionPlan {
        SwapStep[] steps;
        uint256 expectedFinalAmount;
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

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
    event MultiStepPlanGenerated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 stepCount
    );
    
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
    // MAIN FUNCTIONS FOR Executor INTEGRATION
    // ============================================================================
    /**
     * @notice Get accurate quote and execution data for Executor - THIS IS THE MAIN FUNCTION
     * @dev Returns executable calldata that Executor can use directly without LSTSwapRouter touching assets
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param recipient The final recipient of tokens (usually Executor)
     * @return quotedAmount The accurate quoted output amount
     * @return executionData The calldata for Executor to execute directly on DEX
     * @return protocol The protocol to use
     * @return targetContract The DEX contract Executor should call
     * @return value ETH value to send (if ETH swap)
     */
    function getQuoteAndExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
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
        if (recipient == address(0)) revert InvalidAddress();

        // Validate cross-category early
        if (_isCrossCategory(tokenIn, tokenOut)) {
            revert NoRouteFound();
        }

        // Find optimal strategy
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, 0);

        // Get quote with proper fallback mechanism
        uint256 minAmountOut;

        if (strategy.protocol == Protocol.MultiStep) {
            // Special handling for multi-step
            (address[] memory tokens, Protocol[] memory protocols, bytes[] memory routeDatas, ) = abi.decode(
                strategy.primaryRouteData,
                (address[], Protocol[], bytes[], uint256[])
            );

            // Calculate dynamic min amounts for all steps
            uint256[] memory calculatedMinAmounts;
            (calculatedMinAmounts, quotedAmount) = _calculateMultiStepMinAmounts(
                tokens,
                amountIn,
                protocols,
                routeDatas
            );

            // Use the final step's minimum as overall minimum
            minAmountOut = calculatedMinAmounts[calculatedMinAmounts.length - 1];

            // Update strategy with calculated amounts
            strategy.primaryRouteData = abi.encode(tokens, protocols, routeDatas, calculatedMinAmounts);
        } else {
            // Standard quote for single/bridge routes
            (quotedAmount, minAmountOut) = _getQuoteWithFallback(tokenIn, tokenOut, amountIn, strategy);
        }

        // Generate execution data based on route type
        if (strategy.routeType == RouteType.Bridge) {
            // For bridge routes, calculate first leg minimum
            (uint256 firstLegQuote, uint256 firstLegMin) = _getQuoteWithFallback(
                tokenIn,
                strategy.bridgeAsset,
                amountIn,
                ExecutionStrategy({
                    routeType: RouteType.Direct,
                    protocol: strategy.protocol,
                    bridgeAsset: address(0),
                    primaryRouteData: strategy.primaryRouteData,
                    secondaryRouteData: "",
                    expectedGas: _estimateGasForProtocol(strategy.protocol)
                })
            );

            // Get first step execution data
            (executionData, targetContract) = _generateDirectExecutionData(
                ExecutionStrategy({
                    routeType: RouteType.Direct,
                    protocol: strategy.protocol,
                    bridgeAsset: address(0),
                    primaryRouteData: strategy.primaryRouteData,
                    secondaryRouteData: "",
                    expectedGas: _estimateGasForProtocol(strategy.protocol)
                }),
                tokenIn,
                strategy.bridgeAsset,
                amountIn,
                firstLegMin, // Use calculated minimum for first leg
                recipient
            );

            // Wrap with bridge metadata for Executor
            executionData = abi.encode(
                uint8(2), // Bridge flag
                targetContract,
                executionData,
                strategy.bridgeAsset,
                tokenOut,
                minAmountOut // This is the overall minimum for the entire route
            );

            protocol = Protocol.MultiStep; // Executor treats bridge as MultiStep
        } else if (strategy.protocol == Protocol.MultiStep) {
            // Multi-step: get first execution with calculated minimums
            (
                address[] memory tokens,
                Protocol[] memory protocols,
                bytes[] memory routeDatas,
                uint256[] memory minAmounts
            ) = abi.decode(strategy.primaryRouteData, (address[], Protocol[], bytes[], uint256[]));

            ExecutionStrategy memory firstStep = ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: protocols[0],
                bridgeAsset: address(0),
                primaryRouteData: routeDatas[0],
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(protocols[0])
            });

            (bytes memory firstExecution, address firstTarget) = _generateDirectExecutionData(
                firstStep,
                tokens[0],
                tokens[1],
                amountIn,
                minAmounts[0], // Use calculated minimum
                recipient
            );

            targetContract = firstTarget;

            // Wrap with multi-step metadata
            executionData = abi.encode(
                uint8(3), // Multi-step flag
                firstTarget,
                firstExecution,
                tokens,
                protocols,
                routeDatas,
                minAmounts // Pass all calculated minimums
            );

            protocol = Protocol.MultiStep;
        } else {
            // Single step execution - direct DEX call
            (executionData, targetContract) = _generateDirectExecutionData(
                strategy,
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                recipient
            );
            protocol = strategy.protocol;
        }

        // Set ETH value if needed
        value = (tokenIn == ETH_ADDRESS) ? amountIn : 0;

        emit ExecutionDataGenerated(tokenIn, tokenOut, amountIn, protocol, block.timestamp);
    }
    
    /**
     * @notice Get complete swap execution plan for Executor
     * @dev Returns all necessary data for Executor to execute swap(s) blindly
     */
    function getCompleteExecutionPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        returns (
            uint256 quotedOutput,
            uint256 minAmountOut,
            ExecutionStep[] memory steps,
            uint256 totalGas,
            uint256 ethValue
        )
    {
        // Find strategy
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, 0);

        // Get quote with fallback
        (quotedOutput, minAmountOut) = _getQuoteWithFallback(tokenIn, tokenOut, amountIn, strategy);

        // Build execution steps
        if (strategy.routeType == RouteType.Bridge) {
            steps = new ExecutionStep[](2);

            // First step: tokenIn -> bridgeAsset
            (bytes memory data1, address target1) = _generateDirectExecutionData(
                ExecutionStrategy({
                    routeType: RouteType.Direct,
                    protocol: strategy.protocol,
                    bridgeAsset: address(0),
                    primaryRouteData: strategy.primaryRouteData,
                    secondaryRouteData: "",
                    expectedGas: _estimateGasForProtocol(strategy.protocol)
                }),
                tokenIn,
                strategy.bridgeAsset,
                amountIn,
                0, // No min for intermediate
                recipient
            );

            steps[0] = ExecutionStep({
                target: target1,
                value: tokenIn == ETH_ADDRESS ? amountIn : 0,
                data: data1,
                tokenIn: tokenIn,
                tokenOut: strategy.bridgeAsset,
                requiresApproval: tokenIn != ETH_ADDRESS,
                isCurvePool: strategy.protocol == Protocol.Curve
            });

            // Second step will be determined after first completes
            steps[1] = ExecutionStep({
                target: address(0), // To be filled by Executor
                value: 0,
                data: "",
                tokenIn: strategy.bridgeAsset,
                tokenOut: tokenOut,
                requiresApproval: true,
                isCurvePool: false
            });
        } else if (strategy.protocol == Protocol.MultiStep) {
            // Decode multi-step
            (
                address[] memory tokens,
                Protocol[] memory protocols,
                bytes[] memory routeDatas,
                uint256[] memory minAmounts
            ) = abi.decode(strategy.primaryRouteData, (address[], Protocol[], bytes[], uint256[]));

            steps = new ExecutionStep[](protocols.length);

            // Build each step
            for (uint256 i = 0; i < protocols.length; i++) {
                ExecutionStrategy memory stepStrategy = ExecutionStrategy({
                    routeType: RouteType.Direct,
                    protocol: protocols[i],
                    bridgeAsset: address(0),
                    primaryRouteData: routeDatas[i],
                    secondaryRouteData: "",
                    expectedGas: _estimateGasForProtocol(protocols[i])
                });

                (bytes memory data, address target) = _generateDirectExecutionData(
                    stepStrategy,
                    tokens[i],
                    tokens[i + 1],
                    i == 0 ? amountIn : 0, // Only first step has known input
                    minAmounts[i],
                    recipient
                );

                steps[i] = ExecutionStep({
                    target: target,
                    value: (i == 0 && tokens[i] == ETH_ADDRESS) ? amountIn : 0,
                    data: data,
                    tokenIn: tokens[i],
                    tokenOut: tokens[i + 1],
                    requiresApproval: tokens[i] != ETH_ADDRESS,
                    isCurvePool: protocols[i] == Protocol.Curve
                });
            }
        } else {
            // Single step
            steps = new ExecutionStep[](1);

            (bytes memory data, address target) = _generateDirectExecutionData(
                strategy,
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                recipient
            );

            steps[0] = ExecutionStep({
                target: target,
                value: tokenIn == ETH_ADDRESS ? amountIn : 0,
                data: data,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                requiresApproval: tokenIn != ETH_ADDRESS,
                isCurvePool: strategy.protocol == Protocol.Curve
            });
        }

        // Calculate total gas
        totalGas = strategy.expectedGas;
        ethValue = tokenIn == ETH_ADDRESS ? amountIn : 0;
    }

    /**
     * @notice Get bridge route second leg execution data
     * @dev Called by Executor after first swap completes - properly calculates second leg minimum
     */
    function getBridgeSecondLegData(
        address bridgeAsset,
        address finalToken,
        uint256 bridgeAmount,
        uint256 originalMinOut,
        address recipient
    ) external returns (bytes memory executionData, address targetContract, bool requiresApproval) {
        // Get the bridge->final route
        bytes32 routeKey = keccak256(abi.encodePacked(bridgeAsset, finalToken));
        RouteConfig memory config = routes[routeKey];

        require(config.isConfigured, "Bridge route not found");

        // Generate execution data
        ExecutionStrategy memory strategy = ExecutionStrategy({
            routeType: RouteType.Direct,
            protocol: config.protocol,
            bridgeAsset: address(0),
            primaryRouteData: _encodeRouteData(config, bridgeAsset, finalToken),
            secondaryRouteData: "",
            expectedGas: _estimateGasForProtocol(config.protocol)
        });

        // Calculate proper minAmountOut for second leg based on actual bridge amount
        (uint256 quotedAmount, uint256 secondLegMinOut) = _getQuoteWithFallback(
            bridgeAsset,
            finalToken,
            bridgeAmount,
            strategy
        );

        // Use the calculated min for second leg, but ensure it meets original requirement
        uint256 effectiveMinOut = secondLegMinOut;

        // If the calculated second leg output is less than original, we need to ensure
        // we still meet the original minimum requirement
        if (secondLegMinOut < originalMinOut) {
            effectiveMinOut = originalMinOut;
        }

        (executionData, targetContract) = _generateDirectExecutionData(
            strategy,
            bridgeAsset,
            finalToken,
            bridgeAmount,
            effectiveMinOut,
            recipient
        );

        requiresApproval = bridgeAsset != ETH_ADDRESS;
    }

    /**
     * @notice Get next step execution data for multi-step swaps
     * @dev Called by Executor after completing previous step
     */
    function getNextStepExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata fullRouteData,
        uint256 stepIndex,
        address recipient
    ) external view returns (bytes memory executionData, address targetContract, bool isFinalStep) {
        // Decode the full route data
        (
            address[] memory tokens,
            Protocol[] memory protocols,
            bytes[] memory routeDatas,
            uint256[] memory minAmounts
        ) = abi.decode(fullRouteData, (address[], Protocol[], bytes[], uint256[]));

        require(stepIndex < protocols.length, "Invalid step index");

        // Check if this is the final step
        isFinalStep = (stepIndex == protocols.length - 1);

        // Generate execution data for this step
        ExecutionStrategy memory stepStrategy = ExecutionStrategy({
            routeType: RouteType.Direct,
            protocol: protocols[stepIndex],
            bridgeAsset: address(0),
            primaryRouteData: routeDatas[stepIndex],
            secondaryRouteData: "",
            expectedGas: _estimateGasForProtocol(protocols[stepIndex])
        });

        // Use actual recipient for final step, Executor address for intermediate steps
        address stepRecipient = isFinalStep ? recipient : msg.sender;

        (executionData, targetContract) = _generateDirectExecutionData(
            stepStrategy,
            tokens[stepIndex],
            tokens[stepIndex + 1],
            amountIn,
            minAmounts[stepIndex],
            stepRecipient
        );
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

        // Basic validation
        if (amountIn == 0) {
            return (false, "Zero amount", 0);
        }
        if (tokenIn == tokenOut) {
            return (false, "Same token swap", 0);
        }
        // Check cross-category
        if (_isCrossCategory(tokenIn, tokenOut)) {
            return (false, "Cross-category swap forbidden", 0);
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
     * @dev Returns execution bytecode for Executor - can be called with staticcall
     */
    function generateSwapExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external view returns (bytes memory executionData, Protocol protocol, uint256 expectedGas) {
        ExecutionStrategy memory strategy = _findOptimalExecutionStrategy(tokenIn, tokenOut, amountIn, minAmountOut);

        protocol = strategy.protocol;
        expectedGas = strategy.expectedGas;

        // If minAmountOut is 0, calculate it from estimate
        if (minAmountOut == 0) {
            uint256 estimate = _estimateSwapOutputView(tokenIn, tokenOut, amountIn, strategy);
            uint256 slippage = slippageTolerance[tokenIn][tokenOut];
            if (slippage == 0) revert NoConfigSlippage();
            minAmountOut = (estimate * (10000 - slippage)) / 10000;
        }

        if (strategy.routeType == RouteType.Bridge) {
            executionData = _generateComplexRouteData(strategy, tokenIn, tokenOut, amountIn, minAmountOut, recipient);
        } else {
            (executionData, ) = _generateDirectExecutionData(
                strategy,
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                recipient
            );
        }
    }

    /**
     * @notice Get WETH conversion instructions for Executor
     * @dev Tells Executor when to wrap/unwrap ETH
     */
    function getETHConversionData(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool isInput
    ) external view returns (bool needsConversion, bytes memory conversionData, address conversionTarget) {
        if (isInput && tokenIn == ETH_ADDRESS) {
            // Need to wrap ETH to WETH
            needsConversion = true;
            conversionTarget = address(WETH);
            conversionData = abi.encodeWithSelector(IWETH.deposit.selector);
        } else if (!isInput && tokenOut == ETH_ADDRESS) {
            // Need to unwrap WETH to ETH
            needsConversion = true;
            conversionTarget = address(WETH);
            conversionData = abi.encodeWithSelector(IWETH.withdraw.selector, amount);
        } else {
            needsConversion = false;
        }
    }

    /**
     * @notice Check if swap needs WETH wrapping/unwrapping
     */
    function getWETHRequirements(
        address tokenIn,
        address tokenOut,
        Protocol protocol
    ) external view returns (bool needsWrap, bool needsUnwrap, address wethAddress) {
        wethAddress = address(WETH);

        // Check if we need to wrap ETH
        if (tokenIn == ETH_ADDRESS && protocol != Protocol.Curve && protocol != Protocol.DirectMint) {
            needsWrap = true;
        }

        // Check if we need to unwrap to ETH
        if (tokenOut == ETH_ADDRESS && protocol != Protocol.Curve && protocol != Protocol.DirectMint) {
            needsUnwrap = true;
        }
    }

    /**
     * @notice Get all possible routes for a token pair
     */
    function getAllPossibleRoutes(
        address tokenIn,
        address tokenOut
    )
        external
        view
        returns (
            bool hasDirect,
            bool hasReverse,
            bool hasBridge,
            address bridgeAsset,
            uint256 estimatedDirectGas,
            uint256 estimatedBridgeGas
        )
    {
        bytes32 directKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        bytes32 reverseKey = keccak256(abi.encodePacked(tokenOut, tokenIn));

        RouteConfig memory directRoute = routes[directKey];
        RouteConfig memory reverseRoute = routes[reverseKey];

        hasDirect = directRoute.isConfigured;
        hasReverse = reverseRoute.isConfigured;

        // Check bridge
        bridgeAsset = _getBridgeAsset(tokenIn, tokenOut);
        if (bridgeAsset != address(0)) {
            bytes32 firstKey = keccak256(abi.encodePacked(tokenIn, bridgeAsset));
            bytes32 secondKey = keccak256(abi.encodePacked(bridgeAsset, tokenOut));
            hasBridge = routes[firstKey].isConfigured && routes[secondKey].isConfigured;

            if (hasBridge) {
                estimatedBridgeGas =
                    _estimateGasForProtocol(routes[firstKey].protocol) +
                    _estimateGasForProtocol(routes[secondKey].protocol);
            }
        }

        if (hasDirect) {
            estimatedDirectGas = _estimateGasForProtocol(directRoute.protocol);
        } else if (hasReverse) {
            estimatedDirectGas = _estimateGasForProtocol(reverseRoute.protocol);
        }
    }

    /**
     * @notice Validate route configuration before execution
     */
    function validateRouteConfiguration(
        address tokenIn,
        address tokenOut
    ) external view returns (bool isValid, string memory error, uint256 configuredSlippage) {
        // Check token support
        if (!farSupportedTokens[tokenIn] && tokenIn != ETH_ADDRESS) {
            return (false, "Input token not supported", 0);
        }

        if (!farSupportedTokens[tokenOut] && tokenOut != ETH_ADDRESS) {
            return (false, "Output token not supported", 0);
        }

        // Check route exists
        try this._findOptimalExecutionStrategyView(tokenIn, tokenOut, 1e18, 0) returns (ExecutionStrategy memory) {
            isValid = true;
            error = "";
        } catch {
            return (false, "No route configured", 0);
        }

        // Get slippage
        configuredSlippage = slippageTolerance[tokenIn][tokenOut];
        if (configuredSlippage == 0) revert NoConfigSlippage();
    }

    /**
     * @notice Get custom DEX execution data
     * @dev Returns execution info without executing
     */
    function getCustomDEXExecutionData(
        address targetDEX,
        bytes calldata proposedCalldata,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        view
        returns (bool isValid, string memory validationError, bytes memory approvalData, uint256 estimatedGas)
    {
        // Validate DEX
        if (!registeredDEXes[targetDEX]) {
            return (false, "DEX not registered", "", 0);
        }

        if (block.timestamp < dexRegistrationTime[targetDEX] + DEX_TIMELOCK) {
            return (false, "DEX timelock not expired", "", 0);
        }

        // Validate selector
        if (proposedCalldata.length < 4) {
            return (false, "Invalid calldata", "", 0);
        }

        bytes4 selector = bytes4(proposedCalldata[:4]);

        if (dangerousSelectors[selector]) {
            return (false, "Dangerous selector", "", 0);
        }

        if (!whitelistedSelectors[selector]) {
            return (false, "Selector not whitelisted", "", 0);
        }

        // Generate approval data if needed
        if (tokenIn != ETH_ADDRESS) {
            approvalData = abi.encodeWithSelector(IERC20.approve.selector, targetDEX, amountIn);
        }

        isValid = true;
        validationError = "";
        estimatedGas = MAX_DEX_GAS_LIMIT;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Get quote with automatic fallback to configured slippage
     * @dev Implements try quoter -> use tight buffer, catch -> use raw tested slippage values
     */
    function _getQuoteWithFallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        ExecutionStrategy memory strategy
    ) internal returns (uint256 quotedAmount, uint256 minAmountOut) {
        // Try quoter first
        try this._performQuoteExternal(tokenIn, tokenOut, amountIn, strategy.primaryRouteData) returns (
            uint256 quoterOutput
        ) {
            if (quoterOutput > 0) {
                // Quoter succeeded - use tight buffer
                quotedAmount = quoterOutput;
                minAmountOut = (quotedAmount * (10000 - TIGHT_BUFFER_BPS)) / 10000;
                return (quotedAmount, minAmountOut);
            }
        } catch {
            // Quoter failed - continue to fallback
        }

        // Fallback: Use raw decimal-adjusted amount as quote (no haircuts)
        quotedAmount = _getRawDecimalAdjustedAmount(amountIn, tokenIn, tokenOut);

        // Get pre-tested slippage for this pair
        uint256 slippage = slippageTolerance[tokenIn][tokenOut];
        if (slippage == 0) {
            // No configured slippage means route not properly tested
            revert NoConfigSlippage();
        }

        // For bridge routes, use combined slippage of both legs
        if (strategy.routeType == RouteType.Bridge) {
            // Get slippage for second leg
            uint256 secondLegSlippage = slippageTolerance[strategy.bridgeAsset][tokenOut];
            if (secondLegSlippage == 0) {
                secondLegSlippage = slippageTolerance[tokenOut][strategy.bridgeAsset]; // Try reverse
            }

            // Combine slippages (not just double) - more accurate
            slippage = slippage + secondLegSlippage;
            if (slippage > MAX_SLIPPAGE) slippage = MAX_SLIPPAGE;
        }

        // Apply the pre-tested slippage directly
        minAmountOut = (quotedAmount * (10000 - slippage)) / 10000;
    }

    /**
     * @notice Get raw decimal-adjusted amount without any haircuts
     * @dev Pure decimal conversion with no reductions
     */
    function _getRawDecimalAdjustedAmount(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256) {
        uint8 decimalsIn = tokenIn == ETH_ADDRESS ? 18 : tokenDecimals[tokenIn];
        uint8 decimalsOut = tokenOut == ETH_ADDRESS ? 18 : tokenDecimals[tokenOut];

        // MODIFY: Add validation
        require(decimalsIn > 0 && decimalsOut > 0, "Token decimals not configured");

        if (decimalsIn == decimalsOut) {
            return amountIn;
        } else if (decimalsIn > decimalsOut) {
            return amountIn / (10 ** (decimalsIn - decimalsOut));
        } else {
            return amountIn * (10 ** (decimalsOut - decimalsIn));
        }
    }

    /**
     * @notice Calculate minimum amounts for each step in multi-step swap (enhanced)
     * @dev Now takes token path instead of just protocols
     */
    function _calculateMultiStepMinAmounts(
        address[] memory tokens,
        uint256 amountIn,
        Protocol[] memory protocols,
        bytes[] memory routeDatas
    ) internal returns (uint256[] memory minAmounts, uint256 finalQuotedAmount) {
        minAmounts = new uint256[](protocols.length);
        uint256 currentAmount = amountIn;

        for (uint256 i = 0; i < protocols.length; i++) {
            // Get quote for this step
            ExecutionStrategy memory stepStrategy = ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: protocols[i],
                bridgeAsset: address(0),
                primaryRouteData: routeDatas[i],
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(protocols[i])
            });

            (uint256 stepQuote, uint256 stepMin) = _getQuoteWithFallback(
                tokens[i],
                tokens[i + 1],
                currentAmount,
                stepStrategy
            );

            minAmounts[i] = stepMin;
            currentAmount = stepQuote; // Use quote for next step input
        }

        finalQuotedAmount = currentAmount;
    }
    /**
     * @notice Generate direct execution data for single-step swaps
     * @dev Returns calldata that Executor can execute directly on DEX
     */
    function _generateDirectExecutionData(
        ExecutionStrategy memory strategy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) internal view returns (bytes memory executionData, address targetContract) {
        if (strategy.protocol == Protocol.UniswapV3) {
            UniswapV3Route memory route = abi.decode(strategy.primaryRouteData, (UniswapV3Route));
            targetContract = address(uniswapRouter);

            if (!route.isMultiHop) {
                executionData = abi.encodeWithSelector(
                    IUniswapV3Router.exactInputSingle.selector,
                    IUniswapV3Router.ExactInputSingleParams({
                        tokenIn: tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn,
                        tokenOut: tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut,
                        fee: route.fee,
                        recipient: recipient,
                        deadline: block.timestamp + 1800,
                        amountIn: amountIn,
                        amountOutMinimum: minAmountOut,
                        sqrtPriceLimitX96: 0
                    })
                );
            } else {
                executionData = abi.encodeWithSelector(
                    IUniswapV3Router.exactInput.selector,
                    IUniswapV3Router.ExactInputParams({
                        path: route.path,
                        recipient: recipient,
                        deadline: block.timestamp + 1800,
                        amountIn: amountIn,
                        amountOutMinimum: minAmountOut
                    })
                );
            }
        } else if (strategy.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(strategy.primaryRouteData, (CurveRoute));
            targetContract = route.pool;

            // Generate direct calldata for Curve
            if (route.useUnderlying) {
                executionData = abi.encodeWithSelector(
                    ICurvePool.exchange_underlying.selector,
                    route.indexIn,
                    route.indexOut,
                    amountIn,
                    minAmountOut
                );
            } else {
                executionData = abi.encodeWithSelector(
                    ICurvePool.exchange.selector,
                    route.indexIn,
                    route.indexOut,
                    amountIn,
                    minAmountOut
                );
            }
        } else if (strategy.protocol == Protocol.DirectMint) {
            address minter = abi.decode(strategy.primaryRouteData, (address));
            targetContract = minter;

            executionData = abi.encodeWithSelector(IFrxETHMinter.submitAndDeposit.selector, recipient);
        } else if (strategy.protocol == Protocol.MultiHop) {
            targetContract = address(uniswapRouter);
            bytes memory path = strategy.primaryRouteData;

            executionData = abi.encodeWithSelector(
                IUniswapV3Router.exactInput.selector,
                IUniswapV3Router.ExactInputParams({
                    path: path,
                    recipient: recipient,
                    deadline: block.timestamp + 1800,
                    amountIn: amountIn,
                    amountOutMinimum: minAmountOut
                })
            );
        } else {
            revert UnsupportedRoute();
        }
    }
    /**
     * @notice Generate complex route data for multi-step/bridge swaps
     * @dev Returns structured data for Executor to execute multiple swaps
     */
    function _generateComplexRouteData(
        ExecutionStrategy memory strategy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) internal view returns (bytes memory) {
        if (strategy.routeType == RouteType.Bridge) {
            // Bridge route: two separate swaps
            ExecutionStrategy memory firstStep = ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: strategy.protocol,
                bridgeAsset: address(0),
                primaryRouteData: strategy.primaryRouteData,
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(strategy.protocol)
            });

            // Get execution data for first swap
            (bytes memory firstExecution, address firstTarget) = _generateDirectExecutionData(
                firstStep,
                tokenIn,
                strategy.bridgeAsset,
                amountIn,
                0, // No minimum for intermediate
                recipient // Important: bridge asset goes to recipient (Executor)
            );

            // Decode second route for protocol info
            RouteConfig memory secondRoute;
            bytes32 secondKey = keccak256(abi.encodePacked(strategy.bridgeAsset, tokenOut));
            secondRoute = routes[secondKey];

            // Return structured data for Executor
            return
                abi.encode(
                    uint8(2), // Flag: Bridge swap
                    tokenIn,
                    strategy.bridgeAsset,
                    tokenOut,
                    amountIn,
                    minAmountOut,
                    firstTarget,
                    firstExecution,
                    secondRoute.protocol,
                    strategy.secondaryRouteData
                );
        } else if (strategy.protocol == Protocol.MultiStep) {
            // Multi-step route
            (
                address[] memory tokens,
                Protocol[] memory protocols,
                bytes[] memory routeDatas,
                uint256[] memory minAmounts
            ) = abi.decode(strategy.primaryRouteData, (address[], Protocol[], bytes[], uint256[]));

            // Generate first step data
            ExecutionStrategy memory firstStep = ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: protocols[0],
                bridgeAsset: address(0),
                primaryRouteData: routeDatas[0],
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(protocols[0])
            });

            (bytes memory firstExecution, address firstTarget) = _generateDirectExecutionData(
                firstStep,
                tokens[0],
                tokens[1],
                amountIn,
                minAmounts[0],
                recipient
            );

            // Return structured data
            return
                abi.encode(
                    uint8(3), // Flag: Multi-step swap
                    tokens,
                    protocols,
                    routeDatas,
                    minAmounts,
                    firstTarget,
                    firstExecution,
                    recipient
                );
        }

        revert UnsupportedRoute();
    }

    /**
     * @notice Decode complex execution data for Executor
     * @dev Helper function for Executor to understand complex route data
     */
    function decodeComplexExecutionData(
        bytes calldata complexData
    )
        external
        pure
        returns (uint8 routeType, address firstTarget, bytes memory firstCalldata, bytes memory additionalData)
    {
        routeType = abi.decode(complexData, (uint8));

        if (routeType == 2) {
            // Bridge swap
            (, address target, bytes memory calldata_, address bridgeAsset, address finalToken, uint256 minOut) = abi
                .decode(complexData, (uint8, address, bytes, address, address, uint256));

            firstTarget = target;
            firstCalldata = calldata_;
            additionalData = abi.encode(bridgeAsset, finalToken, minOut);
        } else if (routeType == 3) {
            // Multi-step swap
            (
                ,
                address target,
                bytes memory calldata_,
                address[] memory tokens,
                Protocol[] memory protocols,
                bytes[] memory routeDatas,
                uint256[] memory minAmounts
            ) = abi.decode(complexData, (uint8, address, bytes, address[], Protocol[], bytes[], uint256[]));

            firstTarget = target;
            firstCalldata = calldata_;
            additionalData = abi.encode(tokens, protocols, routeDatas, minAmounts);
        }
    }
    /**
     * @notice Find optimal execution strategy (enhanced with multi-hop support)
     * @dev Now handles 3+ hop routes via MultiStep protocol
     */
    function _findOptimalExecutionStrategy(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (ExecutionStrategy memory strategy) {
        // Validate cross-category early
        if (_isCrossCategory(tokenIn, tokenOut)) {
            revert NoRouteFound();
        }

        // Try to find multi-hop route
        (
            bool found,
            address[] memory path,
            Protocol[] memory protocols,
            bytes[] memory routeDatas
        ) = _findMultiHopRoute(tokenIn, tokenOut, MAX_MULTI_STEP_OPERATIONS);

        if (!found) {
            revert NoRouteFound();
        }

        // Single hop - direct route
        if (path.length == 2) {
            strategy.routeType = RouteType.Direct;
            strategy.protocol = protocols[0];
            strategy.primaryRouteData = routeDatas[0];
            strategy.expectedGas = _estimateGasForProtocol(protocols[0]);
            return strategy;
        }

        // Two hops - bridge route
        if (path.length == 3) {
            strategy.routeType = RouteType.Bridge;
            strategy.protocol = protocols[0];
            strategy.bridgeAsset = path[1];
            strategy.primaryRouteData = routeDatas[0];
            strategy.secondaryRouteData = routeDatas[1];
            strategy.expectedGas = _estimateGasForProtocol(protocols[0]) + _estimateGasForProtocol(protocols[1]);
            return strategy;
        }

        // Three or more hops - multi-step route
        strategy.routeType = RouteType.Direct; // Will be treated as MultiStep by protocol
        strategy.protocol = Protocol.MultiStep;

        // Create placeholder min amounts (will be calculated later)
        uint256[] memory placeholderMinAmounts = new uint256[](protocols.length);
        for (uint256 i = 0; i < protocols.length; i++) {
            placeholderMinAmounts[i] = 0; // Will be calculated in _calculateMultiStepMinAmounts
        }

        strategy.primaryRouteData = abi.encode(path, protocols, routeDatas, placeholderMinAmounts);
        strategy.expectedGas = _calculateMultiStepGas(protocols);
        return strategy;
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
     * @notice External quote function with Curve and Uniswap support
     * @dev Elegantly handles both protocols with proper validation
     */
    function _performQuoteExternal(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory routeData
    ) external returns (uint256 expectedOutput) {
        require(msg.sender == address(this), "Internal only");

        if (routeData.length == 0) return 0;

        // Elegant protocol detection without try-catch overhead
        bytes4 routeSignature = bytes4(routeData);

        // Curve route signature check
        if (routeSignature == bytes4(keccak256("CurveRoute"))) {
            return _performCurveQuote(tokenIn, tokenOut, amountIn, routeData);
        }

        // Default to Uniswap quoting
        return _performUniswapQuote(tokenIn, tokenOut, amountIn, routeData);
    }

    /**
     * @notice Perform Curve pool quote with elegant fallback
     * @dev Handles both regular and underlying variants seamlessly
     */
    function _performCurveQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory routeData
    ) internal returns (uint256) {
        CurveRoute memory route = abi.decode(routeData, (CurveRoute));

        // Pre-calculate validation bounds for efficiency
        uint256 rawAmount = _getRawDecimalAdjustedAmount(amountIn, tokenIn, tokenOut);
        uint256 upperBound = (rawAmount * 11000) / 10000; // 110%
        uint256 lowerBound = (rawAmount * 9000) / 10000; // 90%

        // Single assembly block for gas-efficient external call
        uint256 outputAmount;
        bool success;

        assembly {
            // Prepare calldata for get_dy or get_dy_underlying
            let freePtr := mload(0x40)

            // Function selector based on useUnderlying
            let selector := 0x5e0d443f // get_dy(int128,int128,uint256)
            if eq(mload(add(routeData, 0x80)), 1) {
                // Check useUnderlying
                selector := 0x07211ef7 // get_dy_underlying(int128,int128,uint256)
            }

            mstore(freePtr, selector)
            mstore(add(freePtr, 0x04), mload(add(routeData, 0x40))) // indexIn
            mstore(add(freePtr, 0x24), mload(add(routeData, 0x60))) // indexOut
            mstore(add(freePtr, 0x44), amountIn)

            success := staticcall(
                gas(),
                mload(add(routeData, 0x20)), // pool address
                freePtr,
                0x64,
                freePtr,
                0x20
            )

            if success {
                outputAmount := mload(freePtr)
            }
        }

        // Validate output with elegant boundary check
        if (success && outputAmount >= lowerBound && outputAmount <= upperBound) {
            return outputAmount;
        }

        return 0; // Trigger fallback
    }

    /**
     * @notice Perform Uniswap V3 quote with multi-fee tier support
     * @dev Extracted for clarity and reusability
     */
    function _performUniswapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory routeData
    ) internal returns (uint256) {
        // Convert ETH to WETH for quoter
        address quoteTokenIn = tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn;
        address quoteTokenOut = tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut;

        // Extract fee tier from route data efficiently
        uint24 primaryFee = _extractUniswapFee(routeData);

        // Try primary fee tier first
        uint256 quotedAmount = _tryUniswapQuote(quoteTokenIn, quoteTokenOut, primaryFee, amountIn);
        if (quotedAmount > 0) return quotedAmount;

        // Elegant fee tier fallback array
        uint24[4] memory feeTiers = [uint24(500), uint24(3000), uint24(10000), uint24(100)];

        for (uint256 i = 0; i < feeTiers.length; i++) {
            if (feeTiers[i] == primaryFee) continue; // Skip already tried

            quotedAmount = _tryUniswapQuote(quoteTokenIn, quoteTokenOut, feeTiers[i], amountIn);
            if (quotedAmount > 0) return quotedAmount;
        }

        return 0; // Trigger fallback
    }

    /**
     * @notice Try single Uniswap quote with validation
     * @dev Isolated for clean error handling
     */
    function _tryUniswapQuote(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn
    ) internal returns (uint256) {
        try uniswapQuoter.quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0) returns (uint256 amount) {
            // Validate against reasonable bounds
            uint256 rawAmount = _getRawDecimalAdjustedAmount(amountIn, tokenIn, tokenOut);

            if (amount >= (rawAmount * 5000) / 10000 && amount <= (rawAmount * 11000) / 10000) {
                return amount;
            }
        } catch {
            // Silent fail - try next option
        }

        return 0;
    }

    /**
     * @notice Extract Uniswap fee from route data
     * @dev Pure function for gas efficiency
     */
    function _extractUniswapFee(bytes memory routeData) internal pure returns (uint24) {
        if (routeData.length < 32) return 3000; // Default

        // UniswapV3Route struct has fee at second position
        uint24 fee;
        assembly {
            fee := mload(add(routeData, 0x40))
        }

        return fee == 0 ? 3000 : fee;
    }
    /**
     * @notice Try to decode Uniswap route
     */
    function _tryDecodeUniswapRoute(bytes memory routeData) external pure returns (uint24) {
        UniswapV3Route memory route = abi.decode(routeData, (UniswapV3Route));
        return route.fee;
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
        } else if (config.protocol == Protocol.MultiHop) {
            return config.routeData;
        } else if (config.protocol == Protocol.MultiStep) {
            return config.routeData;
        }

        return config.routeData;
    }

    /**
     * @notice Encode reverse route data with proper execution parameters
     */
    function _encodeReverseRouteData(
        RouteConfig memory config,
        address tokenIn,
        address tokenOut
    ) internal pure returns (bytes memory) {
        if (config.protocol == Protocol.UniswapV3) {
            if (config.path.length > 0) {
                // Multi-hop path needs reversal
                bytes memory reversedPath = _reversePath(config.path);
                return
                    abi.encode(
                        UniswapV3Route({pool: config.pool, fee: config.fee, isMultiHop: true, path: reversedPath})
                    );
            } else {
                // Single hop - just swap the tokens logically
                return abi.encode(UniswapV3Route({pool: config.pool, fee: config.fee, isMultiHop: false, path: ""}));
            }
        } else if (config.protocol == Protocol.Curve) {
            // Swap indices for reverse
            return
                abi.encode(
                    CurveRoute({
                        pool: config.pool,
                        indexIn: config.tokenIndexOut,
                        indexOut: config.tokenIndexIn,
                        useUnderlying: config.useUnderlying
                    })
                );
        } else if (config.protocol == Protocol.MultiHop) {
            // Reverse the entire path
            return _reversePath(config.routeData);
        } else if (config.protocol == Protocol.DirectMint) {
            // DirectMint cannot be reversed
            revert UnsupportedRoute();
        }

        return config.routeData;
    }

    /**
     * @notice Reverse a Uniswap V3 path
     */
    function _reversePath(bytes memory path) internal pure returns (bytes memory) {
        require(path.length >= 43, "Path too short");
        require((path.length - 20) % 23 == 0, "Invalid path length");

        uint256 numPools = (path.length - 20) / 23;
        bytes memory reversed = new bytes(path.length);

        // Copy the last token to the beginning
        for (uint256 i = 0; i < 20; i++) {
            reversed[i] = path[path.length - 20 + i];
        }

        // Reverse each pool + token pair
        for (uint256 i = 0; i < numPools; i++) {
            uint256 srcPoolStart = 20 + i * 23;
            uint256 dstPoolStart = 20 + (numPools - 1 - i) * 23;

            // Copy fee (3 bytes)
            for (uint256 j = 0; j < 3; j++) {
                reversed[dstPoolStart + j] = path[srcPoolStart + j];
            }

            // Copy token (20 bytes)
            uint256 srcTokenStart = srcPoolStart + 3;
            uint256 dstTokenStart = dstPoolStart + 3;

            // For all but the last pool, copy the preceding token
            if (i < numPools - 1) {
                for (uint256 j = 0; j < 20; j++) {
                    reversed[dstTokenStart + j] = path[srcTokenStart - 23 + j];
                }
            } else {
                // For the last pool, copy the first token
                for (uint256 j = 0; j < 20; j++) {
                    reversed[dstTokenStart + j] = path[j];
                }
            }
        }

        return reversed;
    }

    /**
     * @notice Apply production slippage configuration with all tested values
     */
    function _applyProductionSlippageConfig() internal {
        // ETH to LST tokens - very tight
        slippageTolerance[ETH_ADDRESS][0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84] = 50; // ETH->stETH
        slippageTolerance[ETH_ADDRESS][FRXETH] = 50; // ETH->frxETH
        slippageTolerance[ETH_ADDRESS][SFRXETH] = 50; // ETH->sfrxETH

        // WETH to LST tokens - varying by liquidity
        slippageTolerance[address(WETH)][0xBe9895146f7AF43049ca1c1AE358B0541Ea49704] = 350; // WETH->cbETH
        slippageTolerance[address(WETH)][RETH] = 750; // WETH->rETH
        slippageTolerance[address(WETH)][OSETH] = 500; // WETH->osETH

        // Reverse routes
        slippageTolerance[0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84][ETH_ADDRESS] = 50;
        slippageTolerance[SFRXETH][ETH_ADDRESS] = 50;
        slippageTolerance[0xBe9895146f7AF43049ca1c1AE358B0541Ea49704][address(WETH)] = 350;
        slippageTolerance[RETH][address(WETH)] = 750;
        slippageTolerance[OSETH][address(WETH)] = 500;

        // BTC wrapped pairs
        slippageTolerance[WBTC][0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa] = 200; // WBTC->uniBTC
        slippageTolerance[0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa][WBTC] = 200;

        // Bridge routes through WETH
        slippageTolerance[0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84][RETH] = 800; // stETH->rETH
        slippageTolerance[RETH][OSETH] = 600; // rETH->osETH
    }

    /**
     * @notice Get bridge asset for a token pair
     */
    function _getBridgeAsset(address tokenIn, address tokenOut) internal view returns (address) {
        // No bridge for same token
        if (tokenIn == tokenOut) return address(0);

        // Get asset types
        AssetType typeIn = tokenIn == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenIn];
        AssetType typeOut = tokenOut == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenOut];

        // Cross-category forbidden - return early
        if (typeIn != typeOut) return address(0);

        // BTC tokens always bridge through WBTC
        if (typeIn == AssetType.BTC_WRAPPED && typeOut == AssetType.BTC_WRAPPED) {
            // Only use WBTC as bridge if it's not one of the tokens
            if (tokenIn != WBTC && tokenOut != WBTC) {
                // Check if both routes exist
                bytes32 firstKey = keccak256(abi.encodePacked(tokenIn, WBTC));
                bytes32 secondKey = keccak256(abi.encodePacked(WBTC, tokenOut));
                bytes32 firstReverseKey = keccak256(abi.encodePacked(WBTC, tokenIn));
                bytes32 secondReverseKey = keccak256(abi.encodePacked(tokenOut, WBTC));

                bool firstExists = routes[firstKey].isConfigured || routes[firstReverseKey].isConfigured;
                bool secondExists = routes[secondKey].isConfigured || routes[secondReverseKey].isConfigured;

                if (firstExists && secondExists) {
                    return WBTC;
                }
            }
        }

        // ETH LST tokens - try WETH first, then ETH
        if (typeIn == AssetType.ETH_LST && typeOut == AssetType.ETH_LST) {
            // Try WETH bridge first (most common according to config)
            if (tokenIn != address(WETH) && tokenOut != address(WETH)) {
                bytes32 firstKey = keccak256(abi.encodePacked(tokenIn, address(WETH)));
                bytes32 secondKey = keccak256(abi.encodePacked(address(WETH), tokenOut));
                bytes32 firstReverseKey = keccak256(abi.encodePacked(address(WETH), tokenIn));
                bytes32 secondReverseKey = keccak256(abi.encodePacked(tokenOut, address(WETH)));

                bool firstExists = routes[firstKey].isConfigured || routes[firstReverseKey].isConfigured;
                bool secondExists = routes[secondKey].isConfigured || routes[secondReverseKey].isConfigured;

                if (firstExists && secondExists) {
                    return address(WETH);
                }
            }

            // Try ETH bridge for tokens that have ETH pairs
            if (tokenIn != ETH_ADDRESS && tokenOut != ETH_ADDRESS) {
                bytes32 firstKey = keccak256(abi.encodePacked(tokenIn, ETH_ADDRESS));
                bytes32 secondKey = keccak256(abi.encodePacked(ETH_ADDRESS, tokenOut));
                bytes32 firstReverseKey = keccak256(abi.encodePacked(ETH_ADDRESS, tokenIn));
                bytes32 secondReverseKey = keccak256(abi.encodePacked(tokenOut, ETH_ADDRESS));

                bool firstExists = routes[firstKey].isConfigured || routes[firstReverseKey].isConfigured;
                bool secondExists = routes[secondKey].isConfigured || routes[secondReverseKey].isConfigured;

                if (firstExists && secondExists) {
                    return ETH_ADDRESS;
                }
            }
        }

        return address(0);
    }

    /*
    function _getDefaultSlippage(address tokenIn, address tokenOut) internal view returns (uint256) {
        AssetType typeIn = assetTypes[tokenIn];
        AssetType typeOut = assetTypes[tokenOut];

        // Same type swaps - lower slippage
        if (typeIn == typeOut) {
            if (typeIn == AssetType.STABLE) return 30; // 0.3%
            if (typeIn == AssetType.ETH_LST) return 50; // 0.5%
            if (typeIn == AssetType.BTC_WRAPPED) return 100; // 1%
        }

        // Cross-type swaps - higher slippage
        if (typeIn == AssetType.VOLATILE || typeOut == AssetType.VOLATILE) {
            return 500; // 5%
        }

        return 200; // 2% default
    }

    function _getSimpleEstimate(uint256 amountIn, address tokenIn, address tokenOut) internal view returns (uint256) {
        // Handle ETH as 18 decimals
        uint8 decimalsIn = tokenIn == ETH_ADDRESS ? 18 : tokenDecimals[tokenIn];
        uint8 decimalsOut = tokenOut == ETH_ADDRESS ? 18 : tokenDecimals[tokenOut];

        // Default to 18 if not set
        if (decimalsIn == 0) decimalsIn = 18;
        if (decimalsOut == 0) decimalsOut = 18;

        // Get asset types
        AssetType typeIn = tokenIn == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenIn];
        AssetType typeOut = tokenOut == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenOut];

        // Start with decimal adjustment
        uint256 estimate;
        if (decimalsIn == decimalsOut) {
            estimate = amountIn;
        } else if (decimalsIn > decimalsOut) {
            estimate = amountIn / (10 ** (decimalsIn - decimalsOut));
        } else {
            estimate = amountIn * (10 ** (decimalsOut - decimalsIn));
        }

        // Apply type-based adjustments
        if (typeIn == AssetType.ETH_LST && typeOut == AssetType.ETH_LST) {
            // ETH LST pairs are close to 1:1 after decimal adjustment
            // Check if either token is rebasing (stETH)
            if (
                tokenIn == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 ||
                tokenOut == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
            ) {
                return (estimate * 9900) / 10000; // 1% haircut for rebasing
            } else {
                return (estimate * 9950) / 10000; // 0.5% haircut for non-rebasing
            }
        } else if (typeIn == AssetType.BTC_WRAPPED && typeOut == AssetType.BTC_WRAPPED) {
            // BTC wrapped pairs are very close to 1:1
            return (estimate * 9980) / 10000; // 0.2% haircut
        } else if (typeIn == AssetType.STABLE && typeOut == AssetType.STABLE) {
            // Stablecoins should be exactly 1:1 after decimal adjustment
            return (estimate * 9990) / 10000; // 0.1% haircut
        } else {
            // Different types or volatile - shouldn't happen due to cross-category check
            // But if it does, apply conservative estimate
            return (estimate * 9500) / 10000; // 5% haircut
        }
    }
*/
    /**
     * @notice Estimate gas for protocol with better accuracy
     */
    function _estimateGasForProtocol(Protocol protocol) internal pure returns (uint256) {
        if (protocol == Protocol.UniswapV3) return 150000;
        if (protocol == Protocol.Curve) return 250000; // Increased for Curve complexity
        if (protocol == Protocol.DirectMint) return 120000;
        if (protocol == Protocol.MultiHop) return 300000;
        if (protocol == Protocol.MultiStep) return 500000;
        return 200000; // Default
    }

    /**
     * @notice Calculate gas for multi-step route
     */
    function _calculateMultiStepGas(Protocol[] memory protocols) internal pure returns (uint256) {
        uint256 totalGas = 50000; // Base overhead
        for (uint256 i = 0; i < protocols.length; i++) {
            totalGas += _estimateGasForProtocol(protocols[i]);
        }
        return totalGas;
    }

    /**
     * @notice Estimate swap output (view safe)
     */
    function _estimateSwapOutputView(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        ExecutionStrategy memory strategy
    ) internal view returns (uint256) {
        // For view context, use simple estimation
        return _getRawDecimalAdjustedAmount(amountIn, tokenIn, tokenOut);
    }

    /**
     * @notice Validate strategy pools
     */
    function _validateStrategyPools(ExecutionStrategy memory strategy) internal view {
        if (strategy.protocol == Protocol.UniswapV3) {
            UniswapV3Route memory route = abi.decode(strategy.primaryRouteData, (UniswapV3Route));
            if (!route.isMultiHop && route.pool != address(0)) {
                if (!poolWhitelist[route.pool]) revert PoolNotWhitelisted();
                if (poolPaused[route.pool]) revert PoolIsPaused();
            }
        } else if (strategy.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(strategy.primaryRouteData, (CurveRoute));
            if (!poolWhitelist[route.pool]) revert PoolNotWhitelisted();
            if (poolPaused[route.pool]) revert PoolIsPaused();
        }
    }

    /**
     * @notice Compute Uniswap V3 pool address
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

    // ============================================================================
    // ROUTE CONFIGURATION
    // ============================================================================

    /**
     * @notice Configure a new route
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param protocol Protocol to use
     * @param poolAddress Pool address (for Uniswap/Curve)
     * @param fee Fee tier (for Uniswap)
     * @param curveIndices Token indices (for Curve)
     * @param useUnderlying Use underlying (for Curve)
     * @param specialContract Special contract (for DirectMint)
     * @param password Security password
     */
    function configureRoute(
        address tokenIn,
        address tokenOut,
        Protocol protocol,
        address poolAddress,
        uint24 fee,
        int128[2] memory curveIndices,
        bool useUnderlying,
        address specialContract,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");
        require(tokenIn != address(0) && tokenOut != address(0), "Invalid tokens");
        require(tokenIn != tokenOut, "Same token");

        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));

        // Create route config
        RouteConfig memory config = RouteConfig({
            protocol: protocol,
            pool: poolAddress,
            fee: fee,
            directSwap: true,
            path: "",
            tokenIndexIn: curveIndices[0],
            tokenIndexOut: curveIndices[1],
            useUnderlying: useUnderlying,
            specialContract: specialContract,
            isConfigured: true,
            routeData: ""
        });

        // Encode route data based on protocol
        if (protocol == Protocol.UniswapV3) {
            config.routeData = abi.encode(UniswapV3Route({pool: poolAddress, fee: fee, isMultiHop: false, path: ""}));
        } else if (protocol == Protocol.Curve) {
            config.routeData = abi.encode(
                CurveRoute({
                    pool: poolAddress,
                    indexIn: curveIndices[0],
                    indexOut: curveIndices[1],
                    useUnderlying: useUnderlying
                })
            );
        } else if (protocol == Protocol.DirectMint) {
            config.routeData = abi.encode(specialContract);
        }

        routes[routeKey] = config;
        emit RouteConfigured(tokenIn, tokenOut, protocol, poolAddress);
    }

    /**
     * @notice Configure a multi-hop route
     * @param tokenIn Starting token
     * @param tokenOut Ending token
     * @param path Encoded Uniswap V3 path
     * @param password Security password
     */
    function configureMultiHopRoute(
        address tokenIn,
        address tokenOut,
        bytes calldata path,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");
        require(path.length >= 43, "Path too short");
        require((path.length - 20) % 23 == 0, "Invalid path length");

        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));

        RouteConfig memory config = RouteConfig({
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

        routes[routeKey] = config;
        emit RouteConfigured(tokenIn, tokenOut, Protocol.MultiHop, address(0));
    }

    /**
     * @notice Configure a multi-step route
     * @param tokenIn Starting token
     * @param tokenOut Ending token
     * @param tokens Token path
     * @param protocols Protocols for each step
     * @param routeDatas Route data for each step
     * @param minAmounts Minimum amounts for each step
     * @param password Security password
     */
    function configureMultiStepRoute(
        address tokenIn,
        address tokenOut,
        address[] calldata tokens,
        Protocol[] calldata protocols,
        bytes[] calldata routeDatas,
        uint256[] calldata minAmounts,
        string calldata password
    ) external onlyRouteManager {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Invalid password");
        require(tokens.length >= 2, "Invalid tokens");
        require(tokens[0] == tokenIn && tokens[tokens.length - 1] == tokenOut, "Token mismatch");
        require(protocols.length == tokens.length - 1, "Invalid protocols");
        require(routeDatas.length == protocols.length, "Invalid route data");
        require(minAmounts.length == protocols.length, "Invalid min amounts");

        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));

        // Encode multi-step data
        bytes memory encodedData = abi.encode(tokens, protocols, routeDatas, minAmounts);

        RouteConfig memory config = RouteConfig({
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
            routeData: encodedData
        });

        routes[routeKey] = config;
        emit RouteConfigured(tokenIn, tokenOut, Protocol.MultiStep, address(0));
    }

    // ============================================================================
    // ADMIN FUNCTIONS
    // ============================================================================

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

    /**
     * @notice Register a new DEX for custom routing
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
     */
    function unregisterDEX(address dex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(registeredDEXes[dex], "DEX not registered");
        require(block.timestamp >= dexRegistrationTime[dex] + DEX_TIMELOCK, "Timelock not expired");

        registeredDEXes[dex] = false;
        emit DexUnregistered(dex, msg.sender, block.timestamp);
    }

    /**
     * @notice Whitelist a function selector for custom DEX calls
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

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Generate complete execution plan for multi-step swaps (enhanced)
     * @dev Now handles any number of hops discovered by route finding
     */
    function getCompleteMultiStepPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) external returns (uint256 totalQuotedAmount, MultiStepExecutionPlan memory plan) {
        // Validate inputs
        if (amountIn == 0) revert ZeroAmount();
        if (tokenIn == tokenOut) revert SameTokenSwap();
        if (_isCrossCategory(tokenIn, tokenOut)) revert NoRouteFound();

        // Find multi-hop route
        (
            bool found,
            address[] memory path,
            Protocol[] memory protocols,
            bytes[] memory routeDatas
        ) = _findMultiHopRoute(tokenIn, tokenOut, MAX_MULTI_STEP_OPERATIONS);

        if (!found) {
            revert NoRouteFound();
        }

        // Calculate all minimum amounts
        uint256[] memory minAmounts;
        (minAmounts, totalQuotedAmount) = _calculateMultiStepMinAmounts(path, amountIn, protocols, routeDatas);

        // Build execution steps
        plan.steps = new SwapStep[](protocols.length);
        uint256 currentAmount = amountIn;

        for (uint256 i = 0; i < protocols.length; i++) {
            SwapStep memory step;
            step.tokenIn = path[i];
            step.tokenOut = path[i + 1];
            step.amountIn = currentAmount;
            step.minAmountOut = minAmounts[i];
            step.protocol = protocols[i];

            // Generate execution data for this step
            ExecutionStrategy memory stepStrategy = ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: protocols[i],
                bridgeAsset: address(0),
                primaryRouteData: routeDatas[i],
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(protocols[i])
            });

            (step.data, step.target) = _generateDirectExecutionData(
                stepStrategy,
                step.tokenIn,
                step.tokenOut,
                step.amountIn,
                step.minAmountOut,
                recipient
            );

            step.value = (step.tokenIn == ETH_ADDRESS) ? step.amountIn : 0;
            plan.steps[i] = step;

            // Update for next iteration - use quote as input for next step
            if (i < protocols.length - 1) {
                currentAmount = (minAmounts[i] * 10050) / 10000; // Add 0.5% buffer
            }
        }

        plan.expectedFinalAmount = totalQuotedAmount;
        emit MultiStepPlanGenerated(tokenIn, tokenOut, amountIn, plan.steps.length);
    }

    /**
     * @notice Build complete multi-step execution plan
     * @dev Pre-calculates all amounts and generates all calldata upfront
     */
    function _buildMultiStepPlan(
        ExecutionStrategy memory strategy,
        uint256 amountIn,
        address recipient
    ) internal returns (MultiStepExecutionPlan memory plan) {
        // Decode multi-step configuration
        (address[] memory tokens, Protocol[] memory protocols, bytes[] memory routeDatas, ) = abi.decode(
            strategy.primaryRouteData,
            (address[], Protocol[], bytes[], uint256[])
        );

        // Pre-calculate all amounts
        uint256[] memory minAmounts;
        uint256 finalAmount;
        (minAmounts, finalAmount) = _calculateMultiStepMinAmounts(tokens, amountIn, protocols, routeDatas);

        // Build execution steps
        plan.steps = new SwapStep[](protocols.length);
        uint256 currentAmount = amountIn;

        for (uint256 i = 0; i < protocols.length; i++) {
            SwapStep memory step;
            step.tokenIn = tokens[i];
            step.tokenOut = tokens[i + 1];
            step.amountIn = currentAmount;
            step.minAmountOut = minAmounts[i];
            step.protocol = protocols[i];

            // Generate execution data for this step
            ExecutionStrategy memory stepStrategy = ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: protocols[i],
                bridgeAsset: address(0),
                primaryRouteData: routeDatas[i],
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(protocols[i])
            });

            (step.data, step.target) = _generateDirectExecutionData(
                stepStrategy,
                step.tokenIn,
                step.tokenOut,
                step.amountIn,
                step.minAmountOut,
                recipient
            );

            step.value = (step.tokenIn == ETH_ADDRESS) ? step.amountIn : 0;
            plan.steps[i] = step;

            // Update for next iteration
            currentAmount = (minAmounts[i] * 10050) / 10000; // Add 0.5% buffer for next step
        }

        plan.expectedFinalAmount = finalAmount;
    }

    /**
     * @notice Build bridge swap as multi-step plan
     * @dev Converts bridge route to two-step execution plan
     */
    function _buildBridgePlan(
        ExecutionStrategy memory strategy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal returns (MultiStepExecutionPlan memory plan) {
        plan.steps = new SwapStep[](2);

        // First leg: tokenIn -> bridgeAsset
        (uint256 firstLegQuote, uint256 firstLegMin) = _getQuoteWithFallback(
            tokenIn,
            strategy.bridgeAsset,
            amountIn,
            ExecutionStrategy({
                routeType: RouteType.Direct,
                protocol: strategy.protocol,
                bridgeAsset: address(0),
                primaryRouteData: strategy.primaryRouteData,
                secondaryRouteData: "",
                expectedGas: _estimateGasForProtocol(strategy.protocol)
            })
        );

        SwapStep memory firstStep;
        firstStep.tokenIn = tokenIn;
        firstStep.tokenOut = strategy.bridgeAsset;
        firstStep.amountIn = amountIn;
        firstStep.minAmountOut = firstLegMin;
        firstStep.protocol = strategy.protocol;

        (firstStep.data, firstStep.target) = _generateDirectExecutionData(
            strategy,
            tokenIn,
            strategy.bridgeAsset,
            amountIn,
            firstLegMin,
            recipient
        );

        firstStep.value = (tokenIn == ETH_ADDRESS) ? amountIn : 0;
        plan.steps[0] = firstStep;

        // Second leg: bridgeAsset -> tokenOut
        bytes32 secondRouteKey = keccak256(abi.encodePacked(strategy.bridgeAsset, tokenOut));
        RouteConfig memory secondConfig = routes[secondRouteKey];

        ExecutionStrategy memory secondStrategy = ExecutionStrategy({
            routeType: RouteType.Direct,
            protocol: secondConfig.protocol,
            bridgeAsset: address(0),
            primaryRouteData: secondConfig.routeData,
            secondaryRouteData: "",
            expectedGas: _estimateGasForProtocol(secondConfig.protocol)
        });

        (uint256 secondLegQuote, uint256 secondLegMin) = _getQuoteWithFallback(
            strategy.bridgeAsset,
            tokenOut,
            firstLegQuote,
            secondStrategy
        );

        SwapStep memory secondStep;
        secondStep.tokenIn = strategy.bridgeAsset;
        secondStep.tokenOut = tokenOut;
        secondStep.amountIn = firstLegQuote;
        secondStep.minAmountOut = secondLegMin;
        secondStep.protocol = secondConfig.protocol;

        (secondStep.data, secondStep.target) = _generateDirectExecutionData(
            secondStrategy,
            strategy.bridgeAsset,
            tokenOut,
            firstLegQuote,
            secondLegMin,
            recipient
        );

        secondStep.value = (strategy.bridgeAsset == ETH_ADDRESS) ? firstLegQuote : 0;
        plan.steps[1] = secondStep;

        plan.expectedFinalAmount = secondLegQuote;
    }

    /**
     * @notice Wrap single step in plan for consistent interface
     */
    function _wrapSingleStepPlan(
        ExecutionStrategy memory strategy,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal returns (MultiStepExecutionPlan memory plan) {
        plan.steps = new SwapStep[](1);

        (uint256 quotedAmount, uint256 minAmountOut) = _getQuoteWithFallback(tokenIn, tokenOut, amountIn, strategy);

        SwapStep memory step;
        step.tokenIn = tokenIn;
        step.tokenOut = tokenOut;
        step.amountIn = amountIn;
        step.minAmountOut = minAmountOut;
        step.protocol = strategy.protocol;

        (step.data, step.target) = _generateDirectExecutionData(
            strategy,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            recipient
        );

        step.value = (tokenIn == ETH_ADDRESS) ? amountIn : 0;
        plan.steps[0] = step;
        plan.expectedFinalAmount = quotedAmount;
    }

    /**
     * @notice Check if a route exists (enhanced with multi-hop support)
     * @dev Now discovers routes up to MAX_MULTI_STEP_OPERATIONS hops
     */
    function hasRoute(address tokenIn, address tokenOut) external view returns (bool) {
        if (tokenIn == tokenOut) return false;
        if (_isCrossCategory(tokenIn, tokenOut)) return false;

        // Try to find multi-hop route
        (bool found, , , ) = _findMultiHopRoute(tokenIn, tokenOut, MAX_MULTI_STEP_OPERATIONS);
        return found;
    }

    /**
     * @notice Find multi-hop route with iterative breadth-first search
     * @dev More reliable than recursive approach - finds shortest paths first
     */
    function _findMultiHopRoute(
        address tokenIn,
        address tokenOut,
        uint256 maxHops
    )
        internal
        view
        returns (bool found, address[] memory path, Protocol[] memory protocols, bytes[] memory routeDatas)
    {
        if (maxHops == 0 || tokenIn == tokenOut) return (false, new address[](0), new Protocol[](0), new bytes[](0));

        // Try direct route first (1-hop)
        bytes32 directKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        bytes32 reverseKey = keccak256(abi.encodePacked(tokenOut, tokenIn));

        if (routes[directKey].isConfigured) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            protocols = new Protocol[](1);
            protocols[0] = routes[directKey].protocol;

            routeDatas = new bytes[](1);
            routeDatas[0] = routes[directKey].routeData;

            return (true, path, protocols, routeDatas);
        }

        if (routes[reverseKey].isConfigured) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            protocols = new Protocol[](1);
            protocols[0] = routes[reverseKey].protocol;

            routeDatas = new bytes[](1);
            routeDatas[0] = _encodeReverseRouteData(routes[reverseKey], tokenOut, tokenIn);

            return (true, path, protocols, routeDatas);
        }

        // Try 2-hop routes (bridge routes)
        if (maxHops >= 2) {
            address[] memory intermediates = _getIntermediateTokens(tokenIn, tokenOut);

            for (uint256 i = 0; i < intermediates.length; i++) {
                address bridge = intermediates[i];

                // Check first leg: tokenIn -> bridge
                bool firstLegExists = false;
                Protocol firstProtocol;
                bytes memory firstRouteData;

                bytes32 firstDirectKey = keccak256(abi.encodePacked(tokenIn, bridge));
                bytes32 firstReverseKey = keccak256(abi.encodePacked(bridge, tokenIn));

                if (routes[firstDirectKey].isConfigured) {
                    firstLegExists = true;
                    firstProtocol = routes[firstDirectKey].protocol;
                    firstRouteData = routes[firstDirectKey].routeData;
                } else if (routes[firstReverseKey].isConfigured) {
                    firstLegExists = true;
                    firstProtocol = routes[firstReverseKey].protocol;
                    firstRouteData = _encodeReverseRouteData(routes[firstReverseKey], bridge, tokenIn);
                }

                if (!firstLegExists) continue;

                // Check second leg: bridge -> tokenOut
                bool secondLegExists = false;
                Protocol secondProtocol;
                bytes memory secondRouteData;

                bytes32 secondDirectKey = keccak256(abi.encodePacked(bridge, tokenOut));
                bytes32 secondReverseKey = keccak256(abi.encodePacked(tokenOut, bridge));

                if (routes[secondDirectKey].isConfigured) {
                    secondLegExists = true;
                    secondProtocol = routes[secondDirectKey].protocol;
                    secondRouteData = routes[secondDirectKey].routeData;
                } else if (routes[secondReverseKey].isConfigured) {
                    secondLegExists = true;
                    secondProtocol = routes[secondReverseKey].protocol;
                    secondRouteData = _encodeReverseRouteData(routes[secondReverseKey], tokenOut, bridge);
                }

                if (secondLegExists) {
                    // Found 2-hop route!
                    path = new address[](3);
                    path[0] = tokenIn;
                    path[1] = bridge;
                    path[2] = tokenOut;

                    protocols = new Protocol[](2);
                    protocols[0] = firstProtocol;
                    protocols[1] = secondProtocol;

                    routeDatas = new bytes[](2);
                    routeDatas[0] = firstRouteData;
                    routeDatas[1] = secondRouteData;

                    return (true, path, protocols, routeDatas);
                }
            }
        }

        // Try 3-hop routes if needed
        if (maxHops >= 3) {
            return _find3HopRoute(tokenIn, tokenOut);
        }

        return (false, new address[](0), new Protocol[](0), new bytes[](0));
    }

    /**
     * @notice Find 3-hop routes specifically
     * @dev Handles cases like STETH->WETH->RETH->OSETH
     */
    function _find3HopRoute(
        address tokenIn,
        address tokenOut
    )
        internal
        view
        returns (bool found, address[] memory path, Protocol[] memory protocols, bytes[] memory routeDatas)
    {
        address[] memory intermediates = _getIntermediateTokens(tokenIn, tokenOut);

        // Try each intermediate as first bridge
        for (uint256 i = 0; i < intermediates.length; i++) {
            address firstBridge = intermediates[i];

            // Check if tokenIn -> firstBridge exists
            if (!_hasDirectRoute(tokenIn, firstBridge)) continue;

            // Try each intermediate as second bridge
            for (uint256 j = 0; j < intermediates.length; j++) {
                address secondBridge = intermediates[j];
                if (secondBridge == firstBridge) continue;

                // Check the 3-hop path: tokenIn -> firstBridge -> secondBridge -> tokenOut
                if (_hasDirectRoute(firstBridge, secondBridge) && _hasDirectRoute(secondBridge, tokenOut)) {
                    // Build the path
                    path = new address[](4);
                    path[0] = tokenIn;
                    path[1] = firstBridge;
                    path[2] = secondBridge;
                    path[3] = tokenOut;

                    protocols = new Protocol[](3);
                    routeDatas = new bytes[](3);

                    // Get route data for each leg
                    (protocols[0], routeDatas[0]) = _getRouteInfo(tokenIn, firstBridge);
                    (protocols[1], routeDatas[1]) = _getRouteInfo(firstBridge, secondBridge);
                    (protocols[2], routeDatas[2]) = _getRouteInfo(secondBridge, tokenOut);

                    return (true, path, protocols, routeDatas);
                }
            }
        }

        return (false, new address[](0), new Protocol[](0), new bytes[](0));
    }

    /**
     * @notice Check if direct route exists (either direction)
     */
    function _hasDirectRoute(address tokenA, address tokenB) internal view returns (bool) {
        bytes32 directKey = keccak256(abi.encodePacked(tokenA, tokenB));
        bytes32 reverseKey = keccak256(abi.encodePacked(tokenB, tokenA));
        return routes[directKey].isConfigured || routes[reverseKey].isConfigured;
    }

    /**
     * @notice Get route protocol and data (handles reverse routes)
     */
    function _getRouteInfo(
        address tokenA,
        address tokenB
    ) internal view returns (Protocol protocol, bytes memory routeData) {
        bytes32 directKey = keccak256(abi.encodePacked(tokenA, tokenB));
        bytes32 reverseKey = keccak256(abi.encodePacked(tokenB, tokenA));

        if (routes[directKey].isConfigured) {
            protocol = routes[directKey].protocol;
            routeData = routes[directKey].routeData;
        } else if (routes[reverseKey].isConfigured) {
            protocol = routes[reverseKey].protocol;
            routeData = _encodeReverseRouteData(routes[reverseKey], tokenB, tokenA);
        } else {
            revert("No route found");
        }
    }

    /**
     * @notice Recursive multi-hop route discovery
     * @dev Core algorithm for finding complex routes
     */
    function _findMultiHopRouteRecursive(
        address tokenIn,
        address tokenOut,
        uint256 remainingHops,
        address[] memory visitedTokens
    )
        internal
        view
        returns (bool found, address[] memory path, Protocol[] memory protocols, bytes[] memory routeDatas)
    {
        if (remainingHops == 0) return (false, new address[](0), new Protocol[](0), new bytes[](0));

        // Prevent infinite loops
        for (uint256 i = 0; i < visitedTokens.length; i++) {
            if (visitedTokens[i] == tokenIn) {
                return (false, new address[](0), new Protocol[](0), new bytes[](0));
            }
        }

        // Get potential intermediate tokens based on asset type
        address[] memory intermediateTokens = _getIntermediateTokens(tokenIn, tokenOut);

        for (uint256 i = 0; i < intermediateTokens.length; i++) {
            address intermediate = intermediateTokens[i];

            // Skip if already visited
            bool alreadyVisited = false;
            for (uint256 j = 0; j < visitedTokens.length; j++) {
                if (visitedTokens[j] == intermediate) {
                    alreadyVisited = true;
                    break;
                }
            }
            if (alreadyVisited) continue;

            // Check if there's a direct route from tokenIn to intermediate
            bytes32 directKey = keccak256(abi.encodePacked(tokenIn, intermediate));
            bytes32 reverseKey = keccak256(abi.encodePacked(intermediate, tokenIn));

            if (!routes[directKey].isConfigured && !routes[reverseKey].isConfigured) continue;

            // Create new visited array
            address[] memory newVisited = new address[](visitedTokens.length + 1);
            for (uint256 j = 0; j < visitedTokens.length; j++) {
                newVisited[j] = visitedTokens[j];
            }
            newVisited[visitedTokens.length] = tokenIn;

            // Recursively find route from intermediate to tokenOut
            (
                bool foundNext,
                address[] memory nextPath,
                Protocol[] memory nextProtocols,
                bytes[] memory nextRouteDatas
            ) = _findMultiHopRouteRecursive(intermediate, tokenOut, remainingHops - 1, newVisited);

            if (foundNext) {
                // Construct complete path
                path = new address[](nextPath.length + 1);
                path[0] = tokenIn;
                for (uint256 j = 0; j < nextPath.length; j++) {
                    path[j + 1] = nextPath[j];
                }

                // Construct protocols
                protocols = new Protocol[](nextProtocols.length + 1);
                protocols[0] = routes[directKey].isConfigured
                    ? routes[directKey].protocol
                    : routes[reverseKey].protocol;
                for (uint256 j = 0; j < nextProtocols.length; j++) {
                    protocols[j + 1] = nextProtocols[j];
                }

                // Construct route datas
                routeDatas = new bytes[](nextRouteDatas.length + 1);
                if (routes[directKey].isConfigured) {
                    routeDatas[0] = routes[directKey].routeData;
                } else {
                    routeDatas[0] = _encodeReverseRouteData(routes[reverseKey], intermediate, tokenIn);
                }
                for (uint256 j = 0; j < nextRouteDatas.length; j++) {
                    routeDatas[j + 1] = nextRouteDatas[j];
                }

                return (true, path, protocols, routeDatas);
            }
        }

        return (false, new address[](0), new Protocol[](0), new bytes[](0));
    }

    /**
     * @notice Get potential intermediate tokens (simplified and more reliable)
     */
    function _getIntermediateTokens(address tokenIn, address tokenOut) internal view returns (address[] memory) {
        AssetType typeIn = tokenIn == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenIn];
        AssetType typeOut = tokenOut == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenOut];

        // Cross-category not allowed
        if (typeIn != typeOut && !(typeIn == AssetType.ETH_LST && typeOut == AssetType.ETH_LST)) {
            return new address[](0);
        }

        if (typeIn == AssetType.ETH_LST) {
            // ETH LST tokens - return all major tokens except input/output
            address[] memory allCandidates = new address[](6);
            allCandidates[0] = address(WETH); // Most liquid
            allCandidates[1] = ETH_ADDRESS; // Native ETH
            allCandidates[2] = RETH; // rETH
            allCandidates[3] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
            allCandidates[4] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
            allCandidates[5] = OSETH; // osETH

            // Filter out input and output tokens
            uint256 validCount = 0;
            for (uint256 i = 0; i < allCandidates.length; i++) {
                if (allCandidates[i] != tokenIn && allCandidates[i] != tokenOut) {
                    validCount++;
                }
            }

            address[] memory result = new address[](validCount);
            uint256 resultIndex = 0;
            for (uint256 i = 0; i < allCandidates.length; i++) {
                if (allCandidates[i] != tokenIn && allCandidates[i] != tokenOut) {
                    result[resultIndex++] = allCandidates[i];
                }
            }

            return result;
        } else if (typeIn == AssetType.BTC_WRAPPED) {
            // BTC wrapped tokens - use WBTC as bridge
            if (tokenIn != WBTC && tokenOut != WBTC) {
                address[] memory result = new address[](1);
                result[0] = WBTC;
                return result;
            }
        }

        return new address[](0);
    }

    /**
     * @notice Get route configuration
     */
    function getRoute(address tokenIn, address tokenOut) external view returns (RouteConfig memory) {
        bytes32 routeKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        return routes[routeKey];
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

    /**
     * @notice Check if swap is cross-category (forbidden)
     */
    function _isCrossCategory(address tokenIn, address tokenOut) internal view returns (bool) {
        AssetType typeIn = tokenIn == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenIn];
        AssetType typeOut = tokenOut == ETH_ADDRESS ? AssetType.ETH_LST : assetTypes[tokenOut];

        // Same type is always allowed
        if (typeIn == typeOut) return false;

        // ETH is considered ETH_LST, so ETH <-> ETH_LST is allowed
        if (
            (tokenIn == ETH_ADDRESS && tokenOut != address(0) && assetTypes[tokenOut] == AssetType.ETH_LST) ||
            (tokenOut == ETH_ADDRESS && tokenIn != address(0) && assetTypes[tokenIn] == AssetType.ETH_LST)
        ) {
            return false;
        }

        // Everything else is cross-category
        return true;
    }

    /**
     * @notice Validate multi-step route configuration
     */
    function _validateMultiStepRoute(
        address[] memory tokens,
        Protocol[] memory protocols,
        bytes[] memory routeDatas
    ) internal view returns (bool) {
        // Check array lengths
        if (tokens.length < 2) return false;
        if (protocols.length != tokens.length - 1) return false;
        if (routeDatas.length != protocols.length) return false;

        // Validate each step doesn't create cross-category swap
        for (uint256 i = 0; i < protocols.length; i++) {
            if (_isCrossCategory(tokens[i], tokens[i + 1])) {
                return false;
            }
        }

        return true;
    }

    function emergencyWithdraw(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(paused(), "Not in emergency");
        if (token == ETH_ADDRESS) {
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}