"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.defenderClient = void 0;
const defender_sdk_1 = require("@openzeppelin/defender-sdk");
/**
 * Client for OZ Defender
 *
 */
exports.defenderClient = new defender_sdk_1.Defender({
    apiKey: process.env.OZD_API_KEY,
    apiSecret: process.env.OZD_API_SECRET,
});
