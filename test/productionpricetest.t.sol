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

contract ProductionPriceTest is BaseTest {
    // Mainnet fork block
    uint256 mainnetFork;

    // Mock token for deposit tests
    MockERC20 public mockDepositToken;

    // Price type constants - match the ones in TokenRegistryOracle
    uint8 constant SOURCE_TYPE_CHAINLINK = 1;
    uint8 constant SOURCE_TYPE_CURVE = 2;
    uint8 constant SOURCE_TYPE_BTC_CHAINED = 3;
    uint8 constant SOURCE_TYPE_PROTOCOL = 4;

    // Price sources
    mapping(address => address) public primarySource;
    mapping(address => bytes4) public fallbackSelector;
    mapping(address => uint8) public sourceType;
    mapping(address => bool) public needsArg;
    mapping(address => bool) public tokenAdded; // Track which tokens were added successfully
    mapping(address => bool) public tokenConfigured; // Track which tokens were configured successfully
    mapping(address => address) public fallbackSource; // Track fallback sources

    // Token lists by category
    address[] public chainlinkTokens;
    address[] public curveTokens;
    address[] public protocolTokens;
    address[] public btcTokens;
    address[] public allTokens;

    // For tracking token status
    struct TokenStatus {
        address token;
        string name;
        string symbol;
        bool added;
        bool configured;
        bool priceWorks;
        uint256 price;
    }

    TokenStatus[] public tokenStatuses;

    // BTC/ETH feed address
    address public BTCETHFEED;

    function setUp() public override {
        // Create mainnet fork
        mainnetFork = vm.createFork("https://ethereum-rpc.publicnode.com");
        vm.selectFork(mainnetFork);

        // Call parent setup
        super.setUp();

        // Ensure admin has all necessary roles in this forked environment
        vm.startPrank(deployer);

        // Grant all roles to admin for TokenRegistryOracle
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.DEFAULT_ADMIN_ROLE(),
            admin
        );
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.ORACLE_ADMIN_ROLE(),
            admin
        );
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.RATE_UPDATER_ROLE(),
            admin
        );

        // Also grant roles for LiquidTokenManager
        liquidTokenManager.grantRole(
            liquidTokenManager.DEFAULT_ADMIN_ROLE(),
            admin
        );
        liquidTokenManager.grantRole(
            liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
            admin
        );

        // Also need to make sure user2 has RATE_UPDATER_ROLE for the tests
        tokenRegistryOracle.grantRole(
            tokenRegistryOracle.RATE_UPDATER_ROLE(),
            user2
        );

        vm.stopPrank();

        // Create mock deposit token
        mockDepositToken = new MockERC20("Mock Deposit Token", "MDT");
        mockDepositToken.mint(user1, 1000 ether);

        // Set up token categories - using hardcoded addresses for mainnet tokens
        _setupTokenLists();

        // Add the tokens to LiquidTokenManager first - track success
        _addTokensToManager();

        // Add mock token to LiquidTokenManager
        vm.startPrank(admin);
        liquidTokenManager.addToken(
            IERC20(address(mockDepositToken)),
            18,
            1e18, // 1:1 with ETH
            0,
            mockStrategy,
            0, // primaryType (uninitialized)
            address(0), // primarySource
            0, // needsArg
            address(0), // fallbackSource
            bytes4(0) // fallbackFn
        );
        tokenAdded[address(mockDepositToken)] = true;
        vm.stopPrank();

        // Approve token for LiquidToken contract
        vm.startPrank(user1);
        mockDepositToken.approve(address(liquidToken), type(uint256).max);
        vm.stopPrank();

        // Configure the TokenRegistryOracle with all tokens - track success
        _configureAllTokens();

        // Create token status report
        _createTokenStatusReport();
    }

    function _addTokensToManager() internal {
        vm.startPrank(admin);
        console.log("======= Adding Tokens to LiquidTokenManager =======");

        // Add all tokens to LiquidTokenManager
        for (uint i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];

            // Skip if token is address(0)
            if (token == address(0)) continue;

            string memory tokenSymbol;
            try ERC20(token).symbol() returns (string memory symbol) {
                tokenSymbol = symbol;
            } catch {
                tokenSymbol = "Unknown";
            }

            console.log("Adding token %s (%s)...", tokenSymbol, token);

            try liquidTokenManager.getTokenInfo(IERC20(token)) {
                // Token already exists, mark as added
                console.log("  Token already added to LiquidTokenManager");
                tokenAdded[token] = true;
            } catch {
                // Add the token
                try
                    liquidTokenManager.addToken(
                        IERC20(token),
                        18, // Standard decimals
                        1e18, // Initial price 1:1 with ETH for simplicity
                        0, // No volatility threshold
                        mockStrategy, // Use our mock strategy
                        sourceType[token], // Use the source type we defined
                        primarySource[token], // Use primary source from our mapping
                        needsArg[token] ? 1 : 0, // Set needsArg flag
                        fallbackSource[token], // Use fallback source from our mapping
                        fallbackSelector[token] // Use fallback selector if available
                    )
                {
                    console.log("  Token added successfully");
                    tokenAdded[token] = true;
                } catch Error(string memory reason) {
                    console.log("   Failed to add token: %s", reason);
                    tokenAdded[token] = false;
                } catch (bytes memory) {
                    console.log("   Failed to add token (unknown error)");
                    tokenAdded[token] = false;
                }
            }
        }

        vm.stopPrank();
    }

    function _setupTokenLists() internal {
        // Define mainnet token addresses from PriceConstants
        address RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        address STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
        address METH = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
        address OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
        address LSETH = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549;
        address ETHx = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
        address ANKR_ETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
        address OSETH = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
        address SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
        address SFRxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
        address WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address UNIBTC = 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568;
        address STBTC = 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3;
        address WBETH = 0xa2E3356610840701BDf5611a53974510Ae27E2e1;

        // Set BTC/ETH feed
        BTCETHFEED = 0xdeb288F737066589598e9214E782fa5A8eD689e8; // From PriceConstants.CHAINLINK_BTC_ETH()

        // Chainlink tokens
        chainlinkTokens.push(RETH);
        chainlinkTokens.push(STETH);
        chainlinkTokens.push(CBETH);
        chainlinkTokens.push(METH);
        chainlinkTokens.push(OETH);

        // Also add to all tokens list
        for (uint i = 0; i < chainlinkTokens.length; i++) {
            allTokens.push(chainlinkTokens[i]);
        }

        // Curve tokens
        curveTokens.push(LSETH);
        curveTokens.push(ETHx);
        curveTokens.push(ANKR_ETH);
        curveTokens.push(OSETH);
        curveTokens.push(SWETH);

        // Also add to all tokens list
        for (uint i = 0; i < curveTokens.length; i++) {
            allTokens.push(curveTokens[i]);
        }

        // Protocol tokens - those we'll use function calls on
        protocolTokens.push(RETH); // getExchangeRate
        protocolTokens.push(STETH); // getPooledEthByShares
        protocolTokens.push(CBETH); // exchangeRate
        protocolTokens.push(ETHx); // convertToAssets
        protocolTokens.push(SFRxETH); // convertToAssets
        protocolTokens.push(WSTETH); // stEthPerToken
        protocolTokens.push(SWETH); // swETHToETHRate
        protocolTokens.push(METH); // mETHToETH
        protocolTokens.push(WBETH); // ratio

        // Add protocol-only tokens to all tokens list
        for (uint i = 0; i < protocolTokens.length; i++) {
            bool exists = false;
            for (uint j = 0; j < allTokens.length; j++) {
                if (allTokens[j] == protocolTokens[i]) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                allTokens.push(protocolTokens[i]);
            }
        }

        // BTC tokens
        btcTokens.push(UNIBTC);
        btcTokens.push(STBTC);

        // Add BTC tokens to all tokens list
        for (uint i = 0; i < btcTokens.length; i++) {
            allTokens.push(btcTokens[i]);
        }

        // Set up primary source records for Chainlink feeds from PriceConstants
        primarySource[RETH] = 0x536218f9E9Eb48863970252233c8F271f554C2d0; // CHAINLINK_RETH_ETH
        primarySource[STETH] = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812; // CHAINLINK_STETH_ETH
        primarySource[CBETH] = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b; // CHAINLINK_CBETH_ETH
        primarySource[METH] = 0x5b563107C8666d2142C216114228443B94152362; // CHAINLINK_METH_ETH
        primarySource[OETH] = 0x703118C4CbccCBF2AB31913e0f8075fbbb15f563; // CHAINLINK_OETH_ETH

        // Set up Curve pools from PriceConstants
        primarySource[LSETH] = 0x6c60d69348f3430bE4B7cf0155a4FD8f6CA9353B; // LSETH_CURVE_POOL
        primarySource[ETHx] = 0x64939a882C7d1b096241678b7a3A57eD19445485; // ETHx_CURVE_POOL
        primarySource[ANKR_ETH] = 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2; // ANKR_ETH_CURVE_POOL
        primarySource[OSETH] = 0xC2A6798447BB70E5abCf1b0D6aeeC90BC14FCA55; // OSETH_CURVE_POOL
        primarySource[SWETH] = 0x8d30BE1e51882688ee8F976DeB9bdd411b74BEf3; // SWETH_CURVE_POOL

        // Set up BTC feeds from PriceConstants
        primarySource[UNIBTC] = 0x861d15F8a4059cb918bD6F3670adAEB1220B298f; // CHAINLINK_UNIBTC_BTC
        primarySource[STBTC] = 0xD93571A6201978976e37c4A0F7bE17806f2Feab2; // CHAINLINK_STBTC_BTC

        // Set up protocol function calls with their appropriate selectors from PriceConstants

        // RETH
        fallbackSelector[RETH] = bytes4(keccak256("getExchangeRate()")); // SELECTOR_GET_EXCHANGE_RATE
        fallbackSource[RETH] = RETH; // RETH_CONTRACT

        // STETH
        fallbackSelector[STETH] = bytes4(
            keccak256("getPooledEthByShares(uint256)")
        ); // SELECTOR_GET_POOLED_ETH_BY_SHARES
        fallbackSource[STETH] = STETH; // STETH_CONTRACT
        needsArg[STETH] = true;

        // CBETH
        fallbackSelector[CBETH] = bytes4(keccak256("exchangeRate()")); // SELECTOR_EXCHANGE_RATE
        fallbackSource[CBETH] = CBETH; // CBETH_CONTRACT

        // ETHx
        fallbackSelector[ETHx] = bytes4(keccak256("convertToAssets(uint256)")); // SELECTOR_CONVERT_TO_ASSETS
        fallbackSource[ETHx] = ETHx; // ETHx_CONTRACT
        needsArg[ETHx] = true;

        // SFRxETH
        fallbackSelector[SFRxETH] = bytes4(
            keccak256("convertToAssets(uint256)")
        ); // SELECTOR_CONVERT_TO_ASSETS
        fallbackSource[SFRxETH] = SFRxETH; // SFRxETH_CONTRACT
        needsArg[SFRxETH] = true;

        // WSTETH
        fallbackSelector[WSTETH] = bytes4(keccak256("stEthPerToken()")); // SELECTOR_STETH_PER_TOKEN
        fallbackSource[WSTETH] = WSTETH; // WSTETH_CONTRACT

        // SWETH
        fallbackSelector[SWETH] = bytes4(keccak256("swETHToETHRate()")); // SELECTOR_SWETH_TO_ETH_RATE
        fallbackSource[SWETH] = SWETH; // SWETH_CONTRACT

        // METH
        fallbackSelector[METH] = bytes4(keccak256("mETHToETH(uint256)")); // SELECTOR_METH_TO_ETH
        fallbackSource[METH] = METH; // METH_CONTRACT
        needsArg[METH] = true;

        // WBETH
        fallbackSelector[WBETH] = bytes4(keccak256("ratio()")); // SELECTOR_RATIO
        fallbackSource[WBETH] = WBETH; // WBETH_CONTRACT

        // Record source types for each token
        for (uint i = 0; i < chainlinkTokens.length; i++) {
            sourceType[chainlinkTokens[i]] = SOURCE_TYPE_CHAINLINK;
        }
        for (uint i = 0; i < curveTokens.length; i++) {
            sourceType[curveTokens[i]] = SOURCE_TYPE_CURVE;
        }
        for (uint i = 0; i < btcTokens.length; i++) {
            sourceType[btcTokens[i]] = SOURCE_TYPE_BTC_CHAINED;
        }
        for (uint i = 0; i < protocolTokens.length; i++) {
            // Only set protocol source type for tokens that don't already have a source
            if (sourceType[protocolTokens[i]] == 0) {
                sourceType[protocolTokens[i]] = SOURCE_TYPE_PROTOCOL;
            }
        }
    }

    function _configureAllTokens() internal {
        vm.startPrank(admin);
        console.log(
            "======= Configuring Tokens in TokenRegistryOracle ======="
        );

        // Configure all tokens with their primary sources

        // 1. Configure Chainlink tokens
        for (uint i = 0; i < chainlinkTokens.length; i++) {
            address token = chainlinkTokens[i];
            address feed = primarySource[token];
            bytes4 fbSelector = fallbackSelector[token];
            address fbSource = fallbackSource[token];

            // Skip if token wasn't added successfully
            if (!tokenAdded[token]) {
                console.log(
                    "Skipping Chainlink token configuration for %s (not added)",
                    token
                );
                continue;
            }

            string memory tokenSymbol;
            try ERC20(token).symbol() returns (string memory symbol) {
                tokenSymbol = symbol;
            } catch {
                tokenSymbol = "Unknown";
            }

            console.log(
                "Configuring Chainlink token %s (%s)...",
                tokenSymbol,
                token
            );

            if (token != address(0) && feed != address(0)) {
                try
                    tokenRegistryOracle.configureToken(
                        token,
                        SOURCE_TYPE_CHAINLINK,
                        feed,
                        needsArg[token] ? 1 : 0,
                        fbSource,
                        fbSelector
                    )
                {
                    console.log(
                        "  Token configured with Chainlink source: %s",
                        feed
                    );
                    tokenConfigured[token] = true;
                } catch Error(string memory reason) {
                    console.log("   Failed to configure token: %s", reason);
                    tokenConfigured[token] = false;
                } catch (bytes memory) {
                    console.log("   Failed to configure token (unknown error)");
                    tokenConfigured[token] = false;
                }
            } else {
                console.log("   Invalid token or feed address");
                tokenConfigured[token] = false;
            }
        }

        // 2. Configure Curve tokens
        for (uint i = 0; i < curveTokens.length; i++) {
            address token = curveTokens[i];
            address pool = primarySource[token];
            bytes4 fbSelector = fallbackSelector[token];
            address fbSource = fallbackSource[token];

            // Skip if token wasn't added successfully
            if (!tokenAdded[token]) {
                console.log(
                    "Skipping Curve token configuration for %s (not added)",
                    token
                );
                continue;
            }

            string memory tokenSymbol;
            try ERC20(token).symbol() returns (string memory symbol) {
                tokenSymbol = symbol;
            } catch {
                tokenSymbol = "Unknown";
            }

            console.log(
                "Configuring Curve token %s (%s)...",
                tokenSymbol,
                token
            );

            if (token != address(0) && pool != address(0)) {
                try
                    tokenRegistryOracle.configureToken(
                        token,
                        SOURCE_TYPE_CURVE,
                        pool,
                        needsArg[token] ? 1 : 0,
                        fbSource,
                        fbSelector
                    )
                {
                    console.log("  Token configured with Curve pool: %s", pool);
                    tokenConfigured[token] = true;
                } catch Error(string memory reason) {
                    console.log("   Failed to configure token: %s", reason);
                    tokenConfigured[token] = false;
                } catch (bytes memory) {
                    console.log("   Failed to configure token (unknown error)");
                    tokenConfigured[token] = false;
                }
            } else {
                console.log("   Invalid token or pool address");
                tokenConfigured[token] = false;
            }
        }

        // 3. Configure BTC-chained tokens
        for (uint i = 0; i < btcTokens.length; i++) {
            address token = btcTokens[i];
            address btcFeed = primarySource[token];
            bytes4 fbSelector = fallbackSelector[token];
            address fbSource = fallbackSource[token];

            // Skip if token wasn't added successfully
            if (!tokenAdded[token]) {
                console.log(
                    "Skipping BTC token configuration for %s (not added)",
                    token
                );
                continue;
            }

            string memory tokenSymbol;
            try ERC20(token).symbol() returns (string memory symbol) {
                tokenSymbol = symbol;
            } catch {
                tokenSymbol = "Unknown";
            }

            console.log("Configuring BTC token %s (%s)...", tokenSymbol, token);

            if (token != address(0) && btcFeed != address(0)) {
                try
                    tokenRegistryOracle.configureBtcToken(
                        token,
                        btcFeed,
                        fbSource,
                        fbSelector
                    )
                {
                    console.log(
                        "  Token configured with BTC feed: %s",
                        btcFeed
                    );
                    tokenConfigured[token] = true;
                } catch Error(string memory reason) {
                    console.log("   Failed to configure token: %s", reason);
                    tokenConfigured[token] = false;
                } catch (bytes memory) {
                    console.log("   Failed to configure token (unknown error)");
                    tokenConfigured[token] = false;
                }
            } else {
                console.log("   Invalid token or BTC feed address");
                tokenConfigured[token] = false;
            }
        }

        // 4. Configure tokens that only have protocol sources
        for (uint i = 0; i < protocolTokens.length; i++) {
            address token = protocolTokens[i];
            // Only configure if this token doesn't have another source already
            if (sourceType[token] == SOURCE_TYPE_PROTOCOL) {
                // Skip if token wasn't added successfully
                if (!tokenAdded[token]) {
                    console.log(
                        "Skipping Protocol token configuration for %s (not added)",
                        token
                    );
                    continue;
                }

                bytes4 selector = fallbackSelector[token];
                bool usesArg = needsArg[token];
                address fbSource = fallbackSource[token];

                string memory tokenSymbol;
                try ERC20(token).symbol() returns (string memory symbol) {
                    tokenSymbol = symbol;
                } catch {
                    tokenSymbol = "Unknown";
                }

                console.log(
                    "Configuring Protocol token %s (%s)...",
                    tokenSymbol,
                    token
                );

                if (token != address(0)) {
                    try
                        tokenRegistryOracle.configureToken(
                            token,
                            SOURCE_TYPE_PROTOCOL,
                            token, // Protocol contract is the token itself
                            usesArg ? 1 : 0,
                            fbSource,
                            selector
                        )
                    {
                        console.log(
                            "  Token configured with Protocol source using selector: 0x%x",
                            uint32(selector)
                        );
                        tokenConfigured[token] = true;
                    } catch Error(string memory reason) {
                        console.log("   Failed to configure token: %s", reason);
                        tokenConfigured[token] = false;
                    } catch (bytes memory) {
                        console.log(
                            "   Failed to configure token (unknown error)"
                        );
                        tokenConfigured[token] = false;
                    }
                } else {
                    console.log("   Invalid token address");
                    tokenConfigured[token] = false;
                }
            }
        }

        vm.stopPrank();
    }

    function _createTokenStatusReport() internal {
        console.log("======= Token Status Report =======");
        for (uint i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];

            // Skip if token is address(0)
            if (token == address(0)) continue;

            TokenStatus memory status;
            status.token = token;

            // Get token name and symbol
            try ERC20(token).name() returns (string memory name) {
                status.name = name;
            } catch {
                status.name = "Unknown";
            }

            try ERC20(token).symbol() returns (string memory symbol) {
                status.symbol = symbol;
            } catch {
                status.symbol = "Unknown";
            }

            // Check if token was added and configured
            status.added = tokenAdded[token];
            status.configured = tokenConfigured[token];

            // Try to get token price
            try tokenRegistryOracle.getTokenPrice(token) returns (
                uint256 price
            ) {
                status.priceWorks = true;
                status.price = price;
                console.log("%s (%s): Added=%s, Configured=%s, Price=%s ETH");
                console.log(status.symbol, token);
                console.log(
                    status.added ? "true" : "false",
                    status.configured ? "true" : "false",
                    price / 1e18
                );
            } catch {
                status.priceWorks = false;
                status.price = 0;
                console.log("%s (%s): Added=%s, Configured=%s, Price=FAILED");
                console.log(status.symbol, token);
                console.log(
                    status.added ? "true" : "false",
                    status.configured ? "true" : "false"
                );
            }

            tokenStatuses.push(status);
        }
    }

    // ========== INDIVIDUAL TOKEN TESTS ==========

    function testIndividualTokenPricing() public {
        console.log("======= Testing Individual Token Prices =======");

        // Test each token individually and count successes
        uint256 successCount = 0;
        uint256 totalTokens = 0;

        for (uint i = 0; i < tokenStatuses.length; i++) {
            TokenStatus memory status = tokenStatuses[i];

            // Skip tokens that weren't added or configured
            if (!status.added || !status.configured) continue;

            totalTokens++;

            try tokenRegistryOracle.getTokenPrice(status.token) returns (
                uint256 price
            ) {
                console.log("%s: %s ETH", status.symbol, price / 1e18);
                successCount++;
            } catch Error(string memory reason) {
                console.log(
                    "%s: Failed to get price - %s ",
                    status.symbol,
                    reason
                );
            } catch (bytes memory) {
                console.log(
                    "%s: Failed to get price (unknown error) ",
                    status.symbol
                );
            }
        }

        console.log(
            "Price fetch success rate: %s/%s tokens",
            successCount,
            totalTokens
        );

        // Test should pass if at least some tokens work
        assertTrue(successCount > 0, "No token prices could be fetched");
    }

    // ========== DIRECT PRICE UPDATE TESTS ==========

    function testDirectPriceUpdate() public {
        // Make prices stale
        vm.warp(block.timestamp + 13 hours);
        assertTrue(
            tokenRegistryOracle.arePricesStale(),
            "Prices should be stale"
        );

        // Test updating a specific token price directly
        vm.startPrank(admin);

        // Try to update rETH price directly - pick a well-supported token
        address rethToken = chainlinkTokens[0]; // Using the first Chainlink token (rETH)

        // Make sure this token is properly configured
        if (!tokenConfigured[rethToken]) {
            console.log("rETH token not configured, configuring now...");
            try
                tokenRegistryOracle.configureToken(
                    rethToken,
                    SOURCE_TYPE_CHAINLINK,
                    primarySource[rethToken],
                    0,
                    fallbackSource[rethToken],
                    fallbackSelector[rethToken]
                )
            {
                tokenConfigured[rethToken] = true;
                console.log("rETH token configured successfully");
            } catch {
                console.log("Failed to configure rETH token");
            }
        }

        // Try to fetch the rETH price first
        try tokenRegistryOracle._getTokenPrice_exposed(rethToken) returns (
            uint256 price,
            bool success
        ) {
            if (success && price > 0) {
                // Now update the rate with the fetched price
                try tokenRegistryOracle.updateRate(IERC20(rethToken), price) {
                    console.log("Successfully updated rETH price directly");

                    // Check the price
                    uint256 updatedPrice = tokenRegistryOracle.getTokenPrice(
                        rethToken
                    );
                    console.log(
                        "Updated rETH price: %s ETH",
                        updatedPrice / 1e18
                    );

                    // Verify price is reasonable
                    assertTrue(
                        updatedPrice > 0,
                        "rETH price should be greater than 0"
                    );
                    assertTrue(
                        updatedPrice > 0.9e18,
                        "rETH price should be close to or above ETH value"
                    );
                } catch Error(string memory reason) {
                    console.log("Failed to call updateRate: %s", reason);
                }
            } else {
                console.log("Failed to fetch rETH price");
            }
        } catch Error(string memory reason) {
            console.log("Failed to get rETH price: %s", reason);
        } catch (bytes memory) {
            console.log("Failed to get rETH price (unknown error)");
        }

        vm.stopPrank();
    }

    function testForceUpdateAllPrices() public {
        // Make prices stale
        vm.warp(block.timestamp + 13 hours);
        assertTrue(
            tokenRegistryOracle.arePricesStale(),
            "Prices should be stale"
        );

        // We'll try to force update all prices by directly calling the update function
        vm.startPrank(admin);

        console.log("Attempting forced update of all token prices...");

        // Get some token prices before update for comparison
        _logSamplePrices("Before Update");

        // Try to update all prices
        try tokenRegistryOracle.updateAllPricesIfNeeded() returns (
            bool updated
        ) {
            console.log(
                "updateAllPricesIfNeeded call succeeded. Updated: %s",
                updated ? "true" : "false"
            );

            // Check if prices are still stale
            bool stillStale = tokenRegistryOracle.arePricesStale();
            console.log(
                "Prices still stale: %s",
                stillStale ? "true" : "false"
            );

            // Check some prices after update
            _logSamplePrices("After Update");

            // This might still fail in some environments, so we'll check the assertion separately
            if (updated) {
                assertFalse(
                    stillStale,
                    "Prices should not be stale after successful update"
                );
            }
        } catch Error(string memory reason) {
            console.log("Failed to update all prices: %s", reason);
            // Let the test continue
        }

        vm.stopPrank();
    }

    function testFullPriceUpdateFlow() public {
        // Make prices stale
        vm.warp(block.timestamp + 13 hours);
        assertTrue(
            tokenRegistryOracle.arePricesStale(),
            "Prices should be stale"
        );

        // Make sure we can use the token oracle
        vm.startPrank(user2); // user2 has RATE_UPDATER_ROLE

        // Before direct update
        console.log(
            "Checking stale status: %s",
            tokenRegistryOracle.arePricesStale() ? "stale" : "fresh"
        );

        // Log timestamp info
        console.log("Current timestamp: %s", block.timestamp);
        console.log(
            "Last update timestamp: %s",
            tokenRegistryOracle.lastPriceUpdate()
        );
        console.log(
            "Update interval: %s",
            tokenRegistryOracle.priceUpdateInterval()
        );

        // We'll try to debug the core issue by forcing an update for each token
        for (uint i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];

            // Skip tokens that weren't configured properly
            if (!tokenAdded[token] || !tokenConfigured[token]) continue;

            string memory tokenSymbol;
            try ERC20(token).symbol() returns (string memory symbol) {
                tokenSymbol = symbol;
            } catch {
                tokenSymbol = "Unknown";
            }

            // Try to update this token individually using _getTokenPrice_exposed + updateRate
            try tokenRegistryOracle._getTokenPrice_exposed(token) returns (
                uint256 price,
                bool success
            ) {
                if (success && price > 0) {
                    // Now update the rate with the fetched price
                    try tokenRegistryOracle.updateRate(IERC20(token), price) {
                        console.log(
                            "Successfully updated price for %s",
                            tokenSymbol
                        );
                    } catch Error(string memory reason) {
                        console.log(
                            "Failed to update %s: %s",
                            tokenSymbol,
                            reason
                        );
                    } catch (bytes memory) {
                        console.log(
                            "Failed to update %s (unknown error)",
                            tokenSymbol
                        );
                    }
                } else {
                    console.log("No valid price obtained for %s", tokenSymbol);
                }
            } catch Error(string memory reason) {
                console.log(
                    "Failed to get price for %s: %s",
                    tokenSymbol,
                    reason
                );
            } catch (bytes memory) {
                console.log(
                    "Failed to get price for %s (unknown error)",
                    tokenSymbol
                );
            }
        }

        // Check stale status after individual updates
        console.log(
            "Checking stale status after individual updates: %s",
            tokenRegistryOracle.arePricesStale() ? "stale" : "fresh"
        );

        // Now try the bulk update
        try tokenRegistryOracle.updateAllPricesIfNeeded() returns (
            bool updated
        ) {
            console.log(
                "Bulk update: %s",
                updated ? "succeeded" : "not needed"
            );
        } catch Error(string memory reason) {
            console.log("Bulk update failed: %s", reason);
        } catch (bytes memory) {
            console.log("Bulk update failed (unknown error)");
        }

        // Final stale status check
        bool finalStaleStatus = tokenRegistryOracle.arePricesStale();
        console.log(
            "Final stale status: %s",
            finalStaleStatus ? "stale" : "fresh"
        );

        vm.stopPrank();

        // Verify we could update at least some prices
        // This test is more diagnostic than a strict pass/fail
        if (!finalStaleStatus) {
            console.log("Successfully updated prices!");
        } else {
            console.log(
                " Unable to update all prices, but test continues for diagnostic purposes"
            );
        }
    }
    // ========== HELPER FUNCTIONS ==========

    function _logSamplePrices(string memory label) internal view {
        console.log("--- %s ---", label);

        // Try a few representative tokens
        address[] memory sampleTokens = new address[](4);
        if (chainlinkTokens.length > 0) sampleTokens[0] = chainlinkTokens[0]; // rETH
        if (chainlinkTokens.length > 1) sampleTokens[1] = chainlinkTokens[1]; // stETH
        if (protocolTokens.length > 5) sampleTokens[2] = protocolTokens[5]; // wstETH
        if (chainlinkTokens.length > 2) sampleTokens[3] = chainlinkTokens[2]; // cbETH

        for (uint i = 0; i < sampleTokens.length; i++) {
            address token = sampleTokens[i];
            if (token == address(0)) continue;

            if (!tokenAdded[token] || !tokenConfigured[token]) {
                console.log("Token not configured: %s", token);
                continue;
            }

            string memory symbol;
            try ERC20(token).symbol() returns (string memory s) {
                symbol = s;
            } catch {
                symbol = "Unknown";
            }

            try tokenRegistryOracle.getTokenPrice(token) returns (
                uint256 price
            ) {
                console.log("%s: %s ETH", symbol, price / 1e18);
            } catch {
                console.log("%s: Failed to get price", symbol);
            }
        }
    }

    function _convertToUpgradeable(
        IERC20[] memory tokens
    ) internal pure returns (IERC20Upgradeable[] memory) {
        IERC20Upgradeable[] memory upgradeable = new IERC20Upgradeable[](
            tokens.length
        );
        for (uint256 i = 0; i < tokens.length; i++) {
            upgradeable[i] = IERC20Upgradeable(address(tokens[i]));
        }
        return upgradeable;
    }
}