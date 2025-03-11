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
    console.log("\n=== 🧪 Test 3: Starting Price Fetching ===");
    expect(configs.length).toBeGreaterThan(0);
    
    for (const [configIndex, config] of configs.entries()) {
      console.log(`\n[📊 Config ${configIndex + 1}]`);
      console.log(`⏱️  Update Interval: ${config.update_interval_minutes} minutes`);
      console.log(`🔌 Enabled Providers: ${
        Object.entries(config.price_providers)
          .filter(([_, cfg]) => cfg?.enabled)
          .map(([name]) => name)
          .join(', ') || 'None'
      }`);
  
      const tokenAddresses = Object.keys(config.token_mappings);
      for (const tokenAddress of tokenAddresses) {
        const symbol = config.token_mappings[tokenAddress];
        console.log(`\n💎 Processing ${symbol} (${tokenAddress})`);
        const prices: BN[] = [];
  
        if (config.price_providers.coingecko?.enabled) {
          console.log(`🦎 Fetching CoinGecko price...`);
          const price = await fetchPriceFromCoingecko(
            config.price_providers.coingecko.base_url,
            symbol
          );
          if (price) {
            prices.push(price);
            console.log(`✅ CoinGecko: ${price.toFixed(4)}`);
          } else {
            console.log(`⚠️  No CoinGecko price found`);
          }
        }
        
        if (config.price_providers.binance?.enabled) {
          console.log(`🅱️ Fetching Binance price...`);
          const price = await fetchPriceFromBinance(
            config.price_providers.binance.base_url,
            symbol
          );
          if (price) {
            prices.push(price);
            console.log(`✅ Binance: ${price.toFixed(4)}`);
          } else {
            console.log(`⚠️  No Binance price found`);
          }
        }
  
        expect(prices.length).toBeGreaterThan(0);
        console.log(`📊 Final Prices: ${prices.map(p => p.toFixed(4)).join(' | ')}`);
      }
    }
    console.log("\n=== 🎉 Test 3: Price Fetching Completed ===");
  }, 60000);
  
  afterAll(() => {
    jest.restoreAllMocks();
  });
});