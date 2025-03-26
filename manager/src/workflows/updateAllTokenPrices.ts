import { DEPLOYMENT, LIQUID_TOKEN_ADDRESS } from "../utils/forge";
import { batchUpdateRates } from "../tasks/price-updater/batchUpdateRates";

interface Token {
  address: string;
  pricePerUnit: string;
  decimals: number;
  cmcId: number;
}

interface TokenWithQuote extends Token {
  ethPrice: number;
}

const LAT_API_URL = process.env.LAT_API_URL;
const PRICE_UPDATE_THRESHOLD = 0.001;

export async function updateAllTokenPrices() {
  try {
    if (
      !process.env.PRICE_UPDATER_PRIVATE_KEY ||
      !process.env.CMC_API_KEY ||
      (DEPLOYMENT === "local" &&
        !process.env.VALID_LIQUID_TOKEN_ADDRESS_BACKEND)
    )
      throw new Error("Env vars not set correctly.");

    // Fetch all supported tokens
    const latResponse = await fetch(
      DEPLOYMENT === "local"
        ? `${LAT_API_URL}/lat/${process.env.VALID_LIQUID_TOKEN_ADDRESS_BACKEND}/tokens`
        : `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/tokens`
    );

    if (!latResponse.ok) {
      throw new Error(
        `Failed to fetch LAT data: ${latResponse.status} ${latResponse.statusText}`
      );
    }

    const tokens = (await latResponse.json()).data as Token[];

    const cmcTokenIds = tokens.map((t) => t.cmcId);
    const CMC_API =
      "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest";
    const keysStr = cmcTokenIds.filter((id) => id !== 0).join(",");
    const cmcResponse = await fetch(`${CMC_API}?id=${keysStr}&convert=eth`, {
      headers: { "X-CMC_PRO_API_KEY": process.env.CMC_API_KEY },
    });

    if (!cmcResponse.ok) {
      throw new Error(
        `Failed to fetch price data from CMC: ${cmcResponse.status} ${cmcResponse.statusText}`
      );
    }

    // biome-ignore lint/suspicious/noExplicitAny: <explanation>
    const quotes = Object.values((await cmcResponse.json()).data) as any[];
    const tokenQuotes: TokenWithQuote[] = tokens.map((token) => {
      const quote = quotes.find((q) => q.id === token.cmcId);

      return {
        ...token,
        ethPrice: quote ? quote.quote.ETH.price : 0,
      };
    });

    // Find tokens that need price updates
    const addresses: `0x${string}`[] = [];
    const prices: bigint[] = [];
    for (const token of tokenQuotes) {
      try {
        const tokenAddress = token.address as `0x${string}`;
        const currentPrice = Number(token.pricePerUnit);
        const newPrice = token.ethPrice;
        const priceDifference =
          Math.abs(currentPrice - newPrice) / currentPrice;
        const ethPrice = BigInt(Math.round(newPrice * 10 ** token.decimals));

        // Requires update if price diff > threshold
        const requiresUpdate = priceDifference > PRICE_UPDATE_THRESHOLD;

        if (requiresUpdate) {
          addresses.push(tokenAddress);
          prices.push(ethPrice);
        }
      } catch (error) {
        console.log(`Error processing token ${token.address}:`, error);
      }
    }

    await batchUpdateRates(addresses, prices);
  } catch (error) {
    console.log("Error: ", error);
  }
}
