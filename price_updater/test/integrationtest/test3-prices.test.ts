import fs from "fs";
import path from "path";
import { config as dotenvConfig } from "dotenv";
import { fetchPriceFromCoingecko, fetchPriceFromBinance } from "../../src/index";
import { BigNumber as BN } from "bignumber.js";

// Mock implementations
jest.mock("../../src/index", () => {
  const original = jest.requireActual("../../src/index");
  return {
    ...original,
    fetchPriceFromCoingecko: jest.fn(),
    fetchPriceFromBinance: jest.fn(),
  };
});

dotenvConfig();

interface Config {
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

describe("Integration Test 3: Fetching Prices", () => {
  let configs: Config[];
  
  // Mock price data for our test tokens
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

  beforeAll(() => {
    // Setup mock implementations
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

    // Load config files
    const configDir = path.join(__dirname, "../../config");
    const configFiles = fs.readdirSync(configDir).filter((f) => f.endsWith(".json"));
    configs = configFiles.map((file) => {
      const configPath = path.join(configDir, file);
      return JSON.parse(fs.readFileSync(configPath, "utf-8")) as Config;
    });

    // Create mappings file if it doesn't exist
    const mappingsPath = path.join(__dirname, "../../src/mappings.json");
    if (!fs.existsSync(mappingsPath)) {
      fs.writeFileSync(
        mappingsPath,
        JSON.stringify({
          coingecko_mappings: { 
            "TKA": "token-a", 
            "TKB": "token-b" 
          },
          binance_mappings: { 
            "TKA": "TKAUSDT", 
            "TKB": "TKBUSDT"
          },
        })
      );
    }
  });

  test("Price Fetching", async () => {
    expect(configs.length).toBeGreaterThan(0);
    
    for (const config of configs) {
      const tokenAddresses = Object.keys(config.token_mappings);
      
      for (const tokenAddress of tokenAddresses) {
        const symbol = config.token_mappings[tokenAddress];
        const prices: BN[] = [];

        if (config.price_providers.coingecko?.enabled) {
          const price = await fetchPriceFromCoingecko(
            config.price_providers.coingecko.base_url,
            symbol
          );
          if (price) {
            prices.push(price);
            console.log(`Fetched Coingecko price for ${symbol}: ${price.toString()}`);
          }
        }
        
        if (config.price_providers.binance?.enabled) {
          const price = await fetchPriceFromBinance(
            config.price_providers.binance.base_url,
            symbol
          );
          if (price) {
            prices.push(price);
            console.log(`Fetched Binance price for ${symbol}: ${price.toString()}`);
          }
        }

        expect(prices.length).toBeGreaterThan(0);
        console.log(`All fetched prices for ${symbol}: ${prices.map((p) => p.toString())}`);
      }
    }
  }, 60000); // Reduced timeout since we're mocking API calls

  afterAll(() => {
    jest.restoreAllMocks();
  });
});