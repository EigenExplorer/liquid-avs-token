import { config as dotenvConfig } from "dotenv";
import Web3 from "web3";
import { AbiItem } from "web3-utils";
import fs from "fs";
import path from "path";
import fetch from "node-fetch";
import schedule from "node-schedule";
import { BigNumber as BN } from "bignumber.js";
import winston from "winston";
import { type TransactionReceipt } from "web3"; 

// Load environment variables
dotenvConfig();

// Logger setup
const logger = winston.createLogger({
  level: "info",
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: "error.log", level: "error" }),
    new winston.transports.File({ filename: "combined.log" }),
  ],
});

// Load mappings from external file
const mappingsPath = path.join(__dirname, "mappings.json");
const mappings = JSON.parse(fs.readFileSync(mappingsPath, "utf-8"));

export interface Config {
  web3: {
    provider_uri: string;
  };
  contracts: {
    oracle_address: string;
    oracle_abi_path: string;
    manager_address: string;
    manager_abi_path: string;
  };
  price_providers: {
    coingecko?: { enabled: boolean; base_url: string };
    coinmarketcap?: { enabled: boolean; base_url: string; api_key: string };
    binance?: { enabled: boolean; base_url: string };
  };
  token_mappings: { [address: string]: string };
  update_interval_minutes: number;
  volatility_threshold_bypass: boolean;
  individual_updates_on_batch_failure: boolean;
}

export interface TokenInfo {
  decimals: string;
  pricePerUnit: string;
  volatilityThreshold: string;
}

export interface GasTransaction {
  txHash: string;
  timestamp: number;
  gasUsed: number;
  gasPrice: string;
  ethCost: string;
  tokensUpdated: number;
  gasPerToken: number;
}

export interface GasTrackerData {
  totalGasUsed: number;
  totalEthSpent: string;
  transactions: GasTransaction[];
}

// Gas tracker for monitoring transaction costs
export const gasTracker = {
  transactions: [] as GasTransaction[],
  totalGasUsed: 0,
  totalEthSpent: "0",
  
  // Record a new transaction
  recordTransaction: function(txHash: string, gasUsed: number, gasPrice: string, tokens: string[]) {
    const ethCost = new BN(gasUsed).multipliedBy(new BN(gasPrice)).div(new BN(10).pow(18));
    
    this.transactions.push({
      txHash,
      timestamp: Date.now(),
      gasUsed,
      gasPrice: Web3.utils.fromWei(gasPrice, 'gwei'),
      ethCost: ethCost.toString(),
      tokensUpdated: tokens.length,
      gasPerToken: Math.floor(gasUsed / tokens.length)
    });
    
    this.totalGasUsed += gasUsed;
    this.totalEthSpent = new BN(this.totalEthSpent).plus(ethCost).toString();
    
    // Save transaction log to file
    this.saveToFile();
    
    // Log current stats
    this.logStats();
  },
  
  // Log current gas usage statistics
  logStats: async function(web3?: Web3, account?: any) {
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
        const balance = await web3.eth.getBalance(account.address);
        const ethBalance = Web3.utils.fromWei(balance, 'ether');
        logger.info(`Remaining wallet balance: ${ethBalance} ETH`);
        
        // Estimate remaining updates possible
        if (avgGasPerTx > 0) {
          const price = await web3.eth.getGasPrice();
          const priceBN = new BN(price.toString());
          const ethPerTx = new BN(avgGasPerTx).multipliedBy(priceBN).div(new BN(10).pow(18));
          const estimatedRemainingTxs = new BN(balance.toString()).div(new BN(avgGasPerTx).multipliedBy(priceBN));          logger.info(`Estimated remaining updates: ~${Math.floor(estimatedRemainingTxs.toNumber())}`);
          logger.info(`Estimated ETH per update: ${ethPerTx.toString()} ETH`);
        }
      } catch (error) {
        logger.error("Error calculating wallet statistics:", error);
      }
    }
  },
  
  // Save transaction history to file
  saveToFile: function() {
    try {
      const data: GasTrackerData = {
        totalGasUsed: this.totalGasUsed,
        totalEthSpent: this.totalEthSpent,
        transactions: this.transactions
      };
      
      fs.writeFileSync('gas_tracker.json', JSON.stringify(data, null, 2));
    } catch (error) {
      logger.error("Error saving gas tracker data:", error);
    }
  },
  
  // Load transaction history from file
  loadFromFile: function() {
    try {
      if (fs.existsSync('gas_tracker.json')) {
        const data = JSON.parse(fs.readFileSync('gas_tracker.json', 'utf-8')) as GasTrackerData;
        this.transactions = data.transactions;
        this.totalGasUsed = data.totalGasUsed;
        this.totalEthSpent = data.totalEthSpent;
        logger.info("Loaded gas tracker data from file");
      }
    } catch (error) {
      logger.error("Error loading gas tracker data:", error);
    }
  }
};

// Load gas tracker data at startup
gasTracker.loadFromFile();

const PRICE_DECIMALS = 18;
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 5000;

export function getMedian(prices: BN[]): BN {
  const sorted = prices.sort((a, b) => a.comparedTo(b));
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 !== 0 ? sorted[mid] : sorted[mid - 1].plus(sorted[mid]).div(2);
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function fetchWithRetry(url: string, options: any, retries: number = MAX_RETRIES): Promise<any> {
  try {
    const response = await fetch(url, options);
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
    return await response.json();
  } catch (error) {
    if (retries > 0) {
      logger.warn(`Retrying... attempts left: ${retries}`);
      await sleep(RETRY_DELAY_MS);
      return fetchWithRetry(url, options, retries - 1);
    }
    throw error;
  }
}

export async function fetchPriceFromCoingecko(baseUrl: string, tokenSymbol: string): Promise<BN | null> {
  const tokenId = mappings.coingecko_mappings[tokenSymbol.toLowerCase()];
  if (!tokenId) return null;
  try {
    const data = await fetchWithRetry(
      `${baseUrl}/simple/price?ids=${tokenId}&vs_currencies=usd&precision=full`,
      {}
    );
    return data[tokenId]?.usd ? new BN(data[tokenId].usd) : null;
  } catch (error) {
    logger.error(`CoinGecko error for ${tokenSymbol}:`, error);
    return null;
  }
}

export async function fetchPriceFromCoinMarketCap(baseUrl: string, apiKey: string, tokenSymbol: string): Promise<BN | null> {
  const tokenId = mappings.coinmarketcap_mappings[tokenSymbol];
  if (!tokenId) return null;
  try {
    const response = await fetchWithRetry(
      `${baseUrl}/cryptocurrency/quotes/latest?symbol=${tokenSymbol}`,
      { headers: { "X-CMC_PRO_API_KEY": apiKey } }
    );
    return response.data?.[tokenSymbol]?.quote?.USD?.price ? new BN(response.data[tokenSymbol].quote.USD.price) : null;
  } catch (error) {
    logger.error(`CMC error for ${tokenSymbol}:`, error);
    return null;
  }
}

export async function fetchPriceFromBinance(baseUrl: string, tokenSymbol: string): Promise<BN | null> {
  const tradingPair = mappings.binance_mappings[tokenSymbol];
  if (!tradingPair) return null;
  try {
    const data = await fetchWithRetry(`${baseUrl}/ticker/price?symbol=${tradingPair}`, {});
    return data.price ? new BN(data.price) : null;
  } catch (error) {
    logger.error(`Binance error for ${tokenSymbol}:`, error);
    return null;
  }
}

let configObj: Config;

export async function checkVolatilityThreshold(managerContract: any, tokenAddress: string, newPrice: string): Promise<boolean> {
  try {
    const tokenInfo = await managerContract.methods.getTokenInfo(tokenAddress).call() as TokenInfo;
    const oldPrice = new BN(tokenInfo.pricePerUnit);
    const volatilityThreshold = new BN(tokenInfo.volatilityThreshold);
    if (volatilityThreshold.isZero() || configObj.volatility_threshold_bypass) return true;
    const newPriceBN = new BN(newPrice);
    const changeRatio = newPriceBN.minus(oldPrice).abs().multipliedBy(1e18).dividedBy(oldPrice);
    return changeRatio.lte(volatilityThreshold);
  } catch (error) {
    logger.error(`Volatility check failed for ${tokenAddress}:`, error);
    return true;
  }
}

export async function updateIndividualPrice(
  web3: Web3,
  oracleContract: any,
  managerContract: any,
  account: any,
  tokenAddress: string,
  newPrice: string
): Promise<boolean> {
  try {
    const passes = await checkVolatilityThreshold(managerContract, tokenAddress, newPrice);
    if (!passes) {
      logger.warn(`Volatility threshold exceeded for ${tokenAddress}`);
      return false;
    }
    const tx = oracleContract.methods.updateRate(tokenAddress, newPrice);
    const gas = await tx.estimateGas({ from: account.address });
    const gasPrice = await web3.eth.getGasPrice();
    const nonce = await web3.eth.getTransactionCount(account.address, "pending");
    const signedTx = await account.signTransaction({
      to: oracleContract.options.address,
      data: tx.encodeABI(),
      gas,
      gasPrice,
      nonce,
    });
    const receipt: TransactionReceipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
  logger.info(`Individual update success: ${tokenAddress} -> ${receipt.transactionHash}`);
  gasTracker.recordTransaction(
    receipt.transactionHash.toString(), 
    Number(receipt.gasUsed),  // Convert to Number
    gasPrice.toString(),  // Convert bigint to string,
    [tokenAddress]
  );
    
    return true;
  } catch (error) {
    logger.error(`Individual update failed for ${tokenAddress}:`, error);
    return false;
  }
}

export async function processLAT(cfg: Config) {
  if (!cfg.contracts.oracle_address.startsWith("0x")) {
    throw new Error(`Invalid oracle address: ${cfg.contracts.oracle_address}`);
  }
  configObj = cfg;
  logger.info(`\n=== Processing LAT ${cfg.contracts.oracle_address.substring(0, 8)}... ===`);
  const web3 = new Web3(cfg.web3.provider_uri);
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error("No private key in .env");
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  web3.eth.accounts.wallet.add(account);
  const oracleAbi: AbiItem[] = JSON.parse(fs.readFileSync(path.join(__dirname, cfg.contracts.oracle_abi_path), "utf-8"));
  const oracleContract = new web3.eth.Contract(oracleAbi, cfg.contracts.oracle_address);
  const rateUpdaterRole = await oracleContract.methods.RATE_UPDATER_ROLE().call();
  const hasRole = await oracleContract.methods.hasRole(rateUpdaterRole, account.address).call();
  if (!hasRole) throw new Error(`Account ${account.address} missing RATE_UPDATER_ROLE`);
  const managerAbi: AbiItem[] = JSON.parse(fs.readFileSync(path.join(__dirname, cfg.contracts.manager_abi_path), "utf-8"));
  const managerContract = new web3.eth.Contract(managerAbi, cfg.contracts.manager_address);
  const tokenAddresses = Object.keys(cfg.token_mappings);
  const validUpdates: { address: string; price: string }[] = [];
  for (const tokenAddress of tokenAddresses) {
    const symbol = cfg.token_mappings[tokenAddress];
    const prices: BN[] = [];
    if (cfg.price_providers.coingecko?.enabled) {
      const price = await fetchPriceFromCoingecko(cfg.price_providers.coingecko.base_url, symbol);
      if (price) prices.push(price);
    }
    if (cfg.price_providers.coinmarketcap?.enabled) {
      const price = await fetchPriceFromCoinMarketCap(
        cfg.price_providers.coinmarketcap.base_url,
        cfg.price_providers.coinmarketcap.api_key,
        symbol
      );
      if (price) prices.push(price);
    }
    if (cfg.price_providers.binance?.enabled) {
      const price = await fetchPriceFromBinance(cfg.price_providers.binance.base_url, symbol);
      if (price) prices.push(price);
    }
    if (prices.length < 1) {
      logger.warn(`No prices for ${symbol}`);
      continue;
    }
    const medianPrice = getMedian(prices);
    const scaledPrice = medianPrice.times(10 ** PRICE_DECIMALS).toFixed(0);
    if (await checkVolatilityThreshold(managerContract, tokenAddress, scaledPrice)) {
      validUpdates.push({ address: tokenAddress, price: scaledPrice });
      logger.info(`✅ Valid update: ${symbol} -> ${scaledPrice}`);
    } else {
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
        const gas = await tx.estimateGas({ from: account.address });
        const gasPrice = await web3.eth.getGasPrice();
        const nonce = await web3.eth.getTransactionCount(account.address, "pending");
        
        // Log the gas estimate before sending the transaction
        logger.info(`Gas estimate for batch update: ${gas} units at ${Web3.utils.fromWei(gasPrice, 'gwei')} gwei`);
        logger.info(`Estimated cost: ${Web3.utils.fromWei(new BN(gas.toString()).multipliedBy(new BN(gasPrice.toString())).toString(), 'ether')} ETH`);
        const signedTx = await account.signTransaction({
          to: oracleContract.options.address,
          data: tx.encodeABI(),
          gas,
          gasPrice,
          nonce,
        });
        const receipt: TransactionReceipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
        logger.info(`💎 Batch success: ${receipt.transactionHash}`);
        gasTracker.recordTransaction(
          receipt.transactionHash.toString(), 
          Number(receipt.gasUsed),  // Convert to Number
          gasPrice.toString(),  // Convert bigint to string,
          tokens
        );
        
        // Show wallet status after transaction
        await gasTracker.logStats(web3, account);
        
        break;
      } catch (error) {
        if (--retries === 0) {
          logger.error("Batch failed, fallback to individual updates");
          if (cfg.individual_updates_on_batch_failure) {
            for (const update of validUpdates) {
              await updateIndividualPrice(web3, oracleContract, managerContract, account, update.address, update.price);
              await sleep(1000);
            }
          }
        } else {
          await sleep(RETRY_DELAY_MS);
        }
      }
    }
  }
  
  // Display gas stats at the end of processing
  await gasTracker.logStats(web3, account);
  
  logger.info(`=== LAT processing complete ===\n`);
}

export async function main() {
  const configDir = path.join(__dirname, "configs");
  const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith(".json"));
  for (const configFile of configFiles) {
    const configPath = path.join(configDir, configFile);
    try {
      const cfg: Config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
      await processLAT(cfg);
    } catch (error) {
      logger.error(`Error processing ${configFile}:`, error);
    }
  }
}

export function scheduleUpdates(configs: Config[]) {
  const intervalMinutes = Math.max(15, Math.min(1440, configs[0]?.update_interval_minutes || 720));
  schedule.scheduleJob(`*/${intervalMinutes} * * *`, main);
  logger.info(`Scheduled updates every ${intervalMinutes} minutes`);
}

export async function estimateGasRequirements() {
  const configDir = path.join(__dirname, "configs");
  const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith(".json"));
  const web3 = new Web3(configFiles.length > 0 
    ? JSON.parse(fs.readFileSync(path.join(configDir, configFiles[0]), "utf-8")).web3.provider_uri
    : "http://localhost:8545");
  
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    logger.error("No private key in .env - cannot estimate gas requirements");
    return;
  }
  
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  const balance = await web3.eth.getBalance(account.address);
  const ethBalance = Web3.utils.fromWei(balance, 'ether');
  
  logger.info(`\n=== Gas Requirement Estimates ===`);
  logger.info(`Current wallet balance: ${ethBalance} ETH`);
  
  let totalTokens = 0;
  let totalConfigsProcessed = 0;
  
  for (const configFile of configFiles) {
    const configPath = path.join(configDir, configFile);
    try {
      const cfg: Config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
      const tokenCount = Object.keys(cfg.token_mappings).length;
      totalTokens += tokenCount;
      totalConfigsProcessed++;
      
      logger.info(`Config ${configFile}: ${tokenCount} tokens to update`);
    } catch (error) {
      logger.error(`Error analyzing ${configFile}:`, error);
    }
  }
  
  // Calculate estimates based on historical data if available
  if (gasTracker.transactions.length > 0) {
    const avgGasPerToken = gasTracker.transactions.reduce((sum, tx) => sum + tx.gasPerToken, 0) / gasTracker.transactions.length;
    const recentGasPrice = await web3.eth.getGasPrice();
    
    const estimatedGasForAllTokens = avgGasPerToken * totalTokens;
const estimatedCostInEth = new BN(estimatedGasForAllTokens).multipliedBy(new BN(recentGasPrice.toString())).div(new BN(10).pow(18));    
    logger.info(`Based on historical data:`);
    logger.info(`  Average gas per token: ${Math.floor(avgGasPerToken)}`);
    logger.info(`  Current gas price: ${Web3.utils.fromWei(recentGasPrice, 'gwei')} gwei`);
    logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
    logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
    
    // Calculate how many updates current balance can support
    if (parseFloat(ethBalance) > 0) {
      const supportedUpdates = new BN(balance.toString()).div(new BN(estimatedGasForAllTokens).multipliedBy(new BN(recentGasPrice.toString())));      
      logger.info(`  Current balance can support approximately ${Math.floor(supportedUpdates.toNumber())} complete update cycles`);
    }
  } else {
    // If no historical data, provide rough estimates
    const gasPrice = await web3.eth.getGasPrice();
    
    // Conservative estimates
    const estimatedGasPerToken = 100000; // This is a conservative estimate
    const estimatedGasForAllTokens = estimatedGasPerToken * totalTokens;
    const estimatedCostInEth = new BN(estimatedGasForAllTokens).multipliedBy(new BN(gasPrice.toString())).div(new BN(10).pow(18));    
    logger.info(`No historical data available. Using conservative estimates:`);
    logger.info(`  Estimated gas per token: ${estimatedGasPerToken}`);
    logger.info(`  Current gas price: ${Web3.utils.fromWei(gasPrice, 'gwei')} gwei`);
    logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
    logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
    
    if (parseFloat(ethBalance) > 0) {
      const supportedUpdates = new BN(balance.toString()).div(new BN(estimatedGasForAllTokens).multipliedBy(new BN(gasPrice.toString())));    }
  }
  
  logger.info(`=== End of Gas Estimate ===\n`);
}

export const updater = {
  processLAT,
  main,
  scheduleUpdates,
  checkVolatilityThreshold,
  fetchPriceFromCoingecko,
  fetchPriceFromCoinMarketCap,
  fetchPriceFromBinance,
  updateIndividualPrice,
  estimateGasRequirements,
  gasTracker
};

if (process.env.NODE_ENV !== "test" && !process.env.JEST_WORKER_ID) {
  // Run gas estimation first to provide funding guidance
  estimateGasRequirements()
    .then(() => main())
    .then(() => {
      const configDir = path.join(__dirname, "configs");
      const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith(".json"));
      const configs: Config[] = configFiles.map(file => {
        const configPath = path.join(configDir, file);
        return JSON.parse(fs.readFileSync(configPath, "utf-8"));
      });
      scheduleUpdates(configs);
    })
    .catch(logger.error);
}