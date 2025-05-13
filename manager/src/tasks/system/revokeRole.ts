import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import {
  encodeFunctionData,
  parseAbi,
  getAddress,
  keccak256,
  toBytes,
} from "viem/utils";
import { apiKit, protocolKitOwnerAdmin } from "../../utils/safe";
import { ADMIN, proposeSafeTransaction } from "../../utils/forge";
import { getViemClient } from "../../utils/viemClient";

/**
 * Creates a proposal for revoking a role, with optional safety check to ensure
 * at least one address will still have the role after revocation
 *
 * @param contractAddress
 * @param role
 * @param addressToRevoke
 * @param skipSafetyCheck
 * @returns
 */
export async function revokeRole(
  contractAddress: string,
  role: string,
  addressToRevoke: string,
  skipSafetyCheck = false
) {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");
    const viemClient = getViemClient();
    const roleManagerAbi = parseAbi([
      "function getRoleMemberCount(bytes32) view returns (uint256)",
      "function getRoleMember(bytes32, uint256) view returns (address)",
      "function hasRole(bytes32, address) view returns (bool)",
    ]);

    let roleHash: `0x${string}`;
    if (role === "DEFAULT_ADMIN_ROLE") {
      roleHash =
        "0x0000000000000000000000000000000000000000000000000000000000000000";
    } else if (role.startsWith("0x")) {
      roleHash = role as `0x${string}`; // If already a hex string, use directly
    } else {
      roleHash = keccak256(toBytes(role));
    }

    // Check if the address actually has the role
    const hasRole = await viemClient.readContract({
      address: getAddress(contractAddress),
      abi: roleManagerAbi,
      functionName: "hasRole",
      args: [roleHash, getAddress(addressToRevoke)],
    });

    if (!hasRole)
      throw new Error(
        `Address ${addressToRevoke} does not have the ${role} role`
      );

    // Safety check: Make sure we're not removing the last address with this role
    if (!skipSafetyCheck) {
      // Ensure that there are more than 1 addresses with this role
      const memberCount = await viemClient.readContract({
        address: getAddress(contractAddress),
        abi: roleManagerAbi,
        functionName: "getRoleMemberCount",
        args: [roleHash],
      });

      if (Number(memberCount) <= 1)
        throw new Error(
          `Safety check failed: ${addressToRevoke} is the only address with the ${role} role. If you know what you're doing, disable safety check and try again.`
        );

      // Additional check for critical roles: Ensure that the same address wasn't registered multiple times or zero address was registered
      // We do this by making sure there would be at least one valid address with this role after revocation
      let foundAlternative = false;
      for (let i = 0; i < Number(memberCount); i++) {
        const member = await viemClient.readContract({
          address: getAddress(contractAddress),
          abi: roleManagerAbi,
          functionName: "getRoleMember",
          args: [roleHash, BigInt(i)],
        });

        if (getAddress(member) !== getAddress(addressToRevoke)) {
          foundAlternative = true;
          break;
        }
      }

      if (!foundAlternative) {
        throw new Error(
          `Safety check failed: No alternative addresses found with the ${role} role. If you know what you're doing, disable safety check and try again.`
        );
      }
    }

    // Setup task params
    const abi = parseAbi(["function revokeRole(bytes32,address)"]);
    const metadata = {
      title: `Revoke ${role} Role on ${contractAddress}`,
      description: `Proposal to revoke the ${role} role from ${addressToRevoke} via manual proposal`,
    };

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "revokeRole",
      args: [roleHash, getAddress(addressToRevoke)],
    });
    const metaTransactionData = {
      to: getAddress(contractAddress),
      value: "0",
      data: data,
      operation: OperationType.Call,
    };

    // Create transaction
    const nonce = Number(await apiKit.getNextNonce(ADMIN));
    const safeTransaction = await protocolKitOwnerAdmin.createTransaction({
      transactions: [metaTransactionData],
      options: { nonce },
    });

    // Propose transactions to multisig
    await proposeSafeTransaction(safeTransaction, metadata);
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
