"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updater = exports.gasTracker = void 0;
exports.loadDeploymentData = loadDeploymentData;
exports.normalizePriceData = normalizePriceData;
exports.getMedian = getMedian;
exports.sleep = sleep;
exports.fetchWithRetry = fetchWithRetry;
exports.fetchEthUsdPrice = fetchEthUsdPrice;
exports.convertUsdToEthPrice = convertUsdToEthPrice;
exports.fetchPriceFromCoingecko = fetchPriceFromCoingecko;
exports.fetchPriceFromCoinMarketCap = fetchPriceFromCoinMarketCap;
exports.fetchPriceFromBinance = fetchPriceFromBinance;
exports.checkVolatilityThreshold = checkVolatilityThreshold;
exports.updateIndividualPrice = updateIndividualPrice;
exports.processLAT = processLAT;
exports.main = main;
exports.scheduleUpdates = scheduleUpdates;
exports.estimateGasRequirements = estimateGasRequirements;
const dotenv_1 = require("dotenv");
const web3_1 = __importDefault(require("web3"));
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const node_fetch_1 = __importDefault(require("node-fetch"));
const node_schedule_1 = __importDefault(require("node-schedule"));
const bignumber_js_1 = require("bignumber.js");
const winston_1 = __importDefault(require("winston"));
// Load environment variables
(0, dotenv_1.config)();
// Check for run-once mode
const RUN_ONCE = process.argv.includes('--run-once');
// Environment configuration
const ENV = {
    // Web3 connection
    RPC_URL: process.env.RPC_URL || "http://127.0.0.1:8545",
    NETWORK: process.env.NETWORK || "local",
    // Price provider keys and settings
    COINGECKO_API_KEY: process.env.COINGECKO_API_KEY || "",
    COINGECKO_BASE_URL: process.env.COINGECKO_BASE_URL || "https://api.coingecko.com/api/v3",
    COINGECKO_ENABLED: process.env.COINGECKO_ENABLED !== "false",
    BINANCE_BASE_URL: process.env.BINANCE_BASE_URL || "https://api.binance.com/api/v3",
    BINANCE_ENABLED: process.env.BINANCE_ENABLED !== "false",
    COINMARKETCAP_API_KEY: process.env.COINMARKETCAP_API_KEY || "",
    COINMARKETCAP_BASE_URL: process.env.COINMARKETCAP_BASE_URL || "https://pro-api.coinmarketcap.com/v1",
    COINMARKETCAP_ENABLED: process.env.COINMARKETCAP_ENABLED === "true",
    // Oracle settings
    UPDATE_INTERVAL_MINUTES: parseInt(process.env.UPDATE_INTERVAL_MINUTES || "60", 10),
    VOLATILITY_THRESHOLD_BYPASS: process.env.VOLATILITY_THRESHOLD_BYPASS !== "false",
    INDIVIDUAL_UPDATES_ON_BATCH_FAILURE: process.env.INDIVIDUAL_UPDATES_ON_BATCH_FAILURE !== "false",
    // File paths
    DEPLOYMENT_PATH: process.env.DEPLOYMENT_PATH || "script/outputs/local/mainnet_deployment_data.json",
    ORACLE_ABI_PATH: process.env.ORACLE_ABI_PATH || "./ABIs/TokenRegistryOracle.json",
    MANAGER_ABI_PATH: process.env.MANAGER_ABI_PATH || "./ABIs/LiquidTokenManager.json",
    // Logging
    LOG_LEVEL: process.env.LOG_LEVEL || "info"
};
// Default ETH price in USD if API fails
const FALLBACK_ETH_USD_PRICE = 1850;
// Logger setup with simple format for compatibility with tests
const logger = winston_1.default.createLogger({
    level: ENV.LOG_LEVEL,
    format: winston_1.default.format.combine(winston_1.default.format.timestamp(), winston_1.default.format.json()),
    transports: [
        new winston_1.default.transports.Console(),
        new winston_1.default.transports.File({ filename: "error.log", level: "error" }),
        new winston_1.default.transports.File({ filename: "combined.log" }),
    ],
});
// Safely load mappings from external file with error handling
let mappings;
try {
    const mappingsPath = path_1.default.join(__dirname, "mappings.json");
    if (!fs_1.default.existsSync(mappingsPath)) {
        logger.error(`Mappings file not found: ${mappingsPath}`);
        throw new Error(`Mappings file not found: ${mappingsPath}`);
    }
    mappings = JSON.parse(fs_1.default.readFileSync(mappingsPath, "utf-8"));
    logger.info("Successfully loaded token mappings");
}
catch (error) {
    logger.error(`Failed to load mappings file: ${error}`);
    throw new Error(`Failed to load mappings: ${error}`);
}
// Function to load deployment data and create configurations
function loadDeploymentData() {
    var _a, _b, _c, _d, _e, _f, _g;
    try {
        // Load the deployment data
        const deploymentPath = path_1.default.resolve(process.cwd(), ENV.DEPLOYMENT_PATH);
        if (!fs_1.default.existsSync(deploymentPath)) {
            logger.warn(`Deployment data not found at ${deploymentPath}`);
            return [];
        }
        const deploymentData = JSON.parse(fs_1.default.readFileSync(deploymentPath, "utf-8"));
        logger.info(`Successfully loaded deployment data from ${deploymentPath}`);
        // Extract data from DeployMainnet.s.sol structure
        const configs = [];
        // Check for contract deployments structure
        if (deploymentData.contractDeployments) {
            logger.info("Processing data using contractDeployments structure");
            // First check for regular LAT structure
            if (((_b = (_a = deploymentData.contractDeployments.proxy) === null || _a === void 0 ? void 0 : _a.tokenRegistryOracle) === null || _b === void 0 ? void 0 : _b.address) &&
                ((_d = (_c = deploymentData.contractDeployments.proxy) === null || _c === void 0 ? void 0 : _c.liquidTokenManager) === null || _d === void 0 ? void 0 : _d.address)) {
                // Extract main contract addresses
                const oracleAddress = deploymentData.contractDeployments.proxy.tokenRegistryOracle.address;
                const managerAddress = deploymentData.contractDeployments.proxy.liquidTokenManager.address;
                logger.info(`Found oracle address: ${oracleAddress}`);
                logger.info(`Found manager address: ${managerAddress}`);
                // Extract token data - handle both array and object formats
                let tokenArray = [];
                if (deploymentData.tokens) {
                    if (Array.isArray(deploymentData.tokens)) {
                        tokenArray = deploymentData.tokens;
                    }
                    else {
                        tokenArray = Object.values(deploymentData.tokens);
                    }
                }
                if (tokenArray.length > 0) {
                    logger.info(`Found ${tokenArray.length} tokens in deployment data`);
                    // Build a mapping of token addresses to symbols
                    const tokenMappings = {};
                    for (const token of tokenArray) {
                        const address = token.address || ((_e = token.addresses) === null || _e === void 0 ? void 0 : _e.token);
                        const symbol = token.symbol;
                        if (address && symbol) {
                            tokenMappings[address] = symbol;
                            logger.info(`Mapped token ${symbol} at address ${address.substring(0, 8)}...`);
                        }
                    }
                    if (Object.keys(tokenMappings).length > 0) {
                        // Create a config for the LAT instance
                        const config = {
                            web3: {
                                provider_uri: ENV.RPC_URL
                            },
                            contracts: {
                                oracle_address: oracleAddress,
                                oracle_abi_path: ENV.ORACLE_ABI_PATH,
                                manager_address: managerAddress,
                                manager_abi_path: ENV.MANAGER_ABI_PATH
                            },
                            price_providers: {
                                coingecko: ENV.COINGECKO_ENABLED ? {
                                    enabled: true,
                                    base_url: ENV.COINGECKO_BASE_URL,
                                    api_key: ENV.COINGECKO_API_KEY
                                } : undefined,
                                binance: ENV.BINANCE_ENABLED ? {
                                    enabled: true,
                                    base_url: ENV.BINANCE_BASE_URL
                                } : undefined,
                                coinmarketcap: ENV.COINMARKETCAP_ENABLED ? {
                                    enabled: true,
                                    base_url: ENV.COINMARKETCAP_BASE_URL,
                                    api_key: ENV.COINMARKETCAP_API_KEY
                                } : undefined
                            },
                            token_mappings: tokenMappings,
                            update_interval_minutes: ENV.UPDATE_INTERVAL_MINUTES,
                            volatility_threshold_bypass: ENV.VOLATILITY_THRESHOLD_BYPASS,
                            individual_updates_on_batch_failure: ENV.INDIVIDUAL_UPDATES_ON_BATCH_FAILURE
                        };
                        configs.push(config);
                        logger.info(`Created config with ${Object.keys(tokenMappings).length} tokens`);
                    }
                }
            }
        }
        // Check for multiple instances in an array structure (handle LAT array)
        if (deploymentData.LATInstances && Array.isArray(deploymentData.LATInstances)) {
            logger.info(`Found ${deploymentData.LATInstances.length} LAT instances in deployment data`);
            for (const instance of deploymentData.LATInstances) {
                if (((_f = instance.oracle) === null || _f === void 0 ? void 0 : _f.address) && ((_g = instance.manager) === null || _g === void 0 ? void 0 : _g.address) && instance.tokens) {
                    const oracleAddress = instance.oracle.address;
                    const managerAddress = instance.manager.address;
                    logger.info(`Processing LAT instance with oracle: ${oracleAddress.substring(0, 8)}...`);
                    // Build token mappings
                    const tokenMappings = {};
                    for (const token of instance.tokens) {
                        const address = token.address;
                        const symbol = token.symbol;
                        if (address && symbol) {
                            tokenMappings[address] = symbol;
                        }
                    }
                    if (Object.keys(tokenMappings).length > 0) {
                        const config = {
                            web3: { provider_uri: ENV.RPC_URL },
                            contracts: {
                                oracle_address: oracleAddress,
                                oracle_abi_path: ENV.ORACLE_ABI_PATH,
                                manager_address: managerAddress,
                                manager_abi_path: ENV.MANAGER_ABI_PATH
                            },
                            price_providers: {
                                coingecko: ENV.COINGECKO_ENABLED ? {
                                    enabled: true,
                                    base_url: ENV.COINGECKO_BASE_URL,
                                    api_key: ENV.COINGECKO_API_KEY
                                } : undefined,
                                binance: ENV.BINANCE_ENABLED ? {
                                    enabled: true,
                                    base_url: ENV.BINANCE_BASE_URL
                                } : undefined,
                                coinmarketcap: ENV.COINMARKETCAP_ENABLED ? {
                                    enabled: true,
                                    base_url: ENV.COINMARKETCAP_BASE_URL,
                                    api_key: ENV.COINMARKETCAP_API_KEY
                                } : undefined
                            },
                            token_mappings: tokenMappings,
                            update_interval_minutes: ENV.UPDATE_INTERVAL_MINUTES,
                            volatility_threshold_bypass: ENV.VOLATILITY_THRESHOLD_BYPASS,
                            individual_updates_on_batch_failure: ENV.INDIVIDUAL_UPDATES_ON_BATCH_FAILURE
                        };
                        configs.push(config);
                        logger.info(`Created config for LAT instance with ${Object.keys(tokenMappings).length} tokens`);
                    }
                }
            }
        }
        if (configs.length === 0) {
            logger.warn("No valid LAT configurations found in deployment data");
        }
        else {
            logger.info(`Successfully created ${configs.length} LAT configurations`);
        }
        return configs;
    }
    catch (error) {
        logger.error(`Failed to load deployment data: ${error}`);
        return [];
    }
}
// Gas tracker for monitoring transaction costs
exports.gasTracker = {
    transactions: [],
    totalGasUsed: 0,
    totalEthSpent: "0",
    // Record a new transaction
    recordTransaction: function (txHash, gasUsed, gasPrice, tokens) {
        const ethCost = new bignumber_js_1.BigNumber(gasUsed).multipliedBy(new bignumber_js_1.BigNumber(gasPrice)).div(new bignumber_js_1.BigNumber(10).pow(18));
        this.transactions.push({
            txHash,
            timestamp: Date.now(),
            gasUsed,
            gasPrice: web3_1.default.utils.fromWei(gasPrice, 'gwei'),
            ethCost: ethCost.toString(),
            tokensUpdated: tokens.length,
            gasPerToken: Math.floor(gasUsed / tokens.length)
        });
        this.totalGasUsed += gasUsed;
        this.totalEthSpent = new bignumber_js_1.BigNumber(this.totalEthSpent).plus(ethCost).toString();
        // Save transaction log to file
        this.saveToFile();
    },
    // Log current gas usage statistics
    logStats: function (web3, account) {
        return __awaiter(this, void 0, void 0, function* () {
            const txCount = this.transactions.length;
            const avgGasPerTx = txCount > 0 ? Math.floor(this.totalGasUsed / txCount) : 0;
            logger.info(`=== Gas Usage Statistics ===`);
            logger.info(`Total transactions: ${txCount}`);
            logger.info(`Total gas used: ${this.totalGasUsed}`);
            logger.info(`Total ETH spent: ${this.totalEthSpent}`);
            logger.info(`Average gas per transaction: ${avgGasPerTx}`);
            // Calculate remaining ETH in wallet if we have web3 instance
            if (web3 && account) {
                try {
                    const balance = yield web3.eth.getBalance(account.address);
                    const ethBalance = web3_1.default.utils.fromWei(balance, 'ether');
                    logger.info(`Remaining wallet balance: ${ethBalance} ETH`);
                    // Estimate remaining updates possible
                    if (avgGasPerTx > 0) {
                        const price = yield web3.eth.getGasPrice();
                        const priceBN = new bignumber_js_1.BigNumber(price.toString());
                        const ethPerTx = new bignumber_js_1.BigNumber(avgGasPerTx).multipliedBy(priceBN).div(new bignumber_js_1.BigNumber(10).pow(18));
                        const estimatedRemainingTxs = new bignumber_js_1.BigNumber(balance.toString()).div(new bignumber_js_1.BigNumber(avgGasPerTx).multipliedBy(priceBN));
                        logger.info(`Estimated remaining updates: ~${Math.floor(estimatedRemainingTxs.toNumber())}`);
                        logger.info(`Estimated ETH per update: ${ethPerTx.toString()} ETH`);
                    }
                }
                catch (error) {
                    logger.error("Error calculating wallet statistics:", error);
                }
            }
        });
    },
    // Save transaction history to file
    saveToFile: function () {
        try {
            const data = {
                totalGasUsed: this.totalGasUsed,
                totalEthSpent: this.totalEthSpent,
                transactions: this.transactions
            };
            fs_1.default.writeFileSync('gas_tracker.json', JSON.stringify(data, null, 2));
        }
        catch (error) {
            logger.error("Error saving gas tracker data:", error);
        }
    },
    // Load transaction history from file
    loadFromFile: function () {
        try {
            if (fs_1.default.existsSync('gas_tracker.json')) {
                const data = JSON.parse(fs_1.default.readFileSync('gas_tracker.json', 'utf-8'));
                this.transactions = data.transactions;
                this.totalGasUsed = data.totalGasUsed;
                this.totalEthSpent = data.totalEthSpent;
                logger.info("Loaded gas tracker data from file");
            }
        }
        catch (error) {
            logger.error("Error loading gas tracker data:", error);
        }
    }
};
// Load gas tracker data at startup
exports.gasTracker.loadFromFile();
const PRICE_DECIMALS = 18;
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 5000;
/**
 * Normalizes price data from various API formats to ensure consistent BN representation
 * @param priceData The raw price data from API
 * @param source The source name for logging
 * @param symbol The token symbol for logging
 * @returns Normalized BigNumber or null if invalid
 */
function normalizePriceData(priceData, source, symbol) {
    try {
        // Skip null/undefined values
        if (priceData === null || priceData === undefined) {
            return null;
        }
        // Handle string values (like "123.45")
        if (typeof priceData === 'string') {
            if (!priceData.trim()) {
                return null;
            }
            return new bignumber_js_1.BigNumber(priceData);
        }
        // Handle number values
        if (typeof priceData === 'number') {
            if (!isFinite(priceData)) {
                logger.warn(`${source}: Non-finite price for ${symbol}: ${priceData}`);
                return null;
            }
            return new bignumber_js_1.BigNumber(priceData);
        }
        // For other types, try toString conversion
        return new bignumber_js_1.BigNumber(priceData.toString());
    }
    catch (error) {
        logger.warn(`${source}: Failed to normalize price for ${symbol}: ${error}`);
        return null;
    }
}
function getMedian(prices) {
    const sorted = prices.sort((a, b) => a.comparedTo(b));
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 !== 0 ? sorted[mid] : sorted[mid - 1].plus(sorted[mid]).div(2);
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
function fetchWithRetry(url_1, options_1) {
    return __awaiter(this, arguments, void 0, function* (url, options, retries = MAX_RETRIES) {
        try {
            const response = yield (0, node_fetch_1.default)(url, options);
            if (!response.ok) {
                const statusText = response.statusText;
                const responseBody = yield response.text().catch(() => "");
                throw new Error(`HTTP error! Status: ${response.status}, Message: ${statusText}, Body: ${responseBody.substring(0, 200)}`);
            }
            return yield response.json();
        }
        catch (error) {
            if (retries > 0) {
                logger.warn(`API request failed, retrying in ${RETRY_DELAY_MS}ms... Attempts left: ${retries}`);
                yield sleep(RETRY_DELAY_MS);
                return fetchWithRetry(url, options, retries - 1);
            }
            throw error;
        }
    });
}
/**
 * Fetches the current ETH/USD price from CoinGecko with fallback
 * @returns ETH/USD price as BigNumber or a fallback value if the API fails
 */
function fetchEthUsdPrice() {
    return __awaiter(this, arguments, void 0, function* (baseUrl = ENV.COINGECKO_BASE_URL) {
        try {
            logger.info(`Fetching ETH/USD price from CoinGecko...`);
            const data = yield fetchWithRetry(`${baseUrl}/simple/price?ids=ethereum&vs_currencies=usd&precision=full`, {});
            if (!data || !data.ethereum || data.ethereum.usd === undefined) {
                throw new Error("Invalid response format from CoinGecko");
            }
            const price = normalizePriceData(data.ethereum.usd, 'CoinGecko', 'ETH');
            if (!price || price.isZero()) {
                throw new Error("Received zero or invalid ETH price");
            }
            logger.info(`Fetched ETH/USD price: ${price.toString()} USD per ETH`);
            return price;
        }
        catch (error) {
            logger.error(`Failed to fetch ETH/USD price: ${error instanceof Error ? error.message : String(error)}`);
            // Return fallback price if API call fails
            logger.warn(`Using fallback ETH price: ${FALLBACK_ETH_USD_PRICE} USD per ETH`);
            return new bignumber_js_1.BigNumber(FALLBACK_ETH_USD_PRICE);
        }
    });
}
/**
 * Converts a token's USD price to ETH price
 */
function convertUsdToEthPrice(tokenSymbol, tokenUsdPrice, ethUsdPrice) {
    // Formula: tokenPriceInEth = tokenPriceInUsd / ethPriceInUsd
    const tokenEthPrice = tokenUsdPrice.div(ethUsdPrice);
    logger.info(`Converting ${tokenSymbol}: ${tokenUsdPrice.toString()} USD ÷ ${ethUsdPrice.toString()} USD/ETH = ${tokenEthPrice.toString()} ETH`);
    return tokenEthPrice;
}
function fetchPriceFromCoingecko(baseUrl, tokenSymbol) {
    return __awaiter(this, void 0, void 0, function* () {
        var _a;
        const tokenId = (_a = mappings.coingecko_mappings) === null || _a === void 0 ? void 0 : _a[tokenSymbol.toLowerCase()];
        if (!tokenId) {
            logger.debug(`CoinGecko: No mapping found for ${tokenSymbol}`);
            return null;
        }
        try {
            logger.debug(`CoinGecko: Fetching price for ${tokenSymbol} (ID: ${tokenId})`);
            const data = yield fetchWithRetry(`${baseUrl}/simple/price?ids=${tokenId}&vs_currencies=usd&precision=full`, {});
            if (!data || !data[tokenId] || data[tokenId].usd === undefined) {
                logger.warn(`CoinGecko: Invalid response format for ${tokenSymbol}`);
                return null;
            }
            const price = normalizePriceData(data[tokenId].usd, 'CoinGecko', tokenSymbol);
            if (price) {
                logger.info(`CoinGecko: Got price for ${tokenSymbol}: ${price.toString()} USD`);
            }
            return price;
        }
        catch (error) {
            logger.error(`CoinGecko API error for ${tokenSymbol}: ${error instanceof Error ? error.message : String(error)}`);
            return null;
        }
    });
}
function fetchPriceFromCoinMarketCap(baseUrl, apiKey, tokenSymbol) {
    return __awaiter(this, void 0, void 0, function* () {
        var _a, _b, _c, _d, _e;
        const tokenId = (_a = mappings.coinmarketcap_mappings) === null || _a === void 0 ? void 0 : _a[tokenSymbol];
        if (!tokenId) {
            logger.debug(`CoinMarketCap: No mapping found for ${tokenSymbol}`);
            return null;
        }
        try {
            logger.debug(`CoinMarketCap: Fetching price for ${tokenSymbol}`);
            const response = yield fetchWithRetry(`${baseUrl}/cryptocurrency/quotes/latest?symbol=${tokenSymbol}`, { headers: { "X-CMC_PRO_API_KEY": apiKey } });
            // Safe navigation through the CMC response structure
            if (!((_e = (_d = (_c = (_b = response === null || response === void 0 ? void 0 : response.data) === null || _b === void 0 ? void 0 : _b[tokenSymbol]) === null || _c === void 0 ? void 0 : _c.quote) === null || _d === void 0 ? void 0 : _d.USD) === null || _e === void 0 ? void 0 : _e.price)) {
                logger.warn(`CoinMarketCap: Invalid response format for ${tokenSymbol}`);
                return null;
            }
            const price = normalizePriceData(response.data[tokenSymbol].quote.USD.price, 'CoinMarketCap', tokenSymbol);
            if (price) {
                logger.info(`CoinMarketCap: Got price for ${tokenSymbol}: ${price.toString()} USD`);
            }
            return price;
        }
        catch (error) {
            logger.error(`CoinMarketCap API error for ${tokenSymbol}: ${error instanceof Error ? error.message : String(error)}`);
            return null;
        }
    });
}
function fetchPriceFromBinance(baseUrl, tokenSymbol) {
    return __awaiter(this, void 0, void 0, function* () {
        var _a;
        const tradingPair = (_a = mappings.binance_mappings) === null || _a === void 0 ? void 0 : _a[tokenSymbol];
        if (!tradingPair) {
            logger.debug(`Binance: No mapping found for ${tokenSymbol}`);
            return null;
        }
        try {
            logger.debug(`Binance: Fetching price for ${tokenSymbol} (Pair: ${tradingPair})`);
            const data = yield fetchWithRetry(`${baseUrl}/ticker/price?symbol=${tradingPair}`, {});
            if (!(data === null || data === void 0 ? void 0 : data.price)) {
                logger.warn(`Binance: Invalid response format for ${tokenSymbol}`);
                return null;
            }
            const price = normalizePriceData(data.price, 'Binance', tokenSymbol);
            if (price) {
                logger.info(`Binance: Got price for ${tokenSymbol}: ${price.toString()} USD`);
            }
            return price;
        }
        catch (error) {
            logger.error(`Binance API error for ${tokenSymbol}: ${error instanceof Error ? error.message : String(error)}`);
            return null;
        }
    });
}
let configObj;
function checkVolatilityThreshold(managerContract, tokenAddress, newPrice) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const tokenInfo = yield managerContract.methods.getTokenInfo(tokenAddress).call();
            const oldPrice = new bignumber_js_1.BigNumber(tokenInfo.pricePerUnit);
            const volatilityThreshold = new bignumber_js_1.BigNumber(tokenInfo.volatilityThreshold);
            // Skip check if threshold is zero or bypass is enabled
            if (volatilityThreshold.isZero() || configObj.volatility_threshold_bypass) {
                return true;
            }
            const newPriceBN = new bignumber_js_1.BigNumber(newPrice);
            const changeRatio = newPriceBN.minus(oldPrice).abs().multipliedBy(1e18).dividedBy(oldPrice);
            const result = changeRatio.lte(volatilityThreshold);
            logger.info(`Volatility check for ${tokenAddress}: Old=${oldPrice.toString()}, New=${newPriceBN.toString()}, Change=${changeRatio.div(1e18).times(100).toFixed(2)}%, Threshold=${volatilityThreshold.div(1e18).times(100).toFixed(2)}%, Passed=${result}`);
            return result;
        }
        catch (error) {
            logger.error(`Volatility check failed for ${tokenAddress}:`, error);
            // Return true on error to avoid permanently blocking updates due to technical issues
            return true;
        }
    });
}
function updateIndividualPrice(web3, oracleContract, managerContract, account, tokenAddress, newPrice) {
    return __awaiter(this, void 0, void 0, function* () {
        var _a;
        const symbol = ((_a = Object.entries(configObj.token_mappings).find(([addr]) => addr === tokenAddress)) === null || _a === void 0 ? void 0 : _a[1]) || 'unknown';
        logger.info(`Attempting individual price update for ${symbol} (${tokenAddress.substring(0, 8)}...): ${newPrice}`);
        try {
            const passes = yield checkVolatilityThreshold(managerContract, tokenAddress, newPrice);
            if (!passes) {
                logger.warn(`⚠️ Volatility threshold exceeded for ${symbol} (${tokenAddress.substring(0, 8)}...)`);
                return false;
            }
            const tx = oracleContract.methods.updateRate(tokenAddress, newPrice);
            const gas = yield tx.estimateGas({ from: account.address });
            const gasPrice = yield web3.eth.getGasPrice();
            logger.info(`Gas estimate for ${symbol}: ${gas} units at ${web3_1.default.utils.fromWei(gasPrice, 'gwei')} gwei`);
            const nonce = yield web3.eth.getTransactionCount(account.address, "pending");
            const signedTx = yield account.signTransaction({
                to: oracleContract.options.address,
                data: tx.encodeABI(),
                gas,
                gasPrice,
                nonce,
            });
            logger.info(`Submitting transaction for ${symbol}...`);
            const receipt = yield web3.eth.sendSignedTransaction(signedTx.rawTransaction);
            logger.info(`✅ Individual update success: ${symbol} -> ${receipt.transactionHash}`);
            exports.gasTracker.recordTransaction(receipt.transactionHash.toString(), Number(receipt.gasUsed), gasPrice.toString(), [tokenAddress]);
            return true;
        }
        catch (error) {
            logger.error(`❌ Individual update failed for ${symbol} (${tokenAddress.substring(0, 8)}...): ${error instanceof Error ? error.message : String(error)}`);
            return false;
        }
    });
}
function processLAT(cfg) {
    return __awaiter(this, void 0, void 0, function* () {
        var _a, _b, _c, _d;
        if (!cfg.contracts.oracle_address.startsWith("0x")) {
            throw new Error(`Invalid oracle address: ${cfg.contracts.oracle_address}`);
        }
        configObj = cfg;
        logger.info(`\n=== Processing LAT ${cfg.contracts.oracle_address.substring(0, 8)}... ===`);
        // Create web3 connection and load account
        let web3;
        try {
            web3 = new web3_1.default(cfg.web3.provider_uri);
            // Verify connection
            yield web3.eth.getBlockNumber();
            logger.info(`Connected to blockchain at ${cfg.web3.provider_uri}`);
        }
        catch (error) {
            logger.error(`Failed to connect to blockchain at ${cfg.web3.provider_uri}:`, error);
            throw new Error(`Web3 connection failed: ${error}`);
        }
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey)
            throw new Error("No private key in .env");
        const account = web3.eth.accounts.privateKeyToAccount(privateKey);
        web3.eth.accounts.wallet.add(account);
        logger.info(`Using account: ${account.address.substring(0, 8)}...`);
        // Load contracts
        let oracleContract, managerContract;
        try {
            const oracleAbi = JSON.parse(fs_1.default.readFileSync(path_1.default.join(__dirname, cfg.contracts.oracle_abi_path), "utf-8"));
            oracleContract = new web3.eth.Contract(oracleAbi, cfg.contracts.oracle_address);
            const rateUpdaterRole = yield oracleContract.methods.RATE_UPDATER_ROLE().call();
            const hasRole = yield oracleContract.methods.hasRole(rateUpdaterRole, account.address).call();
            if (!hasRole) {
                throw new Error(`Account ${account.address} missing RATE_UPDATER_ROLE`);
            }
            const managerAbi = JSON.parse(fs_1.default.readFileSync(path_1.default.join(__dirname, cfg.contracts.manager_abi_path), "utf-8"));
            managerContract = new web3.eth.Contract(managerAbi, cfg.contracts.manager_address);
            logger.info(`Contracts loaded successfully. Oracle: ${cfg.contracts.oracle_address.substring(0, 8)}..., Manager: ${cfg.contracts.manager_address.substring(0, 8)}...`);
        }
        catch (error) {
            logger.error("Failed to load contracts:", error);
            throw error;
        }
        // Get tokens to update
        const tokenAddresses = Object.keys(cfg.token_mappings);
        logger.info(`Found ${tokenAddresses.length} tokens to update`);
        // Fetch ETH/USD price first - this is essential for conversion
        const ethUsdPrice = yield fetchEthUsdPrice();
        logger.info(`Using ETH/USD price: ${ethUsdPrice.toString()} USD per ETH`);
        const validUpdates = [];
        // Process each token
        for (const tokenAddress of tokenAddresses) {
            const symbol = cfg.token_mappings[tokenAddress];
            logger.info(`\nProcessing token: ${symbol} (${tokenAddress.substring(0, 8)}...)`);
            const prices = [];
            const priceSources = [];
            // Fetch prices from all configured providers
            if ((_a = cfg.price_providers.coingecko) === null || _a === void 0 ? void 0 : _a.enabled) {
                try {
                    const price = yield fetchPriceFromCoingecko(cfg.price_providers.coingecko.base_url, symbol);
                    if (price) {
                        prices.push(price);
                        priceSources.push("CoinGecko");
                    }
                }
                catch (error) {
                    logger.error(`Failed to fetch price from CoinGecko for ${symbol}:`, error);
                }
            }
            if ((_b = cfg.price_providers.coinmarketcap) === null || _b === void 0 ? void 0 : _b.enabled) {
                try {
                    const price = yield fetchPriceFromCoinMarketCap(cfg.price_providers.coinmarketcap.base_url, cfg.price_providers.coinmarketcap.api_key, symbol);
                    if (price) {
                        prices.push(price);
                        priceSources.push("CoinMarketCap");
                    }
                }
                catch (error) {
                    logger.error(`Failed to fetch price from CoinMarketCap for ${symbol}:`, error);
                }
            }
            if ((_c = cfg.price_providers.binance) === null || _c === void 0 ? void 0 : _c.enabled) {
                try {
                    const price = yield fetchPriceFromBinance(cfg.price_providers.binance.base_url, symbol);
                    if (price) {
                        prices.push(price);
                        priceSources.push("Binance");
                    }
                }
                catch (error) {
                    logger.error(`Failed to fetch price from Binance for ${symbol}:`, error);
                }
            }
            if (prices.length < 1) {
                logger.warn(`⚠️ No prices available for ${symbol} from any source`);
                continue;
            }
            // Log sources used for this token
            logger.info(`${symbol}: Got prices from ${priceSources.join(", ")}`);
            if (prices.length > 1) {
                logger.info(`${symbol}: Raw prices: ${prices.map(p => p.toString()).join(', ')}`);
            }
            // Calculate median price in USD
            const medianUsdPrice = getMedian(prices);
            logger.info(`${symbol}: Median USD price: ${medianUsdPrice.toString()} USD`);
            // EXPLICIT USD TO ETH CONVERSION - using string values to preserve precision
            const usdPriceStr = medianUsdPrice.toString();
            const ethUsdPriceStr = ethUsdPrice.toString();
            logger.info(`CONVERSION: Converting ${usdPriceStr} USD to ETH using ETH price of ${ethUsdPriceStr} USD`);
            // Create fresh BN instances from strings
            const usdPriceBN = new bignumber_js_1.BigNumber(usdPriceStr);
            const ethUsdPriceBN = new bignumber_js_1.BigNumber(ethUsdPriceStr);
            // Perform division to get ETH price
            const ethPriceBN = usdPriceBN.div(ethUsdPriceBN);
            logger.info(`${symbol}: Price in ETH: ${ethPriceBN.toString()} ETH`);
            // Scale to on-chain representation (multiply by 10^18)
            const scaledPrice = ethPriceBN.times(new bignumber_js_1.BigNumber(10).pow(PRICE_DECIMALS)).toFixed(0);
            logger.info(`${symbol}: Final blockchain value: ${scaledPrice} (${ethPriceBN.toString()} ETH)`);
            // Add to validUpdates with the ETH price
            if (yield checkVolatilityThreshold(managerContract, tokenAddress, scaledPrice)) {
                validUpdates.push({ address: tokenAddress, price: scaledPrice });
                logger.info(`✅ Valid update: ${symbol} -> ${scaledPrice} (${ethPriceBN.toString()} ETH)`);
            }
            else {
                logger.warn(`⛔️ Volatility rejection: ${symbol} -> ${scaledPrice} (${ethPriceBN.toString()} ETH)`);
            }
        }
        // Process batch updates
        if (validUpdates.length > 0) {
            const tokens = validUpdates.map(u => u.address);
            const prices = validUpdates.map(u => u.price);
            logger.info(`\nAttempting batch update for ${tokens.length} tokens`);
            let retries = MAX_RETRIES;
            while (retries > 0) {
                try {
                    const tx = oracleContract.methods.batchUpdateRates(tokens, prices);
                    // Estimate gas for the transaction
                    const gas = yield tx.estimateGas({ from: account.address });
                    const gasPrice = yield web3.eth.getGasPrice();
                    const nonce = yield web3.eth.getTransactionCount(account.address, "pending");
                    // Log the gas estimate
                    logger.info(`Gas estimate for batch update: ${gas} units at ${web3_1.default.utils.fromWei(gasPrice, 'gwei')} gwei`);
                    logger.info(`Estimated cost: ${web3_1.default.utils.fromWei(new bignumber_js_1.BigNumber(gas.toString()).multipliedBy(new bignumber_js_1.BigNumber(gasPrice.toString())).toString(), 'ether')} ETH`);
                    // Create and sign transaction
                    const signedTx = yield account.signTransaction({
                        to: oracleContract.options.address,
                        data: tx.encodeABI(),
                        gas,
                        gasPrice,
                        nonce,
                    });
                    // Send transaction
                    logger.info(`Submitting batch transaction to network...`);
                    const receipt = yield web3.eth.sendSignedTransaction(signedTx.rawTransaction);
                    // Log success and gas used
                    logger.info(`💎 Batch update successful: ${receipt.transactionHash}`);
                    logger.info(`Gas used: ${receipt.gasUsed} (${(Number(receipt.gasUsed) / Number(gas) * 100).toFixed(1)}% of estimate)`);
                    // Record transaction in gas tracker
                    exports.gasTracker.recordTransaction(receipt.transactionHash.toString(), Number(receipt.gasUsed), gasPrice.toString(), tokens);
                    // Show wallet status after transaction
                    yield exports.gasTracker.logStats(web3, account);
                    break;
                }
                catch (error) {
                    const errorMsg = error instanceof Error ? error.message : String(error);
                    if (--retries === 0) {
                        logger.error(`Batch update failed after all retries: ${errorMsg}`);
                        // Fall back to individual updates if configured
                        if (cfg.individual_updates_on_batch_failure) {
                            logger.info(`Falling back to individual updates for ${validUpdates.length} tokens`);
                            for (const update of validUpdates) {
                                const symbol = ((_d = Object.entries(cfg.token_mappings).find(([addr]) => addr === update.address)) === null || _d === void 0 ? void 0 : _d[1]) || 'unknown';
                                logger.info(`Processing individual update for ${symbol} (${update.address.substring(0, 8)}...)`);
                                yield updateIndividualPrice(web3, oracleContract, managerContract, account, update.address, update.price);
                                yield sleep(1000); // Delay between individual transactions
                            }
                        }
                    }
                    else {
                        logger.warn(`Batch update attempt failed, retrying (${retries} attempts left): ${errorMsg}`);
                        yield sleep(RETRY_DELAY_MS);
                    }
                }
            }
        }
        else {
            logger.info(`No valid updates to process`);
        }
        // Display gas stats at the end of processing
        yield exports.gasTracker.logStats(web3, account);
        logger.info(`=== LAT processing complete ===\n`);
    });
}
function main() {
    return __awaiter(this, void 0, void 0, function* () {
        logger.info("Starting price oracle update process" + (RUN_ONCE ? " (one-time run)" : ""));
        try {
            // First try loading from deployment data
            logger.info(`Checking for deployment data at ${ENV.DEPLOYMENT_PATH}`);
            const deploymentConfigs = loadDeploymentData();
            if (deploymentConfigs.length > 0) {
                logger.info(`Loaded ${deploymentConfigs.length} configurations from deployment data`);
                // Process each config from deployment data
                for (const cfg of deploymentConfigs) {
                    yield processLAT(cfg);
                }
                logger.info("Price oracle update from deployment data completed");
                return deploymentConfigs;
            }
            // Fall back to config files if no deployment data
            logger.info("No deployment data found, checking config directory");
            const configDir = path_1.default.join(__dirname, "configs");
            if (!fs_1.default.existsSync(configDir)) {
                logger.error(`Config directory not found: ${configDir}`);
                throw new Error("No configuration sources available");
            }
            const configFiles = fs_1.default.readdirSync(configDir).filter(f => f.endsWith(".json"));
            logger.info(`Found ${configFiles.length} configuration files`);
            if (configFiles.length === 0) {
                logger.error("No configuration files found");
                throw new Error("No configuration sources available");
            }
            // Process each config file
            const fileConfigs = [];
            for (const configFile of configFiles) {
                const configPath = path_1.default.join(configDir, configFile);
                logger.info(`Processing config file: ${configFile}`);
                try {
                    const cfg = JSON.parse(fs_1.default.readFileSync(configPath, "utf-8"));
                    fileConfigs.push(cfg);
                    yield processLAT(cfg);
                }
                catch (error) {
                    logger.error(`Error processing ${configFile}:`, error);
                }
            }
            logger.info("Price oracle update from config files completed");
            return fileConfigs;
        }
        catch (error) {
            logger.error(`Error in main process: ${error}`);
            throw error;
        }
    });
}
function scheduleUpdates() {
    // Skip scheduling in run-once mode
    if (RUN_ONCE) {
        logger.info("Skipping scheduled updates in run-once mode");
        return;
    }
    try {
        logger.info("Setting up scheduled price updates");
        // First try loading from deployment data
        const deploymentConfigs = loadDeploymentData();
        const configs = deploymentConfigs.length > 0 ? deploymentConfigs : [];
        // If no deployment data, try config files
        if (configs.length === 0) {
            const configDir = path_1.default.join(__dirname, "configs");
            if (fs_1.default.existsSync(configDir)) {
                const configFiles = fs_1.default.readdirSync(configDir).filter(f => f.endsWith(".json"));
                for (const file of configFiles) {
                    try {
                        const configPath = path_1.default.join(configDir, file);
                        const cfg = JSON.parse(fs_1.default.readFileSync(configPath, "utf-8"));
                        configs.push(cfg);
                    }
                    catch (error) {
                        logger.error(`Failed to load config file ${file}:`, error);
                    }
                }
            }
        }
        if (configs.length === 0) {
            logger.error("No configurations available for scheduling updates");
            return;
        }
        // Get update interval from environment or first config
        const intervalMinutes = ENV.UPDATE_INTERVAL_MINUTES || configs[0].update_interval_minutes || 60;
        // Ensure interval is within reasonable bounds
        const boundedInterval = Math.max(15, Math.min(1440, intervalMinutes));
        const cronExpression = `*/${boundedInterval} * * * *`;
        logger.info(`Scheduling updates with cron expression: ${cronExpression} (every ${boundedInterval} minutes)`);
        const job = node_schedule_1.default.scheduleJob(cronExpression, () => __awaiter(this, void 0, void 0, function* () {
            logger.info(`Scheduled job triggered at ${new Date().toISOString()}`);
            try {
                yield main();
            }
            catch (error) {
                logger.error("Scheduled update failed:", error);
            }
        }));
        if (job) {
            logger.info(`Next scheduled update: ${job.nextInvocation().toISOString()}`);
        }
        else {
            logger.error("Failed to schedule updates");
        }
    }
    catch (error) {
        logger.error(`Failed to schedule updates: ${error}`);
    }
}
function estimateGasRequirements() {
    return __awaiter(this, void 0, void 0, function* () {
        // Skip gas estimates in run-once mode
        if (RUN_ONCE) {
            return;
        }
        logger.info(`\n=== Gas Requirement Estimates ===`);
        try {
            // First try deployment data
            const deploymentConfigs = loadDeploymentData();
            // Fall back to config files if needed
            const configs = deploymentConfigs.length > 0 ? deploymentConfigs : [];
            if (configs.length === 0) {
                const configDir = path_1.default.join(__dirname, "configs");
                if (fs_1.default.existsSync(configDir)) {
                    const configFiles = fs_1.default.readdirSync(configDir).filter(f => f.endsWith(".json"));
                    for (const file of configFiles) {
                        try {
                            const configPath = path_1.default.join(configDir, file);
                            const cfg = JSON.parse(fs_1.default.readFileSync(configPath, "utf-8"));
                            configs.push(cfg);
                        }
                        catch (error) {
                            logger.error(`Failed to load config file ${file}:`, error);
                        }
                    }
                }
            }
            if (configs.length === 0) {
                logger.warn("No configurations found for gas estimation");
                return;
            }
            // Initialize web3 using the RPC URL
            const web3 = new web3_1.default(ENV.RPC_URL || configs[0].web3.provider_uri);
            const privateKey = process.env.PRIVATE_KEY;
            if (!privateKey) {
                logger.error("No private key in .env - cannot estimate gas requirements");
                return;
            }
            // Get account balance
            const account = web3.eth.accounts.privateKeyToAccount(privateKey);
            let balance;
            try {
                balance = (yield web3.eth.getBalance(account.address)).toString();
            }
            catch (error) {
                logger.error(`Failed to get account balance: ${error}`);
                return;
            }
            const ethBalance = web3_1.default.utils.fromWei(balance, 'ether');
            logger.info(`Current wallet balance: ${ethBalance} ETH`);
            // Count total tokens across all configs
            let totalTokens = 0;
            for (const cfg of configs) {
                const tokenCount = Object.keys(cfg.token_mappings).length;
                totalTokens += tokenCount;
                const tokenSymbols = Object.values(cfg.token_mappings).join(', ');
                logger.info(`Found configuration for tokens: ${tokenSymbols}`);
            }
            logger.info(`Total tokens to be updated: ${totalTokens}`);
            // Calculate estimates based on historical data if available
            if (exports.gasTracker.transactions.length > 0) {
                const avgGasPerToken = exports.gasTracker.transactions.reduce((sum, tx) => sum + tx.gasPerToken, 0) / exports.gasTracker.transactions.length;
                let recentGasPrice;
                try {
                    recentGasPrice = (yield web3.eth.getGasPrice()).toString();
                }
                catch (error) {
                    logger.error(`Failed to get gas price: ${error}`);
                    return;
                }
                const estimatedGasForAllTokens = avgGasPerToken * totalTokens;
                const estimatedCostInEth = new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(recentGasPrice)).div(new bignumber_js_1.BigNumber(10).pow(18));
                logger.info(`Based on historical data:`);
                logger.info(`  Average gas per token: ${Math.floor(avgGasPerToken)}`);
                logger.info(`  Current gas price: ${web3_1.default.utils.fromWei(recentGasPrice, 'gwei')} gwei`);
                logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
                logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
                // Calculate how many updates current balance can support
                if (parseFloat(ethBalance) > 0) {
                    const supportedUpdates = new bignumber_js_1.BigNumber(balance).div(new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(recentGasPrice)));
                    logger.info(`  Current balance can support approximately ${Math.floor(supportedUpdates.toNumber())} complete update cycles`);
                }
            }
            else {
                // If no historical data, provide rough estimates
                let gasPrice;
                try {
                    gasPrice = (yield web3.eth.getGasPrice()).toString();
                }
                catch (error) {
                    logger.error(`Failed to get gas price: ${error}`);
                    return;
                }
                // Conservative estimates
                const estimatedGasPerToken = 100000; // This is a conservative estimate
                const estimatedGasForAllTokens = estimatedGasPerToken * totalTokens;
                const estimatedCostInEth = new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(gasPrice)).div(new bignumber_js_1.BigNumber(10).pow(18));
                logger.info(`No historical data available. Using conservative estimates:`);
                logger.info(`  Estimated gas per token: ${estimatedGasPerToken}`);
                logger.info(`  Current gas price: ${web3_1.default.utils.fromWei(gasPrice, 'gwei')} gwei`);
                logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
                logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
                if (parseFloat(ethBalance) > 0) {
                    const supportedUpdates = new bignumber_js_1.BigNumber(balance).div(new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(gasPrice)));
                    logger.info(`  Current balance can support approximately ${Math.floor(supportedUpdates.toNumber())} complete update cycles`);
                }
            }
            logger.info(`=== End of Gas Estimate ===\n`);
        }
        catch (error) {
            logger.error(`Gas estimation failed: ${error}`);
        }
    });
}
// Export key functions for potential use in other modules
exports.updater = {
    processLAT,
    main,
    scheduleUpdates,
    checkVolatilityThreshold,
    fetchPriceFromCoingecko,
    fetchPriceFromCoinMarketCap,
    fetchPriceFromBinance,
    fetchEthUsdPrice,
    convertUsdToEthPrice,
    updateIndividualPrice,
    estimateGasRequirements,
    gasTracker: exports.gasTracker,
    loadDeploymentData
};
// Run the application if this is the main module (not imported elsewhere)
if (process.env.NODE_ENV !== "test" && !process.env.JEST_WORKER_ID) {
    try {
        if (RUN_ONCE) {
            // Run once mode - just run main() and exit
            logger.info('Running in one-time update mode');
            main()
                .then(() => {
                logger.info('One-time price update completed');
                process.exit(0);
            })
                .catch(error => {
                logger.error('Error during one-time price update:', error);
                process.exit(1);
            });
        }
        else {
            // Normal mode - run gas estimation, main, and schedule updates
            estimateGasRequirements()
                .then(() => main())
                .then(() => {
                scheduleUpdates();
            })
                .catch(error => {
                logger.error("Application error:", error);
                process.exit(1);
            });
        }
    }
    catch (error) {
        logger.error("Fatal application error:", error);
        process.exit(1);
    }
}
