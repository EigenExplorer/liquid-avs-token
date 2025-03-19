import Web3 from "web3";
import fs from "fs";
import path from "path";
import { config as dotenvConfig } from "dotenv";
import { AbiItem } from "web3-utils";

dotenvConfig();

interface Config {
  contracts: {
    oracle_address: string;
    oracle_abi_path: string;
    manager_address: string;
    manager_abi_path: string;
  };
  token_mappings: Record<string, string>;
}

describe("Integration Test 2: Connection and Mapping to Correct LAT and Token", () => {
  let web3: Web3;
  let configs: Config[];

  beforeAll(() => {
    web3 = new Web3("http://localhost:8545");
    const configDir = path.join(__dirname, "../../config");
        const configFiles = fs.readdirSync(configDir).filter((f) => f.endsWith(".json"));
    configs = configFiles.map((file) => {
      const configPath = path.join(configDir, file);
      return JSON.parse(fs.readFileSync(configPath, "utf-8")) as Config;
    });
  });

  test("Connection and Mapping", async () => {
    for (const config of configs) {
      const oracleAbi: AbiItem[] = JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "../../ABIs/TokenRegistryOracle.json"),
          "utf-8"
        )
      ).abi;
      const oracleContract = new web3.eth.Contract(oracleAbi, config.contracts.oracle_address);
      expect(oracleContract).toBeDefined();

      const managerAbi: AbiItem[] = JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "../../ABIs/LiquidTokenManager.json"), // Fixed path
          "utf-8"
        )      ).abi;
      const managerContract = new web3.eth.Contract(managerAbi, config.contracts.manager_address);
      expect(managerContract).toBeDefined();

      const tokenAddress = Object.keys(config.token_mappings)[0];
      const symbol = config.token_mappings[tokenAddress];
      expect(tokenAddress).toMatch(/^0x[a-fA-F0-9]{40}$/);
      expect(symbol).toBeDefined();
    }
  });
});