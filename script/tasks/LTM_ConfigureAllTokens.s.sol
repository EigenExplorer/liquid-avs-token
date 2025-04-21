// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {LiquidTokenManager} from "../../src/core/LiquidTokenManager.sol";
import {TokenRegistryOracle} from "../../src/utils/TokenRegistryOracle.sol";

/// @title ConfigureAllTokens
/// @notice Network-aware configuration task for tokens with verified price sources
contract ConfigureAllTokens is Script, Test {
    // Source types
    uint8 constant SOURCE_TYPE_CHAINLINK = 1;
    uint8 constant SOURCE_TYPE_CURVE = 2;
    uint8 constant SOURCE_TYPE_BTC_CHAINED = 3;
    uint8 constant SOURCE_TYPE_PROTOCOL = 4;

    // Default amount for protocols that need arguments
    uint256 constant DEFAULT_AMOUNT = 1e18;

    // Function selectors
    bytes4 constant SELECTOR_GET_EXCHANGE_RATE = 0x8af07e89; // getExchangeRate()
    bytes4 constant SELECTOR_GET_POOLED_ETH_BY_SHARES = 0x7a28fb88; // getPooledEthByShares(uint256)
    bytes4 constant SELECTOR_EXCHANGE_RATE = 0xbd6d894d; // exchangeRate()
    bytes4 constant SELECTOR_STETH_PER_TOKEN = 0xcd55c2ad; // stEthPerToken()
    bytes4 constant SELECTOR_RATIO = 0xce1e09c0; // ratio()
    bytes4 constant SELECTOR_CONVERT_TO_ASSETS = 0x07a2d13a; // convertToAssets(uint256)
    bytes4 constant SELECTOR_SWETH_TO_ETH_RATE = 0xd65ab1f6; // swETHToETHRate()
    bytes4 constant SELECTOR_UNDERLYING_BALANCE_FROM_SHARES = 0x0a8a5f53; // underlyingBalanceFromShares(uint256)
    bytes4 constant SELECTOR_GET_RATE = 0x679aefce; // getRate()
    bytes4 constant SELECTOR_METH_TO_ETH = 0xf961a013; // mETHToETH(uint256)
    bytes4 constant SELECTOR_GET_PRICE_PER_FULL_SHARE = 0x77c7b8fc; // getPricePerFullShare()

    // Feeds - Mainnet
    address constant BTC_ETH_FEED = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Token configuration with all necessary parameters for both oracle and manager
    struct TokenConfig {
        string name;
        address token;
        uint8 decimals;
        uint256 initialPrice;
        uint256 volatilityThreshold;
        address strategy;
        uint8 sourceType;
        address primarySource;
        uint8 needsArg;
        address fallbackSource;
        bytes4 fallbackSelector;
        bool isBtcToken; // Used for mainnet BTC tokens
        uint256 observedRate; // Used for Holesky observed test rates
    }

    /**
     * @notice Main entry point for configuring tokens
     * @param configFileName Path to the deployment configuration file
     */
    function run(string memory configFileName) public {
        string memory configPath = string(
            bytes(string.concat("script/outputs", configFileName))
        );
        string memory config = vm.readFile(configPath);

        // Get contract addresses from deployment data
        address liquidTokenManagerAddress = stdJson.readAddress(
            config,
            ".contractDeployments.proxy.liquidTokenManager.address"
        );
        address tokenRegistryOracleAddress = stdJson.readAddress(
            config,
            ".contractDeployments.proxy.tokenRegistryOracle.address"
        );

        // Load contract instances
        LiquidTokenManager liquidTokenManager = LiquidTokenManager(
            liquidTokenManagerAddress
        );
        TokenRegistryOracle tokenRegistryOracle = TokenRegistryOracle(
            tokenRegistryOracleAddress
        );

        // Detect network based on NETWORK environment variable
        string memory networkEnv;
        bool isMainnet = false;
        bool isHolesky = false;

        try vm.envString("NETWORK") returns (string memory value) {
            networkEnv = value;
            if (keccak256(bytes(networkEnv)) == keccak256(bytes("mainnet"))) {
                isMainnet = true;
                console.log(
                    "Using mainnet configuration (from NETWORK env var)"
                );
            } else if (
                keccak256(bytes(networkEnv)) == keccak256(bytes("holesky"))
            ) {
                isHolesky = true;
                console.log(
                    "Using holesky configuration (from NETWORK env var)"
                );
            } else {
                console.log("NETWORK env var found: %s", networkEnv);
            }
        } catch {
            console.log(
                "NETWORK env var not found, falling back to chain ID detection"
            );
        }

        // If NETWORK not set, use chain ID detection as fallback
        if (!isMainnet && !isHolesky) {
            uint256 chainId = block.chainid;
            if (chainId == 1) {
                isMainnet = true;
                console.log("Detected mainnet (chainId: 1)");
            } else if (chainId == 17000) {
                isHolesky = true;
                console.log("Detected holesky (chainId: 17000)");
            } else if (chainId == 31337) {
                // Local Anvil - try to guess from config filename
                if (
                    bytes(configFileName).length > 0 &&
                    (bytes(config).length > 0 && bytes(config)[0] != 0)
                ) {
                    // Check config for "holesky" as last resort
                    if (indexOf(config, "holesky") != -1) {
                        isHolesky = true;
                        console.log(
                            "Detected Anvil fork of Holesky (from config content)"
                        );
                    } else {
                        isMainnet = true;
                        console.log(
                            "Detected Anvil fork of Mainnet (default for Anvil)"
                        );
                    }
                } else {
                    isMainnet = true;
                    console.log("Defaulting to Mainnet configuration");
                }
            } else {
                revert("Unsupported network and no NETWORK env var set");
            }
        }

        // Get the appropriate token configurations
        TokenConfig[] memory tokens;
        if (isMainnet) {
            console.log("=== CONFIGURING MAINNET TOKENS ===");
            tokens = getMainnetTokenConfigs();
        } else if (isHolesky) {
            console.log("=== CONFIGURING HOLESKY TOKENS ===");
            tokens = getHoleskyTokenConfigs();
        } else {
            revert("No network configuration selected");
        }

        vm.startBroadcast();

        console.log("LiquidTokenManager: %s", liquidTokenManagerAddress);
        console.log("TokenRegistryOracle: %s", tokenRegistryOracleAddress);
        console.log("Configuring %d tokens", tokens.length);

        // Configure each token
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenConfig memory config = tokens[i];
            console.log(
                "\nProcessing %s (%s)",
                config.name,
                addressToString(config.token)
            );

            // Check if token is already added to LiquidTokenManager
            bool isTokenSupported = false;
            try liquidTokenManager.getTokenInfo(IERC20(config.token)) returns (
                LiquidTokenManager.TokenInfo memory
            ) {
                isTokenSupported = true;
                console.log("Token already configured in LiquidTokenManager");
            } catch {}

            if (!isTokenSupported) {
                console.log("Adding token to LiquidTokenManager");

                try
                    liquidTokenManager.addToken(
                        IERC20(config.token),
                        config.decimals,
                        config.initialPrice,
                        config.volatilityThreshold,
                        IStrategy(config.strategy),
                        config.sourceType,
                        config.primarySource,
                        config.needsArg,
                        config.fallbackSource,
                        config.fallbackSelector
                    )
                {
                    console.log("Successfully added token");

                    // Check if we can get the price
                    try
                        tokenRegistryOracle.getTokenPrice(address(config.token))
                    returns (uint256 price) {
                        console.log("Verified price: %s ETH", formatEth(price));
                    } catch Error(string memory reason) {
                        console.log("Failed to get price: %s", reason);
                    } catch {
                        console.log("Failed to get price (unknown error)");
                    }
                } catch Error(string memory reason) {
                    console.log("Failed to add token: %s", reason);
                } catch {
                    console.log("Failed to add token (unknown error)");
                }
            } else {
                // In case the token was added but the price source wasn't configured correctly
                try
                    tokenRegistryOracle.configureToken(
                        config.token,
                        config.sourceType,
                        config.primarySource,
                        config.needsArg,
                        config.fallbackSource,
                        config.fallbackSelector
                    )
                {
                    console.log("Updated token price source configuration");

                    // Check if we can get the price
                    try
                        tokenRegistryOracle.getTokenPrice(address(config.token))
                    returns (uint256 price) {
                        console.log("Verified price: %s ETH", formatEth(price));
                    } catch Error(string memory reason) {
                        console.log("Failed to get price: %s", reason);
                    } catch {
                        console.log("Failed to get price (unknown error)");
                    }
                } catch Error(string memory reason) {
                    console.log("Failed to update price source: %s", reason);
                } catch {
                    console.log(
                        "Failed to update price source (unknown error)"
                    );
                }
            }
        }

        vm.stopBroadcast();
        console.log("\n=== TOKEN CONFIGURATION COMPLETE ===");
    }

    /**
     * @notice Helper function to find substring in string
     * @param haystack The string to search in
     * @param needle The substring to search for
     * @return position The position of the substring or -1 if not found
     */
    function indexOf(
        string memory haystack,
        string memory needle
    ) internal pure returns (int) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length > haystackBytes.length) {
            return -1;
        }

        for (uint i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool isMatched = true;
            for (uint j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    isMatched = false;
                    break;
                }
            }
            if (isMatched) {
                return int(i);
            }
        }
        return -1;
    }

    /**
     * @notice Get configurations for mainnet tokens based on test results
     * @return Array of token configurations
     */
    function getMainnetTokenConfigs()
        internal
        pure
        returns (TokenConfig[] memory)
    {
        TokenConfig[] memory configs = new TokenConfig[](15);

        // Strategy addresses
        address ethLSTStrategy = 0x1111111111111111111111111111111111111111;
        address btcTokenStrategy = 0x2222222222222222222222222222222222222222;
        uint256 defaultVolatilityThreshold = 5e16; // 5% threshold

        // 1. rETH - VERIFIED CORRECT
        configs[0] = TokenConfig({
            name: "rETH",
            token: 0xae78736Cd615f374D3085123A210448E74Fc6393,
            decimals: 18,
            initialPrice: 1080000000000000000, // 1.08 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0x536218f9E9Eb48863970252233c8F271f554C2d0, // CHAINLINK_RETH_ETH
            needsArg: 0,
            fallbackSource: 0xae78736Cd615f374D3085123A210448E74Fc6393,
            fallbackSelector: SELECTOR_GET_EXCHANGE_RATE,
            isBtcToken: false,
            observedRate: 0
        });

        // 2. stETH - VERIFIED CORRECT
        configs[1] = TokenConfig({
            name: "stETH",
            token: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            decimals: 18,
            initialPrice: 1030000000000000000, // 1.03 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812, // CHAINLINK_STETH_ETH
            needsArg: 1,
            fallbackSource: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            fallbackSelector: SELECTOR_GET_POOLED_ETH_BY_SHARES,
            isBtcToken: false,
            observedRate: 0
        });

        // 3. cbETH - VERIFIED CORRECT
        configs[2] = TokenConfig({
            name: "cbETH",
            token: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704,
            decimals: 18,
            initialPrice: 1040000000000000000, // 1.04 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b, // CHAINLINK_CBETH_ETH
            needsArg: 0,
            fallbackSource: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704,
            fallbackSelector: SELECTOR_EXCHANGE_RATE,
            isBtcToken: false,
            observedRate: 0
        });

        // 4. wstETH - VERIFIED CORRECT
        configs[3] = TokenConfig({
            name: "wstETH",
            token: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            decimals: 18,
            initialPrice: 1150000000000000000, // 1.15 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            needsArg: 0,
            fallbackSource: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            fallbackSelector: SELECTOR_STETH_PER_TOKEN,
            isBtcToken: false,
            observedRate: 0
        });

        // 5. METH - VERIFIED CORRECT
        configs[4] = TokenConfig({
            name: "METH",
            token: 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f,
            decimals: 18,
            initialPrice: 1020000000000000000, // 1.02 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0x5b563107C8666d2142C216114228443B94152362, // CHAINLINK_METH_ETH
            needsArg: 1,
            fallbackSource: 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f,
            fallbackSelector: SELECTOR_METH_TO_ETH,
            isBtcToken: false,
            observedRate: 0
        });

        // 6. osETH - CORRECTED
        configs[5] = TokenConfig({
            name: "osETH",
            token: 0x0C4576Ca1c365868E162554AF8e385dc3e7C66D9, // Token address
            decimals: 18,
            initialPrice: 1050000000000000000, // 1.05 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d, // CORRECTED: OS_ETH_CURVE_POOL from test
            needsArg: 1,
            fallbackSource: 0x2A261e60FB14586B474C208b1B7AC6D0f5000306, // CORRECTED: Protocol contract from test
            fallbackSelector: SELECTOR_CONVERT_TO_ASSETS,
            isBtcToken: false,
            observedRate: 0
        });

        // 7. ETHx - CORRECTED
        configs[6] = TokenConfig({
            name: "ETHx",
            token: 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b, // Token address
            decimals: 18,
            initialPrice: 1060000000000000000, // 1.06 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492, // CORRECTED: ETHX_CURVE_POOL from test
            needsArg: 0, // CORRECTED: Does not need arg for getExchangeRate
            fallbackSource: 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737, // CORRECTED: Implementation contract from test
            fallbackSelector: SELECTOR_GET_EXCHANGE_RATE, // CORRECTED: Proper selector based on test
            isBtcToken: false,
            observedRate: 0
        });

        // 8. swETH - CORRECTED
        configs[7] = TokenConfig({
            name: "swETH",
            token: 0xf951E335afb289353dc249e82926178EaC7DEd78,
            decimals: 18,
            initialPrice: 1030000000000000000, // 1.03 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL, // CORRECTED: Use protocol directly since Curve failed
            primarySource: 0xf951E335afb289353dc249e82926178EaC7DEd78, // CORRECTED: Use token itself as primary
            needsArg: 0,
            fallbackSource: 0xf951E335afb289353dc249e82926178EaC7DEd78,
            fallbackSelector: SELECTOR_SWETH_TO_ETH_RATE,
            isBtcToken: false,
            observedRate: 0
        });

        // 9. lsETH - CORRECTED
        configs[8] = TokenConfig({
            name: "lsETH",
            token: 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549,
            decimals: 18,
            initialPrice: 1010000000000000000, // 1.01 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL, // CORRECTED: Use protocol directly since Curve failed
            primarySource: 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549, // CORRECTED: Use token as primary
            needsArg: 1,
            fallbackSource: 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549,
            fallbackSelector: SELECTOR_UNDERLYING_BALANCE_FROM_SHARES,
            isBtcToken: false,
            observedRate: 0
        });

        // 10. ankrETH - VERIFIED CORRECT
        configs[9] = TokenConfig({
            name: "ankrETH",
            token: 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb,
            decimals: 18,
            initialPrice: 1020000000000000000, // 1.02 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2, // ANKR_ETH_CURVE_POOL
            needsArg: 0,
            fallbackSource: 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb,
            fallbackSelector: SELECTOR_RATIO,
            isBtcToken: false,
            observedRate: 0
        });

        // 11. OETH - CORRECTED
        configs[10] = TokenConfig({
            name: "OETH",
            token: 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3,
            decimals: 18,
            initialPrice: 1050000000000000000, // 1.05 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0x703118C4CbccCBF2AB31913e0f8075fbbb15f563, // CHAINLINK_OETH_ETH
            needsArg: 1,
            fallbackSource: 0xDcEe70654261AF21C44c093C300eD3Bb97b78192, // CORRECTED: Protocol contract from test
            fallbackSelector: SELECTOR_CONVERT_TO_ASSETS,
            isBtcToken: false,
            observedRate: 0
        });

        // 12. wbETH
        configs[11] = TokenConfig({
            name: "wbETH",
            token: 0xa2E3356610840701BDf5611a53974510Ae27E2e1,
            decimals: 18,
            initialPrice: 1070000000000000000, // 1.07 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: 0xa2E3356610840701BDf5611a53974510Ae27E2e1,
            needsArg: 0,
            fallbackSource: 0xa2E3356610840701BDf5611a53974510Ae27E2e1,
            fallbackSelector: SELECTOR_GET_RATE,
            isBtcToken: false,
            observedRate: 0
        });

        // 13. uniBTC (BTC token) - CORRECTED
        configs[12] = TokenConfig({
            name: "uniBTC",
            token: 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568,
            decimals: 18,
            initialPrice: 30000000000000000000, // 30 ETH (BTC price in ETH)
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: btcTokenStrategy,
            sourceType: SOURCE_TYPE_BTC_CHAINED,
            primarySource: 0x861d15F8a4059cb918bD6F3670adAEB1220B298f, // CHAINLINK_UNIBTC_BTC
            needsArg: 0,
            fallbackSource: 0x004E9C3EF86bc1ca1f0bB5C7662861Ee93350568,
            fallbackSelector: SELECTOR_GET_PRICE_PER_FULL_SHARE,
            isBtcToken: true,
            observedRate: 0
        });

        // 14. stBTC (BTC token) - CORRECTED
        configs[13] = TokenConfig({
            name: "stBTC",
            token: 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3,
            decimals: 18,
            initialPrice: 30000000000000000000, // 30 ETH (BTC price in ETH)
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: btcTokenStrategy,
            sourceType: SOURCE_TYPE_BTC_CHAINED,
            primarySource: 0xD93571A6201978976e37c4A0F7bE17806f2Feab2, // CHAINLINK_STBTC_BTC
            needsArg: 1,
            fallbackSource: 0xdF217EFD8f3ecb5E837aedF203C28c1f06854017, // CORRECTED: Should use vault from test
            fallbackSelector: SELECTOR_CONVERT_TO_ASSETS,
            isBtcToken: true,
            observedRate: 0
        });

        // 15. sfrxETH - VERIFIED CORRECT
        configs[14] = TokenConfig({
            name: "sfrxETH",
            token: 0xac3E018457B222d93114458476f3E3416Abbe38F,
            decimals: 18,
            initialPrice: 1100000000000000000, // 1.10 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: 0xac3E018457B222d93114458476f3E3416Abbe38F,
            needsArg: 1,
            fallbackSource: 0xac3E018457B222d93114458476f3E3416Abbe38F,
            fallbackSelector: SELECTOR_CONVERT_TO_ASSETS,
            isBtcToken: false,
            observedRate: 0
        });

        return configs;
    }

    /**
     * @notice Get configurations for Holesky testnet tokens based on test results
     * @return Array of token configurations
     */
    function getHoleskyTokenConfigs()
        internal
        pure
        returns (TokenConfig[] memory)
    {
        TokenConfig[] memory configs = new TokenConfig[](5);

        // Strategy address for Holesky
        address holeskyEthLstStrategy = 0x1111111111111111111111111111111111111111;
        uint256 defaultVolatilityThreshold = 5e16; // 5% threshold

        // Token addresses - Holesky with correct checksums
        address RETH = 0x7322c24752f79c05FFD1E2a6FCB97020C1C264F1;
        address STETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
        address LSETH = 0x1d8b30cC38Dba8aBce1ac29Ea27d9cFd05379A09;
        address ANKR_ETH = 0x8783C9C904e1bdC87d9168AE703c8481E8a477Fd;
        address SFRXETH = 0xa63f56985F9C7F3bc9fFc5685535649e0C1a55f3;

        // 1. rETH - Worked with getExchangeRate()
        configs[0] = TokenConfig({
            name: "rETH",
            token: RETH,
            decimals: 18,
            initialPrice: 967200000000000000, // 0.9672 ETH as observed in test
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: holeskyEthLstStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: RETH, // Using the token itself as the primary source
            needsArg: 0, // Function doesn't require args
            fallbackSource: RETH, // Same fallback
            fallbackSelector: SELECTOR_GET_EXCHANGE_RATE,
            isBtcToken: false,
            observedRate: 967200000000000000 // 0.9672 ETH
        });

        // 2. stETH - Worked with getPooledEthByShares()
        configs[1] = TokenConfig({
            name: "stETH",
            token: STETH,
            decimals: 18,
            initialPrice: 848500000000000000, // 0.8485 ETH as observed in test
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: holeskyEthLstStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: STETH, // Using the token itself as the primary source
            needsArg: 1, // Function requires an argument
            fallbackSource: STETH, // Same fallback
            fallbackSelector: SELECTOR_GET_POOLED_ETH_BY_SHARES,
            isBtcToken: false,
            observedRate: 848500000000000000 // 0.8485 ETH
        });

        // 3. lsETH - Worked with underlyingBalanceFromShares()
        configs[2] = TokenConfig({
            name: "lsETH",
            token: LSETH,
            decimals: 18,
            initialPrice: 1020100000000000000, // 1.0201 ETH as observed in test
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: holeskyEthLstStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: LSETH, // Using the token itself as the primary source
            needsArg: 1, // Function requires an argument
            fallbackSource: LSETH, // Same fallback
            fallbackSelector: SELECTOR_UNDERLYING_BALANCE_FROM_SHARES,
            isBtcToken: false,
            observedRate: 1020100000000000000 // 1.0201 ETH
        });

        // 4. ankrETH - Worked with ratio()
        configs[3] = TokenConfig({
            name: "ankrETH",
            token: ANKR_ETH,
            decimals: 18,
            initialPrice: 1000000000000000000, // 1.0000 ETH as observed in test
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: holeskyEthLstStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: ANKR_ETH, // Using the token itself as the primary source
            needsArg: 0, // Function doesn't require args
            fallbackSource: ANKR_ETH, // Same fallback
            fallbackSelector: SELECTOR_RATIO,
            isBtcToken: false,
            observedRate: 1000000000000000000 // 1.0000 ETH
        });

        // 5. sfrxETH - Worked with convertToAssets()
        configs[4] = TokenConfig({
            name: "sfrxETH",
            token: SFRXETH,
            decimals: 18,
            initialPrice: 1138000000000000000, // 1.1380 ETH as observed in test
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: holeskyEthLstStrategy,
            sourceType: SOURCE_TYPE_PROTOCOL,
            primarySource: SFRXETH, // Using the token itself as the primary source
            needsArg: 1, // Function requires an argument
            fallbackSource: SFRXETH, // Same fallback
            fallbackSelector: SELECTOR_CONVERT_TO_ASSETS,
            isBtcToken: false,
            observedRate: 1138000000000000000 // 1.1380 ETH
        });

        return configs;
    }

    // Helper function to format ETH values with 4 decimal places
    function formatEth(uint256 amount) internal pure returns (string memory) {
        if (amount == 0) return "0.0000";

        uint256 whole = amount / 1e18;
        uint256 fraction = (amount % 1e18) / 1e14;
        return
            string(
                abi.encodePacked(
                    vm.toString(whole),
                    ".",
                    fraction < 10
                        ? "000"
                        : fraction < 100
                            ? "00"
                            : fraction < 1000
                                ? "0"
                                : "",
                    vm.toString(fraction)
                )
            );
    }

    // Helper function to convert address to string
    function addressToString(
        address _addr
    ) internal pure returns (string memory) {
        bytes memory result = new bytes(42);
        result[0] = 0x30; // ASCII for '0'
        result[1] = 0x78; // ASCII for 'x'

        bytes memory alphabet = "0123456789abcdef";
        uint160 addr = uint160(_addr);
        for (uint i = 0; i < 20; i++) {
            uint8 value = uint8(addr & 0xff);
            result[2 + i * 2] = alphabet[value >> 4];
            result[2 + i * 2 + 1] = alphabet[value & 0x0f];
            addr = addr >> 8;
        }

        return string(result);
    }
}