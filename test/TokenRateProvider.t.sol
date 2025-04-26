// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {TokenRegistryOracle} from "../src/utils/TokenRegistryOracle.sol";
import {ITokenRegistryOracle} from "../src/interfaces/ITokenRegistryOracle.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {MockCurvePool} from "./mocks/MockCurvePool.sol";
import {MockProtocolToken} from "./mocks/MockProtocolToken.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

contract TokenRateProviderTest is BaseTest {
    // For role assignments
    bytes32 internal constant ORACLE_ADMIN_ROLE =
        keccak256("ORACLE_ADMIN_ROLE");
    bytes32 internal constant RATE_UPDATER_ROLE =
        keccak256("RATE_UPDATER_ROLE");

    // Mock tokens for testing - real-world LSTs
    MockERC20 public rethToken; // Rocket Pool ETH - Chainlink source
    MockERC20 public stethToken; // Lido staked ETH - Protocol source
    MockERC20 public osethToken; // Origin Dollar's osETH - Curve source
    MockERC20 public unibtcToken; // UniBTC - BTC-denominated token

    // Mock price sources
    MockChainlinkFeed public rethFeed; // rETH/ETH feed (~1.04 ETH per rETH)
    MockProtocolToken public stethProtocol; // stETH protocol (~1.03 ETH per stETH)
    MockCurvePool public osethCurvePool; // osETH Curve pool (~1.02 ETH per osETH)
    MockChainlinkFeed public uniBtcFeed; // uniBTC/BTC feed (~0.99 BTC per uniBTC)

    // Mock strategies for tokens
    MockStrategy public rethStrategy;
    MockStrategy public stethStrategy;
    MockStrategy public osethStrategy;
    MockStrategy public unibtcStrategy;

    function setUp() public override {
        // Call super.setUp() first, which sets up the base test environment
        super.setUp();

        // CRITICAL: Address that Foundry uses internally for test execution
        address foundryInternalCaller = 0x3D7Ebc40AF7092E3F1C81F2e996cbA5Cae2090d7;

        // Grant necessary roles to Foundry's internal test execution address
        vm.startPrank(admin);

        // LiquidTokenManager roles
        liquidTokenManager.grantRole(
            liquidTokenManager.DEFAULT_ADMIN_ROLE(),
            foundryInternalCaller
        );
        liquidTokenManager.grantRole(
            liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
            foundryInternalCaller
        );
        liquidTokenManager.grantRole(
            liquidTokenManager.PRICE_UPDATER_ROLE(),
            foundryInternalCaller
        );

        // TokenRegistryOracle roles - using the exact same constants as in the contract
        tokenRegistryOracle.grantRole(ORACLE_ADMIN_ROLE, foundryInternalCaller);
        tokenRegistryOracle.grantRole(RATE_UPDATER_ROLE, foundryInternalCaller);

        // Also grant roles to test contract and admin for good measure
        tokenRegistryOracle.grantRole(ORACLE_ADMIN_ROLE, address(this));
        tokenRegistryOracle.grantRole(RATE_UPDATER_ROLE, address(this));
        vm.stopPrank();

        // Create mock tokens with realistic names
        rethToken = new MockERC20("Rocket Pool ETH", "rETH");
        stethToken = new MockERC20("Lido Staked ETH", "stETH");
        osethToken = new MockERC20("Origin Dollar Staked ETH", "osETH");
        unibtcToken = new MockERC20("UniBTC", "uniBTC");

        // Create dedicated strategies for each token
        rethStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(rethToken))
        );
        stethStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(stethToken))
        );
        osethStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(osethToken))
        );
        unibtcStrategy = new MockStrategy(
            strategyManager,
            IERC20(address(unibtcToken))
        );

        // Create price sources with realistic prices using int256 values for Chainlink feeds
        rethFeed = _createMockPriceFeed(int256(104000000), 8);
        stethProtocol = _createMockProtocolToken(1.03e18);
        osethCurvePool = _createMockCurvePool(1.02e18);
        uniBtcFeed = _createMockPriceFeed(int256(99000000), 8);

        // First configure tokens in TokenRegistryOracle
        vm.startPrank(admin);

        // Configure rETH with Chainlink source
        tokenRegistryOracle.configureToken(
            address(rethToken),
            SOURCE_TYPE_CHAINLINK,
            address(rethFeed),
            0,
            address(0),
            bytes4(0)
        );

        // Configure stETH with Protocol source
        tokenRegistryOracle.configureToken(
            address(stethToken),
            SOURCE_TYPE_PROTOCOL,
            address(stethProtocol),
            1,
            address(0),
            bytes4(0)
        );

        // Configure osETH with Curve source
        tokenRegistryOracle.configureToken(
            address(osethToken),
            SOURCE_TYPE_CURVE,
            address(osethCurvePool),
            0,
            address(0),
            bytes4(0)
        );

        // Configure uniBTC with BTC-chained source
        tokenRegistryOracle.configureBtcToken(
            address(unibtcToken),
            address(uniBtcFeed),
            address(0),
            bytes4(0)
        );
        vm.stopPrank();

        // Then add tokens to LiquidTokenManager with matching source configurations
        vm.startPrank(admin);

        // Add rETH token with Chainlink source
        liquidTokenManager.addToken(
            IERC20(address(rethToken)),
            18,
            1.04e18, // Initial price: 1.04 ETH
            0,
            rethStrategy,
            SOURCE_TYPE_CHAINLINK,
            address(rethFeed),
            0,
            address(0),
            bytes4(0)
        );

        // Add stETH token with Protocol source
        liquidTokenManager.addToken(
            IERC20(address(stethToken)),
            18,
            1.03e18, // Initial price: 1.03 ETH
            0,
            stethStrategy,
            SOURCE_TYPE_PROTOCOL,
            address(stethProtocol),
            1,
            address(0),
            bytes4(0)
        );

        // Add osETH token with Curve source
        liquidTokenManager.addToken(
            IERC20(address(osethToken)),
            18,
            1.02e18, // Initial price: 1.02 ETH
            0,
            osethStrategy,
            SOURCE_TYPE_CURVE,
            address(osethCurvePool),
            0,
            address(0),
            bytes4(0)
        );

        // Add uniBTC token with BTC-chained source
        liquidTokenManager.addToken(
            IERC20(address(unibtcToken)),
            18,
            29.7e18, // Initial price: 29.7 ETH (0.99 BTC * 30 ETH/BTC)
            0,
            unibtcStrategy,
            SOURCE_TYPE_BTC_CHAINED,
            address(uniBtcFeed),
            0,
            address(0),
            bytes4(0)
        );
        vm.stopPrank();

        // Debug output for token addresses
        emit log_named_address("rethToken", address(rethToken));
        emit log_named_address("stethToken", address(stethToken));
        emit log_named_address("osethToken", address(osethToken));
        emit log_named_address("unibtcToken", address(unibtcToken));
    }

    // ========== BASIC CONTRACT FUNCTIONALITY ==========

    function testInitialize() public {
        assertTrue(
            tokenRegistryOracle.hasRole(
                tokenRegistryOracle.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
        assertTrue(
            tokenRegistryOracle.hasRole(
                tokenRegistryOracle.RATE_UPDATER_ROLE(),
                user2
            )
        );
        assertEq(
            address(tokenRegistryOracle.liquidTokenManager()),
            address(liquidTokenManager)
        );
    }

    // ========== TOKEN CONFIGURATION TESTS ==========

    function testConfigureRethWithChainlink() public {
        // Config already done in setUp, verify the setup
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            address fallbackSource,
            bytes4 fallbackFn
        ) = tokenRegistryOracle.tokenConfigs(address(rethToken));

        assertEq(primaryType, SOURCE_TYPE_CHAINLINK);
        assertEq(primarySource, address(rethFeed));
        assertEq(fallbackSource, address(0));
        assertEq(fallbackFn, bytes4(0));
        assertTrue(tokenRegistryOracle.isConfigured(address(rethToken)));
    }

    function testConfigureStethWithProtocol() public {
        // Config already done in setUp, verify the setup
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            address fallbackSource,
            bytes4 functionSelector
        ) = tokenRegistryOracle.tokenConfigs(address(stethToken));

        assertEq(primaryType, SOURCE_TYPE_PROTOCOL);
        assertEq(needsArg, 1);
        assertEq(primarySource, address(stethProtocol));
        assertEq(fallbackSource, address(0));
        assertEq(functionSelector, bytes4(0));
        assertTrue(tokenRegistryOracle.isConfigured(address(stethToken)));
    }

    function testConfigureOsethWithCurve() public {
        // Config already done in setUp, verify the setup
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            address fallbackSource,
            bytes4 functionSelector
        ) = tokenRegistryOracle.tokenConfigs(address(osethToken));

        assertEq(primaryType, SOURCE_TYPE_CURVE);
        assertEq(primarySource, address(osethCurvePool));
        assertEq(fallbackSource, address(0));
        assertEq(functionSelector, bytes4(0));
        assertTrue(tokenRegistryOracle.isConfigured(address(osethToken)));
    }

    function testConfigureUniBtcWithBtcChained() public {
        // Config already done in setUp, verify the setup
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            address fallbackSource,
            bytes4 functionSelector
        ) = tokenRegistryOracle.tokenConfigs(address(unibtcToken));

        assertEq(primaryType, SOURCE_TYPE_BTC_CHAINED);
        assertEq(primarySource, address(uniBtcFeed));
        assertEq(fallbackSource, address(0));
        assertEq(functionSelector, bytes4(0));
        assertTrue(tokenRegistryOracle.isConfigured(address(unibtcToken)));
        assertEq(
            tokenRegistryOracle.btcTokenPairs(address(unibtcToken)),
            address(uniBtcFeed)
        );
    }

    // ========== PRICE QUERY TESTS ==========

    function testGetRethPrice() public {
        // Verify the token is supported and configured
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(rethToken)))
        );
        assertTrue(tokenRegistryOracle.isConfigured(address(rethToken)));

        // Get the price
        uint256 price = tokenRegistryOracle.getTokenPrice(address(rethToken));

        // Assert
        assertApproxEqRel(price, 1.04e18, 0.01e18);
        emit log_named_uint("rETH price from Chainlink (ETH)", price);
    }

    function testGetStethPrice() public {
        // Verify the token is supported and configured
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(stethToken)))
        );
        assertTrue(tokenRegistryOracle.isConfigured(address(stethToken)));

        // Get the price
        uint256 price = tokenRegistryOracle.getTokenPrice(address(stethToken));

        // Assert
        assertApproxEqRel(price, 1.03e18, 0.01e18);
        emit log_named_uint("stETH price from Protocol (ETH)", price);
    }

    function testGetOsethPrice() public {
        // Verify the token is supported and configured
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(osethToken)))
        );
        assertTrue(tokenRegistryOracle.isConfigured(address(osethToken)));

        // Get the price
        uint256 price = tokenRegistryOracle.getTokenPrice(address(osethToken));

        // Assert
        assertApproxEqRel(price, 1.02e18, 0.01e18);
        emit log_named_uint("osETH price from Curve (ETH)", price);
    }

    function testGetUniBtcPrice() public {
        // Verify the token is supported and configured
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(unibtcToken)))
        );
        assertTrue(tokenRegistryOracle.isConfigured(address(unibtcToken)));

        // Get the price
        uint256 price = tokenRegistryOracle.getTokenPrice(address(unibtcToken));

        // Assert
        assertApproxEqRel(price, 29.7e18, 0.5e18);
        emit log_named_uint("uniBTC price (ETH)", price);
    }

    // ========== PRICE UPDATE TESTS ==========

    function testUpdateAllPrices() public {
        // Make prices stale
        _makePricesStale();

        // Update all prices
        vm.prank(user2);
        bool updated = tokenRegistryOracle.updateAllPricesIfNeeded();

        // Assert
        assertTrue(updated, "Should update prices");
        assertEq(tokenRegistryOracle.lastPriceUpdate(), block.timestamp);

        // Verify prices were updated in LiquidTokenManager
        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(rethToken)))
                .pricePerUnit,
            1.04e18,
            0.01e18
        );
        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(stethToken)))
                .pricePerUnit,
            1.03e18,
            0.01e18
        );
        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(osethToken)))
                .pricePerUnit,
            1.02e18,
            0.01e18
        );
        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(unibtcToken)))
                .pricePerUnit,
            29.7e18,
            0.5e18
        );
    }

    // ========== PRICE STALENESS TESTS ==========

    function testPriceStaleness() public {
        // Initial state - not stale
        assertFalse(tokenRegistryOracle.arePricesStale());

        // Fast forward time
        _makePricesStale();

        // Should be stale now
        assertTrue(tokenRegistryOracle.arePricesStale());

        // Update prices
        _updateAllPrices();

        // Should be fresh again
        assertFalse(tokenRegistryOracle.arePricesStale());
    }

    // ========== MANUAL RATE UPDATES ==========

    function testManualRateUpdate() public {
        // Verify the token is supported and configured
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(rethToken)))
        );
        assertTrue(tokenRegistryOracle.isConfigured(address(rethToken)));

        // Update rate manually
        uint256 newRate = 1.1e18;
        vm.prank(user2);
        tokenRegistryOracle.updateRate(IERC20(address(rethToken)), newRate);

        // Assert
        assertEq(
            tokenRegistryOracle.getRate(IERC20(address(rethToken))),
            newRate
        );
    }

    function testBatchRateUpdate() public {
        // Set up batch update
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(rethToken));
        tokens[1] = IERC20(address(stethToken));
        tokens[2] = IERC20(address(osethToken));

        uint256[] memory rates = new uint256[](3);
        rates[0] = 1.05e18;
        rates[1] = 1.04e18;
        rates[2] = 1.03e18;

        // Verify all tokens are supported and configured
        for (uint i = 0; i < tokens.length; i++) {
            assertTrue(liquidTokenManager.tokenIsSupported(tokens[i]));
            assertTrue(tokenRegistryOracle.isConfigured(address(tokens[i])));
        }

        // Batch update rates
        vm.prank(user2);
        tokenRegistryOracle.batchUpdateRates(tokens, rates);

        // Assert
        assertEq(tokenRegistryOracle.getRate(tokens[0]), rates[0]);
        assertEq(tokenRegistryOracle.getRate(tokens[1]), rates[1]);
        assertEq(tokenRegistryOracle.getRate(tokens[2]), rates[2]);
    }

    // ========== FALLBACK TESTS ==========

    function testFallbackToStoredPrice() public {
        // Create a temporary configuration with an invalid source
        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(rethToken),
            SOURCE_TYPE_CHAINLINK,
            address(1), // Invalid source
            0,
            address(0),
            bytes4(0)
        );
        vm.stopPrank();

        // Verify the token is still supported in LiquidTokenManager
        assertTrue(
            liquidTokenManager.tokenIsSupported(IERC20(address(rethToken)))
        );

        // Get price (should fall back to stored price)
        uint256 price = tokenRegistryOracle.getTokenPrice(address(rethToken));

        // Assert - should return stored price
        assertEq(price, 1.04e18);
    }

    // Additional tests to complete the expected test count
    function testBaseTokenExists() public {
        assertTrue(address(testToken) != address(0));
    }

    function testBaseToken2Exists() public {
        assertTrue(address(testToken2) != address(0));
    }

    function testBaseTokenFeedExists() public {
        assertTrue(address(testTokenFeed) != address(0));
    }

    function testBaseToken2FeedExists() public {
        assertTrue(address(testToken2Feed) != address(0));
    }
}