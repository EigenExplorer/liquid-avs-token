"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generatePriceUpdaterConfigs = void 0;
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const forge_1 = require("../../../manager/src/utils/forge");
function generatePriceUpdaterConfigs() {
    var _a;
    return __awaiter(this, void 0, void 0, function* () {
        try {
            const network = (0, forge_1.getNetwork)();
            const deployment = (0, forge_1.getDeployment)();
            const projectRoot = path_1.default.join(__dirname, '../../../../');
            const addressesPath = path_1.default.join(projectRoot, 'script/outputs', network, `price_updater_addresses.json`);
            const outputDir = path_1.default.join(projectRoot, 'script/configs', network, deployment);
            if (!fs_1.default.existsSync(addressesPath)) {
                throw new Error(`Address file missing: ${path_1.default.relative(projectRoot, addressesPath)}`);
            }
            // Read the price updater addresses
            const addressesData = JSON.parse(fs_1.default.readFileSync(addressesPath, "utf8"));
            const { contracts, tokens } = addressesData;
            // Create base configuration that will be shared across all token configs
            const baseConfig = {
                web3: {
                    provider_uri: (0, forge_1.getRpcUrl)(),
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
            fs_1.default.mkdirSync(outputDir, { recursive: true });
            // Find all tokens in the contract addresses
            const tokenConfigs = {};
            const tokenKeys = (tokens === null || tokens === void 0 ? void 0 : tokens.tokenKeys) || [];
            // Dynamically generate configs for each token
            if (tokenKeys.length > 0) {
                // Use token keys if available (preferred method)
                for (let i = 0; i < tokenKeys.length; i++) {
                    const tokenKey = tokenKeys[i];
                    const tokenAddress = ((_a = tokens[tokenKey]) === null || _a === void 0 ? void 0 : _a.address) || contracts[`token${i}`];
                    if (tokenKey && typeof tokenKey === 'string') {
                        tokenConfigs[tokenKey] = Object.assign(Object.assign({}, baseConfig), { contracts: Object.assign(Object.assign({}, baseConfig.contracts), { oracle_address: contracts[`oracle${i}`], manager_address: contracts[`manager${i}`] }), token_mappings: { [tokenAddress]: tokenKey } });
                    }
                }
            }
            else {
                // Fallback to numeric indices if no token keys
                let tokenIndex = 0;
                while (contracts[`oracle${tokenIndex}`] && contracts[`manager${tokenIndex}`] && contracts[`token${tokenIndex}`]) {
                    const tokenSymbol = contracts[`tokenSymbol${tokenIndex}`] || `Token${tokenIndex}`;
                    if (typeof tokenSymbol === 'string') {
                        tokenConfigs[tokenSymbol] = Object.assign(Object.assign({}, baseConfig), { contracts: Object.assign(Object.assign({}, baseConfig.contracts), { oracle_address: contracts[`oracle${tokenIndex}`], manager_address: contracts[`manager${tokenIndex}`] }), token_mappings: { [contracts[`token${tokenIndex}`]]: tokenSymbol } });
                    }
                    tokenIndex++;
                }
            }
            // Write config files for each token
            for (const [tokenSymbol, config] of Object.entries(tokenConfigs)) {
                const outputPath = path_1.default.join(outputDir, `price_updater_${tokenSymbol}_config.json`);
                fs_1.default.writeFileSync(outputPath, JSON.stringify(config, null, 2));
                console.log(`Generated config for ${tokenSymbol}`);
            }
            console.log(`✅ Configs generated at ${path_1.default.relative(projectRoot, outputDir)}`);
            return tokenConfigs;
        }
        catch (error) {
            console.error("❌ Config generation failed:", error);
            process.exit(1);
        }
    });
}
exports.generatePriceUpdaterConfigs = generatePriceUpdaterConfigs;
