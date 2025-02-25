import { Defender } from "@openzeppelin/defender-sdk";

export const defenderClient = new Defender({
  apiKey: process.env.OZD_API_KEY,
  apiSecret: process.env.OZD_API_SECRET,
});
