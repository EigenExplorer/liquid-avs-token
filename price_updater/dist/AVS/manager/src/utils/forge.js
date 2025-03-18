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
exports.getOutputData = exports.getAdmin = exports.getConfigFile = exports.getRpcUrl = exports.getNetwork = exports.getDeployment = exports.createOzProposal = exports.extractTransactions = exports.forgeCommand = exports.getLiquidTokenAddress = exports.getAdminAddress = exports.DEPLOYMENT = exports.NETWORK = void 0;
// Modified to avoid import.meta.url and top-level await
require("dotenv/config");
const defenderClient_1 = require("./defenderClient");
const promises_1 = __importDefault(require("node:fs/promises"));
const node_path_1 = __importDefault(require("node:path"));
// Use __dirname directly (assuming CommonJS module)
const __dirname = process.cwd();
exports.NETWORK = getNetwork();
exports.DEPLOYMENT = getDeployment();
// Remove top-level await by creating async functions for later use
function getAdminAddress() {
    return __awaiter(this, void 0, void 0, function* () {
        return yield getAdmin();
    });
}
exports.getAdminAddress = getAdminAddress;
function getLiquidTokenAddress() {
    return __awaiter(this, void 0, void 0, function* () {
        const data = yield getOutputData();
        return data.addresses.liquidToken;
    });
}
exports.getLiquidTokenAddress = getLiquidTokenAddress;
/**
 * Returns the forge command used to call a task from the /script folder
 *
 * @param task
 * @param sender
 * @param sig
 * @param params
 * @returns
 */
function forgeCommand(task, sender, sig, params) {
    return `forge script ../script/tasks/${task} --rpc-url ${getRpcUrl()} --json --sender ${sender} --sig '${sig}' -- ${getConfigFile()} ${params} -vvvv`;
}
exports.forgeCommand = forgeCommand;
/**
 * Extracts all simulated transactions from forge script execution simulation
 *
 * @param stdout
 * @returns
 */
function extractTransactions(stdout) {
    return __awaiter(this, void 0, void 0, function* () {
        const broadcastMatch = stdout.match(/"transactions":"([^"]+)"/);
        if (!broadcastMatch)
            throw new Error("Could not find broadcast file path in output");
        const broadcastData = JSON.parse(yield promises_1.default.readFile(broadcastMatch[1].replace(/\\\\/g, "\\"), "utf8"));
        const transactions = broadcastData.transactions;
        if (!transactions || !Array.isArray(transactions))
            throw new Error("No transactions found");
        return transactions;
    });
}
exports.extractTransactions = extractTransactions;
/**
 * Creates a proposal on OZ Defender to the admin multisig for a given simulated transaction
 *
 * @param tx
 * @param title
 * @param description
 * @returns
 */
function createOzProposal(
// biome-ignore lint/suspicious/noExplicitAny: <explanation>
tx, title, description) {
    return __awaiter(this, void 0, void 0, function* () {
        const functionSignature = tx.function;
        const functionNameMatch = functionSignature.match(/^([^(]+)\((.*)\)$/);
        if (!functionNameMatch) {
            throw new Error(`Could not parse function signature: ${functionSignature}`);
        }
        const functionInputs = tx.arguments || [];
        const functionName = functionNameMatch[1];
        const parameterString = functionNameMatch[2];
        const parameterTypes = parseParameterTypes(parameterString);
        const inputs = parameterTypes.map((type, index) => ({
            name: `param${index}`,
            type: type,
        }));
        const proposal = yield defenderClient_1.defenderClient.proposal.create({
            proposal: {
                contract: {
                    address: tx.transaction.to,
                    network: exports.NETWORK,
                },
                title: title,
                description: description,
                type: "custom",
                functionInterface: {
                    name: functionName,
                    inputs: inputs,
                },
                functionInputs: functionInputs,
                via: process.env.ADMIN_PUBLIC_KEY,
                viaType: "Safe",
            },
        });
        if (!proposal)
            throw new Error("Couldn't create proposal");
        return proposal;
    });
}
exports.createOzProposal = createOzProposal;
// --- Helper functions ---
/**
 * Returns whether the deployment is local or public (testnet/mainnet)
 * Defaults to public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
function getDeployment() {
    const deployment = process.env.DEPLOYMENT;
    if (!deployment || deployment !== "local")
        return "public";
    return "local";
}
exports.getDeployment = getDeployment;
/**
 * Returns the network of the deployment
 * Defaults to mainnet if `NETWORK` env var not set
 *
 * @returns
 */
function getNetwork() {
    const network = process.env.NETWORK;
    if (!network || network !== "holesky")
        return "mainnet";
    return "holesky";
}
exports.getNetwork = getNetwork;
/**
 * Returns the RPC URL
 * Defaults to local if `RPC_URL` env var not set
 *
 * @returns
 */
function getRpcUrl() {
    const rpcUrl = process.env.RPC_URL;
    if (!rpcUrl || exports.DEPLOYMENT === "local")
        return "http://localhost:8545";
    return rpcUrl;
}
exports.getRpcUrl = getRpcUrl;
/**
 * Returns the input config used to create the deployment
 * Defaults to mainnet if `NETWORK` env var not set & public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
function getConfigFile() {
    if (exports.NETWORK === "mainnet") {
        if (exports.DEPLOYMENT === "local")
            return "/local/mainnet_deployment_data.json";
        return "/mainnet/deployment_data.json";
    }
    if (exports.DEPLOYMENT === "local")
        return "/local/holesky_deployment_data.json";
    return "/holesky/deployment_data.json";
}
exports.getConfigFile = getConfigFile;
/**
 * Returns the admin public key
 * Defaults to local forge test account #0 if `ADMIN_PUBLIC_KEY` env var not set
 * @returns
 */
function getAdmin() {
    return __awaiter(this, void 0, void 0, function* () {
        if (exports.DEPLOYMENT === "local")
            return (yield getOutputData()).roles.admin;
        return (process.env.ADMIN_PUBLIC_KEY || "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    });
}
exports.getAdmin = getAdmin;
/**
 * Returns the output file created after the deployment
 * Defaults to mainnet if `NETWORK` env var not set & public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
function getOutputData() {
    return __awaiter(this, void 0, void 0, function* () {
        return JSON.parse(yield promises_1.default.readFile(node_path_1.default.resolve(__dirname, `../../../script/outputs${getConfigFile()}`), "utf8"));
    });
}
exports.getOutputData = getOutputData;
/**
 * Returns an array of parameter types from a function signature with support for complex types like tuples
 *
 * @param parameterString
 * @returns
 */
function parseParameterTypes(parameterString) {
    if (!parameterString.trim()) {
        return [];
    }
    const result = [];
    let currentParam = "";
    let parenDepth = 0;
    for (let i = 0; i < parameterString.length; i++) {
        const char = parameterString[i];
        if (char === "(" && parenDepth === 0) {
            parenDepth++;
            currentParam += char;
        }
        else if (char === "(" && parenDepth > 0) {
            parenDepth++;
            currentParam += char;
        }
        else if (char === ")" && parenDepth > 1) {
            parenDepth--;
            currentParam += char;
        }
        else if (char === ")" && parenDepth === 1) {
            parenDepth--;
            currentParam += char;
        }
        else if (char === "," && parenDepth === 0) {
            if (currentParam.trim()) {
                result.push(currentParam.trim());
                currentParam = "";
            }
        }
        else {
            currentParam += char;
        }
    }
    if (currentParam.trim()) {
        result.push(currentParam.trim());
    }
    return result;
}
