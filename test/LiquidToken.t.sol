// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {MockCurvePool} from "./mocks/MockCurvePool.sol";
import {MockProtocolToken} from "./mocks/MockProtocolToken.sol";
import {ITokenRegistryOracle} from "../src/interfaces/ITokenRegistryOracle.sol";
import {TokenRegistryOracle} from "../src/utils/TokenRegistryOracle.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {LiquidToken} from "../src/core/LiquidToken.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";

contract LiquidTokenTest is BaseTest {
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
        liquidTokenManager.setVolatilityThreshold(testToken, 0); // Disable volatility check
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

    function testDeposit() public {
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256[] memory mintedShares = liquidToken.deposit(
            _convertToUpgradeable(assets),
            amounts,
            user1
        );
        uint256 shares = mintedShares[0];

        assertEq(shares, 10 ether, "Incorrect number of shares minted");
        assertEq(
            liquidToken.balanceOf(user1),
            10 ether,
            "Incorrect balance after deposit"
        );
        assertEq(
            testToken.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect token balance in LiquidToken"
        );
    }

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestWithdrawal() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));

        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        liquidToken.approve(user1, amountsToWithdraw[0]);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();

        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect balance after withdrawal request"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testWithdrawalRequestIdsAreAlwaysUnique() public {
        vm.startPrank(user1);

        // Setup initial deposit
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Make 3 withdrawal requests
        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 1 ether;

        // First request
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        // Second request - same block.timestamp
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        // Third request - different block
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 15);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        // Verify each request ID is unique
        bytes32[] memory requestIds = liquidToken.getUserWithdrawalRequests(user1);
        assertEq(requestIds.length, 3, "Should have 3 withdrawal requests");
        assertTrue(requestIds[0] != requestIds[1], "First and second request IDs should be different");
        assertTrue(requestIds[1] != requestIds[2], "Second and third request IDs should be different");
        assertTrue(requestIds[0] != requestIds[2], "First and third request IDs should be different");

        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestIdUniqueness() public {
        // Setup initial state
        uint256 depositAmount = 5 ether;
        testToken.mint(user1, depositAmount * 3); // Mint enough for 3 deposits
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), depositAmount * 3); // Approve for all deposits
        
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;
        
        // Make two deposits
        uint256[] memory shares1 = liquidToken.deposit(assets, amounts, user1);
        uint256[] memory shares2 = liquidToken.deposit(assets, amounts, user1);
        
        // Create withdrawal amounts arrays
        uint256[] memory withdrawShares1 = new uint256[](1);
        withdrawShares1[0] = shares1[0];
        uint256[] memory withdrawShares2 = new uint256[](1);
        withdrawShares2[0] = shares2[0];
        
        // Approve LiquidToken to burn shares for first two withdrawals
        liquidToken.approve(address(liquidToken), shares1[0] + shares2[0]);
        
        // Store request IDs
        bytes32[] memory requestIds = new bytes32[](3);
        
        // First withdrawal
        vm.recordLogs();
        liquidToken.requestWithdrawal(assets, withdrawShares1);
        Vm.Log[] memory entries1 = vm.getRecordedLogs();
        // Find WithdrawalRequested event and extract requestId
        for (uint i = 0; i < entries1.length; i++) {
            if (entries1[i].topics[0] == keccak256("WithdrawalRequested(bytes32,address,address[],uint256[],uint256)")) {
                requestIds[0] = bytes32(entries1[i].topics[1]);
                break;
            }
        }
        
        // Second withdrawal in same block
        vm.recordLogs();
        liquidToken.requestWithdrawal(assets, withdrawShares2);
        Vm.Log[] memory entries2 = vm.getRecordedLogs();
        for (uint i = 0; i < entries2.length; i++) {
            if (entries2[i].topics[0] == keccak256("WithdrawalRequested(bytes32,address,address[],uint256[],uint256)")) {
                requestIds[1] = bytes32(entries2[i].topics[1]);
                break;
            }
        }
        
        // Verify first two IDs are different
        assertTrue(requestIds[0] != requestIds[1], "Request IDs should be unique even in same block");
        
        // Make another deposit for third request
        uint256[] memory shares3 = liquidToken.deposit(assets, amounts, user1);
        uint256[] memory withdrawShares3 = new uint256[](1);
        withdrawShares3[0] = shares3[0];
        
        // Approve shares for third withdrawal
        liquidToken.approve(address(liquidToken), shares3[0]);
        
        // Third withdrawal with same parameters
        vm.recordLogs();
        liquidToken.requestWithdrawal(assets, withdrawShares3);
        Vm.Log[] memory entries3 = vm.getRecordedLogs();
        for (uint i = 0; i < entries3.length; i++) {
            if (entries3[i].topics[0] == keccak256("WithdrawalRequested(bytes32,address,address[],uint256[],uint256)")) {
                requestIds[2] = bytes32(entries3[i].topics[1]);
                break;
            }
        }
        
        // Verify all request IDs are unique
        assertTrue(requestIds[2] != requestIds[0], "Request ID should be different even with same parameters");
        assertTrue(requestIds[2] != requestIds[1], "Request ID should be different from second request");
        
        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestIdAcrossBlocks() public {
        // Setup initial state
        uint256 depositAmount = 5 ether;
        testToken.mint(user1, depositAmount * 3); // Mint enough for 3 deposits
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), depositAmount * 3);
        
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;
        
        // Make initial deposit
        uint256[] memory shares = liquidToken.deposit(assets, amounts, user1);
        
        // Create withdrawal shares array
        uint256[] memory withdrawShares = new uint256[](1);
        withdrawShares[0] = shares[0] / 3; // Use 1/3 of shares each time
        
        // Approve shares for withdrawal
        liquidToken.approve(address(liquidToken), shares[0]);
        
        // Make withdrawals across different blocks
        bytes32[] memory requestIds = new bytes32[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            // Move to next block
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);
            
            vm.recordLogs();
            liquidToken.requestWithdrawal(assets, withdrawShares);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            
            // Extract request ID
            for (uint j = 0; j < entries.length; j++) {
                if (entries[j].topics[0] == keccak256("WithdrawalRequested(bytes32,address,address[],uint256[],uint256)")) {
                    requestIds[i] = bytes32(entries[j].topics[1]);
                    break;
                }
            }
            
            // Verify uniqueness with previous IDs
            for (uint256 j = 0; j < i; j++) {
                assertTrue(requestIds[i] != requestIds[j], "Request IDs should be unique across blocks");
            }
        }
        
        vm.stopPrank();
    }
    */

    function testTransferAssets() public {
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 5 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(
            _convertToUpgradeable(assets),
            amountsToTransfer
        );

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token balance in liquid token manager"
        );
    }

    function testDepositMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        uint256[] memory mintedShares = liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
        uint256 shares1 = mintedShares[0];
        uint256 shares2 = mintedShares[1];

        assertEq(
            shares1,
            10 ether,
            "Incorrect number of shares minted for token1"
        );
        assertEq(
            shares2,
            5 ether,
            "Incorrect number of shares minted for token2"
        );
        assertEq(
            liquidToken.balanceOf(user1),
            15 ether,
            "Incorrect total balance after deposits"
        );
        vm.stopPrank();
    }
    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestWithdrawalMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](2);
        amountsToWithdraw[0] = 5 ether;
        amountsToWithdraw[1] = 2 ether;

        liquidToken.approve(user1, 7 ether);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();

        assertEq(
            liquidToken.balanceOf(user1),
            8 ether,
            "Incorrect balance after withdrawal request"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testFulfillWithdrawalMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](2);
        amountsToWithdraw[0] = 5 ether;
        amountsToWithdraw[1] = 2 ether;

        liquidToken.approve(user1, 7 ether);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Fast forward time
        vm.warp(block.timestamp + 15 days);

        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token1 balance after withdrawal"
        );
        assertEq(
            testToken2.balanceOf(user1),
            97 ether,
            "Incorrect token2 balance after withdrawal"
        );
    }
    */

    function testTransferMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
        vm.stopPrank();

        uint256[] memory amountsToTransfer = new uint256[](2);
        amountsToTransfer[0] = 5 ether;
        amountsToTransfer[1] = 2 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(
            _convertToUpgradeable(assets),
            amountsToTransfer
        );

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token1 balance in liquidTokenManager"
        );
        assertEq(
            testToken2.balanceOf(address(liquidTokenManager)),
            2 ether,
            "Incorrect token2 balance in liquidTokenManager"
        );
    }

    function testDepositArrayLengthMismatch() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](2); // Mismatch in length
        amountsToDeposit[0] = 5 ether;
        amountsToDeposit[1] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ArrayLengthMismatch.selector);
        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
    }

    function testDepositZeroAmount() public {
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 0 ether;

        vm.expectRevert(ILiquidToken.ZeroAmount.selector);
        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
    }

    function testDepositUnsupportedAsset() public {
        ERC20 unsupportedToken = new MockERC20("Unsupported Token", "UT");
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(unsupportedToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(unsupportedToken)
            )
        );
        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
    }

    function testDepositZeroShares() public {
        // Mock a scenario where the conversion rate makes the shares zero
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10;

        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeWithSelector(
                ILiquidTokenManager.convertToUnitOfAccount.selector,
                IERC20(address(testToken)),
                10
            ),
            abi.encode(0) // Conversion returns zero, leading to ZeroShares
        );

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ZeroShares.selector);
        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
    }

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestWithdrawalArrayLengthMismatch() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToWithdraw = new uint256[](2); // Mismatch in length
        amountsToWithdraw[0] = 5 ether;
        amountsToWithdraw[1] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ArrayLengthMismatch.selector);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestWithdrawalUnsupportedAsset() public {
        IERC20 unsupportedToken = new MockERC20("Unsupported Token", "UT");
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = unsupportedToken;
        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 10 ether;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILiquidToken.UnsupportedAsset.selector, address(unsupportedToken)));
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestWithdrawalZeroAmount() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 0; // Zero withdrawal amount

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ZeroAmount.selector);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testRequestWithdrawalInsufficientBalance() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 11 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.InsufficientBalance.selector,
                address(liquidToken),
                11 ether,
                10 ether
            )
        );
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testInvalidWithdrawalRequest() public {
            IERC20[] memory assets = new IERC20[](1);
            assets[0] = IERC20(address(testToken));
            uint256[] memory amountsToDeposit = new uint256[](1);
            amountsToDeposit[0] = 10 ether;

            vm.startPrank(user1);
            liquidToken.deposit(assets, amountsToDeposit, user1);
            
            uint256[] memory amountsToWithdraw = new uint256[](1);
            amountsToWithdraw[0] = 5 ether;
            liquidToken.requestWithdrawal(assets, amountsToWithdraw);
            vm.stopPrank();

            // User2 attempts to fulfill User1's withdrawal request
            bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

            vm.prank(user2);
            vm.expectRevert(ILiquidToken.InvalidWithdrawalRequest.selector);
            liquidToken.fulfillWithdrawal(requestId);
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testWithdrawalAlreadyFulfilled() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        vm.startPrank(user1);
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];
        vm.warp(block.timestamp + 15 days);
        liquidToken.fulfillWithdrawal(requestId);
        
        // User attempts to fulfill the same withdrawal request again
        vm.expectRevert(ILiquidToken.WithdrawalAlreadyFulfilled.selector);
        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testFulfillWithdrawalBeforeDelay() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        liquidToken.approve(user1, amountsToWithdraw[0]);
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);

        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];

        // Fast forward time, but not enough
        vm.warp(block.timestamp + 13 days);

        vm.expectRevert(ILiquidToken.WithdrawalDelayNotMet.selector);
        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();
    }
    */

    function testTransferAssetsNotLiquidTokenManager() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.NotLiquidTokenManager.selector,
                user1
            )
        );
        liquidToken.transferAssets(_convertToUpgradeable(assets), amounts);
    }

    function testTransferAssetsInsufficientBalance() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        vm.prank(user1);
        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 20 ether; // More than available

        vm.prank(address(liquidTokenManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.InsufficientBalance.selector,
                address(testToken),
                10 ether,
                20 ether
            )
        );
        liquidToken.transferAssets(
            _convertToUpgradeable(assets),
            amountsToTransfer
        );
    }

    function testPause() public {
        vm.prank(pauser);
        liquidToken.pause();

        assertTrue(liquidToken.paused(), "Contract should be paused");

        // OpenZeppelin v4 uses string revert reasons instead of error selectors
        vm.expectRevert("Pausable: paused");
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
    }

    function testUnpause() public {
        vm.prank(pauser);
        liquidToken.pause();

        vm.prank(admin);
        liquidToken.unpause();

        assertFalse(liquidToken.paused(), "Contract should be unpaused");

        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(
            _convertToUpgradeable(assets),
            amountsToDeposit,
            user1
        );
    }

    function testPauseUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        liquidToken.pause();
    }

    /// Tests for deposit functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testZeroAddressInput() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(0));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        // Attempt to deposit with an incorrect address (address(0))
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                IERC20(address(0))
            )
        );
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Valid deposit
        assets[0] = IERC20(address(testToken));
        liquidToken.deposit(assets, amountsToDeposit, user1);

        // Attempt to withdraw with a zero address
        assets[0] = IERC20(address(0));
        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = 5 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(assets[0])
            )
        );
        liquidToken.requestWithdrawal(assets, amountsToWithdraw);
        vm.stopPrank();

        // Attempt to transfer assets with a zero address
        vm.prank(address(liquidTokenManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(assets[0])
            )
        );

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 5 ether;
        liquidToken.transferAssets(assets, amountsToTransfer);
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testConsecutiveWithdrawalRequestsWithFulfillments() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory withdrawal1Amounts = new uint256[](1);
        withdrawal1Amounts[0] = 5 ether;
        liquidToken.requestWithdrawal(assets, withdrawal1Amounts);

        // Second withdrawal request before fulfilling the first
        uint256[] memory withdrawal2Amounts = new uint256[](1);
        withdrawal2Amounts[0] = 2 ether;
        liquidToken.requestWithdrawal(assets, withdrawal2Amounts);

        assertEq(
            liquidToken.balanceOf(user1),
            3 ether,
            "Incorrect balance after second withdrawal request"
        );

        // There should be two withdrawal requests in the queue
        assertEq(
            liquidToken.getUserWithdrawalRequests(user1).length,
            2,
            "Incorrect number of withdrawal requests"
        );

        vm.warp(block.timestamp + 15 days);

        // Fulfill the first withdrawal request
        bytes32 firstRequestId = liquidToken.getUserWithdrawalRequests(user1)[
            0
        ];
        uint256 totalSupplyBeforeFirstFulfillment = liquidToken.totalSupply();
        liquidToken.fulfillWithdrawal(firstRequestId);

        // Check balances after the first fulfillment
        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after first withdrawal fulfillment"
        );
        assertEq(
            liquidToken.totalSupply(),
            totalSupplyBeforeFirstFulfillment - 5 ether,
            "Incorrect total supply after first withdrawal (tokens not burned)"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            2 ether,
            "Contract should not hold first deposit liquid tokens after first fulfillment"
        );

        // Fulfill the second withdrawal request
        bytes32 secondRequestId = liquidToken.getUserWithdrawalRequests(user1)[
            1
        ];
        uint256 totalSupplyBeforeSecondFulfillment = liquidToken.totalSupply();
        liquidToken.fulfillWithdrawal(secondRequestId);

        // Check balances after the second fulfillment
        assertEq(
            testToken.balanceOf(user1),
            97 ether,
            "Incorrect testToken balance after second withdrawal"
        );
        assertEq(
            liquidToken.totalSupply(),
            totalSupplyBeforeSecondFulfillment - 2 ether,
            "Incorrect total supply after second withdrawal (tokens not burned)"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after second fulfillment"
        );

        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testMultipleUsersMultipleWithdrawals() public {
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDepositUser1 = new uint256[](1);
        amountsToDepositUser1[0] = 10 ether;
        
        liquidToken.deposit(assets, amountsToDepositUser1, user1);

        vm.prank(user2);
        uint256[] memory amountsToDepositUser2 = new uint256[](1);
        amountsToDepositUser2[0] = 20 ether;
        liquidToken.deposit(assets, amountsToDepositUser2, user2);

        vm.startPrank(user1);
        uint256[] memory amountsUser1Withdrawal = new uint256[](1);
        amountsUser1Withdrawal[0] = 5 ether;
        liquidToken.requestWithdrawal(assets, amountsUser1Withdrawal);

        bytes32 requestIdUser1 = liquidToken.getUserWithdrawalRequests(user1)[
            0
        ];
        vm.warp(block.timestamp + liquidToken.WITHDRAWAL_DELAY());
        liquidToken.fulfillWithdrawal(requestIdUser1);
        
        // Check balances for User1
        assertEq(
            testToken.balanceOf(user1),
            95 ether,
            "Incorrect token balance after withdrawal for User1"
        );
        assertEq(
            liquidToken.balanceOf(user1),
            5 ether,
            "Incorrect remaining balance after withdrawal for User1"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after User1's fulfillment"
        );

        vm.stopPrank();
        vm.startPrank(user2);

        uint256[] memory amountsUser2Withdrawal = new uint256[](1);
        amountsUser2Withdrawal[0] = 10 ether;
        liquidToken.requestWithdrawal(assets, amountsUser2Withdrawal);

        bytes32 requestIdUser2 = liquidToken.getUserWithdrawalRequests(user2)[
            0
        ];
        vm.warp(block.timestamp + liquidToken.WITHDRAWAL_DELAY());
        liquidToken.fulfillWithdrawal(requestIdUser2);

        // Check balances for User2
        assertEq(
            testToken.balanceOf(user2),
            90 ether,
            "Incorrect token balance after withdrawal for User2"
        );
        assertEq(
            liquidToken.balanceOf(user2),
            10 ether,
            "Incorrect remaining balance after withdrawal for User2"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after User2's fulfillment"
        );

        vm.stopPrank();
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testMultipleTokensWithdrawalsWithPriceChangeAfterDeposit() public {
        vm.startPrank(admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        liquidTokenManager.updatePrice(IERC20(address(testToken)), 1e18); // 1 testToken = 1 unit
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 units
        vm.stopPrank();

        // User1 deposits 10 ether of testToken and 10 ether of testToken2
        vm.startPrank(user1);
        
        IERC20[] memory depositAssets = new IERC20[](2);
        depositAssets[0] = IERC20(address(testToken));
        depositAssets[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 10 ether;
        depositAmounts[1] = 10 ether;
        
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        // Check totalSupply, totalAssets, and contract balances after deposits
        assertEq(
            liquidToken.totalSupply(),
            20 ether,
            "Incorrect total supply after deposits"
        );
        assertEq(
            liquidToken.totalAssets(),
            20 ether,
            "Incorrect total assets after deposits"
        );
        assertEq(
            testToken.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect testToken balance in contract after deposits"
        );
        assertEq(
            testToken2.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect testToken2 balance in contract after deposits"
        );

        vm.stopPrank();

        // Simulate a price increase for testToken
        vm.startPrank(admin);
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 3e18); // 1 testToken = 3 units (price increase)
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 2e18); // 1 testToken2 = 2 units (price increase)
        vm.stopPrank();

        // User1 requests complete withdrawal
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 12 ether;
        amounts[1] = 8 ether;
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();

        // Fulfill withdrawal
        vm.startPrank(user1);
        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];
        vm.warp(block.timestamp + 15 days);
        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        assertEq(
            testToken.balanceOf(address(liquidToken)),
            0 ether,
            "Incorrect testToken balance in contract after withdrawal fulfillment"
        );
        assertEq(
            testToken2.balanceOf(address(liquidToken)),
            0 ether,
            "Incorrect testToken2 balance in contract after withdrawal fulfillment"
        );

        // Check totalSupply, totalAssets, and contract balances after withdrawal fulfillment
        assertEq(
            liquidToken.totalSupply(),
            0 ether,
            "Incorrect total supply after withdrawal fulfillment"
        );

        // Check balances for User1
        assertEq(
            testToken.balanceOf(user1),
            100 ether,
            "Incorrect testToken balance after withdrawal for User1"
        );
        assertEq(
            testToken2.balanceOf(user1),
            100 ether,
            "Incorrect testToken2 balance after withdrawal for User1"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after User1's fulfillment"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testMultipleTokensWithdrawalsWithPriceChangeAfterRequest() public {
        vm.startPrank(admin);
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);

        liquidTokenManager.updatePrice(IERC20(address(testToken)), 1e18); // 1 testToken = 1 unit
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 1e18); // 1 testToken2 = 1 units
        vm.stopPrank();

        // User1 deposits 10 ether of testToken and 10 ether of testToken2
        vm.startPrank(user1);
        
        IERC20[] memory depositAssets = new IERC20[](2);
        depositAssets[0] = IERC20(address(testToken));
        depositAssets[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 10 ether;
        depositAmounts[1] = 10 ether;
        
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        // Check totalSupply, totalAssets, and contract balances after deposits
        assertEq(
            liquidToken.totalSupply(),
            20 ether,
            "Incorrect total supply after deposits"
        );
        assertEq(
            liquidToken.totalAssets(),
            20 ether,
            "Incorrect total assets after deposits"
        );
        assertEq(
            testToken.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect testToken balance in contract after deposits"
        );
        assertEq(
            testToken2.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect testToken2 balance in contract after deposits"
        );

        vm.stopPrank();

        // User1 requests complete withdrawal
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 12 ether;
        amounts[1] = 8 ether;
        liquidToken.requestWithdrawal(assets, amounts);
        vm.stopPrank();

        // Simulate a price increase for testToken
        vm.startPrank(admin);
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 3e18); // 1 testToken = 3 units (price increase)
        liquidTokenManager.updatePrice(IERC20(address(testToken2)), 2e18); // 1 testToken2 = 2 units (price increase)
        vm.stopPrank();

        // Fulfill withdrawal
        vm.startPrank(user1);
        bytes32 requestId = liquidToken.getUserWithdrawalRequests(user1)[0];
        vm.warp(block.timestamp + 15 days);
        liquidToken.fulfillWithdrawal(requestId);
        vm.stopPrank();

        assertEq(
            testToken.balanceOf(address(liquidToken)),
            0 ether,
            "Incorrect testToken balance in contract after withdrawal fulfillment"
        );
        assertEq(
            testToken2.balanceOf(address(liquidToken)),
            0 ether,
            "Incorrect testToken2 balance in contract after withdrawal fulfillment"
        );

        // Check totalSupply, totalAssets, and contract balances after withdrawal fulfillment
        assertEq(
            liquidToken.totalSupply(),
            0 ether,
            "Incorrect total supply after withdrawal fulfillment"
        );

        // Check balances for User1
        assertEq(
            testToken.balanceOf(user1),
            100 ether,
            "Incorrect testToken balance after withdrawal for User1"
        );
        assertEq(
            testToken2.balanceOf(user1),
            100 ether,
            "Incorrect testToken2 balance after withdrawal for User1"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)),
            0,
            "Contract should not hold any liquid tokens after User1's fulfillment"
        );
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testShareLockingInWithdrawalRequest() public {
        // Setup: User deposits tokens first
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 10 ether;
        
        liquidToken.deposit(assets, depositAmounts, user1);
        
        // Check initial state
        uint256 initialTotalSupply = liquidToken.totalSupply();
        uint256 initialUserBalance = liquidToken.balanceOf(user1);
        assertEq(initialTotalSupply, 10 ether, "Initial total supply incorrect");
        assertEq(initialUserBalance, 10 ether, "Initial user balance incorrect");
        
        // Request withdrawal
        uint256[] memory withdrawShares = new uint256[](1);
        withdrawShares[0] = 5 ether;
        liquidToken.requestWithdrawal(assets, withdrawShares);
        
        // Verify shares are locked (transferred to contract)
        uint256 newTotalSupply = liquidToken.totalSupply();
        uint256 newUserBalance = liquidToken.balanceOf(user1);
        assertEq(newTotalSupply, 10 ether, "Total supply should remain the same");
        assertEq(newUserBalance, 5 ether, "User balance should be reduced by withdrawn shares");
        assertEq(liquidToken.balanceOf(address(liquidToken)), 5 ether, "Contract should hold locked shares");
        
        // Wait for withdrawal delay
        vm.warp(block.timestamp + liquidToken.WITHDRAWAL_DELAY());
        
        // Get the latest withdrawal request
        bytes32[] memory requests = liquidToken.getUserWithdrawalRequests(user1);
        bytes32 requestId = requests[requests.length - 1];
        
        // Fulfill withdrawal
        liquidToken.fulfillWithdrawal(requestId);
        
        // Verify shares are burned after fulfillment
        assertEq(liquidToken.totalSupply(), 5 ether, "Total supply should be reduced after burning");
        assertEq(liquidToken.balanceOf(user1), 5 ether, "User balance should remain the same after fulfillment");
        assertEq(liquidToken.balanceOf(address(liquidToken)), 0, "Contract should not hold shares after fulfillment");
    }
    */

    /// Tests for withdrawal functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testShareLockingWithMultipleAssets() public {
        // Setup: User deposits multiple tokens
        vm.startPrank(user1);
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 10 ether;
        depositAmounts[1] = 20 ether;
        liquidToken.deposit(assets, depositAmounts, user1);
        
        // Check initial state
        uint256 initialTotalSupply = liquidToken.totalSupply();
        uint256 initialUserBalance = liquidToken.balanceOf(user1);
        
        // Request withdrawal of multiple assets
        uint256[] memory withdrawShares = new uint256[](2);
        withdrawShares[0] = 5 ether;
        withdrawShares[1] = 10 ether;
        liquidToken.requestWithdrawal(assets, withdrawShares);
        
        // Verify shares are locked (transferred to contract)
        uint256 totalSharesLocked = withdrawShares[0] + withdrawShares[1];
        assertEq(
            liquidToken.totalSupply(), 
            initialTotalSupply, 
            "Total supply should remain the same after locking"
        );
        assertEq(
            liquidToken.balanceOf(user1), 
            initialUserBalance - totalSharesLocked, 
            "User balance should be reduced by locked shares"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)), 
            totalSharesLocked, 
            "Contract should hold locked shares"
        );
        
        // Fulfill withdrawal for each asset
        vm.warp(block.timestamp + liquidToken.WITHDRAWAL_DELAY());
        bytes32[] memory requests = liquidToken.getUserWithdrawalRequests(user1);
        for (uint256 i = 0; i < requests.length; i++) {
            liquidToken.fulfillWithdrawal(requests[i]);
        }
        
        // Verify shares are burned after fulfillment
        assertEq(
            liquidToken.totalSupply(), 
            initialTotalSupply - totalSharesLocked, 
            "Total supply should be reduced after burning"
        );
        assertEq(
            liquidToken.balanceOf(user1), 
            initialUserBalance - totalSharesLocked, 
            "User balance should remain the same after fulfillment"
        );
        assertEq(
            liquidToken.balanceOf(address(liquidToken)), 
            0, 
            "Contract should not hold shares after fulfillment"
        );
    }
    */

    function testTotalAssetsCalculationEdgeCases() public {
        vm.startPrank(admin);

        // Test with maximum possible token amount
        uint256 maxAmount = type(uint256).max / 2; // Avoid overflow
        testToken.mint(user1, maxAmount);

        vm.startPrank(user1);
        testToken.approve(address(liquidToken), maxAmount);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = maxAmount;

        liquidToken.deposit(_convertToUpgradeable(assets), amounts, user1);

        // Verify total assets matches deposit
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            maxAmount,
            "Total assets should match max deposit"
        );

        // Test precision with small amounts
        uint256 smallAmount = 1;
        testToken.mint(user2, smallAmount);

        vm.startPrank(user2);
        testToken.approve(address(liquidToken), smallAmount);
        amounts[0] = smallAmount;

        liquidToken.deposit(_convertToUpgradeable(assets), amounts, user2);

        // Verify small amounts are tracked correctly
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            maxAmount + smallAmount,
            "Total assets should include small amount"
        );
    }
    /// Tests for locked token recovery functionality that will be implemented in future versions
    /// OUT OF SCOPE FOR V1
    /**
    function testLockedTokenRecovery() public {
        // Test direct transfer to contract
        uint256 directAmount = 1 ether;
        testToken.mint(address(this), directAmount);
        testToken.transfer(address(liquidToken), directAmount);
        
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        
        // Verify total assets excludes direct transfers
        assertEq(liquidToken.assetBalances(address(testToken)), 0, "Total assets should not include direct transfers");
        
        // Test failed withdrawal scenario
        vm.startPrank(user1);
        uint256 depositAmount = 5 ether;
        testToken.mint(user1, depositAmount);
        testToken.approve(address(liquidToken), depositAmount);
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;
        
        uint256[] memory shares = liquidToken.deposit(assets, amounts, user1);
        
        // Approve LiquidToken to burn shares for withdrawal
        liquidToken.approve(address(liquidToken), shares[0]);
        
        // Request withdrawal
        liquidToken.requestWithdrawal(assets, amounts);
        
        // Verify assets are still tracked correctly
        assertEq(liquidToken.assetBalances(address(testToken)), depositAmount, "Total assets should track pending withdrawals");
        assertEq(liquidToken.queuedAssetBalances(address(testToken)), 0, "Queued assets should be 0 until withdrawal is fulfilled");
    }
    */

    function testTotalAssetsWithStrategyMigration() public {
        vm.startPrank(admin);

        // Initial deposit
        uint256 depositAmount = 10 ether;
        testToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        testToken.approve(address(liquidToken), depositAmount);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;

        liquidToken.deposit(_convertToUpgradeable(assets), amounts, user1);

        // Verify initial total assets
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            depositAmount,
            "Initial total assets incorrect"
        );

        // Simulate strategy migration
        vm.startPrank(admin);

        // Verify total assets remained constant through migration
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            depositAmount,
            "Total assets changed during migration"
        );
    }

    // Helper function to convert IERC20[] to IERC20Upgradeable[](for test)
    function _convertToUpgradeable(
        IERC20[] memory tokens
    ) internal pure returns (IERC20Upgradeable[] memory) {
        IERC20Upgradeable[] memory upgradeableTokens = new IERC20Upgradeable[](
            tokens.length
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            upgradeableTokens[i] = IERC20Upgradeable(address(tokens[i]));
        }
        return upgradeableTokens;
    }
}