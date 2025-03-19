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
const logger = winston.createLogger({
  level: ENV.LOG_LEVEL,
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

// Safely load mappings from external file with error handling
let mappings: any;
try {
  const mappingsPath = path.join(__dirname, "mappings.json");
  if (!fs.existsSync(mappingsPath)) {
    logger.error(`Mappings file not found: ${mappingsPath}`);
    throw new Error(`Mappings file not found: ${mappingsPath}`);
  }
  mappings = JSON.parse(fs.readFileSync(mappingsPath, "utf-8"));
  logger.info("Successfully loaded token mappings");
} catch (error) {
  logger.error(`Failed to load mappings file: ${error}`);
  throw new Error(`Failed to load mappings: ${error}`);
}

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
    coingecko?: { enabled: boolean; base_url: string; api_key?: string };
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

// Function to load deployment data and create configurations
export function loadDeploymentData(): Config[] {
  try {
    // Load the deployment data
    const deploymentPath = path.resolve(process.cwd(), ENV.DEPLOYMENT_PATH);
    
    if (!fs.existsSync(deploymentPath)) {
      logger.warn(`Deployment data not found at ${deploymentPath}`);
      return [];
    }
    
    const deploymentData = JSON.parse(fs.readFileSync(deploymentPath, "utf-8"));
    logger.info(`Successfully loaded deployment data from ${deploymentPath}`);
    
    // Extract data from DeployMainnet.s.sol structure
    const configs: Config[] = [];
    
    // Check for contract deployments structure
    if (deploymentData.contractDeployments) {
      logger.info("Processing data using contractDeployments structure");
      
      // First check for regular LAT structure
      if (deploymentData.contractDeployments.proxy?.tokenRegistryOracle?.address && 
          deploymentData.contractDeployments.proxy?.liquidTokenManager?.address) {
        
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
          } else {
            tokenArray = Object.values(deploymentData.tokens);
          }
        }
        
        if (tokenArray.length > 0) {
          logger.info(`Found ${tokenArray.length} tokens in deployment data`);
          
          // Build a mapping of token addresses to symbols
          const tokenMappings: {[address: string]: string} = {};
          
          for (const token of tokenArray) {
            const address = token.address || token.addresses?.token;
            const symbol = token.symbol;
            
            if (address && symbol) {
              tokenMappings[address] = symbol;
              logger.info(`Mapped token ${symbol} at address ${address.substring(0, 8)}...`);
            }
          }
          
          if (Object.keys(tokenMappings).length > 0) {
            // Create a config for the LAT instance
            const config: Config = {
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
        if (instance.oracle?.address && instance.manager?.address && instance.tokens) {
          const oracleAddress = instance.oracle.address;
          const managerAddress = instance.manager.address;
          
          logger.info(`Processing LAT instance with oracle: ${oracleAddress.substring(0, 8)}...`);
          
          // Build token mappings
          const tokenMappings: {[address: string]: string} = {};
          
          for (const token of instance.tokens) {
            const address = token.address;
            const symbol = token.symbol;
            
            if (address && symbol) {
              tokenMappings[address] = symbol;
            }
          }
          
          if (Object.keys(tokenMappings).length > 0) {
            const config: Config = {
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
    } else {
      logger.info(`Successfully created ${configs.length} LAT configurations`);
    }
    
    return configs;
  } catch (error) {
    logger.error(`Failed to load deployment data: ${error}`);
    return [];
  }
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
          const estimatedRemainingTxs = new BN(balance.toString()).div(new BN(avgGasPerTx).multipliedBy(priceBN));
          logger.info(`Estimated remaining updates: ~${Math.floor(estimatedRemainingTxs.toNumber())}`);
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

/**
 * Normalizes price data from various API formats to ensure consistent BN representation
 * @param priceData The raw price data from API
 * @param source The source name for logging
 * @param symbol The token symbol for logging
 * @returns Normalized BigNumber or null if invalid
 */
export function normalizePriceData(priceData: any, source: string, symbol: string): BN | null {
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
      return new BN(priceData);
    }
    
    // Handle number values
    if (typeof priceData === 'number') {
      if (!isFinite(priceData)) {
        logger.warn(`${source}: Non-finite price for ${symbol}: ${priceData}`);
        return null;
      }
      return new BN(priceData);
    }

    // For other types, try toString conversion
    return new BN(priceData.toString());
  } catch (error) {
    logger.warn(`${source}: Failed to normalize price for ${symbol}: ${error}`);
    return null;
  }
}

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
    if (!response.ok) {
      const statusText = response.statusText;
      const responseBody = await response.text().catch(() => "");
      throw new Error(`HTTP error! Status: ${response.status}, Message: ${statusText}, Body: ${responseBody.substring(0, 200)}`);
    }
    return await response.json();
  } catch (error) {
    if (retries > 0) {
      logger.warn(`API request failed, retrying in ${RETRY_DELAY_MS}ms... Attempts left: ${retries}`);
      await sleep(RETRY_DELAY_MS);
      return fetchWithRetry(url, options, retries - 1);
    }
    throw error;
  }
}

/**
 * Fetches the current ETH/USD price from CoinGecko with fallback
 * @returns ETH/USD price as BigNumber or a fallback value if the API fails
 */
export async function fetchEthUsdPrice(baseUrl: string = ENV.COINGECKO_BASE_URL): Promise<BN> {
  try {
    logger.info(`Fetching ETH/USD price from CoinGecko...`);
    const data = await fetchWithRetry(
      `${baseUrl}/simple/price?ids=ethereum&vs_currencies=usd&precision=full`,
      {}
    );
    
    if (!data || !data.ethereum || data.ethereum.usd === undefined) {
      throw new Error("Invalid response format from CoinGecko");
    }
    
    const price = normalizePriceData(data.ethereum.usd, 'CoinGecko', 'ETH');
    if (!price || price.isZero()) {
      throw new Error("Received zero or invalid ETH price");
    }
    
    logger.info(`Fetched ETH/USD price: ${price.toString()} USD per ETH`);
    return price;
  } catch (error) {
    logger.error(`Failed to fetch ETH/USD price: ${error instanceof Error ? error.message : String(error)}`);
    
    // Return fallback price if API call fails
    logger.warn(`Using fallback ETH price: ${FALLBACK_ETH_USD_PRICE} USD per ETH`);
    return new BN(FALLBACK_ETH_USD_PRICE);
  }
}

/**
 * Converts a token's USD price to ETH price
 */
export function convertUsdToEthPrice(tokenSymbol: string, tokenUsdPrice: BN, ethUsdPrice: BN): BN {
  // Formula: tokenPriceInEth = tokenPriceInUsd / ethPriceInUsd
  const tokenEthPrice = tokenUsdPrice.div(ethUsdPrice);
  logger.info(`Converting ${tokenSymbol}: ${tokenUsdPrice.toString()} USD ÷ ${ethUsdPrice.toString()} USD/ETH = ${tokenEthPrice.toString()} ETH`);
  return tokenEthPrice;
}

export async function fetchPriceFromCoingecko(baseUrl: string, tokenSymbol: string): Promise<BN | null> {
  const tokenId = mappings.coingecko_mappings?.[tokenSymbol.toLowerCase()];
  if (!tokenId) {
    logger.debug(`CoinGecko: No mapping found for ${tokenSymbol}`);
    return null;
  }
  
  try {
    logger.debug(`CoinGecko: Fetching price for ${tokenSymbol} (ID: ${tokenId})`);
    const data = await fetchWithRetry(
      `${baseUrl}/simple/price?ids=${tokenId}&vs_currencies=usd&precision=full`,
      {}
    );
    
    if (!data || !data[tokenId] || data[tokenId].usd === undefined) {
      logger.warn(`CoinGecko: Invalid response format for ${tokenSymbol}`);
      return null;
    }
    
    const price = normalizePriceData(data[tokenId].usd, 'CoinGecko', tokenSymbol);
    if (price) {
      logger.info(`CoinGecko: Got price for ${tokenSymbol}: ${price.toString()} USD`);
    }
    return price;
  } catch (error) {
    logger.error(`CoinGecko API error for ${tokenSymbol}: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}

export async function fetchPriceFromCoinMarketCap(baseUrl: string, apiKey: string, tokenSymbol: string): Promise<BN | null> {
  const tokenId = mappings.coinmarketcap_mappings?.[tokenSymbol];
  if (!tokenId) {
    logger.debug(`CoinMarketCap: No mapping found for ${tokenSymbol}`);
    return null;
  }
  
  try {
    logger.debug(`CoinMarketCap: Fetching price for ${tokenSymbol}`);
    const response = await fetchWithRetry(
      `${baseUrl}/cryptocurrency/quotes/latest?symbol=${tokenSymbol}`,
      { headers: { "X-CMC_PRO_API_KEY": apiKey } }
    );
    
    // Safe navigation through the CMC response structure
    if (!response?.data?.[tokenSymbol]?.quote?.USD?.price) {
      logger.warn(`CoinMarketCap: Invalid response format for ${tokenSymbol}`);
      return null;
    }
    
    const price = normalizePriceData(response.data[tokenSymbol].quote.USD.price, 'CoinMarketCap', tokenSymbol);
    if (price) {
      logger.info(`CoinMarketCap: Got price for ${tokenSymbol}: ${price.toString()} USD`);
    }
    return price;
  } catch (error) {
    logger.error(`CoinMarketCap API error for ${tokenSymbol}: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}

export async function fetchPriceFromBinance(baseUrl: string, tokenSymbol: string): Promise<BN | null> {
  const tradingPair = mappings.binance_mappings?.[tokenSymbol];
  if (!tradingPair) {
    logger.debug(`Binance: No mapping found for ${tokenSymbol}`);
    return null;
  }
  
  try {
    logger.debug(`Binance: Fetching price for ${tokenSymbol} (Pair: ${tradingPair})`);
    const data = await fetchWithRetry(`${baseUrl}/ticker/price?symbol=${tradingPair}`, {});
    
    if (!data?.price) {
      logger.warn(`Binance: Invalid response format for ${tokenSymbol}`);
      return null;
    }
    
    const price = normalizePriceData(data.price, 'Binance', tokenSymbol);
    if (price) {
      logger.info(`Binance: Got price for ${tokenSymbol}: ${price.toString()} USD`);
    }
    return price;
  } catch (error) {
    logger.error(`Binance API error for ${tokenSymbol}: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}

let configObj: Config;

export async function checkVolatilityThreshold(managerContract: any, tokenAddress: string, newPrice: string): Promise<boolean> {
  try {
    const tokenInfo = await managerContract.methods.getTokenInfo(tokenAddress).call() as TokenInfo;
    const oldPrice = new BN(tokenInfo.pricePerUnit);
    const volatilityThreshold = new BN(tokenInfo.volatilityThreshold);
    
    // Skip check if threshold is zero or bypass is enabled
    if (volatilityThreshold.isZero() || configObj.volatility_threshold_bypass) {
      return true;
    }
    
    const newPriceBN = new BN(newPrice);
    const changeRatio = newPriceBN.minus(oldPrice).abs().multipliedBy(1e18).dividedBy(oldPrice);
    
    const result = changeRatio.lte(volatilityThreshold);
    logger.info(`Volatility check for ${tokenAddress}: Old=${oldPrice.toString()}, New=${newPriceBN.toString()}, Change=${changeRatio.div(1e18).times(100).toFixed(2)}%, Threshold=${volatilityThreshold.div(1e18).times(100).toFixed(2)}%, Passed=${result}`);
    
    return result;
  } catch (error) {
    logger.error(`Volatility check failed for ${tokenAddress}:`, error);
    // Return true on error to avoid permanently blocking updates due to technical issues
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
  const symbol = Object.entries(configObj.token_mappings).find(([addr]) => addr === tokenAddress)?.[1] || 'unknown';
  logger.info(`Attempting individual price update for ${symbol} (${tokenAddress.substring(0, 8)}...): ${newPrice}`);
  
  try {
    const passes = await checkVolatilityThreshold(managerContract, tokenAddress, newPrice);
    if (!passes) {
      logger.warn(`⚠️ Volatility threshold exceeded for ${symbol} (${tokenAddress.substring(0, 8)}...)`);
      return false;
    }
    
    const tx = oracleContract.methods.updateRate(tokenAddress, newPrice);
    const gas = await tx.estimateGas({ from: account.address });
    const gasPrice = await web3.eth.getGasPrice();
    
    logger.info(`Gas estimate for ${symbol}: ${gas} units at ${Web3.utils.fromWei(gasPrice, 'gwei')} gwei`);
    
    const nonce = await web3.eth.getTransactionCount(account.address, "pending");
    const signedTx = await account.signTransaction({
      to: oracleContract.options.address,
      data: tx.encodeABI(),
      gas,
      gasPrice,
      nonce,
    });
    
    logger.info(`Submitting transaction for ${symbol}...`);
    const receipt: TransactionReceipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
    
    logger.info(`✅ Individual update success: ${symbol} -> ${receipt.transactionHash}`);
    gasTracker.recordTransaction(
      receipt.transactionHash.toString(), 
      Number(receipt.gasUsed),
      gasPrice.toString(),
      [tokenAddress]
    );
    
    return true;
  } catch (error) {
    logger.error(`❌ Individual update failed for ${symbol} (${tokenAddress.substring(0, 8)}...): ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

export async function processLAT(cfg: Config) {
  if (!cfg.contracts.oracle_address.startsWith("0x")) {
    throw new Error(`Invalid oracle address: ${cfg.contracts.oracle_address}`);
  }
  
  configObj = cfg;
  logger.info(`\n=== Processing LAT ${cfg.contracts.oracle_address.substring(0, 8)}... ===`);
  
  // Create web3 connection and load account
  let web3: Web3;
  try {
    web3 = new Web3(cfg.web3.provider_uri);
    
    // Verify connection
    await web3.eth.getBlockNumber();
    logger.info(`Connected to blockchain at ${cfg.web3.provider_uri}`);
  } catch (error) {
    logger.error(`Failed to connect to blockchain at ${cfg.web3.provider_uri}:`, error);
    throw new Error(`Web3 connection failed: ${error}`);
  }
  
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error("No private key in .env");
  
  const account = web3.eth.accounts.privateKeyToAccount(privateKey);
  web3.eth.accounts.wallet.add(account);
  logger.info(`Using account: ${account.address.substring(0, 8)}...`);
  
  // Load contracts
  let oracleContract, managerContract;
  try {
    const oracleAbi: AbiItem[] = JSON.parse(fs.readFileSync(path.join(__dirname, cfg.contracts.oracle_abi_path), "utf-8"));
    oracleContract = new web3.eth.Contract(oracleAbi, cfg.contracts.oracle_address);
    
    const rateUpdaterRole = await oracleContract.methods.RATE_UPDATER_ROLE().call();
    const hasRole = await oracleContract.methods.hasRole(rateUpdaterRole, account.address).call();
    
    if (!hasRole) {
      throw new Error(`Account ${account.address} missing RATE_UPDATER_ROLE`);
    }
    
    const managerAbi: AbiItem[] = JSON.parse(fs.readFileSync(path.join(__dirname, cfg.contracts.manager_abi_path), "utf-8"));
    managerContract = new web3.eth.Contract(managerAbi, cfg.contracts.manager_address);
    
    logger.info(`Contracts loaded successfully. Oracle: ${cfg.contracts.oracle_address.substring(0, 8)}..., Manager: ${cfg.contracts.manager_address.substring(0, 8)}...`);
  } catch (error) {
    logger.error("Failed to load contracts:", error);
    throw error;
  }
  
  // Get tokens to update
  const tokenAddresses = Object.keys(cfg.token_mappings);
  logger.info(`Found ${tokenAddresses.length} tokens to update`);
  
  // Fetch ETH/USD price first - this is essential for conversion
  const ethUsdPrice = await fetchEthUsdPrice();
  logger.info(`Using ETH/USD price: ${ethUsdPrice.toString()} USD per ETH`);
  
  const validUpdates: { address: string; price: string }[] = [];
  
  // Process each token
  for (const tokenAddress of tokenAddresses) {
    const symbol = cfg.token_mappings[tokenAddress];
    logger.info(`\nProcessing token: ${symbol} (${tokenAddress.substring(0, 8)}...)`);
    
    const prices: BN[] = [];
    const priceSources: string[] = [];
    
    // Fetch prices from all configured providers
    if (cfg.price_providers.coingecko?.enabled) {
      try {
        const price = await fetchPriceFromCoingecko(cfg.price_providers.coingecko.base_url, symbol);
        if (price) {
          prices.push(price);
          priceSources.push("CoinGecko");
        }
      } catch (error) {
        logger.error(`Failed to fetch price from CoinGecko for ${symbol}:`, error);
      }
    }
    
    if (cfg.price_providers.coinmarketcap?.enabled) {
      try {
        const price = await fetchPriceFromCoinMarketCap(
          cfg.price_providers.coinmarketcap.base_url,
          cfg.price_providers.coinmarketcap.api_key,
          symbol
        );
        if (price) {
          prices.push(price);
          priceSources.push("CoinMarketCap");
        }
      } catch (error) {
        logger.error(`Failed to fetch price from CoinMarketCap for ${symbol}:`, error);
      }
    }
    
    if (cfg.price_providers.binance?.enabled) {
      try {
        const price = await fetchPriceFromBinance(cfg.price_providers.binance.base_url, symbol);
        if (price) {
          prices.push(price);
          priceSources.push("Binance");
        }
      } catch (error) {
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
const usdPriceBN = new BN(usdPriceStr);
const ethUsdPriceBN = new BN(ethUsdPriceStr);

// Perform division to get ETH price
const ethPriceBN = usdPriceBN.div(ethUsdPriceBN);
logger.info(`${symbol}: Price in ETH: ${ethPriceBN.toString()} ETH`);

// Scale to on-chain representation (multiply by 10^18)
const scaledPrice = ethPriceBN.times(new BN(10).pow(PRICE_DECIMALS)).toFixed(0);
logger.info(`${symbol}: Final blockchain value: ${scaledPrice} (${ethPriceBN.toString()} ETH)`);

// Add to validUpdates with the ETH price
if (await checkVolatilityThreshold(managerContract, tokenAddress, scaledPrice)) {
    validUpdates.push({ address: tokenAddress, price: scaledPrice });
    logger.info(`✅ Valid update: ${symbol} -> ${scaledPrice} (${ethPriceBN.toString()} ETH)`);
} else {
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
        const gas = await tx.estimateGas({ from: account.address });
        const gasPrice = await web3.eth.getGasPrice();
        const nonce = await web3.eth.getTransactionCount(account.address, "pending");
        
        // Log the gas estimate
        logger.info(`Gas estimate for batch update: ${gas} units at ${Web3.utils.fromWei(gasPrice, 'gwei')} gwei`);
        logger.info(`Estimated cost: ${Web3.utils.fromWei(new BN(gas.toString()).multipliedBy(new BN(gasPrice.toString())).toString(), 'ether')} ETH`);
        
        // Create and sign transaction
        const signedTx = await account.signTransaction({
          to: oracleContract.options.address,
          data: tx.encodeABI(),
          gas,
          gasPrice,
          nonce,
        });
        
        // Send transaction
        logger.info(`Submitting batch transaction to network...`);
        const receipt: TransactionReceipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
        
        // Log success and gas used
        logger.info(`💎 Batch update successful: ${receipt.transactionHash}`);
        logger.info(`Gas used: ${receipt.gasUsed} (${(Number(receipt.gasUsed) / Number(gas) * 100).toFixed(1)}% of estimate)`);
        
        // Record transaction in gas tracker
        gasTracker.recordTransaction(
          receipt.transactionHash.toString(), 
          Number(receipt.gasUsed),
          gasPrice.toString(),
          tokens
        );
        
        // Show wallet status after transaction
        await gasTracker.logStats(web3, account);
        
        break;
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        
        if (--retries === 0) {
          logger.error(`Batch update failed after all retries: ${errorMsg}`);
          
          // Fall back to individual updates if configured
          if (cfg.individual_updates_on_batch_failure) {
            logger.info(`Falling back to individual updates for ${validUpdates.length} tokens`);
            
            for (const update of validUpdates) {
              const symbol = Object.entries(cfg.token_mappings).find(([addr]) => addr === update.address)?.[1] || 'unknown';
              logger.info(`Processing individual update for ${symbol} (${update.address.substring(0, 8)}...)`);
              
              await updateIndividualPrice(web3, oracleContract, managerContract, account, update.address, update.price);
              await sleep(1000); // Delay between individual transactions
            }
          }
        } else {
          logger.warn(`Batch update attempt failed, retrying (${retries} attempts left): ${errorMsg}`);
          await sleep(RETRY_DELAY_MS);
        }
      }
    }
  } else {
    logger.info(`No valid updates to process`);
  }
  
  // Display gas stats at the end of processing
  await gasTracker.logStats(web3, account);
  
  logger.info(`=== LAT processing complete ===\n`);
}
export async function main() {
  logger.info("Starting price oracle update process");
  
  try {
    // First try loading from deployment data
    logger.info(`Checking for deployment data at ${ENV.DEPLOYMENT_PATH}`);
    const deploymentConfigs = loadDeploymentData();
    
    if (deploymentConfigs.length > 0) {
      logger.info(`Loaded ${deploymentConfigs.length} configurations from deployment data`);
      
      // Process each config from deployment data
      for (const cfg of deploymentConfigs) {
        await processLAT(cfg);
      }
      
      logger.info("Price oracle update from deployment data completed");
      return deploymentConfigs;
    }
    
    // Fall back to config files if no deployment data
    logger.info("No deployment data found, checking config directory");
    
    const configDir = path.join(__dirname, "configs");
    if (!fs.existsSync(configDir)) {
      logger.error(`Config directory not found: ${configDir}`);
      throw new Error("No configuration sources available");
    }
    
    const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith(".json"));
    logger.info(`Found ${configFiles.length} configuration files`);
    
    if (configFiles.length === 0) {
      logger.error("No configuration files found");
      throw new Error("No configuration sources available");
    }
    
    // Process each config file
    const fileConfigs: Config[] = [];
    for (const configFile of configFiles) {
      const configPath = path.join(configDir, configFile);
      logger.info(`Processing config file: ${configFile}`);
      
      try {
        const cfg: Config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
        fileConfigs.push(cfg);
        await processLAT(cfg);
      } catch (error) {
        logger.error(`Error processing ${configFile}:`, error);
      }
    }
    
    logger.info("Price oracle update from config files completed");
    return fileConfigs;
  } catch (error) {
    logger.error(`Error in main process: ${error}`);
    throw error;
  }
}

export function scheduleUpdates() {
  try {
    logger.info("Setting up scheduled price updates");
    
    // First try loading from deployment data
    const deploymentConfigs = loadDeploymentData();
    const configs = deploymentConfigs.length > 0 ? deploymentConfigs : [];
    
    // If no deployment data, try config files
    if (configs.length === 0) {
      const configDir = path.join(__dirname, "configs");
      if (fs.existsSync(configDir)) {
        const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith(".json"));
        
        for (const file of configFiles) {
          try {
            const configPath = path.join(configDir, file);
            const cfg: Config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
            configs.push(cfg);
          } catch (error) {
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
    
    const job = schedule.scheduleJob(cronExpression, async () => {
      logger.info(`Scheduled job triggered at ${new Date().toISOString()}`);
      try {
        await main();
      } catch (error) {
        logger.error("Scheduled update failed:", error);
      }
    });
    
    if (job) {
      logger.info(`Next scheduled update: ${job.nextInvocation().toISOString()}`);
    } else {
      logger.error("Failed to schedule updates");
    }
  } catch (error) {
    logger.error(`Failed to schedule updates: ${error}`);
  }
}

export async function estimateGasRequirements() {
  logger.info(`\n=== Gas Requirement Estimates ===`);
  
  try {
    // First try deployment data
    const deploymentConfigs = loadDeploymentData();
    
    // Fall back to config files if needed
    const configs = deploymentConfigs.length > 0 ? deploymentConfigs : [];
    
    if (configs.length === 0) {
      const configDir = path.join(__dirname, "configs");
      if (fs.existsSync(configDir)) {
        const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith(".json"));
        
        for (const file of configFiles) {
          try {
            const configPath = path.join(configDir, file);
            const cfg: Config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
            configs.push(cfg);
          } catch (error) {
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
    const web3 = new Web3(ENV.RPC_URL || configs[0].web3.provider_uri);
    
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
      logger.error("No private key in .env - cannot estimate gas requirements");
      return;
    }
    
    // Get account balance
    const account = web3.eth.accounts.privateKeyToAccount(privateKey);
    let balance: string;
    
    try {
      balance = (await web3.eth.getBalance(account.address)).toString();
    } catch (error) {
      logger.error(`Failed to get account balance: ${error}`);
      return;
    }
    
    const ethBalance = Web3.utils.fromWei(balance, 'ether');
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
    if (gasTracker.transactions.length > 0) {
      const avgGasPerToken = gasTracker.transactions.reduce((sum, tx) => sum + tx.gasPerToken, 0) / gasTracker.transactions.length;
      
      let recentGasPrice: string;
      try {
        recentGasPrice = (await web3.eth.getGasPrice()).toString();
      } catch (error) {
        logger.error(`Failed to get gas price: ${error}`);
        return;
      }
      
      const estimatedGasForAllTokens = avgGasPerToken * totalTokens;
      const estimatedCostInEth = new BN(estimatedGasForAllTokens).multipliedBy(new BN(recentGasPrice)).div(new BN(10).pow(18));
      
      logger.info(`Based on historical data:`);
      logger.info(`  Average gas per token: ${Math.floor(avgGasPerToken)}`);
      logger.info(`  Current gas price: ${Web3.utils.fromWei(recentGasPrice, 'gwei')} gwei`);
      logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
      logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
      
      // Calculate how many updates current balance can support
      if (parseFloat(ethBalance) > 0) {
        const supportedUpdates = new BN(balance).div(new BN(estimatedGasForAllTokens).multipliedBy(new BN(recentGasPrice)));
        logger.info(`  Current balance can support approximately ${Math.floor(supportedUpdates.toNumber())} complete update cycles`);
      }
    } else {
      // If no historical data, provide rough estimates
      let gasPrice: string;
      try {
        gasPrice = (await web3.eth.getGasPrice()).toString();
      } catch (error) {
        logger.error(`Failed to get gas price: ${error}`);
        return;
      }
      
      // Conservative estimates
      const estimatedGasPerToken = 100000; // This is a conservative estimate
      const estimatedGasForAllTokens = estimatedGasPerToken * totalTokens;
      const estimatedCostInEth = new BN(estimatedGasForAllTokens).multipliedBy(new BN(gasPrice)).div(new BN(10).pow(18));
      
      logger.info(`No historical data available. Using conservative estimates:`);
      logger.info(`  Estimated gas per token: ${estimatedGasPerToken}`);
      logger.info(`  Current gas price: ${Web3.utils.fromWei(gasPrice, 'gwei')} gwei`);
      logger.info(`  Estimated gas for all ${totalTokens} tokens: ${estimatedGasForAllTokens}`);
      logger.info(`  Estimated ETH required: ${estimatedCostInEth.toString()} ETH`);
      
      if (parseFloat(ethBalance) > 0) {
        const supportedUpdates = new BN(balance).div(new BN(estimatedGasForAllTokens).multipliedBy(new BN(gasPrice)));
        logger.info(`  Current balance can support approximately ${Math.floor(supportedUpdates.toNumber())} complete update cycles`);
      }
    }
    
    logger.info(`=== End of Gas Estimate ===\n`);
  } catch (error) {
    logger.error(`Gas estimation failed: ${error}`);
  }
}

// Export key functions for potential use in other modules
export const updater = {
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
  gasTracker,
  loadDeploymentData
};

// Run the application if this is the main module (not imported elsewhere)
if (process.env.NODE_ENV !== "test" && !process.env.JEST_WORKER_ID) {
  try {
    // Run gas estimation first to provide funding guidance
    estimateGasRequirements()
      .then(() => main())
      .then(() => {
        scheduleUpdates();
      })
      .catch(error => {
        logger.error("Application error:", error);
        process.exit(1);
      });
  } catch (error) {
    logger.error("Fatal application error:", error);
    process.exit(1);
  }
}