// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";

interface IStakerNode {
    struct Init {
        uint256 id;
        address coordinator;
    }

    event Delegated(address indexed operator);
    event DepositedToStrategy(
        IERC20 asset,
        IStrategy strategy,
        uint256 amount,
        uint256 shares
    );
}
