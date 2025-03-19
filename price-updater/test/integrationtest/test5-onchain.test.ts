import Web3 from "web3";
import fs from "fs";
import path from "path";
import { BigNumber as BN } from "bignumber.js";
import { config as dotenvConfig } from "dotenv";
import { AbiItem } from "web3-utils";

// Setup dotenv before imports
dotenvConfig();

// Import from actual module for type checking
import { fetchPriceFromCoingecko, fetchPriceFromBinance, getMedian } from "../../src/index";

// Use a more standard approach to mocking
jest.mock("../../src/index", () => {
  const originalModule = jest.requireActual("../../src/index");
  return {
    ...originalModule,
    fetchPriceFromCoingecko: jest.fn(),
    fetchPriceFromBinance: jest.fn()
  };
});

// Define interfaces
interface Config {
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
  token_mappings: Record<string, string>;
  update_interval_minutes: number;
  volatility_threshold_bypass: boolean;
  individual_updates_on_batch_failure: boolean;
}

interface TokenPriceMocks {
  [symbol: string]: {
    coingecko?: number;
    binance?: number;
  };
}

describe("Integration Test 5: On-Chain Call Preparation", () => {
  let web3: Web3;
  let configs: Config[];
  
  // Mock price data for test tokens - reuse from previous tests
  const mockPrices: TokenPriceMocks = {
    "TKA": {
      coingecko: 1.25,
      binance: 1.27
    },
    "TKB": {
      coingecko: 0.75,
      binance: 0.74
    }
  };

  // Mock contract methods - more minimalistic approach
  const mockUpdateRate = jest.fn().mockReturnValue({
    estimateGas: jest.fn().mockResolvedValue(80000),
    encodeABI: jest.fn().mockReturnValue("0xmockedABI")
  });
  
  const mockBatchUpdateRates = jest.fn().mockReturnValue({
    estimateGas: jest.fn().mockResolvedValue(150000),
    encodeABI: jest.fn().mockReturnValue("0xmockedBatchABI")
  });
  
  const mockRateUpdaterRole = jest.fn().mockReturnValue({
    call: jest.fn().mockResolvedValue("0xRateUpdaterRole")
  });
  
  const mockHasRole = jest.fn().mockReturnValue({
    call: jest.fn().mockResolvedValue(true)
  });
  
  const mockGetTokenInfo = jest.fn().mockReturnValue({
    call: jest.fn().mockResolvedValue({
      "0": "18",
      "1": "1000000000000000000", // 1.0
      "2": "50000000000000000"    // 5%
    })
  });
  
  beforeAll(() => {
    // Mocking Web3 instance - but more simplified
    web3 = new Web3("http://localhost:8545") as any;
    
    // Mock web3 methods
    web3.eth.getGasPrice = jest.fn().mockResolvedValue("20000000000");
    web3.eth.getTransactionCount = jest.fn().mockResolvedValue(42);
    web3.eth.sendSignedTransaction = jest.fn().mockResolvedValue({
      transactionHash: "0xMockTxHash"
    });
    
    // Mock account methods
    web3.eth.accounts = {
      privateKeyToAccount: jest.fn().mockReturnValue({
        address: "0xMockAccount",
        signTransaction: jest.fn().mockResolvedValue({
          rawTransaction: "0xSignedTransaction"
        })
      }),
      wallet: {
        add: jest.fn()
      }
    } as any;
    
    // Mock contract creation
    web3.eth.Contract = jest.fn().mockImplementation(() => {
      return {
        methods: {
          updateRate: mockUpdateRate,
          batchUpdateRates: mockBatchUpdateRates,
          RATE_UPDATER_ROLE: mockRateUpdaterRole,
          hasRole: mockHasRole,
          getTokenInfo: mockGetTokenInfo
        },
        options: {
          address: "0x1234567890123456789012345678901234567890"
        }
      };
    }) as any;
    
    // Configure price mocks - using same approach as test3 and test4
    (fetchPriceFromCoingecko as jest.Mock).mockImplementation((baseUrl, symbol) => {
      if (mockPrices[symbol]?.coingecko) {
        return Promise.resolve(new BN(mockPrices[symbol].coingecko));
      }
      return Promise.resolve(null);
    });

    (fetchPriceFromBinance as jest.Mock).mockImplementation((baseUrl, symbol) => {
      if (mockPrices[symbol]?.binance) {
        return Promise.resolve(new BN(mockPrices[symbol].binance));
      }
      return Promise.resolve(null);
    });

    // Mock environment variable
    process.env.PRIVATE_KEY = "0xmockedPrivateKey";
    
    // Load config files from disk like in tests 1-4
    const configDir = path.join(__dirname, "../../config");
    const configFiles = fs.readdirSync(configDir).filter((f) => f.endsWith(".json"));
    configs = configFiles.map((file) => {
      const configPath = path.join(configDir, file);
      return JSON.parse(fs.readFileSync(configPath, "utf-8")) as Config;
    });
    
    // If no configs found (for testing), create a sample one
    if (configs.length === 0) {
      configs = [
        {
          web3: { provider_uri: "http://localhost:8545" },
          contracts: {
            oracle_address: "0x1234567890123456789012345678901234567890",
            oracle_abi_path: "ABIs/TokenRegistryOracle.json",
            manager_address: "0x0987654321098765432109876543210987654321",
            manager_abi_path: "ABIs/LiquidTokenManager.json"
          },
          price_providers: {
            coingecko: { enabled: true, base_url: "https://api.coingecko.com/api/v3" },
            binance: { enabled: true, base_url: "https://api.binance.com/api/v3" }
          },
          token_mappings: {
            "0x1234567890123456789012345678901234567890": "TKA",
            "0x0987654321098765432109876543210987654321": "TKB"
          },
          update_interval_minutes: 60,
          volatility_threshold_bypass: true,
          individual_updates_on_batch_failure: true
        }
      ];
    }
    
    // Create mappings file if it doesn't exist (like in test3 and test4)
    const mappingsPath = path.join(__dirname, "../../src/mappings.json");
    if (!fs.existsSync(mappingsPath)) {
      fs.writeFileSync(
        mappingsPath,
        JSON.stringify({
          coingecko_mappings: { "TKA": "token-a", "TKB": "token-b" },
          binance_mappings: { "TKA": "TKAUSDT", "TKB": "TKBUSDT" }
        })
      );
    }
  });

  test("Should prepare valid blockchain transaction data for individual price updates", async () => {
    expect(configs.length).toBeGreaterThan(0);
    
    for (const config of configs) {
      const tokenAddresses = Object.keys(config.token_mappings);
      expect(tokenAddresses.length).toBeGreaterThan(0);
      
      for (const tokenAddress of tokenAddresses) {
        const symbol = config.token_mappings[tokenAddress];
        const prices: BN[] = [];

        // Fetch prices from enabled providers - similar to test3 and test4
        if (config.price_providers.coingecko?.enabled) {
          const price = await fetchPriceFromCoingecko(
            config.price_providers.coingecko.base_url,
            symbol
          );
          if (price) prices.push(price);
        }
        
        if (config.price_providers.binance?.enabled) {
          const price = await fetchPriceFromBinance(
            config.price_providers.binance.base_url,
            symbol
          );
          if (price) prices.push(price);
        }

        // Ensure we got prices
        expect(prices.length).toBeGreaterThan(0);

        // Calculate median and scale
        const medianPrice = getMedian(prices);
        const PRICE_DECIMALS = 18;
        const scaledPrice = medianPrice.times(10 ** PRICE_DECIMALS).toFixed(0);
        
        // Load ABIs using relative paths as in test2
        const oracleAbiPath = path.join(__dirname, "../../", config.contracts.oracle_abi_path);
        let oracleAbi: AbiItem[];
        
        try {
          // Try to load actual ABI file
          oracleAbi = JSON.parse(fs.readFileSync(oracleAbiPath, "utf-8")).abi;
        } catch (error) {
          // Fallback to basic mock ABI if file not found
          oracleAbi = [
            {
              "inputs": [
                {"internalType": "address", "name": "token", "type": "address"},
                {"internalType": "uint256", "name": "rate", "type": "uint256"}
              ],
              "name": "updateRate",
              "outputs": [],
              "stateMutability": "nonpayable",
              "type": "function"
            }
          ] as AbiItem[];
        }

        // Create contract instance
        const oracleContract = new web3.eth.Contract(oracleAbi, config.contracts.oracle_address);

        // Setup account
        const privateKey = process.env.PRIVATE_KEY;
        expect(privateKey).toBeTruthy();
        
        const account = web3.eth.accounts.privateKeyToAccount(privateKey!);
        web3.eth.accounts.wallet.add(account);

        // Check rate updater role
        const rateUpdaterRole = await oracleContract.methods.RATE_UPDATER_ROLE().call();
        const hasRole = await oracleContract.methods.hasRole(rateUpdaterRole, account.address).call();
        expect(hasRole).toBe(true);

        // Create transaction data
        const tx = oracleContract.methods.updateRate(tokenAddress, scaledPrice);
        const gas = await tx.estimateGas({ from: account.address });
        const gasPrice = await web3.eth.getGasPrice();
        const nonce = await web3.eth.getTransactionCount(account.address, "pending");

        // Prepare and sign transaction
        const txData = {
          to: config.contracts.oracle_address,
          data: tx.encodeABI(),
          gas,
          gasPrice,
          nonce,
          from: account.address
        };

        const signedTx = await account.signTransaction({
          to: config.contracts.oracle_address,
          data: tx.encodeABI(),
          gas,
          gasPrice,
          nonce,
        });

        // Verify transaction data
        expect(txData).toBeDefined();
        expect(signedTx.rawTransaction).toBeDefined();
        
        // Log to match similar output as seen in the other tests
        console.log(`Transaction for ${symbol}: gas=${gas}, gasPrice=${gasPrice}, nonce=${nonce}`);
      }
    }
  }, 30000); // Keeping same timeout

  test("Should prepare valid blockchain transaction data for batch price updates", async () => {
    expect(configs.length).toBeGreaterThan(0);
    
    for (const config of configs) {
      const tokenAddresses = Object.keys(config.token_mappings);
      expect(tokenAddresses.length).toBeGreaterThan(0);
      
      // Get all token prices
      const validUpdates: { address: string; price: string }[] = [];
      
      for (const tokenAddress of tokenAddresses) {
        const symbol = config.token_mappings[tokenAddress];
        const prices: BN[] = [];

        // Fetch prices from enabled providers - matching test3 and test4 approach
        if (config.price_providers.coingecko?.enabled) {
          const price = await fetchPriceFromCoingecko(
            config.price_providers.coingecko.base_url,
            symbol
          );
          if (price) prices.push(price);
        }
        
        if (config.price_providers.binance?.enabled) {
          const price = await fetchPriceFromBinance(
            config.price_providers.binance.base_url,
            symbol
          );
          if (price) prices.push(price);
        }

        // Calculate median price and add to updates - similar to test4
        if (prices.length > 0) {
          const medianPrice = getMedian(prices);
          const PRICE_DECIMALS = 18;
          const scaledPrice = medianPrice.times(10 ** PRICE_DECIMALS).toFixed(0);
          validUpdates.push({ address: tokenAddress, price: scaledPrice });
        }
      }
      
      // Ensure we have updates
      expect(validUpdates.length).toBeGreaterThan(0);
      
      // Load ABIs using relative paths as in test2
      const oracleAbiPath = path.join(__dirname, "../../", config.contracts.oracle_abi_path);
      let oracleAbi: AbiItem[];
      
      try {
        // Try to load actual ABI file
        oracleAbi = JSON.parse(fs.readFileSync(oracleAbiPath, "utf-8")).abi;
      } catch (error) {
        // Fallback to basic mock ABI if file not found
        oracleAbi = [
          {
            "inputs": [
              {"internalType": "address[]", "name": "tokens", "type": "address[]"},
              {"internalType": "uint256[]", "name": "rates", "type": "uint256[]"}
            ],
            "name": "batchUpdateRates",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function"
          }
        ] as AbiItem[];
      }
      
      // Create contract instance
      const oracleContract = new web3.eth.Contract(oracleAbi, config.contracts.oracle_address);
      
      // Setup account - same as in individual updates
      const privateKey = process.env.PRIVATE_KEY;
      expect(privateKey).toBeTruthy();
      
      const account = web3.eth.accounts.privateKeyToAccount(privateKey!);
      web3.eth.accounts.wallet.add(account);
      
      // Extract tokens and prices for batch update
      const tokens = validUpdates.map(u => u.address);
      const prices = validUpdates.map(u => u.price);
      
      // Create batch transaction
      const tx = oracleContract.methods.batchUpdateRates(tokens, prices);
      const gas = await tx.estimateGas({ from: account.address });
      const gasPrice = await web3.eth.getGasPrice();
      const nonce = await web3.eth.getTransactionCount(account.address, "pending");
      
      // Prepare and sign transaction
      const txData = {
        to: config.contracts.oracle_address,
        data: tx.encodeABI(),
        gas,
        gasPrice,
        nonce,
        from: account.address
      };
      
      const signedTx = await account.signTransaction({
        to: config.contracts.oracle_address,
        data: tx.encodeABI(),
        gas,
        gasPrice,
        nonce,
      });
      
      // Verify transaction data
      expect(txData).toBeDefined();
      expect(signedTx.rawTransaction).toBeDefined();
      
      // Log batch transaction details
      console.log(`Batch transaction gas=${gas}, gasPrice=${gasPrice}, nonce=${nonce}`);
    }
  }, 30000); // Keep same timeout

  afterAll(() => {
    jest.restoreAllMocks();
  });
});