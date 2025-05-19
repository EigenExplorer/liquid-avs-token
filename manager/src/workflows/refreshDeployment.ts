import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { refreshDeploymentAddresses } from "../utils/forge";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const LAT_DEPLOYMENTS_REPO = process.env.LAT_DEPLOYMENTS_REPO;
const GITHUB_ACCESS_TOKEN = process.env.GITHUB_ACCESS_TOKEN;
const DEPLOYMENT_DATA_PATH = path.resolve(
  __dirname,
  "../../../script/outputs/holesky/deployment_data.json"
);

interface VersionWithTimestamp {
  timestamp: number;
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
  data: any;
}

/**
 * Fetches the latest `info.json` from the Github deployments repo and updates
 * the existing `script/outputs/holesky/deployment_data.json`
 * Note: This process is skipped on local deployments
 *
 * @returns
 */
export async function refreshDeployment() {
  try {
    // Skip for local deployments
    if (!process.env.DEPLOYMENT || process.env.DEPLOYMENT === "local") {
      console.log(
        "[Info] Skipping deployment data fetch from GH. Make sure local output file is updated."
      );
      await refreshDeploymentAddresses();
      return;
    }

    if (!LAT_DEPLOYMENTS_REPO || !GITHUB_ACCESS_TOKEN) {
      throw new Error("Env vars not set correctly.");
    }

    const [owner, repo, ...pathParts] = LAT_DEPLOYMENTS_REPO.split("/");

    if (!owner || !repo) {
      throw new Error("Invalid LAT_DEPLOYMENT_REPO format.");
    }

    const headers = new Headers();
    headers.append("Authorization", `token ${process.env.GITHUB_ACCESS_TOKEN}`);
    headers.append("Accept", "application/vnd.github.v3+json");
    const apiUrl = `https://api.github.com/repos/${owner}/${repo}/contents/${pathParts.join(
      "/"
    )}`;

    const response = await fetch(apiUrl, { headers });
    if (!response.ok) {
      throw new Error(`${response.status}: ${await response.text()}`);
    }

    const directoryContents = await response.json();
    const directories = directoryContents.filter((item) => item.type === "dir");

    if (directories.length === 0) {
      throw new Error("No deployments found in repo.");
    }

    // Find deployment timestamps of all deployed versions
    const versionsWithTimestamps: VersionWithTimestamp[] = [];
    for (const dir of directories) {
      try {
        const outputFileUrl = `https://api.github.com/repos/${owner}/${repo}/contents/${pathParts.join(
          "/"
        )}/${dir.name}/info.json`;

        const outputResponse = await fetch(outputFileUrl, { headers });
        if (!outputResponse.ok) {
          continue;
        }

        const outputData = await outputResponse.json();
        const content = Buffer.from(outputData.content, "base64").toString(
          "utf-8"
        );
        const deploymentData = JSON.parse(content);

        if (deploymentData.deploymentTimestamp) {
          versionsWithTimestamps.push({
            timestamp: deploymentData.deploymentTimestamp,
            data: deploymentData,
          });
        }
      } catch (error) {
        console.log(`Error processing info.json for ${dir.name}:`, error);
      }
    }

    if (versionsWithTimestamps.length === 0) {
      throw new Error(
        `No valid deployment data found in any version directory in ${LAT_DEPLOYMENTS_REPO}`
      );
    }

    // Get the latest deployment based on timestamp
    versionsWithTimestamps.sort((a, b) => b.timestamp - a.timestamp);
    const latestVersion = versionsWithTimestamps[0];
    const deploymentData = latestVersion.data;

    await fs.mkdir(path.dirname(DEPLOYMENT_DATA_PATH), { recursive: true });
    await fs.writeFile(
      DEPLOYMENT_DATA_PATH,
      JSON.stringify(deploymentData, null, 2)
    );

    await refreshDeploymentAddresses();
  } catch (error) {
    console.log("[Manager] Error: ", error.message);
    throw error;
  }
}
