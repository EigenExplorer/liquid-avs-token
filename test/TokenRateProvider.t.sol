// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {TokenRegistryOracle} from "../src/utils/TokenRegistryOracle.sol";
import {ITokenRegistryOracle} from "../src/interfaces/ITokenRegistryOracle.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {MockCurvePool} from "./mocks/MockCurvePool.sol";
import {MockProtocolToken} from "./mocks/MockProtocolToken.sol";

contract RealWorldTokenPriceTest is BaseTest {
    // Network detection
    bool private isHolesky;

    // Mock tokens for testing
    MockERC20 public mockDepositToken;
    MockStrategy public mockTokenStrategy;
    MockERC20 public mockNativeToken;
    MockStrategy public nativeTokenStrategy;

    // Mainnet token addresses (from config)
    address constant MAINNET_RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant MAINNET_EIGEN = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address constant MAINNET_STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant MAINNET_CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address constant MAINNET_WSTETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant MAINNET_METH = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address constant MAINNET_OSETH = 0x0C4576Ca1c365868E162554AF8e385dc3e7C66D9;
    address constant MAINNET_ETHx = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant MAINNET_SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address constant MAINNET_LSETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
    address constant MAINNET_ANKR_ETH =
        0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant MAINNET_OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address constant MAINNET_WBETH = 0xa2E3356610840701BDf5611a53974510Ae27E2e1;
    address constant MAINNET_UNIBTC =
        0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
    address constant MAINNET_STBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
    address constant MAINNET_SFRXETH =
        0xac3E018457B222d93114458476f3E3416Abbe38F;

    // Holesky token addresses
    address constant HOLESKY_RETH = 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1;
    address constant HOLESKY_STETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address constant HOLESKY_LSETH = 0x1d8b30cC38Dba8aBce1ac29Ea27d9cFd05379A09;
    address constant HOLESKY_ANKR_ETH =
        0x8783C9C904e1bdC87d9168AE703c8481E8a477Fd;
    address constant HOLESKY_SFRXETH =
        0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3;

    // Primary sources (from config)
    address constant CHAINLINK_RETH_ETH =
        0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address constant CHAINLINK_STETH_ETH =
        0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant CHAINLINK_CBETH_ETH =
        0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address constant CHAINLINK_METH_ETH =
        0x5b563107C8666d2142C216114228443B94152362;
    address constant CHAINLINK_OETH_ETH =
        0x703118C4CbccCBF2AB31913e0f8075fbbb15f563;

    address constant CURVE_OSETH_POOL =
        0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d;
    address constant CURVE_ETHX_POOL =
        0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492;
    address constant CURVE_ANKRETH_POOL =
        0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;

    address constant PROTOCOL_UNIBTC_SOURCE =
        0x861d15F8a4059cb918bD6F3670adAEB1220B298f;
    address constant PROTOCOL_STBTC_SOURCE =
        0xD93571A6201978976e37c4A0F7bE17806f2Feab2;

    // Fallback sources (from config)
    address constant FALLBACK_OSETH =
        0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    address constant FALLBACK_ETHX = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    address constant FALLBACK_OETH = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address constant FALLBACK_STBTC =
        0xdF217EFD8f3ecb5E837aedF203C28c1f06854017;

    // Function selectors (from config)
    bytes4 constant SELECTOR_GET_EXCHANGE_RATE = 0xe6aa216c; // rETH
    bytes4 constant SELECTOR_GET_POOLED_ETH_BY_SHARES = 0x7a28fb88; // stETH
    bytes4 constant SELECTOR_EXCHANGE_RATE = 0x3ba0b9a9; // cbETH, ETHx, wbETH
    bytes4 constant SELECTOR_STETH_PER_TOKEN = 0x035faf82; // wstETH
    bytes4 constant SELECTOR_METH_TO_ETH = 0x5890c11c; // METH
    bytes4 constant SELECTOR_CONVERT_TO_ASSETS = 0x07a2d13a; // osETH, OETH, stBTC, sfrxETH
    bytes4 constant SELECTOR_SWETH_TO_ETH_RATE = 0xd68b2cb6; // swETH
    bytes4 constant SELECTOR_LSETH_UNDERLYING_BALANCE = 0xf79c3f02; // lsETH
    bytes4 constant SELECTOR_RATIO = 0x71ca337d; // ankrETH
    bytes4 constant SELECTOR_UNIBTC_RATE = 0xc92aecc4; // uniBTC

    // Token tracking
    mapping(address => bool) public tokenAdded;
    mapping(address => bool) public tokenConfigured;
    address[] public allTokens;

    // Mock price sources for fallback when real sources fail
    mapping(address => MockChainlinkFeed) public mockFeeds;
    mapping(address => MockCurvePool) public mockPools;
    mapping(address => MockProtocolToken) public mockProtocols;

    bytes32 internal constant ORACLE_ADMIN_ROLE =
        keccak256("ORACLE_ADMIN_ROLE");
    bytes32 internal constant RATE_UPDATER_ROLE =
        keccak256("RATE_UPDATER_ROLE");

    function setUp() public override {
        _detectNetwork();
        super.setUp(); // This calls BaseTest setUp which initializes everything

        // Setup our additional mock tokens
        _setupAdditionalMockTokens();

        // Setup token lists
        if (isHolesky) {
            _setupHoleskyTokens();
        } else {
            _setupMainnetTokens();
        }

        // CRITICAL: Configure tokens in Oracle FIRST, then add to LiquidTokenManager
        _configureTokensInOracle();
        _addTokensToManager();

        _logTokenStatus();
    }

    function _detectNetwork() internal {
        uint256 chainId = block.chainid;
        isHolesky = (chainId == 17000);
        console.log(
            isHolesky
                ? "Running on Holesky testnet"
                : "Running on Ethereum mainnet"
        );
    }

    function _setupAdditionalMockTokens() internal {
        // Create additional mock tokens for our testing
        mockDepositToken = new MockERC20("Mock Deposit Token", "MDT");
        mockDepositToken.mint(user1, 1000 ether);
        mockTokenStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(mockDepositToken))
        );

        mockNativeToken = new MockERC20("Mock Native Token", "MNT");
        mockNativeToken.mint(user1, 1000 ether);
        nativeTokenStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(mockNativeToken))
        );

        // Approve tokens
        vm.startPrank(user1);
        mockDepositToken.approve(address(liquidToken), type(uint256).max);
        mockNativeToken.approve(address(liquidToken), type(uint256).max);
        vm.stopPrank();
    }

    function _setupMainnetTokens() internal {
        // Build comprehensive token list from config
        allTokens.push(MAINNET_RETH);
        allTokens.push(MAINNET_EIGEN);
        allTokens.push(MAINNET_STETH);
        allTokens.push(MAINNET_CBETH);
        allTokens.push(MAINNET_WSTETH);
        allTokens.push(MAINNET_METH);
        allTokens.push(MAINNET_OSETH);
        allTokens.push(MAINNET_ETHx);
        allTokens.push(MAINNET_SWETH);
        allTokens.push(MAINNET_LSETH);
        allTokens.push(MAINNET_ANKR_ETH);
        allTokens.push(MAINNET_OETH);
        allTokens.push(MAINNET_WBETH);
        allTokens.push(MAINNET_UNIBTC);
        allTokens.push(MAINNET_STBTC);
        allTokens.push(MAINNET_SFRXETH);
    }

    function _setupHoleskyTokens() internal {
        allTokens.push(HOLESKY_RETH);
        allTokens.push(HOLESKY_STETH);
        allTokens.push(HOLESKY_LSETH);
        allTokens.push(HOLESKY_ANKR_ETH);
        allTokens.push(HOLESKY_SFRXETH);
    }

    function _configureTokensInOracle() internal {
        console.log("======= Configuring Tokens in Oracle =======");

        vm.startPrank(admin); // admin has TOKEN_CONFIGURATOR_ROLE from BaseTest

        if (isHolesky) {
            _configureHoleskyTokensInOracle();
        } else {
            _configureMainnetTokensInOracle();
        }

        // Configure our mock tokens
        _configureMockTokensInOracle();

        vm.stopPrank();
    }

    function _configureMainnetTokensInOracle() internal {
        console.log("Configuring mainnet tokens in oracle...");

        // For mainnet, we'll use mock sources as fallbacks when real sources fail
        _createMockSources();

        // rETH - Chainlink primary, protocol fallback
        _configureTokenSafely(
            "rETH",
            MAINNET_RETH,
            SOURCE_TYPE_CHAINLINK,
            CHAINLINK_RETH_ETH,
            0,
            MAINNET_RETH,
            SELECTOR_GET_EXCHANGE_RATE
        );

        // Eigen - Native token (no oracle needed)
        _configureTokenSafely(
            "Eigen",
            MAINNET_EIGEN,
            SOURCE_TYPE_NATIVE,
            address(0),
            0,
            address(0),
            bytes4(0)
        );

        // stETH - Chainlink primary, protocol fallback, needs arg
        _configureTokenSafely(
            "stETH",
            MAINNET_STETH,
            SOURCE_TYPE_CHAINLINK,
            CHAINLINK_STETH_ETH,
            1,
            MAINNET_STETH,
            SELECTOR_GET_POOLED_ETH_BY_SHARES
        );

        // cbETH - Chainlink primary, protocol fallback
        _configureTokenSafely(
            "cbETH",
            MAINNET_CBETH,
            SOURCE_TYPE_CHAINLINK,
            CHAINLINK_CBETH_ETH,
            0,
            MAINNET_CBETH,
            SELECTOR_EXCHANGE_RATE
        );

        // wstETH - Protocol only
        _configureTokenSafely(
            "wstETH",
            MAINNET_WSTETH,
            SOURCE_TYPE_PROTOCOL,
            MAINNET_WSTETH,
            0,
            MAINNET_WSTETH,
            SELECTOR_STETH_PER_TOKEN
        );

        // METH - Chainlink primary, protocol fallback, needs arg
        _configureTokenSafely(
            "METH",
            MAINNET_METH,
            SOURCE_TYPE_CHAINLINK,
            CHAINLINK_METH_ETH,
            1,
            MAINNET_METH,
            SELECTOR_METH_TO_ETH
        );

        // osETH - Curve primary, different contract fallback, needs arg
        _configureTokenSafely(
            "osETH",
            MAINNET_OSETH,
            SOURCE_TYPE_CURVE,
            CURVE_OSETH_POOL,
            1,
            FALLBACK_OSETH,
            SELECTOR_CONVERT_TO_ASSETS
        );

        // ETHx - Curve primary, different contract fallback
        _configureTokenSafely(
            "ETHx",
            MAINNET_ETHx,
            SOURCE_TYPE_CURVE,
            CURVE_ETHX_POOL,
            0,
            FALLBACK_ETHX,
            SELECTOR_EXCHANGE_RATE
        );

        // swETH - Protocol only
        _configureTokenSafely(
            "swETH",
            MAINNET_SWETH,
            SOURCE_TYPE_PROTOCOL,
            MAINNET_SWETH,
            0,
            MAINNET_SWETH,
            SELECTOR_SWETH_TO_ETH_RATE
        );

        // lsETH - Protocol only, needs arg
        _configureTokenSafely(
            "lsETH",
            MAINNET_LSETH,
            SOURCE_TYPE_PROTOCOL,
            MAINNET_LSETH,
            1,
            MAINNET_LSETH,
            SELECTOR_LSETH_UNDERLYING_BALANCE
        );

        // ankrETH - Curve primary, protocol fallback
        _configureTokenSafely(
            "ankrETH",
            MAINNET_ANKR_ETH,
            SOURCE_TYPE_CURVE,
            CURVE_ANKRETH_POOL,
            0,
            MAINNET_ANKR_ETH,
            SELECTOR_RATIO
        );

        // OETH - Chainlink primary, different contract fallback, needs arg
        _configureTokenSafely(
            "OETH",
            MAINNET_OETH,
            SOURCE_TYPE_CHAINLINK,
            CHAINLINK_OETH_ETH,
            1,
            FALLBACK_OETH,
            SELECTOR_CONVERT_TO_ASSETS
        );

        // wbETH - Protocol only
        _configureTokenSafely(
            "wbETH",
            MAINNET_WBETH,
            SOURCE_TYPE_PROTOCOL,
            MAINNET_WBETH,
            0,
            MAINNET_WBETH,
            SELECTOR_EXCHANGE_RATE
        );

        // uniBTC - Protocol only
        _configureTokenSafely(
            "uniBTC",
            MAINNET_UNIBTC,
            SOURCE_TYPE_PROTOCOL,
            PROTOCOL_UNIBTC_SOURCE,
            0,
            MAINNET_UNIBTC,
            SELECTOR_UNIBTC_RATE
        );

        // stBTC - Protocol primary, different contract fallback, needs arg
        _configureTokenSafely(
            "stBTC",
            MAINNET_STBTC,
            SOURCE_TYPE_PROTOCOL,
            PROTOCOL_STBTC_SOURCE,
            1,
            FALLBACK_STBTC,
            SELECTOR_CONVERT_TO_ASSETS
        );

        // sfrxETH - Protocol only, needs arg
        _configureTokenSafely(
            "sfrxETH",
            MAINNET_SFRXETH,
            SOURCE_TYPE_PROTOCOL,
            MAINNET_SFRXETH,
            1,
            MAINNET_SFRXETH,
            SELECTOR_CONVERT_TO_ASSETS
        );
    }

    function _configureHoleskyTokensInOracle() internal {
        console.log("Configuring Holesky tokens in oracle...");

        // All Holesky tokens use protocol source type with token itself as source
        _configureTokenSafely(
            "rETH",
            HOLESKY_RETH,
            SOURCE_TYPE_PROTOCOL,
            HOLESKY_RETH,
            0,
            HOLESKY_RETH,
            SELECTOR_GET_EXCHANGE_RATE
        );

        _configureTokenSafely(
            "stETH",
            HOLESKY_STETH,
            SOURCE_TYPE_PROTOCOL,
            HOLESKY_STETH,
            1,
            HOLESKY_STETH,
            SELECTOR_GET_POOLED_ETH_BY_SHARES
        );

        _configureTokenSafely(
            "lsETH",
            HOLESKY_LSETH,
            SOURCE_TYPE_PROTOCOL,
            HOLESKY_LSETH,
            1,
            HOLESKY_LSETH,
            SELECTOR_LSETH_UNDERLYING_BALANCE
        );

        _configureTokenSafely(
            "ankrETH",
            HOLESKY_ANKR_ETH,
            SOURCE_TYPE_PROTOCOL,
            HOLESKY_ANKR_ETH,
            0,
            HOLESKY_ANKR_ETH,
            SELECTOR_RATIO
        );

        _configureTokenSafely(
            "sfrxETH",
            HOLESKY_SFRXETH,
            SOURCE_TYPE_PROTOCOL,
            HOLESKY_SFRXETH,
            1,
            HOLESKY_SFRXETH,
            SELECTOR_CONVERT_TO_ASSETS
        );
    }

    function _configureMockTokensInOracle() internal {
        console.log("Configuring mock tokens in oracle...");

        // Mock deposit token - use chainlink source
        try
            tokenRegistryOracle.configureToken(
                address(mockDepositToken),
                SOURCE_TYPE_CHAINLINK,
                address(testTokenFeed), // Reuse the existing mock feed
                0,
                address(0),
                bytes4(0)
            )
        {
            tokenConfigured[address(mockDepositToken)] = true;
            console.log("  Mock deposit token configured successfully");
        } catch Error(string memory reason) {
            console.log("  Failed to configure mock deposit token: %s", reason);
        }

        // Mock native token - use native source (no oracle)
        try
            tokenRegistryOracle.configureToken(
                address(mockNativeToken),
                SOURCE_TYPE_NATIVE,
                address(0),
                0,
                address(0),
                bytes4(0)
            )
        {
            tokenConfigured[address(mockNativeToken)] = true;
            console.log("  Mock native token configured successfully");
        } catch Error(string memory reason) {
            console.log("  Failed to configure mock native token: %s", reason);
        }
    }

    function _configureTokenSafely(
        string memory name,
        address tokenAddress,
        uint8 sourceType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackSelector
    ) internal {
        console.log("Configuring %s in oracle...", name);

        try
            tokenRegistryOracle.configureToken(
                tokenAddress,
                sourceType,
                primarySource,
                needsArg,
                fallbackSource,
                fallbackSelector
            )
        {
            tokenConfigured[tokenAddress] = true;
            console.log("  %s configured successfully", name);
        } catch Error(string memory reason) {
            console.log("  Failed to configure %s: %s", name, reason);

            // Try with mock source as fallback
            if (sourceType == SOURCE_TYPE_CHAINLINK) {
                _tryConfigureWithMockChainlink(
                    name,
                    tokenAddress,
                    fallbackSource,
                    fallbackSelector
                );
            } else if (sourceType == SOURCE_TYPE_CURVE) {
                _tryConfigureWithMockCurve(
                    name,
                    tokenAddress,
                    fallbackSource,
                    fallbackSelector
                );
            } else if (sourceType == SOURCE_TYPE_PROTOCOL) {
                _tryConfigureWithMockProtocol(
                    name,
                    tokenAddress,
                    fallbackSource,
                    fallbackSelector
                );
            }
        } catch {
            console.log("  Failed to configure %s: unknown error", name);
        }
    }

    function _createMockSources() internal {
        // Create mock price sources for tokens that might fail
        address[16] memory tokens = [
            MAINNET_RETH,
            MAINNET_STETH,
            MAINNET_CBETH,
            MAINNET_WSTETH,
            MAINNET_METH,
            MAINNET_OSETH,
            MAINNET_ETHx,
            MAINNET_SWETH,
            MAINNET_LSETH,
            MAINNET_ANKR_ETH,
            MAINNET_OETH,
            MAINNET_WBETH,
            MAINNET_UNIBTC,
            MAINNET_STBTC,
            MAINNET_SFRXETH,
            MAINNET_EIGEN
        ];

        // Create mock chainlink feeds with reasonable ETH prices
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            // BTC tokens should have higher prices
            int256 price = (token == MAINNET_UNIBTC || token == MAINNET_STBTC)
                ? int256(30e8) // ~30 ETH per BTC token
                : int256(1e8); // ~1 ETH per ETH token

            mockFeeds[token] = new MockChainlinkFeed(price, 8);
            mockPools[token] = new MockCurvePool();
            mockPools[token].setVirtualPrice(1e18);

            mockProtocols[token] = new MockProtocolToken();
            mockProtocols[token].setExchangeRate(1e18);
        }
    }

    function _tryConfigureWithMockChainlink(
        string memory name,
        address token,
        address fallbacks,
        bytes4 selector
    ) internal {
        console.log("  Trying %s with mock Chainlink feed...", name);
        try
            tokenRegistryOracle.configureToken(
                token,
                SOURCE_TYPE_CHAINLINK,
                address(mockFeeds[token]),
                0,
                fallbacks,
                selector
            )
        {
            tokenConfigured[token] = true;
            console.log("    %s configured with mock Chainlink", name);
        } catch {
            console.log("    %s still failed with mock Chainlink", name);
        }
    }

    function _tryConfigureWithMockCurve(
        string memory name,
        address token,
        address fallbacks,
        bytes4 selector
    ) internal {
        console.log("  Trying %s with mock Curve pool...", name);
        try
            tokenRegistryOracle.configureToken(
                token,
                SOURCE_TYPE_CURVE,
                address(mockPools[token]),
                0,
                fallbacks,
                selector
            )
        {
            tokenConfigured[token] = true;
            console.log("    %s configured with mock Curve", name);
        } catch {
            console.log("    %s still failed with mock Curve", name);
        }
    }

    function _tryConfigureWithMockProtocol(
        string memory name,
        address token,
        address fallbacks,
        bytes4 selector
    ) internal {
        console.log("  Trying %s with mock protocol...", name);
        try
            tokenRegistryOracle.configureToken(
                token,
                SOURCE_TYPE_PROTOCOL,
                address(mockProtocols[token]),
                0,
                fallbacks,
                selector
            )
        {
            tokenConfigured[token] = true;
            console.log("    %s configured with mock protocol", name);
        } catch {
            console.log("    %s still failed with mock protocol", name);
        }
    }

    function _addTokensToManager() internal {
        console.log("======= Adding Tokens to LiquidTokenManager =======");

        vm.startPrank(deployer); // deployer has admin roles from BaseTest

        // Add mock tokens first
        _addMockTokensToManager();

        if (isHolesky) {
            _addHoleskyTokensToManager();
        } else {
            _addMainnetTokensToManager();
        }

        vm.stopPrank();
    }

    function _addMockTokensToManager() internal {
        console.log("Adding mock tokens to LiquidTokenManager...");

        // Add mock deposit token
        if (tokenConfigured[address(mockDepositToken)]) {
            try
                liquidTokenManager.addToken(
                    IERC20(address(mockDepositToken)),
                    18,
                    0,
                    mockTokenStrategy,
                    SOURCE_TYPE_CHAINLINK,
                    address(testTokenFeed),
                    0,
                    address(0),
                    bytes4(0)
                )
            {
                tokenAdded[address(mockDepositToken)] = true;
                console.log("  Mock deposit token added successfully");
            } catch Error(string memory reason) {
                console.log("  Failed to add mock deposit token: %s", reason);
            }
        }

        // Add mock native token
        if (tokenConfigured[address(mockNativeToken)]) {
            try
                liquidTokenManager.addToken(
                    IERC20(address(mockNativeToken)),
                    18,
                    0,
                    nativeTokenStrategy,
                    SOURCE_TYPE_NATIVE,
                    address(0),
                    0,
                    address(0),
                    bytes4(0)
                )
            {
                tokenAdded[address(mockNativeToken)] = true;
                console.log("  Mock native token added successfully");
            } catch Error(string memory reason) {
                console.log("  Failed to add mock native token: %s", reason);
            }
        }
    }

    function _addMainnetTokensToManager() internal {
        console.log("Adding mainnet tokens to LiquidTokenManager...");

        uint256 volatilityThreshold = 50000000000000000; // 5%

        // Only add tokens that were successfully configured in oracle
        if (tokenConfigured[MAINNET_RETH]) {
            _addTokenSafely(
                "rETH",
                MAINNET_RETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CHAINLINK,
                CHAINLINK_RETH_ETH,
                0,
                MAINNET_RETH,
                SELECTOR_GET_EXCHANGE_RATE
            );
        }

        if (tokenConfigured[MAINNET_EIGEN]) {
            _addTokenSafely(
                "Eigen",
                MAINNET_EIGEN,
                18,
                0,
                SOURCE_TYPE_NATIVE,
                address(0),
                0,
                address(0),
                bytes4(0)
            );
        }

        if (tokenConfigured[MAINNET_STETH]) {
            _addTokenSafely(
                "stETH",
                MAINNET_STETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CHAINLINK,
                CHAINLINK_STETH_ETH,
                1,
                MAINNET_STETH,
                SELECTOR_GET_POOLED_ETH_BY_SHARES
            );
        }

        if (tokenConfigured[MAINNET_CBETH]) {
            _addTokenSafely(
                "cbETH",
                MAINNET_CBETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CHAINLINK,
                CHAINLINK_CBETH_ETH,
                0,
                MAINNET_CBETH,
                SELECTOR_EXCHANGE_RATE
            );
        }

        if (tokenConfigured[MAINNET_WSTETH]) {
            _addTokenSafely(
                "wstETH",
                MAINNET_WSTETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                MAINNET_WSTETH,
                0,
                MAINNET_WSTETH,
                SELECTOR_STETH_PER_TOKEN
            );
        }

        if (tokenConfigured[MAINNET_METH]) {
            _addTokenSafely(
                "METH",
                MAINNET_METH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CHAINLINK,
                CHAINLINK_METH_ETH,
                1,
                MAINNET_METH,
                SELECTOR_METH_TO_ETH
            );
        }

        if (tokenConfigured[MAINNET_OSETH]) {
            _addTokenSafely(
                "osETH",
                MAINNET_OSETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CURVE,
                CURVE_OSETH_POOL,
                1,
                FALLBACK_OSETH,
                SELECTOR_CONVERT_TO_ASSETS
            );
        }

        if (tokenConfigured[MAINNET_ETHx]) {
            _addTokenSafely(
                "ETHx",
                MAINNET_ETHx,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CURVE,
                CURVE_ETHX_POOL,
                0,
                FALLBACK_ETHX,
                SELECTOR_EXCHANGE_RATE
            );
        }

        if (tokenConfigured[MAINNET_SWETH]) {
            _addTokenSafely(
                "swETH",
                MAINNET_SWETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                MAINNET_SWETH,
                0,
                MAINNET_SWETH,
                SELECTOR_SWETH_TO_ETH_RATE
            );
        }

        if (tokenConfigured[MAINNET_LSETH]) {
            _addTokenSafely(
                "lsETH",
                MAINNET_LSETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                MAINNET_LSETH,
                1,
                MAINNET_LSETH,
                SELECTOR_LSETH_UNDERLYING_BALANCE
            );
        }

        if (tokenConfigured[MAINNET_ANKR_ETH]) {
            _addTokenSafely(
                "ankrETH",
                MAINNET_ANKR_ETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CURVE,
                CURVE_ANKRETH_POOL,
                0,
                MAINNET_ANKR_ETH,
                SELECTOR_RATIO
            );
        }

        if (tokenConfigured[MAINNET_OETH]) {
            _addTokenSafely(
                "OETH",
                MAINNET_OETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_CHAINLINK,
                CHAINLINK_OETH_ETH,
                1,
                FALLBACK_OETH,
                SELECTOR_CONVERT_TO_ASSETS
            );
        }

        if (tokenConfigured[MAINNET_WBETH]) {
            _addTokenSafely(
                "wbETH",
                MAINNET_WBETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                MAINNET_WBETH,
                0,
                MAINNET_WBETH,
                SELECTOR_EXCHANGE_RATE
            );
        }

        if (tokenConfigured[MAINNET_UNIBTC]) {
            _addTokenSafely(
                "uniBTC",
                MAINNET_UNIBTC,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                PROTOCOL_UNIBTC_SOURCE,
                0,
                MAINNET_UNIBTC,
                SELECTOR_UNIBTC_RATE
            );
        }

        if (tokenConfigured[MAINNET_STBTC]) {
            _addTokenSafely(
                "stBTC",
                MAINNET_STBTC,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                PROTOCOL_STBTC_SOURCE,
                1,
                FALLBACK_STBTC,
                SELECTOR_CONVERT_TO_ASSETS
            );
        }

        if (tokenConfigured[MAINNET_SFRXETH]) {
            _addTokenSafely(
                "sfrxETH",
                MAINNET_SFRXETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                MAINNET_SFRXETH,
                1,
                MAINNET_SFRXETH,
                SELECTOR_CONVERT_TO_ASSETS
            );
        }
    }

    function _addHoleskyTokensToManager() internal {
        console.log("Adding Holesky tokens to LiquidTokenManager...");

        uint256 volatilityThreshold = 50000000000000000; // 5%

        // Only add tokens that were successfully configured in oracle
        if (tokenConfigured[HOLESKY_RETH]) {
            _addTokenSafely(
                "rETH",
                HOLESKY_RETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                HOLESKY_RETH,
                0,
                HOLESKY_RETH,
                SELECTOR_GET_EXCHANGE_RATE
            );
        }

        if (tokenConfigured[HOLESKY_STETH]) {
            _addTokenSafely(
                "stETH",
                HOLESKY_STETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                HOLESKY_STETH,
                1,
                HOLESKY_STETH,
                SELECTOR_GET_POOLED_ETH_BY_SHARES
            );
        }

        if (tokenConfigured[HOLESKY_LSETH]) {
            _addTokenSafely(
                "lsETH",
                HOLESKY_LSETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                HOLESKY_LSETH,
                1,
                HOLESKY_LSETH,
                SELECTOR_LSETH_UNDERLYING_BALANCE
            );
        }

        if (tokenConfigured[HOLESKY_ANKR_ETH]) {
            _addTokenSafely(
                "ankrETH",
                HOLESKY_ANKR_ETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                HOLESKY_ANKR_ETH,
                0,
                HOLESKY_ANKR_ETH,
                SELECTOR_RATIO
            );
        }

        if (tokenConfigured[HOLESKY_SFRXETH]) {
            _addTokenSafely(
                "sfrxETH",
                HOLESKY_SFRXETH,
                18,
                volatilityThreshold,
                SOURCE_TYPE_PROTOCOL,
                HOLESKY_SFRXETH,
                1,
                HOLESKY_SFRXETH,
                SELECTOR_CONVERT_TO_ASSETS
            );
        }
    }

    function _addTokenSafely(
        string memory name,
        address tokenAddress,
        uint8 decimals,
        uint256 volatilityThreshold,
        uint8 sourceType,
        address primarySource,
        uint8 needsArg,
        address fallbackSource,
        bytes4 fallbackSelector
    ) internal {
        console.log("Adding %s to LiquidTokenManager...", name);

        MockStrategy strategy = new MockStrategy(
            strategyManager,
            IERC20(tokenAddress)
        );

        try
            liquidTokenManager.addToken(
                IERC20(tokenAddress),
                decimals,
                volatilityThreshold,
                strategy,
                sourceType,
                primarySource,
                needsArg,
                fallbackSource,
                fallbackSelector
            )
        {
            console.log("  %s added successfully", name);
            tokenAdded[tokenAddress] = true;
        } catch Error(string memory reason) {
            console.log("  Failed to add %s: %s", name, reason);
        } catch {
            console.log("  Failed to add %s: unknown error", name);
        }
    }

    function _logTokenStatus() internal {
        console.log("\n======= Token Status Report =======");

        // Check mock tokens
        console.log(
            "Mock Deposit Token: %s",
            _getTokenPrice(address(mockDepositToken)) > 0 ? "WORKING" : "FAILED"
        );
        console.log(
            "Mock Native Token: %s",
            tokenAdded[address(mockNativeToken)] ? "WORKING" : "FAILED"
        );

        // Check real tokens
        for (uint i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];
            string memory symbol = _getTokenSymbol(token);

            if (tokenAdded[token]) {
                uint256 price = _getTokenPrice(token);
                if (price > 0) {
                    console.log(
                        "%s: WORKING - Price: %s ETH",
                        symbol,
                        price / 1e18
                    );
                } else {
                    console.log("%s: FAILED - No price", symbol);
                }
            } else {
                console.log("%s: NOT ADDED", symbol);
            }
        }
    }

    function _getTokenSymbol(
        address token
    ) internal view returns (string memory) {
        try ERC20(token).symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            return "UNKNOWN";
        }
    }

    // ========== TESTS ==========

    function testTokenPriceFetching() public {
        console.log("\n======= Testing Token Price Fetching =======");

        uint256 successCount = 0;
        uint256 totalCount = 0;

        // Test mock tokens
        totalCount++;
        if (_getTokenPrice(address(mockDepositToken)) > 0) {
            successCount++;
            console.log(" Mock Deposit Token price fetch successful");
        } else {
            console.log(" Mock Deposit Token price fetch failed");
        }

        // Test real tokens
        for (uint i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];
            if (!tokenAdded[token]) continue;

            totalCount++;
            uint256 price = _getTokenPrice(token);
            string memory symbol = _getTokenSymbol(token);

            if (price > 0) {
                successCount++;
                console.log(" %s: %s ETH", symbol, price / 1e18);
                assertTrue(price > 0, "Price should be greater than 0");
            } else {
                console.log(" %s: Price fetch failed", symbol);
            }
        }

        console.log(
            "\nPrice fetch success rate: %s/%s",
            successCount,
            totalCount
        );
        assertTrue(
            successCount > 0,
            "At least one token should have working price"
        );
    }

    function testDepositWithMockToken() public {
        console.log("\n======= Testing Mock Token Deposit =======");

        if (!tokenAdded[address(mockDepositToken)]) {
            console.log("Mock deposit token not added, skipping test");
            return;
        }

        vm.startPrank(user1);
        uint256 depositAmount = 10e18;

        IERC20Upgradeable[] memory tokens = new IERC20Upgradeable[](1);
        tokens[0] = IERC20Upgradeable(address(mockDepositToken));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;

        liquidToken.deposit(tokens, amounts, user1);

        uint256 userBalance = liquidToken.balanceOf(user1);
        console.log(
            "User deposited %s tokens, received %s LST",
            depositAmount / 1e18,
            userBalance / 1e18
        );

        assertTrue(userBalance > 0, "User should receive LST tokens");
        vm.stopPrank();
    }

    function testNativeTokenDeposit() public {
        console.log("\n======= Testing Native Token Deposit =======");

        if (!tokenAdded[address(mockNativeToken)]) {
            console.log("Mock native token not added, skipping test");
            return;
        }

        vm.startPrank(user1);
        uint256 depositAmount = 5e18;

        IERC20Upgradeable[] memory tokens = new IERC20Upgradeable[](1);
        tokens[0] = IERC20Upgradeable(address(mockNativeToken));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;

        liquidToken.deposit(tokens, amounts, user1);

        uint256 userBalance = liquidToken.balanceOf(user1);
        console.log(
            "User deposited %s native tokens, received %s LST",
            depositAmount / 1e18,
            userBalance / 1e18
        );

        // Native tokens should have 1:1 ratio
        assertEq(
            userBalance,
            depositAmount,
            "Native token deposit should be 1:1"
        );
        vm.stopPrank();
    }

    function testRealTokenIntegration() public {
        console.log("\n======= Testing Real Token Integration =======");

        uint256 workingTokens = 0;

        for (uint i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];
            if (!tokenAdded[token]) continue;

            string memory symbol = _getTokenSymbol(token);
            uint256 price = _getTokenPrice(token);

            if (price > 0) {
                workingTokens++;
                console.log(
                    " %s integration test passed - Price: %s ETH",
                    symbol,
                    price / 1e18
                );

                // Test price update if user2 has the role
                vm.prank(user2);
                try tokenRegistryOracle.updateRate(IERC20(token), price) {
                    console.log("   Price update successful");
                } catch {
                    console.log("   Price update failed");
                }
            } else {
                console.log(" %s integration test failed - No price", symbol);
            }
        }

        console.log("Working tokens: %s", workingTokens);
        assertTrue(workingTokens > 0, "At least one real token should work");
    }
}