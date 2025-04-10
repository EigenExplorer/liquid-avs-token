// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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

contract TokenRateProviderTest is BaseTest {
    // Mock tokens for testing - real-world LSTs
    MockERC20 public rethToken; // Rocket Pool ETH - Chainlink source
    MockERC20 public stethToken; // Lido stETH - Protocol source
    MockERC20 public osethToken; // Origin Dollar's osETH - Curve source
    MockERC20 public unibtcToken; // UniBTC - BTC-denominated token

    // Mock price sources
    MockChainlinkFeed public rethFeed; // rETH/ETH feed (~1.04 ETH per rETH)
    MockProtocolToken public stethProtocol; // stETH protocol (~1.03 ETH per stETH)
    MockCurvePool public osethCurvePool; // osETH Curve pool (~1.02 ETH per osETH)
    MockChainlinkFeed public uniBtcFeed; // uniBTC/BTC feed (~0.99 BTC per uniBTC)
    MockChainlinkFeed public btcEthFeed; // BTC/ETH feed (~30 ETH per BTC)

    function setUp() public override {
        super.setUp();

        // Disable volatility check for test tokens
        liquidTokenManager.setVolatilityThreshold(testToken, 0);

        // Grant ORACLE_ADMIN_ROLE to admin for configuration
        vm.prank(deployer);
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.ORACLE_ADMIN_ROLE(),
            admin
        );

        // Create mock tokens with realistic names
        rethToken = new MockERC20("Rocket Pool ETH", "rETH");
        stethToken = new MockERC20("Lido Staked ETH", "stETH");
        osethToken = new MockERC20("Origin Dollar Staked ETH", "osETH");
        unibtcToken = new MockERC20("UniBTC", "uniBTC");

        // Create price sources with realistic prices
        // 1. rETH Chainlink feed: 1.04 ETH per rETH (with 8 decimals)
        rethFeed = new MockChainlinkFeed(104000000, 8);

        // 2. stETH protocol: 1.03 ETH per stETH
        stethProtocol = new MockProtocolToken();
        stethProtocol.setExchangeRate(1.03e18);

        // 3. osETH Curve pool: 1.02 ETH per osETH
        osethCurvePool = new MockCurvePool();
        osethCurvePool.setVirtualPrice(1.02e18);

        // 4. uniBTC BTC feed: 0.99 BTC per uniBTC (with 8 decimals)
        uniBtcFeed = new MockChainlinkFeed(99000000, 8);

        // 5. BTC/ETH feed: 30 ETH per BTC (with 8 decimals)
        btcEthFeed = new MockChainlinkFeed(3000000000, 8);

        // Add tokens to LiquidTokenManager with initial prices
        vm.startPrank(admin);
        liquidTokenManager.addToken(
            IERC20(address(rethToken)),
            18,
            1.04e18, // Initial price: 1.04 ETH
            0,
            mockStrategy
        );

        liquidTokenManager.addToken(
            IERC20(address(stethToken)),
            18,
            1.03e18, // Initial price: 1.03 ETH
            0,
            mockStrategy
        );

        liquidTokenManager.addToken(
            IERC20(address(osethToken)),
            18,
            1.02e18, // Initial price: 1.02 ETH
            0,
            mockStrategy
        );

        liquidTokenManager.addToken(
            IERC20(address(unibtcToken)),
            18,
            29.7e18, // Initial price: 29.7 ETH (0.99 BTC * 30 ETH/BTC)
            0,
            mockStrategy
        );

        // Set up BTC/ETH feed in TokenRegistryOracle
        // Use storage hack to set BTCETHFEED
        vm.store(
            address(tokenRegistryOracle),
            bytes32(uint256(3)), // Slot for BTCETHFEED (may need to adjust based on contract)
            bytes32(uint256(uint160(address(btcEthFeed))))
        );
        vm.stopPrank();
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
        // Arrange - Prepare selectors
        bytes4 exchangeRateSelector = bytes4(keccak256("exchangeRate()"));

        // Act - Configure rETH with Chainlink as primary source
        vm.prank(admin);
        tokenRegistryOracle.configureToken(
            address(rethToken),
            1, // Chainlink type
            address(rethFeed),
            0, // No arg needed
            exchangeRateSelector // Fallback function
        );

        // Assert
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            bytes4 fallbackFn
        ) = tokenRegistryOracle.tokenConfigs(address(rethToken));

        assertEq(primaryType, 1, "Should be configured as Chainlink source");
        assertEq(primarySource, address(rethFeed), "Should use rETH feed");
        assertEq(
            fallbackFn,
            exchangeRateSelector,
            "Should use exchange rate as fallback"
        );
        assertTrue(
            tokenRegistryOracle.isConfigured(address(rethToken)),
            "Token should be marked as configured"
        );
    }

    function testConfigureStethWithProtocol() public {
        // Arrange - Prepare selectors
        bytes4 getPooledEthBySharesSelector = bytes4(
            keccak256("getPooledEthByShares(uint256)")
        );

        // Act - Configure stETH with Protocol as primary source
        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(stethToken),
            4, // Protocol type
            address(stethProtocol),
            1, // Needs argument
            getPooledEthBySharesSelector // Primary function
        );
        vm.stopPrank();

        // Assert
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            bytes4 fallbackFn
        ) = tokenRegistryOracle.tokenConfigs(address(stethToken));

        assertEq(primaryType, 4, "Should be configured as Protocol source");
        assertEq(needsArg, 1, "Should be configured to need argument");
        assertEq(
            primarySource,
            address(stethProtocol),
            "Should use stETH protocol contract"
        );
        assertEq(
            fallbackFn,
            getPooledEthBySharesSelector,
            "Should use correct selector"
        );
        assertTrue(
            tokenRegistryOracle.isConfigured(address(stethToken)),
            "Token should be marked as configured"
        );
    }

    function testConfigureOsethWithCurve() public {
        // Arrange - Prepare selectors
        bytes4 convertToAssetsSelector = bytes4(
            keccak256("convertToAssets(uint256)")
        );

        // Act - Configure osETH with Curve as primary source
        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(osethToken),
            2, // Curve type
            address(osethCurvePool),
            0, // No arg needed for Curve
            convertToAssetsSelector // Fallback function
        );
        vm.stopPrank();

        // Assert
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            bytes4 fallbackFn
        ) = tokenRegistryOracle.tokenConfigs(address(osethToken));

        assertEq(primaryType, 2, "Should be configured as Curve source");
        assertEq(
            primarySource,
            address(osethCurvePool),
            "Should use osETH Curve pool"
        );
        assertEq(
            fallbackFn,
            convertToAssetsSelector,
            "Should use correct fallback selector"
        );
        assertTrue(
            tokenRegistryOracle.isConfigured(address(osethToken)),
            "Token should be marked as configured"
        );
    }

    function testConfigureUniBtcWithBtcChained() public {
        // Arrange - Prepare selectors
        bytes4 getRateSelector = bytes4(keccak256("getRate()"));

        // Act - Configure uniBTC with BTC-chained as primary source
        vm.startPrank(admin);
        tokenRegistryOracle.configureBtcToken(
            address(unibtcToken),
            address(uniBtcFeed),
            getRateSelector
        );
        vm.stopPrank();

        // Assert
        (
            uint8 primaryType,
            uint8 needsArg,
            ,
            address primarySource,
            bytes4 fallbackFn
        ) = tokenRegistryOracle.tokenConfigs(address(unibtcToken));

        uint8 expectedType = uint8(
            tokenRegistryOracle.priceConstants().SOURCE_TYPE_BTC_CHAINED()
        );

        assertEq(
            primaryType,
            expectedType,
            "Should be configured as BTC-chained source"
        );
        assertEq(
            primarySource,
            address(uniBtcFeed),
            "Should use uniBTC/BTC feed"
        );
        assertEq(fallbackFn, getRateSelector, "Should use getRate as fallback");
        assertTrue(
            tokenRegistryOracle.isConfigured(address(unibtcToken)),
            "Token should be marked as configured"
        );
        assertEq(
            tokenRegistryOracle.btcTokenPairs(address(unibtcToken)),
            address(uniBtcFeed),
            "Should have BTC pair set"
        );
    }

    // ========== PRICE QUERY TESTS ==========

    function testGetRethPrice() public {
        // Arrange
        bytes4 exchangeRateSelector = bytes4(keccak256("exchangeRate()"));

        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(rethToken),
            1, // Chainlink
            address(rethFeed),
            0, // No arg
            exchangeRateSelector
        );
        vm.stopPrank();

        // Act
        uint256 price = tokenRegistryOracle.getTokenPrice(address(rethToken));

        // Assert - Price should be ~1.04 ETH
        assertApproxEqRel(
            price,
            1.04e18,
            0.01e18,
            "Price should be close to 1.04 ETH"
        );
        emit log_named_uint("rETH price from Chainlink (ETH)", price);
    }

    function testGetStethPrice() public {
        // Arrange - Configure stETH with Protocol as primary source
        bytes4 getPooledEthBySharesSelector = bytes4(
            keccak256("getPooledEthByShares(uint256)")
        );

        // Set up mock protocol contract in PriceConstants
        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(stethToken),
            4, // Protocol type
            address(stethProtocol),
            1, // Needs argument
            getPooledEthBySharesSelector
        );

        // Register stETH protocol address in the oracle for fallback
        vm.store(
            address(tokenRegistryOracle.priceConstants()),
            bytes32(uint256(10)), // Assuming STETH_CONTRACT is at slot 10
            bytes32(uint256(uint160(address(stethProtocol))))
        );
        vm.stopPrank();

        // Act
        uint256 price = tokenRegistryOracle.getTokenPrice(address(stethToken));

        // Assert - Price should be ~1.03 ETH
        assertApproxEqRel(
            price,
            1.03e18,
            0.01e18,
            "Price should be close to 1.03 ETH"
        );
        emit log_named_uint("stETH price from Protocol (ETH)", price);
    }

    function testGetOsethPrice() public {
        // Arrange - Configure osETH with Curve as primary source
        bytes4 convertToAssetsSelector = bytes4(
            keccak256("convertToAssets(uint256)")
        );

        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(osethToken),
            2, // Curve type
            address(osethCurvePool),
            0, // No arg needed for Curve
            convertToAssetsSelector
        );
        vm.stopPrank();

        // Act
        uint256 price = tokenRegistryOracle.getTokenPrice(address(osethToken));

        // Assert - Price should be ~1.02 ETH
        assertApproxEqRel(
            price,
            1.02e18,
            0.01e18,
            "Price should be close to 1.02 ETH"
        );
        emit log_named_uint("osETH price from Curve (ETH)", price);
    }

    function testGetUniBtcPrice() public {
        // Arrange - Configure uniBTC with BTC-chained as primary source
        bytes4 getRateSelector = bytes4(keccak256("getRate()"));

        vm.startPrank(admin);
        tokenRegistryOracle.configureBtcToken(
            address(unibtcToken),
            address(uniBtcFeed),
            getRateSelector
        );
        vm.stopPrank();

        // Act
        uint256 price = tokenRegistryOracle.getTokenPrice(address(unibtcToken));

        // Assert - Price should be ~29.7 ETH (0.99 BTC * 30 ETH/BTC)
        assertApproxEqRel(
            price,
            29.7e18,
            0.5e18,
            "Price should be close to 29.7 ETH"
        );
        emit log_named_uint("uniBTC price (ETH)", price);
    }

    // ========== PRICE UPDATE TESTS ==========

    function testUpdateAllPrices() public {
        // Arrange - Configure all tokens
        vm.startPrank(admin);

        // Configure rETH with Chainlink
        tokenRegistryOracle.configureToken(
            address(rethToken),
            1, // Chainlink
            address(rethFeed),
            0,
            bytes4(keccak256("exchangeRate()"))
        );

        // Configure stETH with Protocol
        tokenRegistryOracle.configureToken(
            address(stethToken),
            4, // Protocol
            address(stethProtocol),
            1,
            bytes4(keccak256("getPooledEthByShares(uint256)"))
        );

        // Configure osETH with Curve
        tokenRegistryOracle.configureToken(
            address(osethToken),
            2, // Curve
            address(osethCurvePool),
            0,
            bytes4(keccak256("convertToAssets(uint256)"))
        );

        // Configure uniBTC with BTC-chained
        tokenRegistryOracle.configureBtcToken(
            address(unibtcToken),
            address(uniBtcFeed),
            bytes4(keccak256("getRate()"))
        );

        // Make prices stale
        vm.warp(block.timestamp + 13 hours);
        vm.stopPrank();

        // Act - Update all prices
        vm.prank(user2); // user2 has RATE_UPDATER_ROLE
        bool updated = tokenRegistryOracle.updateAllPricesIfNeeded();

        // Assert
        assertTrue(updated, "Should update prices");
        assertEq(
            tokenRegistryOracle.lastPriceUpdate(),
            block.timestamp,
            "Should update timestamp"
        );

        // Verify prices were updated in LiquidTokenManager
        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(rethToken)))
                .pricePerUnit,
            1.04e18,
            0.01e18,
            "rETH price should be updated"
        );

        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(stethToken)))
                .pricePerUnit,
            1.03e18,
            0.01e18,
            "stETH price should be updated"
        );

        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(osethToken)))
                .pricePerUnit,
            1.02e18,
            0.01e18,
            "osETH price should be updated"
        );

        assertApproxEqRel(
            liquidTokenManager
                .getTokenInfo(IERC20(address(unibtcToken)))
                .pricePerUnit,
            29.7e18,
            0.5e18,
            "uniBTC price should be updated"
        );
    }

    // ========== PRICE STALENESS TESTS ==========

    function testPriceStaleness() public {
        // Arrange - Configure a token
        vm.prank(admin);
        tokenRegistryOracle.configureToken(
            address(rethToken),
            1, // Chainlink
            address(rethFeed),
            0,
            bytes4(0)
        );

        // Initial state - not stale
        assertFalse(
            tokenRegistryOracle.arePricesStale(),
            "Prices should not be stale initially"
        );

        // Act - Fast forward time
        vm.warp(block.timestamp + 13 hours);

        // Assert - Should be stale now
        assertTrue(
            tokenRegistryOracle.arePricesStale(),
            "Prices should be stale after time passes"
        );

        // Update prices
        vm.prank(user2);
        tokenRegistryOracle.updateAllPricesIfNeeded();

        // Should be fresh again
        assertFalse(
            tokenRegistryOracle.arePricesStale(),
            "Prices should be fresh after update"
        );
    }

    // ========== MANUAL RATE UPDATES ==========

    function testManualRateUpdate() public {
        // Act - Update rate manually
        uint256 newRate = 1.1e18;

        vm.prank(user2);
        tokenRegistryOracle.updateRate(IERC20(address(rethToken)), newRate);

        // Assert
        assertEq(
            tokenRegistryOracle.getRate(IERC20(address(rethToken))),
            newRate,
            "Manual rate update should work"
        );
    }

    function testBatchRateUpdate() public {
        // Arrange
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(rethToken));
        tokens[1] = IERC20(address(stethToken));
        tokens[2] = IERC20(address(osethToken));

        uint256[] memory rates = new uint256[](3);
        rates[0] = 1.05e18;
        rates[1] = 1.04e18;
        rates[2] = 1.03e18;

        // Act
        vm.prank(user2);
        tokenRegistryOracle.batchUpdateRates(tokens, rates);

        // Assert
        assertEq(
            tokenRegistryOracle.getRate(tokens[0]),
            rates[0],
            "rETH rate should be updated"
        );
        assertEq(
            tokenRegistryOracle.getRate(tokens[1]),
            rates[1],
            "stETH rate should be updated"
        );
        assertEq(
            tokenRegistryOracle.getRate(tokens[2]),
            rates[2],
            "osETH rate should be updated"
        );
    }

    // ========== FALLBACK TESTS ==========

    function testFallbackToStoredPrice() public {
        // Arrange - Configure with invalid primary source
        vm.startPrank(admin);
        tokenRegistryOracle.configureToken(
            address(rethToken),
            1, // Chainlink
            address(0), // Invalid source
            0,
            bytes4(0) // No fallback
        );
        vm.stopPrank();

        // Act - Get price (should fall back to stored price)
        uint256 price = tokenRegistryOracle.getTokenPrice(address(rethToken));

        // Assert
        assertEq(
            price,
            1.04e18,
            "Should return the stored price from LiquidTokenManager"
        );
    }
}