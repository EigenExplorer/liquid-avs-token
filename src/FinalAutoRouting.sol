// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IUniswapV3Quoter.sol";
import "./interfaces/ICurvePool.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IFrxETHMinter.sol";

/**
 * @title FinalAutoRouting
 * @notice Production-ready asset swapper with quoter-first optimization
 * @author ThinkOutSideTheBlock
 * @dev Features:
 *      - Quoter-first approach: Try tight slippage first, fallback to config
 *      - All protocols: Uniswap V3, Curve, DirectMint, MultiHop, MultiStep
 *      - Gas-optimized execution with minimal redundancy
 *      - Enterprise-grade security and validation
 */
contract FinalAutoRouting is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // ============================================================================
    // CONSTANTS & IMMUTABLES
    // ============================================================================

    /// @notice WETH contract for protocol interactions
    IWETH public WETH;

    /// @notice Uniswap V3 Router for DEX operations
    IUniswapV3Router public uniswapRouter;

    /// @notice Uniswap V3 Quoter for price discovery
    IUniswapV3Quoter public uniswapQuoter;

    /// @notice frxETH Minter for direct minting operations
    IFrxETHMinter public frxETHMinter;

    /// @notice Password hash for secure route management
    bytes32 public ROUTE_PASSWORD_HASH;

    /// @notice Maximum allowed slippage (20%)
    uint256 public constant MAX_SLIPPAGE = 2000;

    /// @notice ETH placeholder address
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    /// @notice Known token addresses for special routes
    address public constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;

    /// @notice Quoter-first configuration  
    uint256 public constant TIGHT_BUFFER_BPS = 20; // 0.2% buffer for primary swap
    uint256 public constant QUOTE_MAX_AGE = 30; // 30 seconds max quote age
    uint256 public constant MAX_CURVE_TOKENS = 8;
    uint256 public constant EXTERNAL_CALL_GAS_LIMIT = 300000;
    uint256 public constant MAX_PRICE_IMPACT_MULTIPLIER = 10;
    uint256 public constant MAX_MULTI_STEP_OPERATIONS = 5;

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Contract initialization status
    bool private initialized;

    /// @notice Route manager for advanced operations
    address public routeManager;

    /// @notice Authorized callers (typically LiquidTokenManager)
    mapping(address => bool) public authorizedCallers;

    /// @notice Slippage tolerance per token pair (basis points)  MODIFIED: Now for fallback only
    mapping(address => mapping(address => uint256)) public slippageTolerance;

    /// @notice Asset type classification
    mapping(address => AssetType) public assetTypes;

    /// @notice Whitelisted pools for security
    mapping(address => bool) public whitelistedPools;

    /// @notice Supported tokens registry
    mapping(address => bool) public farSupportedTokens;
    /// @notice Emergency pause status per pool
    mapping(address => bool) public poolPaused;

    /// @notice Emergency pause status per protocol
    mapping(Protocol => bool) public protocolPaused;

    /// @notice Token decimal places for normalization
    mapping(address => uint8) public tokenDecimals;

    /// @notice Custom routes enabled by management
    mapping(address => mapping(address => bool)) public customRouteEnabled;

    /// @notice Curve pool configurations
    mapping(address => uint256) public curvePoolTokenCounts;
    mapping(address => CurveInterface) public curvePoolInterfaces;

    /// @notice Configuration update locks to prevent race conditions
    mapping(bytes32 => uint256) private configUpdateLocks;

    /// @notice Route configurations
    mapping(address => mapping(address => RouteConfig)) public routes;

    // ============================================================================
    // DYNAMIC DEX REGISTRY 
    // ============================================================================

    /// @notice Registered dynamic DEXes for backend integration
    mapping(address => bool) public registeredDEXes;

    /// @notice DEX information for logging/tracking
    mapping(address => string) public dexNames;

    /// @notice Array of all registered DEXes
    address[] public allRegisteredDEXes;

    /// @notice Blacklisted dangerous function selectors
    mapping(bytes4 => bool) public dangerousSelectors;

    /// @notice Maximum gas limit for DEX calls
    uint256 public constant MAX_DEX_GAS_LIMIT = 500000;

    /// @notice Array to track blacklisted selectors
    bytes4[] public allDangerousSelectors;
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

    /// @notice Quoter data structure  
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
        int128 tokenIndexIn;
        int128 tokenIndexOut;
        bool useUnderlying;
    }

    struct SlippageConfig {
        address tokenIn;
        address tokenOut;
        uint256 slippageBps;
    }

    struct MultiHopRoute {
        bytes32 routeHash;
        uint256 intermediateMinOut;
        bytes routeData;
    }

    struct MultiStepRoute {
        StepAction[] steps;
    }

    struct StepAction {
        ActionType actionType;
        Protocol protocol;
        address tokenIn;
        address tokenOut;
        bytes routeData;
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
    }

    //added for our new pattern(qouter first then fallback)
    struct OptimalSlippageConfig {
        address tokenIn;
        address tokenOut;
        uint256 slippageBps;
        string routeType; // For documentation
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    event AssetSwapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        Protocol protocol,
        address caller,
        uint256 gasUsed,
        uint256 timestamp,
        bytes32 indexed routeHash
    );

    event AuthorizedCallerUpdated(
        address indexed caller,
        bool authorized,
        address indexed updatedBy,
        uint256 timestamp
    );
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
    event CustomRouteEnabled(
        address indexed tokenIn,
        address indexed tokenOut,
        bool enabled,
        address indexed enabledBy,
        uint256 timestamp
    );
    event PoolEmergencyPaused(address indexed pool, address indexed pausedBy, string reason, uint256 timestamp);
    event ProtocolEmergencyPaused(
        Protocol indexed protocol,
        address indexed pausedBy,
        string reason,
        uint256 timestamp
    );
    event EmergencyApprovalRevoked(
        address indexed token,
        address indexed spender,
        address indexed revokedBy,
        uint256 timestamp
    );
    event MultiStepExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 stepCount,
        address indexed caller,
        uint256 timestamp
    );
    event RouteManagerUpdated(address indexed oldManager, address indexed newManager, uint256 timestamp);
    event RouteConfigured(address indexed tokenIn, address indexed tokenOut, Protocol protocol, address pool);

    /// @notice Quoter-specific events  
    event QuoterSwapAttempted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 quotedOutput,
        bool success
    );
    event FallbackSwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 configSlippage
    );
    // DEX Registry Events
    event DEXRegistered(address indexed dex, string name, uint256 timestamp);
    event DEXRemoved(address indexed dex, string name, uint256 timestamp);
    event BackendSwapExecuted(
        address indexed dex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );
    // Security Events
    event DangerousSelectorAdded(bytes4 indexed selector, string reason, address indexed addedBy, uint256 timestamp);

    event DangerousSelectorRemoved(bytes4 indexed selector, address indexed removedBy, uint256 timestamp);

    event SelectorValidationFailed(bytes4 indexed selector, address indexed dex, uint256 timestamp);
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
    error TokenNotSupportedByFAR();
    error PoolIsPaused();
    error ProtocolIsPaused();
    error InvalidParameter(string parameter);
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidAddress();
    error InvalidRoutePassword();
    error InsufficientAllowance();
    error InvalidTokenIndex();
    error UnsupportedInterface();
    error ExternalCallFailed(string reason);
    error InvalidReturnData();
    error ConfigurationLocked();
    error NormalizationOverflow();
    error InvalidDecimals();
    error UnsupportedRoute();
    error TransferFailed();
    error TooManySteps();
    error InvalidStep();
    error UnauthorizedRouteManager();
    error QuoteTooOld(); 
    error NoConfigSlippage(); 
    // DEX Registry Errors
    error DEXNotRegistered();
    error DEXAlreadyRegistered();
    error UnauthorizedBackendCaller();
    error BackendSwapFailed(string reason);
    // Security Errors
    error DangerousSelector();
    error SelectorAlreadyBlacklisted();
    error SelectorNotBlacklisted();
    // ============================================================================
    // MODIFIERS (unchanged, keeping all security features)
    // ============================================================================

    modifier onlyAuthorizedCaller() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedCaller();
        }
        _;
    }

    modifier onlyRouteManager() {
        if (msg.sender != routeManager && msg.sender != owner()) {
            revert UnauthorizedRouteManager();
        }
        _;
    }

    modifier poolNotPaused(address pool) {
        if (poolPaused[pool]) revert PoolIsPaused();
        _;
    }

    modifier protocolNotPaused(Protocol protocol) {
        if (protocolPaused[protocol]) revert ProtocolIsPaused();
        _;
    }

    modifier hasApproval(
        address token,
        address spender,
        uint256 amount
    ) {
        if (IERC20(token).allowance(msg.sender, spender) < amount) {
            revert InsufficientAllowance();
        }
        _;
    }

    modifier configNotLocked(bytes32 configHash) {
        if (configUpdateLocks[configHash] > block.timestamp) {
            revert ConfigurationLocked();
        }
        configUpdateLocks[configHash] = block.timestamp + 300;
        _;
        delete configUpdateLocks[configHash];
    }

    // ============================================================================
    // CONSTRUCTOR & INITIALIZATION
    // ============================================================================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract with all required parameters
    /// @param _weth WETH contract address
    /// @param _uniswapRouter Uniswap V3 Router address
    /// @param _uniswapQuoter Uniswap V3 Quoter address
    /// @param _frxETHMinter frxETH Minter address
    /// @param _routeManager Route manager address
    /// @param _routePasswordHash Password hash for route management
    /// @param _liquidTokenManager LTM address for authorization
    /// @param _initializeProduction Whether to auto-apply production config
    function initialize(
        address _weth,
        address _uniswapRouter,
        address _uniswapQuoter,
        address _frxETHMinter,
        address _routeManager,
        bytes32 _routePasswordHash,
        address _liquidTokenManager,
        bool _initializeProduction
    ) external initializer {
        // Initialize parent contracts
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // Validate addresses
        if (_weth == address(0)) revert InvalidAddress();
        if (_uniswapRouter == address(0)) revert InvalidAddress();
        if (_uniswapQuoter == address(0)) revert InvalidAddress();
        if (_frxETHMinter == address(0)) revert InvalidAddress();
        if (_routeManager == address(0)) revert InvalidAddress();
        if (_liquidTokenManager == address(0)) revert InvalidAddress();
        if (_routePasswordHash == bytes32(0)) revert InvalidParameter("routePasswordHash");

        // Set immutable-like storage variables
        WETH = IWETH(_weth);
        uniswapRouter = IUniswapV3Router(_uniswapRouter);
        uniswapQuoter = IUniswapV3Quoter(_uniswapQuoter);
        frxETHMinter = IFrxETHMinter(_frxETHMinter);
        routeManager = _routeManager;
        ROUTE_PASSWORD_HASH = _routePasswordHash;

        // Authorize LTM
        authorizedCallers[_liquidTokenManager] = true;
        emit AuthorizedCallerUpdated(_liquidTokenManager, true, msg.sender, block.timestamp);

        // Apply production configuration if requested
        if (_initializeProduction) {
            _applyProductionSlippageConfig();
            _applyProductionTokenConfig();
            _applyProductionPoolConfig();
            _applyProductionRouteConfig();
        }
    }

    /// @notice Apply production token configuration - ETH LST + BTC only (no cross-category)
    function _applyProductionTokenConfig() internal {
        // ETH LST tokens (18 decimals) - From your exact test data
        address[13] memory ethTokens = [
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            0xE95A203B1a91a908F9B9CE46459d101078c2c3cb, // ankrETH
            0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, // cbETH
            0xA35b1B31Ce002FBF2058D22F30f95D405200A15b, // ETHx
            0x5E8422345238F34275888049021821E8E08CAa1f, // frxETH
            0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549, // lsETH
            0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa, // mETH
            0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3, // OETH
            0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38, // osETH
            0xae78736Cd615f374D3085123A210448E74Fc6393, // rETH
            0xac3E018457B222d93114458476f3E3416Abbe38F, // sfrxETH
            0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stETH
            0xf951E335afb289353dc249e82926178EaC7DEd78 // swETH
        ];

        for (uint256 i = 0; i < ethTokens.length; i++) {
            farSupportedTokens[ethTokens[i]] = true;
            assetTypes[ethTokens[i]] = AssetType.ETH_LST;
            tokenDecimals[ethTokens[i]] = 18;
        }

        // Native ETH support
        farSupportedTokens[ETH_ADDRESS] = true;
        assetTypes[ETH_ADDRESS] = AssetType.ETH_LST;
        tokenDecimals[ETH_ADDRESS] = 18;

        // BTC tokens - Only BTC to BTC wrapped (from your config)
        address[3] memory btcTokens = [
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC (8 decimals)
            0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3, // stBTC (18 decimals)
            0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568 // uniBTC (8 decimals)
        ];

        uint8[3] memory btcDecimals = [8, 18, 8]; // Exact from your config

        for (uint256 i = 0; i < btcTokens.length; i++) {
            farSupportedTokens[btcTokens[i]] = true;
            assetTypes[btcTokens[i]] = AssetType.BTC_WRAPPED;
            tokenDecimals[btcTokens[i]] = btcDecimals[i];
        }
    }
    /// @notice Apply production pool whitelist - Only pools from your test/config
    function _applyProductionPoolConfig() internal {
        // Exact pools from your poolWhitelist in config
        address[17] memory pools = [
            0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E, // WETH/ankrETH (fee: 3000)
            0x840DEEef2f115Cf50DA625F7368C24af6fE74410, // WETH/cbETH (fee: 500)
            0x5d811a9d059dDAB0C18B385ad3b752f734f011cB, // WETH/lsETH (fee: 500)
            0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14, // WETH/mETH (fee: 500)
            0x52299416C469843F4e0d54688099966a6c7d720f, // WETH/OETH (fee: 500)
            0x553e9C493678d8606d6a5ba284643dB2110Df823, // WETH/rETH (fee: 100)
            0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D, // WETH/stETH (fee: 10000)
            0x30eA22C879628514f1494d4BBFEF79D21A6B49A2, // WETH/swETH (fee: 500)
            0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0, // WBTC/stBTC (fee: 500)
            0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0, // WBTC/uniBTC (fee: 3000)
            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2, // ETH/ankrETH Curve
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492, // ETH/ETHx Curve
            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577, // ETH/frxETH Curve
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, // ETH/stETH Curve
            0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d, // rETH/osETH Curve
            // Additional pools from your config
            0xCBCdF9626bC03E24f779434178A73a0B4bad62eD, // WETH/WBTC (for BTC routes only)
            0x242017eE869bF0734Bc5E4feb086A52e6391Dd0d // Additional pool from config
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            whitelistedPools[pools[i]] = true;

            // Configure Curve pools (indices 10-14)
            if (i >= 10 && i <= 14) {
                curvePoolTokenCounts[pools[i]] = 2;
                curvePoolInterfaces[pools[i]] = CurveInterface.Both;
            }
        }
    }

    /// @notice Apply production routes - ETH LST + BTC only (no cross-category)
    function _applyProductionRouteConfig() internal {
        // === ETH LST ROUTES (WETH -> ETH LST via Uniswap V3) ===

        // WETH -> ankrETH (fee: 3000)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xE95A203B1a91a908F9B9CE46459d101078c2c3cb] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0xff9704a23d4C4F57C69d86E1113c1e9204Cd804E,
            fee: 3000,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> cbETH (fee: 500)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xBe9895146f7AF43049ca1c1AE358B0541Ea49704] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x840DEEef2f115Cf50DA625F7368C24af6fE74410,
            fee: 500,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> lsETH (fee: 500)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x5d811a9d059dDAB0C18B385ad3b752f734f011cB,
            fee: 500,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> mETH (fee: 500)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x04708077eCa6bb527a5BBbD6358ffb043a9c1C14,
            fee: 500,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> OETH (fee: 500)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x52299416C469843F4e0d54688099966a6c7d720f,
            fee: 500,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> rETH (fee: 100)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xae78736Cd615f374D3085123A210448E74Fc6393] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x553e9C493678d8606d6a5ba284643dB2110Df823,
            fee: 100,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> stETH (fee: 10000)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x63818BbDd21E69bE108A23aC1E84cBf66399Bd7D,
            fee: 10000,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WETH -> swETH (fee: 500)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xf951E335afb289353dc249e82926178EaC7DEd78] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2,
            fee: 500,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // === ETH LST ROUTES (ETH -> ETH LST via Curve) ===

        // ETH -> ankrETH
        routes[ETH_ADDRESS][0xE95A203B1a91a908F9B9CE46459d101078c2c3cb] = RouteConfig({
            protocol: Protocol.Curve,
            pool: 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2,
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 1,
            useUnderlying: false,
            specialContract: address(0)
        });

        // ETH -> ETHx
        routes[ETH_ADDRESS][0xA35b1B31Ce002FBF2058D22F30f95D405200A15b] = RouteConfig({
            protocol: Protocol.Curve,
            pool: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492,
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 1,
            useUnderlying: false,
            specialContract: address(0)
        });

        // ETH -> frxETH
        routes[ETH_ADDRESS][0x5E8422345238F34275888049021821E8E08CAa1f] = RouteConfig({
            protocol: Protocol.Curve,
            pool: 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577,
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 1,
            useUnderlying: false,
            specialContract: address(0)
        });

        // ETH -> stETH
        routes[ETH_ADDRESS][0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84] = RouteConfig({
            protocol: Protocol.Curve,
            pool: 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 1,
            useUnderlying: false,
            specialContract: address(0)
        });

        // === DIRECT MINT ROUTES ===

        // ETH -> sfrxETH (Direct Mint)
        routes[ETH_ADDRESS][0xac3E018457B222d93114458476f3E3416Abbe38F] = RouteConfig({
            protocol: Protocol.DirectMint,
            pool: address(0),
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: 0xbAFA44EFE7901E04E39Dad13167D089C559c1138 // frxETHMinter
        });

        // === MULTI-HOP ROUTES ===

        // WETH -> osETH (via rETH)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38] = RouteConfig({
            protocol: Protocol.MultiHop,
            pool: address(0),
            fee: 0,
            directSwap: false,
            path: abi.encodePacked(
                address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
                uint24(100), // fee
                address(0xae78736Cd615f374D3085123A210448E74Fc6393) // rETH
            ),
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d // Curve pool rETH/osETH
        });

        // === MULTI-STEP ROUTES ===

        // WETH -> sfrxETH (unwrap + mint)
        routes[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2][0xac3E018457B222d93114458476f3E3416Abbe38F] = RouteConfig({
            protocol: Protocol.MultiStep,
            pool: address(0),
            fee: 0,
            directSwap: false,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: 0xbAFA44EFE7901E04E39Dad13167D089C559c1138 // frxETHMinter
        });

        // === BTC ROUTES (WBTC -> BTC Wrapped only) ===

        // WBTC -> stBTC
        routes[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599][0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0,
            fee: 500,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });

        // WBTC -> uniBTC
        routes[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599][0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568] = RouteConfig({
            protocol: Protocol.UniswapV3,
            pool: 0x109707Ad4AbD299b3cF6F2b011c2bff88523E2f0,
            fee: 3000,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: address(0)
        });
    }

    /// @notice Initialize contract (unchanged - keeping all validation)
    function initialize(
        address[] calldata tokenAddresses,
        AssetType[] calldata tokenTypes,
        uint8[] calldata decimals,
        address[] calldata poolAddresses,
        uint256[] calldata poolTokenCounts,
        CurveInterface[] calldata curveInterfaces,
        SlippageConfig[] calldata slippageConfigs
    ) external onlyOwner {
        if (initialized) revert AlreadyInitialized();
        if (tokenAddresses.length != tokenTypes.length) revert InvalidParameter("tokenArrays");
        if (tokenAddresses.length != decimals.length) revert InvalidParameter("decimalsArray");
        if (poolAddresses.length != poolTokenCounts.length) revert InvalidParameter("poolArrays");
        if (poolAddresses.length != curveInterfaces.length) revert InvalidParameter("interfaceArrays");

        // Configure supported tokens
        unchecked {
            for (uint256 i = 0; i < tokenAddresses.length; ++i) {
                address token = tokenAddresses[i];
                uint8 tokenDecimal = decimals[i];

                if (token == address(0)) revert InvalidAddress();
                if (tokenDecimal == 0 || tokenDecimal > 77) revert InvalidDecimals();

                farSupportedTokens[token] = true;
                assetTypes[token] = tokenTypes[i];
                tokenDecimals[token] = tokenDecimal;

                emit TokenSupported(token, true, tokenTypes[i], tokenDecimal, block.timestamp);
            }
        }

        // Whitelist pools
        unchecked {
            for (uint256 i = 0; i < poolAddresses.length; ++i) {
                address pool = poolAddresses[i];
                if (pool == address(0)) revert InvalidAddress();
                if (poolTokenCounts[i] == 0 || poolTokenCounts[i] > MAX_CURVE_TOKENS) {
                    revert InvalidParameter("tokenCount");
                }

                whitelistedPools[pool] = true;
                curvePoolTokenCounts[pool] = poolTokenCounts[i];
                curvePoolInterfaces[pool] = curveInterfaces[i];

                emit PoolWhitelisted(pool, true, curveInterfaces[i], msg.sender, block.timestamp);
            }
        }

        // Configure fallback slippage settings  MODIFIED: Now explicitly for fallback
        unchecked {
            for (uint256 i = 0; i < slippageConfigs.length; ++i) {
                SlippageConfig memory config = slippageConfigs[i];
                if (config.tokenIn == address(0) || config.tokenOut == address(0)) {
                    revert InvalidAddress();
                }
                if (config.slippageBps > MAX_SLIPPAGE) revert InvalidParameter("slippage");

                slippageTolerance[config.tokenIn][config.tokenOut] = config.slippageBps;
                emit SlippageConfigured(
                    config.tokenIn,
                    config.tokenOut,
                    config.slippageBps,
                    msg.sender,
                    block.timestamp
                );
            }
        }

        initialized = true;
    }

    // ============================================================================
    // MAIN SWAP FUNCTION - QUOTER-FIRST APPROACH  COMPLETELY REWRITTEN
    // ============================================================================

    /**
     * @notice Main swap function with quoter-first optimization
     * @dev Flow: 1) Get quote + tight buffer → 2) Fallback to config slippage
     * @param params Swap parameters
     * @return amountOut Amount of output tokens received by caller
     */
    function swapAssets(
        SwapParams memory params
    )
        public
        payable
        onlyAuthorizedCaller
        whenNotPaused
        nonReentrant
        protocolNotPaused(params.protocol)
        returns (uint256 amountOut)
    {
        uint256 gasStart = gasleft();

        // Basic validations
        if (params.amountIn == 0) revert ZeroAmount();
        if (!initialized) revert NotInitialized();
        if (params.tokenIn == params.tokenOut) revert InvalidParameter("sameToken");

        _validateTokenSupport(params.tokenIn, params.tokenOut);

        // Generate route hash for tracking
        bytes32 routeHash = keccak256(
            abi.encode(params.tokenIn, params.tokenOut, params.protocol, params.routeData, block.timestamp)
        );

        // Handle token input
        address actualTokenIn = _handleTokenInput(params);

        //  STEP 1: Try quoter-first approach (tight slippage)
        QuoteData memory quote = _getQuote(params.tokenIn, params.tokenOut, params.amountIn, params);

        if (quote.valid) {
            try this._executeSwapWithQuote(actualTokenIn, params, quote) returns (uint256 result) {
                amountOut = result;
                _handleTokenOutput(params.tokenOut, amountOut);

                emit QuoterSwapAttempted(params.tokenIn, params.tokenOut, params.amountIn, quote.expectedOutput, true);
                emit AssetSwapped(
                    params.tokenIn,
                    params.tokenOut,
                    params.amountIn,
                    amountOut,
                    params.protocol,
                    msg.sender,
                    gasStart - gasleft(),
                    block.timestamp,
                    routeHash
                );
                return amountOut;
            } catch {
                emit QuoterSwapAttempted(params.tokenIn, params.tokenOut, params.amountIn, quote.expectedOutput, false);
                // Continue to fallback
            }
        }

        //  STEP 2: Fallback to config slippage
        uint256 configSlippage = slippageTolerance[params.tokenIn][params.tokenOut];
        if (configSlippage == 0) {
            configSlippage = _getDefaultSlippage(params.tokenIn, params.tokenOut);
        }
        if (configSlippage == 0) revert NoConfigSlippage();

        // Execute with fallback slippage
        amountOut = _executeSwapWithConfig(actualTokenIn, params, configSlippage);
        _handleTokenOutput(params.tokenOut, amountOut);

        emit FallbackSwapExecuted(params.tokenIn, params.tokenOut, params.amountIn, configSlippage);
        emit AssetSwapped(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.protocol,
            msg.sender,
            gasStart - gasleft(),
            block.timestamp,
            routeHash
        );
    }

    // ============================================================================
    // QUOTER FUNCTIONS 
    // ============================================================================

    /**
     * @notice Get quote for swap with validation
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param params Swap parameters for route info
     * @return QuoteData with expected output and validity
     */
    function _getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SwapParams memory params
    ) internal returns (QuoteData memory) {
        try this._performQuote(tokenIn, tokenOut, amountIn, params) returns (uint256 expectedOutput) {
            return QuoteData({expectedOutput: expectedOutput, timestamp: block.timestamp, valid: true});
        } catch {
            return QuoteData(0, 0, false);
        }
    }

    /**
     * @notice Perform actual quote based on protocol
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param params Swap parameters for route data
     * @return expectedOutput Expected output amount
     */
    function _performQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SwapParams memory params
    ) external returns (uint256 expectedOutput) {
        if (params.protocol == Protocol.UniswapV3) {
            UniswapV3Route memory route = abi.decode(params.routeData, (UniswapV3Route));

            if (route.isMultiHop) {
                return uniswapQuoter.quoteExactInput(route.path, amountIn);
            } else {
                address actualTokenIn = tokenIn == ETH_ADDRESS ? address(WETH) : tokenIn;
                address actualTokenOut = tokenOut == ETH_ADDRESS ? address(WETH) : tokenOut;
                return uniswapQuoter.quoteExactInputSingle(actualTokenIn, actualTokenOut, route.fee, amountIn, 0);
            }
        } else if (params.protocol == Protocol.Curve) {
            CurveRoute memory route = abi.decode(params.routeData, (CurveRoute));
            return ICurvePool(route.pool).get_dy(route.tokenIndexIn, route.tokenIndexOut, amountIn);
        } else if (params.protocol == Protocol.DirectMint) {
            // For direct mint, assume 1:1 ratio (this is often the case for ETH→sfrxETH)
            return amountIn;
        } else if (params.protocol == Protocol.MultiHop) {
            // For multi-hop, try to get quote from the underlying route
            MultiHopRoute memory route = abi.decode(params.routeData, (MultiHopRoute));
            UniswapV3Route memory uniRoute = abi.decode(route.routeData, (UniswapV3Route));
            return uniswapQuoter.quoteExactInput(uniRoute.path, amountIn);
        } else if (params.protocol == Protocol.MultiStep) {
            // For multi-step, return conservative estimate
            return (amountIn * 95) / 100; // Assume 5% price impact
        }

        revert UnsupportedRoute();
    }

    /**
     * @notice Execute swap with quoter data and tight buffer
     * @param actualTokenIn Processed token input address
     * @param params Original swap parameters
     * @param quote Quote data with expected output
     * @return amountOut Amount received
     */
    function _executeSwapWithQuote(
        address actualTokenIn,
        SwapParams memory params,
        QuoteData memory quote
    ) external returns (uint256) {
        require(msg.sender == address(this), "Internal only");

        // Check quote freshness
        if (block.timestamp - quote.timestamp > QUOTE_MAX_AGE) revert QuoteTooOld();

        // Calculate minAmountOut with tight buffer
        uint256 minAmountOut = (quote.expectedOutput * (10000 - TIGHT_BUFFER_BPS)) / 10000;

        return _executeSwap(actualTokenIn, params, minAmountOut);
    }

    /**
     * @notice Execute swap with config slippage fallback
     * @param actualTokenIn Processed token input address
     * @param params Original swap parameters
     * @param configSlippage Configured slippage in basis points
     * @return amountOut Amount received
     */
    function _executeSwapWithConfig(
        address actualTokenIn,
        SwapParams memory params,
        uint256 configSlippage
    ) internal returns (uint256) {
        // Try to get a fresh quote for better accuracy
        QuoteData memory fallbackQuote = _getQuote(params.tokenIn, params.tokenOut, params.amountIn, params);

        uint256 expectedOutput;
        if (fallbackQuote.valid) {
            expectedOutput = fallbackQuote.expectedOutput;
        } else {
            // Use simple estimate if quote fails
            expectedOutput = _getSimpleEstimate(params.amountIn, params.tokenIn, params.tokenOut);
        }

        uint256 minAmountOut = (expectedOutput * (10000 - configSlippage)) / 10000;

        return _executeSwap(actualTokenIn, params, minAmountOut);
    }

    /**
     * @notice Low-level swap execution (modified to accept minAmountOut parameter)
     * @param actualTokenIn Processed token input address
     * @param params Original swap parameters
     * @param minAmountOut Minimum acceptable output
     * @return amountOut Amount received
     */
    function _executeSwap(
        address actualTokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Execute protocol-specific swap
        if (params.protocol == Protocol.UniswapV3) {
            amountOut = _performUniswapV3Swap(actualTokenIn, params, minAmountOut);
        } else if (params.protocol == Protocol.Curve) {
            amountOut = _performCurveSwap(actualTokenIn, params, minAmountOut);
        } else if (params.protocol == Protocol.DirectMint) {
            amountOut = _performDirectMint(params);
        } else if (params.protocol == Protocol.MultiHop) {
            amountOut = _performMultiHopSwap(params, minAmountOut);
        } else if (params.protocol == Protocol.MultiStep) {
            amountOut = _performMultiStepSwap(params, minAmountOut);
        } else {
            revert InvalidProtocol();
        }

        if (amountOut < minAmountOut) revert InsufficientOutput();
    }

    /**
     * @notice Simple estimate for fallback when quote fails
     * @param amountIn Input amount
     * @param tokenIn Input token (for future price logic)
     * @param tokenOut Output token (for future price logic)
     * @return Estimated output amount
     */
    function _getSimpleEstimate(uint256 amountIn, address tokenIn, address tokenOut) internal pure returns (uint256) {
        // Simple 1:1 estimate with 5% price impact assumption
        return (amountIn * 95) / 100;
    }

    // ============================================================================
    // MODIFIED PROTOCOL IMPLEMENTATIONS  Updated to accept minAmountOut
    // ============================================================================

    /**
     * @notice Execute Uniswap V3 swap (modified to accept minAmountOut)
     */
    function _performUniswapV3Swap(
        address tokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) private returns (uint256 amountOut) {
        UniswapV3Route memory route = abi.decode(params.routeData, (UniswapV3Route));

        // Pool validation for single-hop swaps
        if (!route.isMultiHop) {
            if (!customRouteEnabled[params.tokenIn][params.tokenOut]) {
                if (!whitelistedPools[route.pool]) revert PoolNotWhitelisted();
                if (poolPaused[route.pool]) revert PoolIsPaused();
            }
        }

        // Set approval
        IERC20(tokenIn).safeApprove(address(uniswapRouter), 0);
        IERC20(tokenIn).safeApprove(address(uniswapRouter), params.amountIn);

        if (route.isMultiHop) {
            try
                uniswapRouter.exactInput(
                    IUniswapV3Router.ExactInputParams({
                        path: route.path,
                        recipient: address(this),
                        deadline: block.timestamp + 300,
                        amountIn: params.amountIn,
                        amountOutMinimum: minAmountOut
                    })
                )
            returns (uint256 _amountOut) {
                amountOut = _amountOut;
                if (amountOut == 0) revert InvalidReturnData();
            } catch Error(string memory reason) {
                revert SwapFailed(string(abi.encodePacked("UniswapV3 multi-hop: ", reason)));
            } catch (bytes memory lowLevelData) {
                revert SwapFailed(_parseRevertReason(lowLevelData));
            }
        } else {
            try
                uniswapRouter.exactInputSingle(
                    IUniswapV3Router.ExactInputSingleParams({
                        tokenIn: tokenIn,
                        tokenOut: params.tokenOut == ETH_ADDRESS ? address(WETH) : params.tokenOut,
                        fee: route.fee,
                        recipient: address(this),
                        deadline: block.timestamp + 300,
                        amountIn: params.amountIn,
                        amountOutMinimum: minAmountOut,
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 _amountOut) {
                amountOut = _amountOut;
                if (amountOut == 0) revert InvalidReturnData();
            } catch Error(string memory reason) {
                revert SwapFailed(string(abi.encodePacked("UniswapV3 single-hop: ", reason)));
            } catch (bytes memory lowLevelData) {
                revert SwapFailed(_parseRevertReason(lowLevelData));
            }
        }

        _resetApproval(tokenIn, address(uniswapRouter));
    }

    /**
     * @notice Execute Curve swap (modified to accept minAmountOut)
     */
    function _performCurveSwap(
        address tokenIn,
        SwapParams memory params,
        uint256 minAmountOut
    ) private returns (uint256 amountOut) {
        CurveRoute memory route = abi.decode(params.routeData, (CurveRoute));

        // Pool validation
        if (!customRouteEnabled[params.tokenIn][params.tokenOut]) {
            if (!whitelistedPools[route.pool]) revert PoolNotWhitelisted();
            if (poolPaused[route.pool]) revert PoolIsPaused();
        }

        _validateCurveTokenIndices(route.pool, route.tokenIndexIn, route.tokenIndexOut);

        // Handle ETH/WETH conversion for Curve
        uint256 amountIn = params.amountIn;
        if (tokenIn == address(WETH) && params.tokenIn == ETH_ADDRESS) {
            WETH.withdraw(amountIn);
        } else if (tokenIn != address(WETH)) {
            IERC20(tokenIn).safeApprove(route.pool, 0);
            IERC20(tokenIn).safeApprove(route.pool, amountIn);
        }

        // Get balance before
        uint256 balanceBefore;
        if (params.tokenOut == ETH_ADDRESS) {
            balanceBefore = address(this).balance;
        } else {
            balanceBefore = IERC20(params.tokenOut).balanceOf(address(this));
        }

        // Execute swap
        CurveInterface interfaceType = curvePoolInterfaces[route.pool];
        if (interfaceType == CurveInterface.None) revert UnsupportedInterface();

        if (
            route.useUnderlying &&
            (interfaceType == CurveInterface.ExchangeUnderlying || interfaceType == CurveInterface.Both)
        ) {
            try
                ICurvePool(route.pool).exchange_underlying{
                    gas: EXTERNAL_CALL_GAS_LIMIT,
                    value: params.tokenIn == ETH_ADDRESS ? amountIn : 0
                }(route.tokenIndexIn, route.tokenIndexOut, amountIn, minAmountOut)
            {
                // Success
            } catch Error(string memory reason) {
                _resetApproval(tokenIn, route.pool);
                revert SwapFailed(string(abi.encodePacked("Curve exchange_underlying: ", reason)));
            } catch (bytes memory lowLevelData) {
                _resetApproval(tokenIn, route.pool);
                revert SwapFailed(_parseRevertReason(lowLevelData));
            }
        } else if (interfaceType == CurveInterface.Exchange || interfaceType == CurveInterface.Both) {
            try
                ICurvePool(route.pool).exchange{
                    gas: EXTERNAL_CALL_GAS_LIMIT,
                    value: params.tokenIn == ETH_ADDRESS ? amountIn : 0
                }(route.tokenIndexIn, route.tokenIndexOut, amountIn, minAmountOut)
            {
                // Success
            } catch Error(string memory reason) {
                _resetApproval(tokenIn, route.pool);
                revert SwapFailed(string(abi.encodePacked("Curve exchange: ", reason)));
            } catch (bytes memory lowLevelData) {
                _resetApproval(tokenIn, route.pool);
                revert SwapFailed(_parseRevertReason(lowLevelData));
            }
        } else {
            revert UnsupportedInterface();
        }

        // Calculate amount out
        uint256 balanceAfter;
        if (params.tokenOut == ETH_ADDRESS) {
            balanceAfter = address(this).balance;
        } else {
            balanceAfter = IERC20(params.tokenOut).balanceOf(address(this));
        }

        amountOut = balanceAfter - balanceBefore;
        if (amountOut == 0) revert InvalidReturnData();

        _resetApproval(tokenIn, route.pool);
    }

    /**
     * @notice Handle direct minting operations (FIXED to use route data)
     */
    function _performDirectMint(SwapParams memory params) private returns (uint256 amountOut) {
        address minterContract = address(frxETHMinter);
        if (params.routeData.length > 0) {
            minterContract = abi.decode(params.routeData, (address));
        }

        if (params.tokenIn == ETH_ADDRESS && params.tokenOut == SFRXETH) {
            //  The minter DOES support ETH->sfrxETH directly!
            try IFrxETHMinter(minterContract).submitAndDeposit{value: params.amountIn}(address(this)) returns (
                uint256 shares
            ) {
                amountOut = shares; //  Make sure we're capturing the return value
                require(amountOut > 0, "No sfrxETH received");
            } catch Error(string memory reason) {
                revert SwapFailed(string(abi.encodePacked("DirectMint: ", reason)));
            } catch (bytes memory lowLevelData) {
                revert SwapFailed(_parseRevertReason(lowLevelData));
            }
        } else {
            revert UnsupportedRoute();
        }
    }
    /**
     * @notice Execute multi-hop swap (modified to accept minAmountOut)
     */
    function _performMultiHopSwap(SwapParams memory params, uint256 minAmountOut) private returns (uint256 amountOut) {
        if (params.tokenIn == address(WETH) && params.tokenOut == OSETH) {
            return _performWETHToOsETHSwap(params, minAmountOut);
        }

        // Generic multi-hop logic
        MultiHopRoute memory route = abi.decode(params.routeData, (MultiHopRoute));
        UniswapV3Route memory uniRoute = abi.decode(route.routeData, (UniswapV3Route));
        uniRoute.isMultiHop = true;

        SwapParams memory modifiedParams = params;
        modifiedParams.routeData = abi.encode(uniRoute);

        address actualTokenIn = _handleTokenInput(params);
        return _performUniswapV3Swap(actualTokenIn, modifiedParams, minAmountOut);
    }

    /**
     * @notice Execute multi-step operations (modified to accept minAmountOut)
     */
    function _performMultiStepSwap(SwapParams memory params, uint256 minAmountOut) private returns (uint256 amountOut) {
        MultiStepRoute memory route = abi.decode(params.routeData, (MultiStepRoute));

        if (route.steps.length == 0) revert InvalidParameter("emptySteps");
        if (route.steps.length > MAX_MULTI_STEP_OPERATIONS) revert TooManySteps();

        uint256 currentAmount = params.amountIn;
        address currentToken = params.tokenIn;

        for (uint256 i = 0; i < route.steps.length; i++) {
            StepAction memory step = route.steps[i];

            if (step.actionType == ActionType.UNWRAP) {
                if (currentToken != address(WETH)) revert InvalidStep();
                WETH.withdraw(currentAmount);
                currentToken = ETH_ADDRESS;
            } else if (step.actionType == ActionType.WRAP) {
                if (currentToken != ETH_ADDRESS) revert InvalidStep();
                WETH.deposit{value: currentAmount}();
                currentToken = address(WETH);
            } else if (step.actionType == ActionType.DIRECT_MINT) {
                if (currentToken != ETH_ADDRESS) revert InvalidStep();
                if (step.tokenOut != SFRXETH) revert InvalidStep();

                try frxETHMinter.submitAndDeposit{value: currentAmount}(address(this)) returns (uint256 _amountOut) {
                    currentAmount = _amountOut;
                    if (currentAmount == 0) revert InvalidReturnData();
                } catch Error(string memory reason) {
                    revert SwapFailed(string(abi.encodePacked("MultiStep DirectMint: ", reason)));
                } catch (bytes memory lowLevelData) {
                    revert SwapFailed(_parseRevertReason(lowLevelData));
                }

                currentToken = SFRXETH;
            } else if (step.actionType == ActionType.SWAP) {
                SwapParams memory stepParams = SwapParams({
                    tokenIn: currentToken,
                    tokenOut: step.tokenOut,
                    amountIn: currentAmount,
                    minAmountOut: 0, // Intermediate step
                    protocol: step.protocol,
                    routeData: step.routeData
                });

                uint256 intermediateMin = _calculateIntermediateMinOut(
                    currentToken,
                    step.tokenOut,
                    currentAmount,
                    minAmountOut
                );

                if (step.protocol == Protocol.UniswapV3) {
                    currentAmount = _performUniswapV3Swap(currentToken, stepParams, intermediateMin);
                } else if (step.protocol == Protocol.Curve) {
                    currentAmount = _performCurveSwap(currentToken, stepParams, intermediateMin);
                } else {
                    revert InvalidProtocol();
                }

                currentToken = step.tokenOut;
            }
        }

        if (currentToken != params.tokenOut) revert InvalidParameter("wrongFinalToken");
        if (currentAmount < minAmountOut) revert InsufficientOutput();

        amountOut = currentAmount;

        emit MultiStepExecuted(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            route.steps.length,
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Execute WETH → rETH → osETH swap (modified to accept minAmountOut)
     */
    function _performWETHToOsETHSwap(
        SwapParams memory params,
        uint256 minAmountOut
    ) private returns (uint256 amountOut) {
        address uniswapPoolAddr = 0x553e9C493678d8606d6a5ba284643dB2110Df823;
        address curvePoolAddr = 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;

        if (poolPaused[uniswapPoolAddr]) revert PoolIsPaused();
        if (poolPaused[curvePoolAddr]) revert PoolIsPaused();

        IERC20(address(WETH)).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Step 1: WETH → rETH
        IERC20(address(WETH)).safeApprove(address(uniswapRouter), params.amountIn);

        uint256 minRETHOut = _calculateIntermediateMinOut(address(WETH), RETH, params.amountIn, minAmountOut);

        uint256 rETHReceived;
        try
            uniswapRouter.exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: address(WETH),
                    tokenOut: RETH,
                    fee: 100,
                    recipient: address(this),
                    deadline: block.timestamp + 300,
                    amountIn: params.amountIn,
                    amountOutMinimum: minRETHOut,
                    sqrtPriceLimitX96: 0
                })
            )
        returns (uint256 _rETHReceived) {
            rETHReceived = _rETHReceived;
            if (rETHReceived == 0) revert InvalidReturnData();
        } catch Error(string memory reason) {
            revert SwapFailed(string(abi.encodePacked("WETH to rETH: ", reason)));
        } catch (bytes memory lowLevelData) {
            revert SwapFailed(_parseRevertReason(lowLevelData));
        }

        _resetApproval(address(WETH), address(uniswapRouter));

        // Step 2: rETH → osETH
        IERC20(RETH).safeApprove(curvePoolAddr, rETHReceived);

        try ICurvePool(curvePoolAddr).exchange{gas: EXTERNAL_CALL_GAS_LIMIT}(1, 0, rETHReceived, minAmountOut) returns (
            uint256 _amountOut
        ) {
            amountOut = _amountOut;
            if (amountOut == 0) revert InvalidReturnData();
        } catch Error(string memory reason) {
            revert SwapFailed(string(abi.encodePacked("rETH to osETH: ", reason)));
        } catch (bytes memory lowLevelData) {
            revert SwapFailed(_parseRevertReason(lowLevelData));
        }

        _resetApproval(RETH, curvePoolAddr);
    }

    // ============================================================================
    // TOKEN HANDLING (changed to handle direct mint )
    // ============================================================================

    function _handleTokenInput(SwapParams memory params) private returns (address) {
        if (params.tokenIn == ETH_ADDRESS) {
            if (msg.value < params.amountIn) revert InvalidParameter("insufficientETH");
            WETH.deposit{value: params.amountIn}();
            if (msg.value > params.amountIn) {
                uint256 refundAmount = msg.value - params.amountIn;
                _refundExcessETH(refundAmount);
            }
            return address(WETH);
        } else {
            IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
            return params.tokenIn;
        }
    }

    function _handleTokenOutput(address tokenOut, uint256 amount) private {
        if (tokenOut == ETH_ADDRESS) {
            WETH.withdraw(amount);
            _safeTransferETH(msg.sender, amount);
        } else {
            IERC20(tokenOut).safeTransfer(msg.sender, amount);
        }
    }

    function _safeTransferETH(address to, uint256 amount) private {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            WETH.deposit{value: amount}();
            IERC20(address(WETH)).safeTransfer(to, amount);
        }
    }

    function _refundExcessETH(uint256 amount) private {
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            WETH.deposit{value: amount}();
            IERC20(address(WETH)).safeTransfer(msg.sender, amount);
        }
    }

    function _resetApproval(address token, address spender) private {
        if (token != address(WETH) && token != ETH_ADDRESS) {
            uint256 remaining = IERC20(token).allowance(address(this), spender);
            if (remaining > 0) {
                IERC20(token).safeApprove(spender, 0);
            }
        }
    }

    // ============================================================================
    // VALIDATION FUNCTIONS (unchanged)
    // ============================================================================

    function _validateTokenSupport(address tokenIn, address tokenOut) private view {
        if (!farSupportedTokens[tokenIn] && tokenIn != ETH_ADDRESS) {
            revert TokenNotSupportedByFAR();
        }
        if (!farSupportedTokens[tokenOut] && tokenOut != ETH_ADDRESS) {
            revert TokenNotSupportedByFAR();
        }
    }

    function _validateCurveTokenIndices(address pool, int128 tokenIndexIn, int128 tokenIndexOut) private view {
        uint256 tokenCount = curvePoolTokenCounts[pool];
        if (tokenCount == 0) revert InvalidParameter("poolNotConfigured");

        if (tokenIndexIn < 0 || uint128(tokenIndexIn) >= tokenCount) {
            revert InvalidTokenIndex();
        }
        if (tokenIndexOut < 0 || uint128(tokenIndexOut) >= tokenCount) {
            revert InvalidTokenIndex();
        }
        if (tokenIndexIn == tokenIndexOut) {
            revert InvalidParameter("sameTokenIndex");
        }
    }

    // ============================================================================
    // HELPER FUNCTIONS (keeping essential ones, removing redundant slippage validation)
    // ============================================================================

    function normalizeAmount(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        uint8 decimalsIn = tokenDecimals[tokenIn];
        uint8 decimalsOut = tokenDecimals[tokenOut];

        if (decimalsIn == 0) decimalsIn = 18;
        if (decimalsOut == 0) decimalsOut = 18;

        if (decimalsIn == decimalsOut) {
            return amountIn;
        } else if (decimalsIn > decimalsOut) {
            uint8 decimalDiff = decimalsIn - decimalsOut;
            uint256 divisor = 10 ** decimalDiff;
            return amountIn / divisor;
        } else {
            uint8 decimalDiff = decimalsOut - decimalsIn;
            uint256 multiplier = 10 ** decimalDiff;

            if (amountIn > type(uint256).max / multiplier) {
                revert NormalizationOverflow();
            }

            return amountIn * multiplier;
        }
    }

    function _calculateIntermediateMinOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 finalMinOut
    ) private view returns (uint256) {
        uint256 slippageBps = slippageTolerance[tokenIn][tokenOut];
        if (slippageBps == 0) {
            slippageBps = 200; // Default 2% for intermediate hops
        }

        uint256 normalizedAmount = normalizeAmount(tokenIn, tokenOut, amountIn);
        return (normalizedAmount * (10000 - slippageBps)) / 10000;
    }

    function _getDefaultSlippage(address tokenIn, address tokenOut) private view returns (uint256) {
        AssetType typeIn = assetTypes[tokenIn];
        AssetType typeOut = assetTypes[tokenOut];

        if (typeIn == AssetType.STABLE && typeOut == AssetType.STABLE) return 30; // 0.3%
        if (typeIn == AssetType.ETH_LST || typeOut == AssetType.ETH_LST) return 200; // 2%
        if (typeIn == AssetType.BTC_WRAPPED || typeOut == AssetType.BTC_WRAPPED) return 300; // 3%
        return 500; // 5% for volatile assets
    }

    function _parseRevertReason(bytes memory data) private pure returns (string memory) {
        if (data.length < 68) return "Low-level call failed";

        assembly {
            data := add(data, 0x04)
        }
        return abi.decode(data, (string));
    }

    function _applyProductionSlippageConfig() internal {
        OptimalSlippageConfig[] memory configs = _getOptimalSlippageConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            slippageTolerance[configs[i].tokenIn][configs[i].tokenOut] = configs[i].slippageBps;
        }
    }
    /**
     * @notice Get optimal slippage configurations from testing results
     * @return Array of optimal slippage configurations
     */
    function _getOptimalSlippageConfigs() private view returns (OptimalSlippageConfig[] memory) {
        OptimalSlippageConfig[] memory configs = new OptimalSlippageConfig[](17);

        //  WETH Direct Swaps (Uniswap V3) - Optimized
        configs[0] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, // cbETH
            slippageBps: 350, // Was: 700 → Now: 350 (-50%)
            routeType: "WETH->cbETH Direct Uniswap"
        });

        configs[1] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549, // lsETH
            slippageBps: 150, // Was: 700 → Now: 150 (-78%)
            routeType: "WETH->lsETH Direct Uniswap"
        });

        configs[2] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa, // mETH
            slippageBps: 100, // Was: 800 → Now: 100 (-87%)
            routeType: "WETH->mETH Direct Uniswap"
        });

        configs[3] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3, // OETH
            slippageBps: 100, // Was: 800 → Now: 100 (-87%)
            routeType: "WETH->OETH Direct Uniswap"
        });

        configs[4] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: RETH,
            slippageBps: 750, // Was: 1300 → Now: 750 (-42%)
            routeType: "WETH->rETH Direct Uniswap"
        });

        configs[5] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stETH
            slippageBps: 100, // Was: 700 → Now: 100 (-86%)
            routeType: "WETH->stETH Direct Uniswap"
        });

        configs[6] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0xf951E335afb289353dc249e82926178EaC7DEd78, // swETH
            slippageBps: 250, // Was: 700 → Now: 250 (-64%)
            routeType: "WETH->swETH Direct Uniswap"
        });

        configs[7] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb, // ankrETH
            slippageBps: 1500, // NEW: Allow with 1500 bps (was failing)
            routeType: "WETH->ankrETH Direct Uniswap"
        });

        //  ETH Direct Swaps (Curve) - Super Efficient
        configs[8] = OptimalSlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb, // ankrETH
            slippageBps: 50, // Was: 700 → Now: 50 (-93%)
            routeType: "ETH->ankrETH Direct Curve"
        });

        configs[9] = OptimalSlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b, // ETHx
            slippageBps: 50, // Was: 700 → Now: 50 (-93%)
            routeType: "ETH->ETHx Direct Curve"
        });

        configs[10] = OptimalSlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: FRXETH,
            slippageBps: 50, // Was: 700 → Now: 50 (-93%)
            routeType: "ETH->frxETH Direct Curve"
        });

        configs[11] = OptimalSlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stETH
            slippageBps: 50, // Was: 500 → Now: 50 (-90%)
            routeType: "ETH->stETH Direct Curve"
        });

        configs[12] = OptimalSlippageConfig({
            tokenIn: ETH_ADDRESS,
            tokenOut: SFRXETH,
            slippageBps: 50, // Was: 500 → Now: 50 (-90%)
            routeType: "ETH->sfrxETH Direct Mint"
        });

        //  Complex Routes - Keep Buffers for Safety
        configs[13] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: OSETH,
            slippageBps: 500, // Multi-hop: keep buffer
            routeType: "WETH->osETH Multi-hop"
        });

        configs[14] = OptimalSlippageConfig({
            tokenIn: address(WETH),
            tokenOut: SFRXETH,
            slippageBps: 400, // Multi-step: keep buffer
            routeType: "WETH->sfrxETH Multi-step"
        });

        //  Reverse Routes (for autoSwapAssets bidirectional support)
        configs[15] = OptimalSlippageConfig({
            tokenIn: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, // cbETH
            tokenOut: address(WETH),
            slippageBps: 350,
            routeType: "cbETH->WETH Reverse"
        });

        configs[16] = OptimalSlippageConfig({
            tokenIn: RETH,
            tokenOut: address(WETH),
            slippageBps: 750,
            routeType: "rETH->WETH Reverse"
        });

        return configs;
    }

    // ============================================================================
    // AUTO SWAP ASSETS
    // ============================================================================

    function autoSwapAssets(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public payable onlyAuthorizedCaller nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "Same token");
        require(amountIn > 0, "Zero amount");
        require(initialized, "Not initialized");

        _validateAssetCategory(tokenIn, tokenOut);

        // 1) Direct route A→B
        if (_routeExists(tokenIn, tokenOut)) {
            SwapParams memory params = _makeSwapParams(tokenIn, tokenOut, amountIn, minAmountOut);
            amountOut = _executeInternalSwap(params);
            _handleTokenOutput(tokenOut, amountOut);
            return amountOut;
        }

        // 2) Reverse route B→A
        if (_routeExists(tokenOut, tokenIn)) {
            SwapParams memory params = _makeReverseSwapParams(tokenOut, tokenIn, amountIn, minAmountOut);
            amountOut = _executeInternalSwap(params);
            _handleTokenOutput(tokenOut, amountOut);
            return amountOut;
        }

        // 3) Bridge route
        address bridgeAsset = _getBridgeAsset(tokenIn, tokenOut);
        if (bridgeAsset != address(0)) {
            if (_routeExists(tokenIn, bridgeAsset) && _routeExists(bridgeAsset, tokenOut)) {
                uint256 intermediateMin = _calculateIntermediateMinOut(tokenIn, bridgeAsset, amountIn, minAmountOut);
                uint256 bridgeAmount = _executeInternalSwap(
                    _makeSwapParams(tokenIn, bridgeAsset, amountIn, intermediateMin)
                );
                amountOut = _executeInternalSwap(_makeSwapParams(bridgeAsset, tokenOut, bridgeAmount, minAmountOut));
                _handleTokenOutput(tokenOut, amountOut);
                return amountOut;
            }

            if (_routeExists(bridgeAsset, tokenIn) && _routeExists(tokenOut, bridgeAsset)) {
                uint256 intermediateMin = _calculateIntermediateMinOut(bridgeAsset, tokenIn, amountIn, minAmountOut);
                uint256 bridgeAmount = _executeInternalSwap(
                    _makeReverseSwapParams(bridgeAsset, tokenIn, amountIn, intermediateMin)
                );
                amountOut = _executeInternalSwap(
                    _makeReverseSwapParams(tokenOut, bridgeAsset, bridgeAmount, minAmountOut)
                );
                _handleTokenOutput(tokenOut, amountOut);
                return amountOut;
            }
        }

        revert("No route found");
    }

    function _executeInternalSwap(SwapParams memory params) internal returns (uint256 amountOut) {
        uint256 gasStart = gasleft();

        if (params.amountIn == 0) revert ZeroAmount();
        if (params.tokenIn == params.tokenOut) revert InvalidParameter("sameToken");

        _validateTokenSupport(params.tokenIn, params.tokenOut);

        //  SPECIAL-CASE DIRECTMINT - BYPASS QUOTER LOGIC
        if (params.protocol == Protocol.DirectMint) {
            // Call directly so msg.value flows into submitAndDeposit
            amountOut = _performDirectMint(params);
            if (amountOut < params.minAmountOut) revert InsufficientOutput();

            // Emit event for tracking
            bytes32 routeHash = keccak256(
                abi.encode(params.tokenIn, params.tokenOut, params.protocol, params.routeData, block.timestamp)
            );
            uint256 gasUsed = gasStart > gasleft() ? gasStart - gasleft() : 0;
            emit AssetSwapped(
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                amountOut,
                params.protocol,
                msg.sender,
                gasUsed,
                block.timestamp,
                routeHash
            );
            return amountOut;
        }

        //  REGULAR FLOW FOR ALL OTHER PROTOCOLS
        bytes32 routeHash = keccak256(
            abi.encode(params.tokenIn, params.tokenOut, params.protocol, params.routeData, block.timestamp)
        );

        // Handle token input for internal swaps (ETH→WETH conversion)
        address actualTokenIn = _handleInternalTokenInput(params);

        // Use quoter-first approach for internal swaps too
        QuoteData memory quote = _getQuote(params.tokenIn, params.tokenOut, params.amountIn, params);

        if (quote.valid) {
            try this._executeSwapWithQuote(actualTokenIn, params, quote) returns (uint256 result) {
                amountOut = result;
            } catch {
                // Fallback to config slippage
                uint256 configSlippage = slippageTolerance[params.tokenIn][params.tokenOut];
                if (configSlippage == 0) {
                    configSlippage = _getDefaultSlippage(params.tokenIn, params.tokenOut);
                }
                if (configSlippage == 0) revert NoConfigSlippage();

                amountOut = _executeSwapWithConfig(actualTokenIn, params, configSlippage);
            }
        } else {
            // Direct fallback if quote fails
            uint256 configSlippage = slippageTolerance[params.tokenIn][params.tokenOut];
            if (configSlippage == 0) {
                configSlippage = _getDefaultSlippage(params.tokenIn, params.tokenOut);
            }
            if (configSlippage == 0) revert NoConfigSlippage();

            amountOut = _executeSwapWithConfig(actualTokenIn, params, configSlippage);
        }

        if (amountOut < params.minAmountOut) revert InsufficientOutput();

        uint256 gasUsed = gasStart > gasleft() ? gasStart - gasleft() : 0;

        emit AssetSwapped(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.protocol,
            msg.sender,
            gasUsed,
            block.timestamp,
            routeHash
        );
    }

    function _handleInternalTokenInput(SwapParams memory params) internal returns (address) {
        if (params.tokenIn == ETH_ADDRESS) {
            if (address(this).balance >= params.amountIn) {
                WETH.deposit{value: params.amountIn}();
                return address(WETH);
            } else {
                revert InvalidParameter("insufficientETH");
            }
        } else {
            uint256 currentBalance = IERC20(params.tokenIn).balanceOf(address(this));
            if (currentBalance < params.amountIn) {
                IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
            }
            return params.tokenIn;
        }
    }

    function _validateAssetCategory(address tokenIn, address tokenOut) internal view {
        AssetType typeIn = assetTypes[tokenIn];
        AssetType typeOut = assetTypes[tokenOut];

        if (tokenIn == ETH_ADDRESS) typeIn = AssetType.ETH_LST;
        if (tokenOut == ETH_ADDRESS) typeOut = AssetType.ETH_LST;

        require(typeIn == typeOut, "Cross-category swaps not supported");
        require(typeIn == AssetType.ETH_LST || typeIn == AssetType.BTC_WRAPPED, "Unsupported asset category");
    }

    function _getBridgeAsset(address tokenIn, address tokenOut) internal view returns (address) {
        AssetType assetType = assetTypes[tokenIn];

        if (tokenIn == ETH_ADDRESS || tokenOut == ETH_ADDRESS) {
            assetType = AssetType.ETH_LST;
        }

        if (assetType == AssetType.ETH_LST) {
            return address(WETH);
        } else if (assetType == AssetType.BTC_WRAPPED) {
            return WBTC;
        }

        return address(0);
    }

    function _makeReverseSwapParams(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (SwapParams memory params) {
        RouteConfig storage rc = routes[tokenA][tokenB];
        require(_routeExists(tokenA, tokenB), "Reverse route does not exist");

        bytes memory routeData;
        Protocol protocol = rc.protocol;

        if (protocol == Protocol.UniswapV3) {
            if (rc.path.length > 0) {
                UniswapV3Route memory route = UniswapV3Route({
                    pool: address(0),
                    fee: 0,
                    isMultiHop: true,
                    path: _reverseUniswapPath(rc.path)
                });
                routeData = abi.encode(route);
            } else {
                UniswapV3Route memory route = UniswapV3Route({pool: rc.pool, fee: rc.fee, isMultiHop: false, path: ""});
                routeData = abi.encode(route);
            }
        } else if (protocol == Protocol.Curve) {
            CurveRoute memory route = CurveRoute({
                pool: rc.pool,
                tokenIndexIn: rc.tokenIndexOut,
                tokenIndexOut: rc.tokenIndexIn,
                useUnderlying: rc.useUnderlying
            });
            routeData = abi.encode(route);
        } else if (protocol == Protocol.DirectMint) {
            //  FIX: Use specialContract from route, fallback to frxETHMinter
            address minter = rc.specialContract != address(0) ? rc.specialContract : address(frxETHMinter);
            routeData = abi.encode(minter);
        } else if (protocol == Protocol.MultiHop || protocol == Protocol.MultiStep) {
            routeData = rc.path;
        }

        params = SwapParams({
            tokenIn: tokenB,
            tokenOut: tokenA,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: protocol,
            routeData: routeData
        });
    }

    function _reverseUniswapPath(bytes memory path) internal pure returns (bytes memory) {
        return path; // For now, return original path
    }

    function _routeExists(address tokenA, address tokenB) internal view returns (bool) {
        RouteConfig storage rc = routes[tokenA][tokenB];
        return (rc.pool != address(0) || rc.path.length > 0 || rc.directSwap || rc.specialContract != address(0));
    }

    function _makeSwapParams(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal view returns (SwapParams memory params) {
        RouteConfig storage rc = routes[tokenIn][tokenOut];
        require(_routeExists(tokenIn, tokenOut), "Route does not exist");

        bytes memory routeData;
        Protocol protocol = rc.protocol;

        if (protocol == Protocol.UniswapV3) {
            if (rc.path.length > 0) {
                UniswapV3Route memory route = UniswapV3Route({
                    pool: address(0),
                    fee: 0,
                    isMultiHop: true,
                    path: rc.path
                });
                routeData = abi.encode(route);
            } else {
                UniswapV3Route memory route = UniswapV3Route({pool: rc.pool, fee: rc.fee, isMultiHop: false, path: ""});
                routeData = abi.encode(route);
            }
        } else if (protocol == Protocol.Curve) {
            CurveRoute memory route = CurveRoute({
                pool: rc.pool,
                tokenIndexIn: rc.tokenIndexIn,
                tokenIndexOut: rc.tokenIndexOut,
                useUnderlying: rc.useUnderlying
            });
            routeData = abi.encode(route);
        } else if (protocol == Protocol.DirectMint) {
            //  FIX: Use specialContract from route, fallback to frxETHMinter
            address minter = rc.specialContract != address(0) ? rc.specialContract : address(frxETHMinter);
            routeData = abi.encode(minter);
        } else if (protocol == Protocol.MultiHop || protocol == Protocol.MultiStep) {
            routeData = rc.path;
        }

        params = SwapParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            protocol: protocol,
            routeData: routeData
        });
    }

    function configureRoute(
        address tokenIn,
        address tokenOut,
        Protocol protocol,
        address pool,
        uint24 fee,
        int128 tokenIndexIn,
        int128 tokenIndexOut,
        string calldata password
    ) public {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Unauthorized");

        routes[tokenIn][tokenOut] = RouteConfig({
            protocol: protocol,
            pool: pool,
            fee: fee,
            directSwap: true,
            path: "",
            tokenIndexIn: tokenIndexIn,
            tokenIndexOut: tokenIndexOut,
            useUnderlying: false,
            specialContract: address(0)
        });

        emit RouteConfigured(tokenIn, tokenOut, protocol, pool);
    }
    /**
     * @notice Configure DirectMint route with special contract
     */
    function configureDirectMintRoute(
        address tokenIn,
        address tokenOut,
        address minterContract,
        string calldata password
    ) external {
        require(keccak256(abi.encode(password, address(this))) == ROUTE_PASSWORD_HASH, "Unauthorized");

        routes[tokenIn][tokenOut] = RouteConfig({
            protocol: Protocol.DirectMint,
            pool: address(0),
            fee: 0,
            directSwap: true,
            path: "",
            tokenIndexIn: 0,
            tokenIndexOut: 0,
            useUnderlying: false,
            specialContract: minterContract //  Store minter here
        });

        emit RouteConfigured(tokenIn, tokenOut, Protocol.DirectMint, minterContract);
    }

    // ============================================================================
    // CONFIGURATION FUNCTIONS (keeping all existing configuration functions unchanged)
    // ============================================================================

    function setAuthorizedCaller(
        address caller,
        bool authorized
    ) external onlyOwner configNotLocked(keccak256(abi.encode("authorizedCaller", caller))) {
        if (caller == address(0)) revert InvalidAddress();
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized, msg.sender, block.timestamp);
    }

    function setSlippageTolerance(
        address tokenIn,
        address tokenOut,
        uint256 slippageBps
    ) external onlyOwner configNotLocked(keccak256(abi.encode("slippage", tokenIn, tokenOut))) {
        if (slippageBps > MAX_SLIPPAGE) revert InvalidParameter("slippage");
        slippageTolerance[tokenIn][tokenOut] = slippageBps;
        emit SlippageConfigured(tokenIn, tokenOut, slippageBps, msg.sender, block.timestamp);
    }

    function enableCustomRoute(
        address tokenIn,
        address tokenOut,
        bool enabled,
        string calldata password
    ) external onlyRouteManager {
        bytes32 passwordHash = keccak256(abi.encode(password, address(this)));
        if (passwordHash != ROUTE_PASSWORD_HASH) revert InvalidRoutePassword();

        customRouteEnabled[tokenIn][tokenOut] = enabled;
        emit CustomRouteEnabled(tokenIn, tokenOut, enabled, msg.sender, block.timestamp);
    }

    function whitelistPool(address pool, bool status, CurveInterface curveInterface) external onlyOwner {
        whitelistedPools[pool] = status;
        if (status) {
            curvePoolInterfaces[pool] = curveInterface;
        }
        emit PoolWhitelisted(pool, status, curveInterface, msg.sender, block.timestamp);
    }

    function supportToken(address token, bool status, AssetType assetType, uint8 decimals) external onlyOwner {
        if (status && (decimals == 0 || decimals > 77)) revert InvalidDecimals();

        farSupportedTokens[token] = status;
        if (status) {
            assetTypes[token] = assetType;
            tokenDecimals[token] = decimals;
        }
        emit TokenSupported(token, status, assetType, decimals, block.timestamp);
    }

    function setCurvePoolConfig(address pool, uint256 tokenCount, CurveInterface curveInterface) external onlyOwner {
        if (tokenCount == 0 || tokenCount > MAX_CURVE_TOKENS) revert InvalidParameter("tokenCount");
        curvePoolTokenCounts[pool] = tokenCount;
        curvePoolInterfaces[pool] = curveInterface;
    }

    function setRouteManager(address _routeManager) external onlyOwner {
        if (_routeManager == address(0)) revert InvalidAddress();
        address oldManager = routeManager;
        routeManager = _routeManager;
        emit RouteManagerUpdated(oldManager, _routeManager, block.timestamp);
    }

    function setTokenDecimals(address token, uint8 decimals) external onlyOwner {
        if (decimals == 0 || decimals > 77) revert InvalidDecimals();
        tokenDecimals[token] = decimals;
    }

    //added for new pattern
    /**
     * @notice Set production-optimized slippage configuration based on testing
     * @dev Call this after initialization to set optimal slippages from testing
     */
    function setProductionSlippageConfig() external onlyOwner {
        OptimalSlippageConfig[] memory configs = _getOptimalSlippageConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            OptimalSlippageConfig memory config = configs[i];
            slippageTolerance[config.tokenIn][config.tokenOut] = config.slippageBps;

            emit SlippageConfigured(config.tokenIn, config.tokenOut, config.slippageBps, msg.sender, block.timestamp);
        }
    }

    /**
     * @notice Batch update slippage configurations
     * @param tokenIns Array of input token addresses
     * @param tokenOuts Array of output token addresses
     * @param slippages Array of slippage values in basis points
     */
    function batchSetSlippageTolerances(
        address[] calldata tokenIns,
        address[] calldata tokenOuts,
        uint256[] calldata slippages
    ) external onlyOwner {
        require(tokenIns.length == tokenOuts.length && tokenOuts.length == slippages.length, "Array length mismatch");

        for (uint256 i = 0; i < tokenIns.length; i++) {
            require(slippages[i] <= MAX_SLIPPAGE, "Slippage too high");

            slippageTolerance[tokenIns[i]][tokenOuts[i]] = slippages[i];

            emit SlippageConfigured(tokenIns[i], tokenOuts[i], slippages[i], msg.sender, block.timestamp);
        }
    }

    // ============================================================================
    // EMERGENCY CONTROLS (keeping all existing emergency functions unchanged)
    // ============================================================================

    function emergencyPausePool(address pool, string calldata reason) external onlyOwner {
        poolPaused[pool] = true;
        emit PoolEmergencyPaused(pool, msg.sender, reason, block.timestamp);
    }

    function emergencyPauseProtocol(Protocol protocol, string calldata reason) external onlyOwner {
        protocolPaused[protocol] = true;
        emit ProtocolEmergencyPaused(protocol, msg.sender, reason, block.timestamp);
    }

    function emergencyRevokeApproval(address token, address spender) external onlyOwner {
        IERC20(token).safeApprove(spender, 0);
        emit EmergencyApprovalRevoked(token, spender, msg.sender, block.timestamp);
    }

    function unpausePool(address pool) external onlyOwner {
        poolPaused[pool] = false;
    }

    function unpauseProtocol(Protocol protocol) external onlyOwner {
        protocolPaused[protocol] = false;
    }

    function emergencyWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        if (!paused()) revert InvalidParameter("notPaused");
        if (recipient == address(0)) revert InvalidAddress();

        if (token == ETH_ADDRESS) {
            (bool success, ) = payable(recipient).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================================================
    // VIEW FUNCTIONS (keeping essential view functions)
    // ============================================================================

    function isAuthorizedCaller(address caller) external view returns (bool) {
        return authorizedCallers[caller];
    }

    function getSlippageTolerance(address tokenIn, address tokenOut) external view returns (uint256) {
        uint256 configured = slippageTolerance[tokenIn][tokenOut];
        return configured == 0 ? _getDefaultSlippage(tokenIn, tokenOut) : configured;
    }

    function getFARTokenInfo(address token) external view returns (bool supported, AssetType assetType, uint8 decimals) {
        return (farSupportedTokens[token], assetTypes[token], tokenDecimals[token]);
    }

    function getPoolInfo(
        address pool
    ) external view returns (bool whitelisted, bool paused, uint256 tokenCount, CurveInterface curveInterface) {
        return (whitelistedPools[pool], poolPaused[pool], curvePoolTokenCounts[pool], curvePoolInterfaces[pool]);
    }

    function calculateSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 normalizedOut, uint256 minOut) {
        normalizedOut = normalizeAmount(tokenIn, tokenOut, amountIn);
        uint256 slippageBps = slippageTolerance[tokenIn][tokenOut];
        if (slippageBps == 0) {
            slippageBps = _getDefaultSlippage(tokenIn, tokenOut);
        }
        minOut = (normalizedOut * (10000 - slippageBps)) / 10000;
    }

    function isCustomRouteEnabled(address tokenIn, address tokenOut) external view returns (bool) {
        return customRouteEnabled[tokenIn][tokenOut];
    }

    function getDefaultSlippage(address tokenIn, address tokenOut) external view returns (uint256) {
        return _getDefaultSlippage(tokenIn, tokenOut);
    }
    // ============================================================================
    // DYNAMIC DEX REGISTRY FUNCTIONS 
    // ============================================================================

    /**
     * @notice Register a new DEX for backend integration
     * @param dex DEX contract address
     * @param name DEX name for identification
     * @param password safe password
     */
    function registerDEX(address dex, string calldata name, string calldata password) external onlyOwner {
        bytes32 passwordHash = keccak256(abi.encode(password, address(this)));
        if (passwordHash != ROUTE_PASSWORD_HASH) revert InvalidRoutePassword();
        if (dex == address(0)) revert InvalidAddress();
        if (registeredDEXes[dex]) revert DEXAlreadyRegistered();

        // Verify DEX has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(dex)
        }
        if (codeSize == 0) revert InvalidAddress();

        registeredDEXes[dex] = true;
        dexNames[dex] = name;
        allRegisteredDEXes.push(dex);

        emit DEXRegistered(dex, name, block.timestamp);
    }

    /**
     * @notice Remove DEX from registry
     * @param dex DEX address to remove
     */
    function removeDEX(address dex) external onlyOwner {
        if (!registeredDEXes[dex]) revert DEXNotRegistered();

        string memory name = dexNames[dex];
        registeredDEXes[dex] = false;
        delete dexNames[dex];

        // Remove from array (optional - can skip for gas efficiency)
        for (uint256 i = 0; i < allRegisteredDEXes.length; i++) {
            if (allRegisteredDEXes[i] == dex) {
                allRegisteredDEXes[i] = allRegisteredDEXes[allRegisteredDEXes.length - 1];
                allRegisteredDEXes.pop();
                break;
            }
        }

        emit DEXRemoved(dex, name, block.timestamp);
    }

    /**
     * @notice Execute trusted backend(onlyRouteManager) swap through registered DEX
     * @param dex Target DEX address
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @param callData Encoded function call data for the DEX
     * @param password password for safety
     * @return amountOut Amount of tokens received
     */
    function executeBackendSwap(
        address dex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata callData,
        string calldata password
    ) external payable onlyRouteManager nonReentrant whenNotPaused returns (uint256 amountOut) {
        bytes32 passwordHash = keccak256(abi.encode(password, address(this)));
        if (passwordHash != ROUTE_PASSWORD_HASH) revert InvalidRoutePassword();
        if (!registeredDEXes[dex]) revert DEXNotRegistered();
        if (amountIn == 0) revert ZeroAmount();

        //  VALIDATE FUNCTION SELECTOR SECURITY
        if (callData.length >= 4) {
            bytes4 selector;
            assembly {
                selector := shr(224, calldataload(add(callData.offset, 0)))
            }

            // Check if selector is dangerous
            if (dangerousSelectors[selector]) {
                emit SelectorValidationFailed(selector, dex, block.timestamp);
                revert DangerousSelector();
            }
        }

        // Handle token input (reuse existing logic)
        if (tokenIn == ETH_ADDRESS) {
            if (msg.value != amountIn) revert InvalidParameter("ethAmount");
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            if (tokenIn != address(WETH)) {
                IERC20(tokenIn).safeApprove(dex, amountIn);
            }
        }

        // Get balance before
        uint256 balanceBefore;
        if (tokenOut == ETH_ADDRESS) {
            balanceBefore = address(this).balance;
        } else {
            balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        }

        //  MODIFIED: Use constant for gas limit
        (bool success, bytes memory result) = dex.call{
            value: tokenIn == ETH_ADDRESS ? amountIn : 0,
            gas: MAX_DEX_GAS_LIMIT
        }(callData);

        if (!success) {
            string memory reason = result.length > 0 ? abi.decode(result, (string)) : "Unknown error";
            revert BackendSwapFailed(reason);
        }

        // Calculate amount received
        uint256 balanceAfter;
        if (tokenOut == ETH_ADDRESS) {
            balanceAfter = address(this).balance;
        } else {
            balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        }

        amountOut = balanceAfter - balanceBefore;
        if (amountOut == 0) revert InvalidReturnData();

        // Send tokens to caller (reuse existing logic)
        _handleTokenOutput(tokenOut, amountOut);

        // Reset approvals
        if (tokenIn != ETH_ADDRESS && tokenIn != address(WETH)) {
            IERC20(tokenIn).safeApprove(dex, 0);
        }

        emit BackendSwapExecuted(dex, tokenIn, tokenOut, amountIn, amountOut, block.timestamp);
    }

    /**
     * @notice Get all registered DEXes
     * @return Array of registered DEX addresses
     */
    function getRegisteredDEXes() external view returns (address[] memory) {
        return allRegisteredDEXes;
    }

    /**
     * @notice Check if DEX is registered
     * @param dex DEX address to check
     * @return Whether DEX is registered
     */
    function isDEXRegistered(address dex) external view returns (bool) {
        return registeredDEXes[dex];
    }

    // ============================================================================
    // SECURITY FUNCTIONS 
    // ============================================================================

    /**
     * @notice Add dangerous selector to blacklist
     * @param selector Function selector to blacklist
     * @param reason Reason for blacklisting
     * @param password Security password
     */
    function addDangerousSelector(
        bytes4 selector,
        string calldata reason,
        string calldata password
    ) external onlyOwner {
        bytes32 passwordHash = keccak256(abi.encode(password, address(this)));
        if (passwordHash != ROUTE_PASSWORD_HASH) revert InvalidRoutePassword();

        if (dangerousSelectors[selector]) revert SelectorAlreadyBlacklisted();

        dangerousSelectors[selector] = true;
        allDangerousSelectors.push(selector);

        emit DangerousSelectorAdded(selector, reason, msg.sender, block.timestamp);
    }

    /**
     * @notice Remove selector from blacklist
     * @param selector Function selector to remove
     * @param password Security password
     */
    function removeDangerousSelector(bytes4 selector, string calldata password) external onlyOwner {
        bytes32 passwordHash = keccak256(abi.encode(password, address(this)));
        if (passwordHash != ROUTE_PASSWORD_HASH) revert InvalidRoutePassword();

        if (!dangerousSelectors[selector]) revert SelectorNotBlacklisted();

        dangerousSelectors[selector] = false;

        // Remove from array (optional for gas efficiency)
        for (uint256 i = 0; i < allDangerousSelectors.length; i++) {
            if (allDangerousSelectors[i] == selector) {
                allDangerousSelectors[i] = allDangerousSelectors[allDangerousSelectors.length - 1];
                allDangerousSelectors.pop();
                break;
            }
        }

        emit DangerousSelectorRemoved(selector, msg.sender, block.timestamp);
    }

    /**
     * @notice Validate function selector safety
     * @param selector Function selector to validate
     */
    function validateSelector(bytes4 selector) public view {
        if (dangerousSelectors[selector]) {
            revert DangerousSelector();
        }
    }

    /**
     * @notice Check if selector is dangerous
     * @param selector Function selector to check
     * @return isDangerous Whether selector is blacklisted
     */
    function isSelectorDangerous(bytes4 selector) external view returns (bool isDangerous) {
        return dangerousSelectors[selector];
    }

    /**
     * @notice Get all dangerous selectors
     * @return selectors Array of blacklisted selectors
     */
    function getAllDangerousSelectors() external view returns (bytes4[] memory) {
        return allDangerousSelectors;
    }

    /**
     * @notice Initialize security with standard dangerous selectors
     * @param password Security password
     */
    function initializeSecurity(string calldata password) external onlyOwner {
        bytes32 passwordHash = keccak256(abi.encode(password, address(this)));
        if (passwordHash != ROUTE_PASSWORD_HASH) revert InvalidRoutePassword();

        bytes4[] memory standardDangerous = _getStandardDangerousSelectors();

        for (uint256 i = 0; i < standardDangerous.length; i++) {
            if (!dangerousSelectors[standardDangerous[i]]) {
                dangerousSelectors[standardDangerous[i]] = true;
                allDangerousSelectors.push(standardDangerous[i]);

                emit DangerousSelectorAdded(
                    standardDangerous[i],
                    "Standard security initialization",
                    msg.sender,
                    block.timestamp
                );
            }
        }
    }

    /**
     * @notice Get standard dangerous selectors
     * @return selectors Array of dangerous function selectors
     */
    function _getStandardDangerousSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](15);
        selectors[0] = bytes4(keccak256("selfdestruct(address)"));
        selectors[1] = bytes4(keccak256("delegatecall(address,bytes)"));
        selectors[2] = bytes4(keccak256("suicide(address)"));
        selectors[3] = bytes4(keccak256("create(uint256,bytes)"));
        selectors[4] = bytes4(keccak256("create2(uint256,bytes32,bytes)"));
        selectors[5] = bytes4(keccak256("staticcall(address,bytes)"));
        selectors[6] = bytes4(keccak256("callcode(address,bytes)"));
        selectors[7] = bytes4(keccak256("extcodecopy(address,uint256,uint256,uint256)"));
        selectors[8] = bytes4(keccak256("setOwner(address)"));
        selectors[9] = bytes4(keccak256("transferOwnership(address)"));
        selectors[10] = bytes4(keccak256("changeOwner(address)"));
        selectors[11] = bytes4(keccak256("renounceOwnership()"));
        selectors[12] = bytes4(keccak256("destroy()"));
        selectors[13] = bytes4(keccak256("kill()"));
        selectors[14] = bytes4(keccak256("suicide()"));

        return selectors;
    }
    // ============================================================================
    // DYNAMIC DEX REGISTRY FUNCTIONS 
    // ============================================================================

    receive() external payable {}
}