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
exports.updater = exports.estimateGasRequirements = exports.scheduleUpdates = exports.main = exports.processLAT = exports.updateIndividualPrice = exports.checkVolatilityThreshold = exports.fetchPriceFromBinance = exports.fetchPriceFromCoinMarketCap = exports.fetchPriceFromCoingecko = exports.fetchWithRetry = exports.sleep = exports.getMedian = exports.gasTracker = void 0;
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
// Logger setup
const logger = winston_1.default.createLogger({
    level: "info",
    format: winston_1.default.format.combine(winston_1.default.format.timestamp(), winston_1.default.format.json()),
    transports: [
        new winston_1.default.transports.Console(),
        new winston_1.default.transports.File({ filename: "error.log", level: "error" }),
        new winston_1.default.transports.File({ filename: "combined.log" }),
    ],
});
// Load mappings from external file
const mappingsPath = path_1.default.join(__dirname, "mappings.json");
const mappings = JSON.parse(fs_1.default.readFileSync(mappingsPath, "utf-8"));
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
        // Log current stats
        this.logStats();
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
function getMedian(prices) {
    const sorted = prices.sort((a, b) => a.comparedTo(b));
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 !== 0 ? sorted[mid] : sorted[mid - 1].plus(sorted[mid]).div(2);
}
exports.getMedian = getMedian;
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
exports.sleep = sleep;
function fetchWithRetry(url, options, retries = MAX_RETRIES) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const response = yield (0, node_fetch_1.default)(url, options);
            if (!response.ok)
                throw new Error(`HTTP error! status: ${response.status}`);
            return yield response.json();
        }
        catch (error) {
            if (retries > 0) {
                logger.warn(`Retrying... attempts left: ${retries}`);
                yield sleep(RETRY_DELAY_MS);
                return fetchWithRetry(url, options, retries - 1);
            }
            throw error;
        }
    });
}
exports.fetchWithRetry = fetchWithRetry;
function fetchPriceFromCoingecko(baseUrl, tokenSymbol) {
    var _a;
    return __awaiter(this, void 0, void 0, function* () {
        const tokenId = mappings.coingecko_mappings[tokenSymbol.toLowerCase()];
        if (!tokenId)
            return null;
        try {
            const data = yield fetchWithRetry(`${baseUrl}/simple/price?ids=${tokenId}&vs_currencies=usd&precision=full`, {});
            return ((_a = data[tokenId]) === null || _a === void 0 ? void 0 : _a.usd) ? new bignumber_js_1.BigNumber(data[tokenId].usd) : null;
        }
        catch (error) {
            logger.error(`CoinGecko error for ${tokenSymbol}:`, error);
            return null;
        }
    });
}
exports.fetchPriceFromCoingecko = fetchPriceFromCoingecko;
function fetchPriceFromCoinMarketCap(baseUrl, apiKey, tokenSymbol) {
    var _a, _b, _c, _d;
    return __awaiter(this, void 0, void 0, function* () {
        const tokenId = mappings.coinmarketcap_mappings[tokenSymbol];
        if (!tokenId)
            return null;
        try {
            const response = yield fetchWithRetry(`${baseUrl}/cryptocurrency/quotes/latest?symbol=${tokenSymbol}`, { headers: { "X-CMC_PRO_API_KEY": apiKey } });
            return ((_d = (_c = (_b = (_a = response.data) === null || _a === void 0 ? void 0 : _a[tokenSymbol]) === null || _b === void 0 ? void 0 : _b.quote) === null || _c === void 0 ? void 0 : _c.USD) === null || _d === void 0 ? void 0 : _d.price) ? new bignumber_js_1.BigNumber(response.data[tokenSymbol].quote.USD.price) : null;
        }
        catch (error) {
            logger.error(`CMC error for ${tokenSymbol}:`, error);
            return null;
        }
    });
}
exports.fetchPriceFromCoinMarketCap = fetchPriceFromCoinMarketCap;
function fetchPriceFromBinance(baseUrl, tokenSymbol) {
    return __awaiter(this, void 0, void 0, function* () {
        const tradingPair = mappings.binance_mappings[tokenSymbol];
        if (!tradingPair)
            return null;
        try {
            const data = yield fetchWithRetry(`${baseUrl}/ticker/price?symbol=${tradingPair}`, {});
            return data.price ? new bignumber_js_1.BigNumber(data.price) : null;
        }
        catch (error) {
            logger.error(`Binance error for ${tokenSymbol}:`, error);
            return null;
        }
    });
}
exports.fetchPriceFromBinance = fetchPriceFromBinance;
let configObj;
function checkVolatilityThreshold(managerContract, tokenAddress, newPrice) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const tokenInfo = yield managerContract.methods.getTokenInfo(tokenAddress).call();
            const oldPrice = new bignumber_js_1.BigNumber(tokenInfo.pricePerUnit);
            const volatilityThreshold = new bignumber_js_1.BigNumber(tokenInfo.volatilityThreshold);
            if (volatilityThreshold.isZero() || configObj.volatility_threshold_bypass)
                return true;
            const newPriceBN = new bignumber_js_1.BigNumber(newPrice);
            const changeRatio = newPriceBN.minus(oldPrice).abs().multipliedBy(1e18).dividedBy(oldPrice);
            return changeRatio.lte(volatilityThreshold);
        }
        catch (error) {
            logger.error(`Volatility check failed for ${tokenAddress}:`, error);
            return true;
        }
    });
}
exports.checkVolatilityThreshold = checkVolatilityThreshold;
function updateIndividualPrice(web3, oracleContract, managerContract, account, tokenAddress, newPrice) {
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const passes = yield checkVolatilityThreshold(managerContract, tokenAddress, newPrice);
            if (!passes) {
                logger.warn(`Volatility threshold exceeded for ${tokenAddress}`);
                return false;
            }
            const tx = oracleContract.methods.updateRate(tokenAddress, newPrice);
            const gas = yield tx.estimateGas({ from: account.address });
            const gasPrice = yield web3.eth.getGasPrice();
            const nonce = yield web3.eth.getTransactionCount(account.address, "pending");
            const signedTx = yield account.signTransaction({
                to: oracleContract.options.address,
                data: tx.encodeABI(),
                gas,
                gasPrice,
                nonce,
            });
            const receipt = yield web3.eth.sendSignedTransaction(signedTx.rawTransaction);
            logger.info(`Individual update success: ${tokenAddress} -> ${receipt.transactionHash}`);
            exports.gasTracker.recordTransaction(receipt.transactionHash, receipt.gasUsed, gasPrice.toString(), // Convert bigint to string,  // Convert bigint to stringice,
            [tokenAddress]);
            return true;
        }
        catch (error) {
            logger.error(`Individual update failed for ${tokenAddress}:`, error);
            return false;
        }
    });
}
exports.updateIndividualPrice = updateIndividualPrice;
function processLAT(cfg) {
    var _a, _b, _c;
    return __awaiter(this, void 0, void 0, function* () {
        if (!cfg.contracts.oracle_address.startsWith("0x")) {
            throw new Error(`Invalid oracle address: ${cfg.contracts.oracle_address}`);
        }
        configObj = cfg;
        logger.info(`\n=== Processing LAT ${cfg.contracts.oracle_address.substring(0, 8)}... ===`);
        const web3 = new web3_1.default(cfg.web3.provider_uri);
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey)
            throw new Error("No private key in .env");
        const account = web3.eth.accounts.privateKeyToAccount(privateKey);
        web3.eth.accounts.wallet.add(account);
        const oracleAbi = JSON.parse(fs_1.default.readFileSync(path_1.default.join(__dirname, cfg.contracts.oracle_abi_path), "utf-8"));
        const oracleContract = new web3.eth.Contract(oracleAbi, cfg.contracts.oracle_address);
        const rateUpdaterRole = yield oracleContract.methods.RATE_UPDATER_ROLE().call();
        const hasRole = yield oracleContract.methods.hasRole(rateUpdaterRole, account.address).call();
        if (!hasRole)
            throw new Error(`Account ${account.address} missing RATE_UPDATER_ROLE`);
        const managerAbi = JSON.parse(fs_1.default.readFileSync(path_1.default.join(__dirname, cfg.contracts.manager_abi_path), "utf-8"));
        const managerContract = new web3.eth.Contract(managerAbi, cfg.contracts.manager_address);
        const tokenAddresses = Object.keys(cfg.token_mappings);
        const validUpdates = [];
        for (const tokenAddress of tokenAddresses) {
            const symbol = cfg.token_mappings[tokenAddress];
            const prices = [];
            if ((_a = cfg.price_providers.coingecko) === null || _a === void 0 ? void 0 : _a.enabled) {
                const price = yield fetchPriceFromCoingecko(cfg.price_providers.coingecko.base_url, symbol);
                if (price)
                    prices.push(price);
            }
            if ((_b = cfg.price_providers.coinmarketcap) === null || _b === void 0 ? void 0 : _b.enabled) {
                const price = yield fetchPriceFromCoinMarketCap(cfg.price_providers.coinmarketcap.base_url, cfg.price_providers.coinmarketcap.api_key, symbol);
                if (price)
                    prices.push(price);
            }
            if ((_c = cfg.price_providers.binance) === null || _c === void 0 ? void 0 : _c.enabled) {
                const price = yield fetchPriceFromBinance(cfg.price_providers.binance.base_url, symbol);
                if (price)
                    prices.push(price);
            }
            if (prices.length < 1) {
                logger.warn(`No prices for ${symbol}`);
                continue;
            }
            const medianPrice = getMedian(prices);
            const scaledPrice = medianPrice.times(Math.pow(10, PRICE_DECIMALS)).toFixed(0);
            if (yield checkVolatilityThreshold(managerContract, tokenAddress, scaledPrice)) {
                validUpdates.push({ address: tokenAddress, price: scaledPrice });
                logger.info(`✅ Valid update: ${symbol} -> ${scaledPrice}`);
            }
            else {
                logger.warn(`⛔️ Volatility rejection: ${symbol}`);
            }
        }
        if (validUpdates.length > 0) {
            const tokens = validUpdates.map(u => u.address);
            const prices = validUpdates.map(u => u.price);
            let retries = MAX_RETRIES;
            while (retries > 0) {
                try {
                    const tx = oracleContract.methods.batchUpdateRates(tokens, prices);
                    const gas = yield tx.estimateGas({ from: account.address });
                    const gasPrice = yield web3.eth.getGasPrice();
                    const nonce = yield web3.eth.getTransactionCount(account.address, "pending");
                    // Log the gas estimate before sending the transaction
                    logger.info(`Gas estimate for batch update: ${gas} units at ${web3_1.default.utils.fromWei(gasPrice, 'gwei')} gwei`);
                    logger.info(`Estimated cost: ${web3_1.default.utils.fromWei(new bignumber_js_1.BigNumber(gas).multipliedBy(new bignumber_js_1.BigNumber(gasPrice.toString())).toString(), 'ether')} ETH`);
                    const signedTx = yield account.signTransaction({
                        to: oracleContract.options.address,
                        data: tx.encodeABI(),
                        gas,
                        gasPrice,
                        nonce,
                    });
                    const receipt = yield web3.eth.sendSignedTransaction(signedTx.rawTransaction);
                    logger.info(`💎 Batch success: ${receipt.transactionHash}`);
                    exports.gasTracker.recordTransaction(receipt.transactionHash, // Now correctly typed as string
                    receipt.gasUsed, gasPrice.toString(), // Convert bigint to string,
                    tokens);
                    // Show wallet status after transaction
                    yield exports.gasTracker.logStats(web3, account);
                    break;
                }
                catch (error) {
                    if (--retries === 0) {
                        logger.error("Batch failed, fallback to individual updates");
                        if (cfg.individual_updates_on_batch_failure) {
                            for (const update of validUpdates) {
                                yield updateIndividualPrice(web3, oracleContract, managerContract, account, update.address, update.price);
                                yield sleep(1000);
                            }
                        }
                    }
                    else {
                        yield sleep(RETRY_DELAY_MS);
                    }
                }
            }
        }
        // Display gas stats at the end of processing
        yield exports.gasTracker.logStats(web3, account);
        logger.info(`=== LAT processing complete ===\n`);
    });
}
exports.processLAT = processLAT;
function main() {
    return __awaiter(this, void 0, void 0, function* () {
        const configDir = path_1.default.join(__dirname, "configs");
        const configFiles = fs_1.default.readdirSync(configDir).filter(f => f.endsWith(".json"));
        for (const configFile of configFiles) {
            const configPath = path_1.default.join(configDir, configFile);
            try {
                const cfg = JSON.parse(fs_1.default.readFileSync(configPath, "utf-8"));
                yield processLAT(cfg);
            }
            catch (error) {
                logger.error(`Error processing ${configFile}:`, error);
            }
        }
    });
}
exports.main = main;
function scheduleUpdates(configs) {
    var _a;
    const intervalMinutes = Math.max(15, Math.min(1440, ((_a = configs[0]) === null || _a === void 0 ? void 0 : _a.update_interval_minutes) || 720));
    node_schedule_1.default.scheduleJob(`*/${intervalMinutes} * * *`, main);
    logger.info(`Scheduled updates every ${intervalMinutes} minutes`);
}
exports.scheduleUpdates = scheduleUpdates;
function estimateGasRequirements() {
    return __awaiter(this, void 0, void 0, function* () {
        const configDir = path_1.default.join(__dirname, "configs");
        const configFiles = fs_1.default.readdirSync(configDir).filter(f => f.endsWith(".json"));
        const web3 = new web3_1.default(configFiles.length > 0
            ? JSON.parse(fs_1.default.readFileSync(path_1.default.join(configDir, configFiles[0]), "utf-8")).web3.provider_uri
            : "http://localhost:8545");
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey) {
            logger.error("No private key in .env - cannot estimate gas requirements");
            return;
        }
        const account = web3.eth.accounts.privateKeyToAccount(privateKey);
        const balance = yield web3.eth.getBalance(account.address);
        const ethBalance = web3_1.default.utils.fromWei(balance, 'ether');
        logger.info(`\n=== Gas Requirement Estimates ===`);
        logger.info(`Current wallet balance: ${ethBalance} ETH`);
        let totalTokens = 0;
        let totalConfigsProcessed = 0;
        for (const configFile of configFiles) {
            const configPath = path_1.default.join(configDir, configFile);
            try {
                const cfg = JSON.parse(fs_1.default.readFileSync(configPath, "utf-8"));
                const tokenCount = Object.keys(cfg.token_mappings).length;
                totalTokens += tokenCount;
                totalConfigsProcessed++;
                logger.info(`Config ${configFile}: ${tokenCount} tokens to update`);
            }
            catch (error) {
                logger.error(`Error analyzing ${configFile}:`, error);
            }
        }
        // Calculate estimates based on historical data if available
        if (exports.gasTracker.transactions.length > 0) {
            const avgGasPerToken = exports.gasTracker.transactions.reduce((sum, tx) => sum + tx.gasPerToken, 0) / exports.gasTracker.transactions.length;
            const recentGasPrice = yield web3.eth.getGasPrice();
            const estimatedGasForAllTokens = avgGasPerToken * totalTokens;
            const estimatedCostInEth = new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(recentGasPrice.toString())).div(new bignumber_js_1.BigNumber(10).pow(18));
            logger.info(`Based on historical data:`);
            logger.info(`  Average gas per token: ${Math.floor(avgGasPerToken)}`);
            logger.info(`  Current gas price: ${web3_1.default.utils.fromWei(recentGasPrice, 'gwei')} gwei`);
            logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
            logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
            // Calculate how many updates current balance can support
            if (parseFloat(ethBalance) > 0) {
                const supportedUpdates = new bignumber_js_1.BigNumber(balance.toString()).div(new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(recentGasPrice.toString())));
                logger.info(`  Current balance can support approximately ${Math.floor(supportedUpdates.toNumber())} complete update cycles`);
            }
        }
        else {
            // If no historical data, provide rough estimates
            const gasPrice = yield web3.eth.getGasPrice();
            // Conservative estimates
            const estimatedGasPerToken = 100000; // This is a conservative estimate
            const estimatedGasForAllTokens = estimatedGasPerToken * totalTokens;
            const estimatedCostInEth = new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(gasPrice.toString())).div(new bignumber_js_1.BigNumber(10).pow(18));
            logger.info(`No historical data available. Using conservative estimates:`);
            logger.info(`  Estimated gas per token: ${estimatedGasPerToken}`);
            logger.info(`  Current gas price: ${web3_1.default.utils.fromWei(gasPrice, 'gwei')} gwei`);
            logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
            logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
            if (parseFloat(ethBalance) > 0) {
                const supportedUpdates = new bignumber_js_1.BigNumber(balance.toString()).div(new bignumber_js_1.BigNumber(estimatedGasForAllTokens).multipliedBy(new bignumber_js_1.BigNumber(gasPrice.toString())));
            }
        }
        logger.info(`=== End of Gas Estimate ===\n`);
    });
}
exports.estimateGasRequirements = estimateGasRequirements;
exports.updater = {
    processLAT,
    main,
    scheduleUpdates,
    checkVolatilityThreshold,
    fetchPriceFromCoingecko,
    fetchPriceFromCoinMarketCap,
    fetchPriceFromBinance,
    updateIndividualPrice,
    estimateGasRequirements,
    gasTracker: exports.gasTracker
};
if (process.env.NODE_ENV !== "test" && !process.env.JEST_WORKER_ID) {
    // Run gas estimation first to provide funding guidance
    estimateGasRequirements()
        .then(() => main())
        .then(() => {
        const configDir = path_1.default.join(__dirname, "configs");
        const configFiles = fs_1.default.readdirSync(configDir).filter(f => f.endsWith(".json"));
        const configs = configFiles.map(file => {
            const configPath = path_1.default.join(configDir, file);
            return JSON.parse(fs_1.default.readFileSync(configPath, "utf-8"));
        });
        scheduleUpdates(configs);
    })
        .catch(logger.error);
}
