import { Defender } from "@openzeppelin/defender-sdk";

/**
 * Client for OZ Defender
 *
 */
export const defenderClient = new Defender({
  apiKey: process.env.OZD_API_KEY,
  apiSecret: process.env.OZD_API_SECRET,
});
