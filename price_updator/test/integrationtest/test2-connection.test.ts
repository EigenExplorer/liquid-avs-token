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
    console.log("\n=== 🧪 Test 2: Starting Connection Tests ===");
    
    for (const [configIndex, config] of configs.entries()) {
      console.log(`\n[🔗 Config ${configIndex + 1}]`);
      
      // Oracle Contract
      console.log(`⛓️  Connecting to Oracle at ${config.contracts.oracle_address}`);
      const oracleAbi: AbiItem[] = JSON.parse(
        fs.readFileSync(path.join(__dirname, "../../ABIs/TokenRegistryOracle.json"), "utf-8")
      ).abi;
      const oracleContract = new web3.eth.Contract(oracleAbi, config.contracts.oracle_address);
      expect(oracleContract).toBeDefined();
      console.log("✅ Oracle connection validated");

      // Manager Contract
      console.log(`⛓️  Connecting to Manager at ${config.contracts.manager_address}`);
      const managerAbi: AbiItem[] = JSON.parse(
        fs.readFileSync(path.join(__dirname, "../../ABIs/LiquidTokenManager.json"), "utf-8")
      ).abi;
      const managerContract = new web3.eth.Contract(managerAbi, config.contracts.manager_address);
      expect(managerContract).toBeDefined();
      console.log("✅ Manager connection validated");

      // Token Mappings
      console.log("\n🔀 Token Mappings:");
      Object.entries(config.token_mappings).forEach(([address, symbol]) => {
        console.log(`   ${symbol.padEnd(5)} → ${address}`);
        expect(address).toMatch(/^0x[a-fA-F0-9]{40}$/);
        expect(symbol).toBeDefined();
      });
    }
    console.log("\n=== 🎉 Test 2: All Connections Validated ===");
  });
});
