// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";

contract MockRewardsCoordinator {
    mapping(address => address) public claimerFor;
    mapping(address => mapping(address => uint256)) public transferAmounts;

    function setClaimerFor(address earner, address claimer) external {
        claimerFor[earner] = claimer;
    }

    function setupClaimTransfer(address token, address to, uint256 amount) external {
        transferAmounts[token][to] = amount;
    }

    function processClaim(IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim, address recipient) external {
        // Simulate transferring tokens for each token leaf
        for (uint256 i = 0; i < claim.tokenLeaves.length; i++) {
            address tokenAddr = address(claim.tokenLeaves[i].token);
            uint256 transferAmount = transferAmounts[tokenAddr][recipient];

            if (transferAmount > 0) {
                IERC20(tokenAddr).transfer(recipient, transferAmount);
            }
        }
    }
}