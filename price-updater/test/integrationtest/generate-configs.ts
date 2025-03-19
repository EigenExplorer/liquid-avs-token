import fs from "fs";
import path from "path";



const addressesFilePath = path.join(__dirname, "../../../addresses.json");
if (!fs.existsSync(addressesFilePath)) {
  console.error("addresses.json not found at", addressesFilePath);
  process.exit(1);
}

const addresses = JSON.parse(fs.readFileSync(addressesFilePath, "utf8")).contracts;

// Config for Token A (EIGEN)
const config1 = {
  web3: { provider_uri: "http://localhost:8545" },
  contracts: {
    oracle_address: addresses.oracleA || "",
    oracle_abi_path: path.join("ABIs", "oracleABI.json"),
    manager_address: addresses.managerA || "",
    manager_abi_path: path.join("ABIs", "managerABI.json"),
  },
  price_providers: {
    coingecko: { enabled: true, base_url: "https://api.coingecko.com/api/v3" },
    coinmarketcap: { enabled: false, base_url: "https://pro-api.coinmarketcap.com", api_key: "" },
    binance: { enabled: true, base_url: "https://api.binance.com/api/v3" },
  },
  token_mappings: { [addresses.tokenA || ""]: "TKA" }, // Changed to "TKA"
  update_interval_minutes: 720,
  volatility_threshold_bypass: false,
  individual_updates_on_batch_failure: true,
};

// Config for Token B (ARPA)
const config2 = {
  web3: { provider_uri: "http://localhost:8545" },
  contracts: {
    oracle_address: addresses.oracleB || "",
    oracle_abi_path: path.join("ABIs", "oracleABI.json"),
    manager_address: addresses.managerB || "",
    manager_abi_path: path.join("ABIs", "managerABI.json"),
  },
  price_providers: {
    coingecko: { enabled: true, base_url: "https://api.coingecko.com/api/v3" },
    coinmarketcap: { enabled: false, base_url: "https://pro-api.coinmarketcap.com", api_key: "" },
    binance: { enabled: true, base_url: "https://api.binance.com/api/v3" },
  },
  token_mappings: { [addresses.tokenB || ""]: "TKB" }, // Changed to "TKB"
  update_interval_minutes: 720,
  volatility_threshold_bypass: false,
  individual_updates_on_batch_failure: true,
};

const outputDir = path.join(__dirname, "../../config/");
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

fs.writeFileSync(path.join(outputDir, "config1.json"), JSON.stringify(config1, null, 2));
fs.writeFileSync(path.join(outputDir, "config2.json"), JSON.stringify(config2, null, 2));

console.log("Config files generated at:", outputDir);