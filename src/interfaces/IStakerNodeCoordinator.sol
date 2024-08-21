// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IOrchestrator} from "../interfaces/IOrchestrator.sol";

interface IStakerNodeCoordinator {
    struct Init {
        IOrchestrator orchestrator;
        IDelegationManager delegationManager;
        IStrategyManager strategyManager;
        uint256 maxNodes;
        address initialOwner;
        address pauser;
        address unpauser;
    }

    event StakerNodeAdded(address nodeAddress);
    event StakerNodeRemoved(address nodeAddress);
    event MaxNodesUpdated(uint256 maxNodes);
    event TokensWithdrawnToNode(address indexed nodeAddress, uint256 amount);

    error ZeroAddress();
    error MaxNodesReached(uint256 maxNodes);
    error NodeAlreadyRegistered(address nodeAddress);
    error NotOwner();
}
