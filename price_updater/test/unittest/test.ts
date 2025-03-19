import { jest } from "@jest/globals";
import type { AbiItem } from "web3-utils";

// -----------------------------------------------------------------------------
// GLOBAL MOCK SETUP
// -----------------------------------------------------------------------------
jest.useFakeTimers(); // Use fake timers for the entire suite

jest.mock("dotenv", () => ({
  config: jest.fn(() => ({
    parsed: {
      PRIVATE_KEY: "test-private-key",
      NODE_ENV: "test",
    },
  })),
}));

// Mock configuration files for two LAT instances
const mockConfigs = {
  "xeigen.json": JSON.stringify({
    web3: { provider_uri: "http://localhost:8545" },
    contracts: {
      oracle_address: "0xXEIGEN_Oracle",
      manager_address: "0xXEIGEN_Manager",
      oracle_abi_path: "../abi/TokenRegistryOracle.json",
      manager_abi_path: "../abi/LiquidTokenManager.json",
    },
    price_providers: {
      coingecko: { enabled: true, base_url: "https://api.coingecko.com/api/v3" },
      binance: { enabled: true, base_url: "https://api.binance.com/api/v3" },
      coinmarketcap: { enabled: false, base_url: "", api_key: "" }
    },
    token_mappings: { "0xec53b830298908ba6C1E959720BC7137c1d9E524": "EIGEN" },
    update_interval_minutes: 720,
    volatility_threshold_bypass: false,
    individual_updates_on_batch_failure: true,
  }),
  "xarpa.json": JSON.stringify({
    web3: { provider_uri: "http://localhost:8546" },
    contracts: {
      oracle_address: "0xXARPA_Oracle",
      manager_address: "0xXARPA_Manager",
      oracle_abi_path: "../abi/TokenRegistryOracle.json",
      manager_abi_path: "../abi/LiquidTokenManager.json",
    },
    price_providers: {
      coingecko: { enabled: true, base_url: "https://api.coingecko.com/api/v3" },
      coinmarketcap: { enabled: false, base_url: "", api_key: "" },
      binance: { enabled: false, base_url: "" }
    },
    token_mappings: { "0xBA50933C268F567BDC86E1aC131BE072C6B0b71a": "ARPA" },
    update_interval_minutes: 1440,
    volatility_threshold_bypass: false,
    individual_updates_on_batch_failure: true,
  }),
};

const mockABI = JSON.stringify([
  {
    "constant": false,
    "inputs": [
      { "name": "tokens", "type": "address[]" },
      { "name": "rates", "type": "uint256[]" }
    ],
    "name": "batchUpdateRates",
    "outputs": [],
    "type": "function"
  }
]);

jest.mock("fs", () => ({
  readdirSync: jest.fn(() => ["xeigen.json", "xarpa.json"]),
  readFileSync: jest.fn((filePath: string) => {
    const filename = filePath.split("/").pop();
    if (
      filename === "TokenRegistryOracle.json" ||
      filename === "LiquidTokenManager.json"
    ) {
      return mockABI;
    }
    return mockConfigs[filename as keyof typeof mockConfigs] || "{}";
  }),
  existsSync: jest.fn(() => true),
}));

jest.mock("path", () => ({
  join: (...args: string[]) => args.join('/'),
  basename: (file: string) => file.split('/').pop() || file,
}));

const mockContracts = new Map<string, any>();

const createWeb3Mock = () => ({
  eth: {
    Contract: jest.fn().mockImplementation((abi: AbiItem[], address: string) => {
      if (!mockContracts.has(address)) {
        const methods = {
          batchUpdateRates: jest.fn().mockReturnValue({
            estimateGas: jest.fn().mockResolvedValue(21000),
            encodeABI: jest.fn().mockReturnValue("0xabcdef"),
          }),
          updateRate: jest.fn().mockReturnValue({
            estimateGas: jest.fn().mockResolvedValue(21000),
            encodeABI: jest.fn().mockReturnValue("0x123456"),
          }),
          hasRole: jest.fn().mockReturnValue({
            call: jest.fn().mockResolvedValue(true),
          }),
          RATE_UPDATER_ROLE: jest.fn().mockReturnValue({
            call: jest.fn().mockResolvedValue("0x123"),
          }),
          getTokenInfo: jest.fn().mockReturnValue({
            call: jest.fn().mockResolvedValue({
              pricePerUnit: "1000000000000000000",
              volatilityThreshold: "100000000000000000000",
              decimals: "18",
            }),
          }),
        };
        mockContracts.set(address, { methods, options: { address } });
      }
      return mockContracts.get(address);
    }),
    accounts: {
      privateKeyToAccount: jest.fn().mockReturnValue({
        address: "0xTestAddress",
        signTransaction: jest.fn().mockResolvedValue({ rawTransaction: "0x123" }),
      }),
      wallet: { add: jest.fn() },
    },
    getTransactionCount: jest.fn().mockResolvedValue(0),
    getGasPrice: jest.fn().mockResolvedValue("1000000000"),
    sendSignedTransaction: jest.fn().mockResolvedValue({ transactionHash: "0xabc" }),
  },
});

jest.mock("web3", () => ({
  __esModule: true,
  default: jest.fn().mockImplementation(() => createWeb3Mock()),
}));

jest.mock("node-fetch", () => ({
  __esModule: true,
  default: jest.fn((url: string) => {
    if (url.includes("coingecko")) {
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ eigenlayer: { usd: 100 } }),
      });
    }
    if (url.includes("binance")) {
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ price: "99.5" }),
      });
    }
    if (url.includes("coinmarketcap")) {
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({
          data: { ARPA: { quote: { USD: { price: 0.051 } } } },
        }),
      });
    }
    return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
  }),
}));

jest.mock("node-schedule", () => ({
  scheduleJob: jest.fn(),
}));

// -----------------------------------------------------------------------------
// IMPORT THE MODULE UNDER TEST
// -----------------------------------------------------------------------------
const indexModule = require("../../src/index");

// -----------------------------------------------------------------------------
// TEST SUITE
// -----------------------------------------------------------------------------
describe("Multi-LAT Price Update Service", () => {
  let consoleLogSpy: jest.SpyInstance, consoleWarnSpy: jest.SpyInstance;

  beforeEach(() => {
    process.env.PRIVATE_KEY = "test-private-key";
    process.env.NODE_ENV = "test";
    jest.clearAllMocks();
    mockContracts.clear();

    const fs = require("fs");
    fs.readdirSync.mockImplementation(() => ["xeigen.json", "xarpa.json"]);
    fs.readFileSync.mockImplementation((filePath: string) => {
      const filename = filePath.split("/").pop();
      if (
        filename === "TokenRegistryOracle.json" ||
        filename === "LiquidTokenManager.json"
      ) {
        return mockABI;
      }
      return mockConfigs[filename as keyof typeof mockConfigs] || "{}";
    });

    // Spy on console.log and console.warn.
    consoleLogSpy = jest.spyOn(console, "log").mockImplementation(() => {});
    consoleWarnSpy = jest.spyOn(console, "warn").mockImplementation(() => {});
  });

  afterEach(() => {
    consoleLogSpy.mockRestore();
    consoleWarnSpy.mockRestore();
  });

  test("1. should load and process multiple LAT configurations", async () => {
    await indexModule.main();
    const processingMessages = consoleLogSpy.mock.calls.filter(call =>
      call[0].includes("=== Processing LAT")
    );
    expect(processingMessages.length).toBe(2);
  });

  test("2. should fetch prices from multiple providers", async () => {
    const cfg = JSON.parse(mockConfigs["xeigen.json"]);
    const fetchMock = require("node-fetch").default;
    fetchMock.mockClear();
    fetchMock.mockImplementation((url: string) => {
      if (url.includes("coingecko")) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ eigenlayer: { usd: 100 } }),
        });
      }
      if (url.includes("binance")) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ price: "99.5" }),
        });
      }
      return Promise.resolve({ ok: false });
    });
    await indexModule.processLAT(cfg);
    const calls = fetchMock.mock.calls;
    const coingeckoCalled = calls.some(call => call[0].includes("api.coingecko.com"));
    const binanceCalled = calls.some(call => call[0].includes("api.binance.com"));
    expect(coingeckoCalled).toBe(true);
    expect(binanceCalled).toBe(true);
  });

  test("3. should update prices via batch transaction", async () => {
    const cfg = JSON.parse(mockConfigs["xeigen.json"]);
    await indexModule.processLAT(cfg);
    const batchMessages = consoleLogSpy.mock.calls.filter(call =>
      call[0].includes("💎 Batch success:")
    );
    expect(batchMessages.length).toBeGreaterThan(0);
  });

  test("4. should handle batch failures with individual updates", async () => {
    const cfg = JSON.parse(mockConfigs["xeigen.json"]);
    const oracleAddress = cfg.contracts.oracle_address;
    // Create a failing oracle that always fails the batch update.
    const failingOracle = {
      methods: {
        batchUpdateRates: jest.fn(() => ({
          estimateGas: jest.fn().mockRejectedValue(new Error("Batch failed")),
          encodeABI: jest.fn().mockReturnValue("0x123"),
        })),
        updateRate: jest.fn(() => ({
          estimateGas: jest.fn().mockResolvedValue(21000),
          encodeABI: jest.fn().mockReturnValue("0x456"),
        })),
        hasRole: jest.fn(() => ({
          call: jest.fn().mockResolvedValue(true),
        })),
        RATE_UPDATER_ROLE: jest.fn(() => ({
          call: jest.fn().mockResolvedValue("0x123"),
        })),
        getTokenInfo: jest.fn(() => ({
          call: jest.fn().mockResolvedValue({
            pricePerUnit: "1000000000000000000",
            volatilityThreshold: "100000000000000000000",
            decimals: "18",
          }),
        })),
      },
      options: { address: oracleAddress },
    };
    mockContracts.set(oracleAddress, failingOracle);
  
    // Spy on the exported updater's updateIndividualPrice.
    const updateSpy = jest
      .spyOn(indexModule.updater, "updateIndividualPrice")
      .mockImplementation(() => Promise.resolve(true));
  
    const processPromise = indexModule.processLAT(cfg);
    // Flush all pending timers (e.g. sleep delays).
    await jest.runAllTimersAsync();
    await processPromise;
    expect(indexModule.updater.updateIndividualPrice).toHaveBeenCalled();
  }, 30000);
  

  test("5. should validate volatility thresholds", async () => {
    const cfg = JSON.parse(mockConfigs["xeigen.json"]);
    cfg.volatility_threshold_bypass = false;
    await indexModule.processLAT(cfg);
    const validUpdates = consoleLogSpy.mock.calls.filter(call =>
      call[0].includes("✅ Valid update: EIGEN")
    );
    expect(validUpdates.length).toBeGreaterThan(0);
  });

  test("6. should schedule updates correctly", () => {
    const scheduleSpy = jest.spyOn(require("node-schedule"), "scheduleJob");
    indexModule.scheduleUpdates([{ update_interval_minutes: 60 }]);
    expect(scheduleSpy).toHaveBeenCalled();
  });

  test("7. should reject invalid oracle addresses", async () => {
    const badConfig = JSON.parse(mockConfigs["xarpa.json"]);
    badConfig.contracts.oracle_address = "invalid-address";
    await expect(indexModule.processLAT(badConfig))
      .rejects.toThrow("Invalid oracle address");
  });
});

// Restore real timers after all tests.
afterAll(() => {
  jest.useRealTimers();
});
