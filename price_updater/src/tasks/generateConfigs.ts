import fs from "fs";
import path from "path";
import { getNetwork, getDeployment, getRpcUrl } from "../../../manager/src/utils/forge";
import { Config } from "../index"; 
// Declare Node.js globals
declare const __filename: string;
declare const __dirname: string;

interface TokenConfig {
  web3: {
    provider_uri: string;
    network: string;
    chain_id: number;
  };
  contracts: {
    oracle_address: string;
    oracle_abi_path: string;
    manager_address: string;
    manager_abi_path: string;
  };
  price_providers: {
    coingecko?: { enabled: boolean; base_url: string; api_key?: string };
    binance?: { enabled: boolean; base_url: string };
  };
  token_mappings: Record<string, string>;
  update_interval_minutes: number;
  volatility_threshold_bypass: boolean;
  individual_updates_on_batch_failure: boolean;
}

export async function generatePriceUpdaterConfigs() {
  try {
    const network = getNetwork();
    const deployment = getDeployment();
    const projectRoot = path.join(__dirname, '../../../../');
    const addressesPath = path.join(
      projectRoot,
      'script/outputs',
      network,
      `price_updater_addresses.json`
    );

    const outputDir = path.join(
      projectRoot,
      'script/configs',
      network,
      deployment
    );

    if (!fs.existsSync(addressesPath)) {
      throw new Error(`Address file missing: ${path.relative(projectRoot, addressesPath)}`);
    }

    // Read the price updater addresses
    const addressesData = JSON.parse(fs.readFileSync(addressesPath, "utf8"));
    const { contracts, tokens } = addressesData;

    // Create base configuration that will be shared across all token configs
    const baseConfig = {
      web3: { 
        provider_uri: getRpcUrl(),
        network,
        chain_id: network === 'mainnet' ? 1 : network === 'holesky' ? 17000 : 31337
      },
      contracts: {
        oracle_abi_path: "./ABIs/TokenRegistryOracle.json",
        manager_abi_path: "./ABIs/LiquidTokenManager.json"
      },
      price_providers: {
        coingecko: { 
          enabled: true,
          base_url: "https://api.coingecko.com/api/v3",
          api_key: process.env.COINGECKO_API_KEY || "" 
        },
        binance: { enabled: true, base_url: "https://api.binance.com/api/v3" 
        }
      },
      update_interval_minutes: 720,
      volatility_threshold_bypass: true,
      individual_updates_on_batch_failure: true
    };

    // Create directory if it doesn't exist
    fs.mkdirSync(outputDir, { recursive: true });
    
    // Find all tokens in the contract addresses
    const tokenConfigs: Record<string, TokenConfig> = {};
    const tokenKeys = tokens?.tokenKeys || [];
    
    // Dynamically generate configs for each token
    if (tokenKeys.length > 0) {
      // Use token keys if available (preferred method)
      for (let i = 0; i < tokenKeys.length; i++) {
        const tokenKey = tokenKeys[i];
        const tokenAddress = tokens[tokenKey]?.address || contracts[`token${i}`];
        
        if (tokenKey && typeof tokenKey === 'string') {
          tokenConfigs[tokenKey] = {
            ...baseConfig,
            contracts: {
              ...baseConfig.contracts,
              oracle_address: contracts[`oracle${i}`],
              manager_address: contracts[`manager${i}`]
            },
            token_mappings: { [tokenAddress]: tokenKey }
          };
        }
      }
    } else {
      // Fallback to numeric indices if no token keys
      let tokenIndex = 0;
      while (contracts[`oracle${tokenIndex}`] && contracts[`manager${tokenIndex}`] && contracts[`token${tokenIndex}`]) {
        const tokenSymbol = contracts[`tokenSymbol${tokenIndex}`] || `Token${tokenIndex}`;
        
        if (typeof tokenSymbol === 'string') {
          tokenConfigs[tokenSymbol] = {
            ...baseConfig,
            contracts: {
              ...baseConfig.contracts,
              oracle_address: contracts[`oracle${tokenIndex}`],
              manager_address: contracts[`manager${tokenIndex}`]
            },
            token_mappings: { [contracts[`token${tokenIndex}`]]: tokenSymbol }
          };
        }
        
        tokenIndex++;
      }
    }
    
    // Write config files for each token
    for (const [tokenSymbol, config] of Object.entries(tokenConfigs)) {
      const outputPath = path.join(outputDir, `price_updater_${tokenSymbol}_config.json`);
      fs.writeFileSync(outputPath, JSON.stringify(config, null, 2));
      console.log(`Generated config for ${tokenSymbol}`);
    }

    console.log(`✅ Configs generated at ${path.relative(projectRoot, outputDir)}`);
    return tokenConfigs;
  } catch (error) {
    console.error("❌ Config generation failed:", error);
    process.exit(1);
  }
}