import fs from "fs";
import path from "path";
import { config as dotenvConfig } from "dotenv";

dotenvConfig();

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
  price_providers: Record<string, any>;
  token_mappings: Record<string, string>;
  update_interval_minutes: number;
  volatility_threshold_bypass: boolean;
  individual_updates_on_batch_failure: boolean;
}

describe("Integration Test 1: Validate Configuration", () => {
  let configs: Config[];

  beforeAll(() => {
    const configDir = path.join(__dirname, "../../config");
    const configFiles = fs.readdirSync(configDir).filter((f) => f.endsWith(".json"));
    configs = configFiles.map((file) => {
      const configPath = path.join(configDir, file);
      return JSON.parse(fs.readFileSync(configPath, "utf-8")) as Config;
    });
    expect(configs.length).toBeGreaterThanOrEqual(1);
  });

  test("Configuration Loading", () => {
    for (const config of configs) {
      expect(config).toHaveProperty("web3");
      expect(config.web3).toHaveProperty("provider_uri");
      expect(config).toHaveProperty("contracts");
      expect(config.contracts).toHaveProperty("oracle_address");
      expect(config.contracts).toHaveProperty("oracle_abi_path");
      expect(config.contracts).toHaveProperty("manager_address");
      expect(config.contracts).toHaveProperty("manager_abi_path");
      expect(config).toHaveProperty("price_providers");
      expect(config).toHaveProperty("token_mappings");
      expect(config).toHaveProperty("update_interval_minutes");
      expect(config).toHaveProperty("volatility_threshold_bypass");
      expect(config).toHaveProperty("individual_updates_on_batch_failure");
    }
  });
});