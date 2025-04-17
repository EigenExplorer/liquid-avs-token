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
/// @notice Comprehensive task to configure all tokens and add them to LiquidTokenManager
/// @dev Run with:
/// forge script --via-ir script/tasks/LTM_ConfigureAllTokens.s.sol:ConfigureAllTokens --rpc-url $RPC_URL --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(string)" -- "/local/deployment_data.json" -vvvv
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
    bytes4 constant SELECTOR_EXCHANGE_RATE = 0x3ba0b9a9; // exchangeRate()
    bytes4 constant SELECTOR_CONVERT_TO_ASSETS = 0x07a2d13a; // convertToAssets(uint256)
    bytes4 constant SELECTOR_SWETH_TO_ETH_RATE = 0x8d928af8; // swETHToETHRate()
    bytes4 constant SELECTOR_STETH_PER_TOKEN = 0x035faf82; // stEthPerToken()
    bytes4 constant SELECTOR_RATIO = 0xce1e09c0; // ratio()
    bytes4 constant SELECTOR_UNDERLYING_BALANCE_FROM_SHARES = 0x0a8a5f53; // underlyingBalanceFromShares(uint256)
    bytes4 constant SELECTOR_METH_TO_ETH = 0xc9f04442; // mETHToETH(uint256)
    bytes4 constant SELECTOR_GET_RATE = 0x679aefce; // getRate()

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
        bool isBtcToken; // If true, will use configureBtcToken instead
    }

    /**
     * @notice Main entry point for configuring all tokens
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

        // Set BTC/ETH feed first as it's needed for BTC tokens
        address CHAINLINK_BTC_ETH = 0xdeb288F737066589598e9214E782fa5A8eD689e8;

        vm.startBroadcast();

        // Set the BTC/ETH feed
        tokenRegistryOracle.setBtcEthFeed(CHAINLINK_BTC_ETH);
        console.log("Set BTC/ETH feed to %s", CHAINLINK_BTC_ETH);

        // Get token configurations
        TokenConfig[] memory tokens = getTokenConfigs();
        console.log("Configuring %d tokens", tokens.length);

        // Configure each token
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenConfig memory config = tokens[i];

            // Check if token is already added to LiquidTokenManager
            bool isTokenSupported = false;
            try liquidTokenManager.getTokenInfo(IERC20(config.token)) returns (
                LiquidTokenManager.TokenInfo memory
            ) {
                isTokenSupported = true;
            } catch {}

            if (!isTokenSupported) {
                console.log("Adding %s to LiquidTokenManager", config.name);

                if (config.isBtcToken) {
                    // Add as BTC token
                    try
                        liquidTokenManager.addBtcToken(
                            IERC20(config.token),
                            config.decimals,
                            config.initialPrice,
                            config.volatilityThreshold,
                            IStrategy(config.strategy),
                            config.primarySource, // BTC feed
                            config.fallbackSource,
                            config.fallbackSelector
                        )
                    {
                        console.log(
                            "Successfully added BTC token %s",
                            config.name
                        );
                    } catch Error(string memory reason) {
                        console.log(
                            "Failed to add BTC token %s: %s",
                            config.name,
                            reason
                        );
                    } catch {
                        console.log(
                            "Failed to add BTC token %s (unknown error)",
                            config.name
                        );
                    }
                } else {
                    // Add as regular ETH token
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
                        console.log("Successfully added token %s", config.name);
                    } catch Error(string memory reason) {
                        console.log(
                            "Failed to add token %s: %s",
                            config.name,
                            reason
                        );
                    } catch {
                        console.log(
                            "Failed to add token %s (unknown error)",
                            config.name
                        );
                    }
                }
            } else {
                console.log(
                    "%s already configured in LiquidTokenManager, skipping",
                    config.name
                );

                // In case the token was added but the price source wasn't configured correctly
                // in the token registry oracle, we'll try to configure it
                if (config.isBtcToken) {
                    try
                        tokenRegistryOracle.configureBtcToken(
                            config.token,
                            config.primarySource,
                            config.fallbackSource,
                            config.fallbackSelector
                        )
                    {
                        console.log(
                            "Updated BTC token source for %s",
                            config.name
                        );
                    } catch {}
                } else {
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
                        console.log("Updated token source for %s", config.name);
                    } catch {}
                }
            }
        }

        vm.stopBroadcast();
        console.log("Token configuration complete!");
    }

    /**
     * @notice Get configurations for all tokens
     * @return Array of token configurations
     */
    function getTokenConfigs() internal pure returns (TokenConfig[] memory) {
        TokenConfig[] memory configs = new TokenConfig[](14);

        // Strategy addresses - we need to replace them as i randomly put these**********
        address ethLSTStrategy = 0x1111111111111111111111111111111111111111;
        address btcTokenStrategy = 0x2222222222222222222222222222222222222222;
        uint256 defaultVolatilityThreshold = 5e16; // 5% threshold

        // 1. rETH
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
            fallbackSource: 0xae78736Cd615f374D3085123A210448E74Fc6393, // rETH address for fallback
            fallbackSelector: SELECTOR_GET_EXCHANGE_RATE,
            isBtcToken: false
        });

        // 2. stETH
        configs[1] = TokenConfig({
            name: "stETH",
            token: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            decimals: 18,
            initialPrice: 1030000000000000000, // 1.03 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812, // CHAINLINK_STETH_ETH
            needsArg: 0,
            fallbackSource: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stETH for fallback
            fallbackSelector: SELECTOR_GET_POOLED_ETH_BY_SHARES,
            isBtcToken: false
        });

        // 3. cbETH
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
            fallbackSource: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704, // cbETH for fallback
            fallbackSelector: SELECTOR_EXCHANGE_RATE,
            isBtcToken: false
        });

        // 4. wstETH
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
            fallbackSource: address(0),
            fallbackSelector: SELECTOR_STETH_PER_TOKEN,
            isBtcToken: false
        });

        // 5. METH
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
            isBtcToken: false
        });

        // 6. osETH
        configs[5] = TokenConfig({
            name: "osETH",
            token: 0x2A261e60FB14586B474C208b1B7AC6D0f5000306,
            decimals: 18,
            initialPrice: 1050000000000000000, // 1.05 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0xC2A6798447BB70E5abCf1b0D6aeeC90BC14FCA55, // OSETH_CURVE_POOL
            needsArg: 0,
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: false
        });

        // 7. ETHx
        configs[6] = TokenConfig({
            name: "ETHx",
            token: 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737,
            decimals: 18,
            initialPrice: 1060000000000000000, // 1.06 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0x64939a882C7d1b096241678b7a3A57eD19445485, // ETHx_CURVE_POOL
            needsArg: 0,
            fallbackSource: 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737,
            fallbackSelector: SELECTOR_CONVERT_TO_ASSETS,
            isBtcToken: false
        });

        // 8. swETH
        configs[7] = TokenConfig({
            name: "swETH",
            token: 0xf951E335afb289353dc249e82926178EaC7DEd78,
            decimals: 18,
            initialPrice: 1030000000000000000, // 1.03 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0x8d30BE1e51882688ee8F976DeB9bdd411b74BEf3, // SWETH_CURVE_POOL
            needsArg: 0,
            fallbackSource: 0xf951E335afb289353dc249e82926178EaC7DEd78,
            fallbackSelector: SELECTOR_SWETH_TO_ETH_RATE,
            isBtcToken: false
        });

        // 9. lsETH
        configs[8] = TokenConfig({
            name: "lsETH",
            token: 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549,
            decimals: 18,
            initialPrice: 1010000000000000000, // 1.01 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CURVE,
            primarySource: 0x6c60d69348f3430bE4B7cf0155a4FD8f6CA9353B, // LSETH_CURVE_POOL
            needsArg: 0,
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: false
        });

        // 10. ankrETH
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
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: false
        });

        // 11. OETH
        configs[10] = TokenConfig({
            name: "OETH",
            token: 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3,
            decimals: 18,
            initialPrice: 1050000000000000000, // 1.05 ETH
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: ethLSTStrategy,
            sourceType: SOURCE_TYPE_CHAINLINK,
            primarySource: 0x703118C4CbccCBF2AB31913e0f8075fbbb15f563, // CHAINLINK_OETH_ETH
            needsArg: 0,
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: false
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
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: false
        });

        // 13. uniBTC (BTC token)
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
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: true
        });

        // 14. stBTC (BTC token)
        configs[13] = TokenConfig({
            name: "stBTC",
            token: 0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3,
            decimals: 18,
            initialPrice: 30000000000000000000, // 30 ETH (BTC price in ETH)
            volatilityThreshold: defaultVolatilityThreshold,
            strategy: btcTokenStrategy,
            sourceType: SOURCE_TYPE_BTC_CHAINED,
            primarySource: 0xD93571A6201978976e37c4A0F7bE17806f2Feab2, // CHAINLINK_STBTC_BTC
            needsArg: 0,
            fallbackSource: address(0),
            fallbackSelector: bytes4(0),
            isBtcToken: true
        });

        return configs;
    }
}