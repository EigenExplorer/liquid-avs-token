// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakerNode} from "../interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library LTMHelpers {
    using Math for uint256;

    function scaleSharesForNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory shares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IDelegationManager delegationManager,
        IStakerNodeCoordinator stakerNodeCoordinator
    ) internal view returns (uint256[] memory) {
        address nodeAddress = address(
            stakerNodeCoordinator.getNodeById(nodeId)
        );
        uint256[] memory scaledShares = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            scaledShares[i] = shares[i].mulDiv(
                delegationManager.depositScalingFactor(
                    nodeAddress,
                    tokenStrategies[assets[i]]
                ),
                1e18
            );
        }

        return scaledShares;
    }

    function scaleSharesForNodeAsset(
        uint256 nodeId,
        IERC20 asset,
        uint256 shares,
        mapping(IERC20 => IStrategy) storage tokenStrategies,
        IDelegationManager delegationManager,
        IStakerNodeCoordinator stakerNodeCoordinator
    ) internal view returns (uint256) {
        address nodeAddress = address(
            stakerNodeCoordinator.getNodeById(nodeId)
        );

        return
            shares.mulDiv(
                delegationManager.depositScalingFactor(
                    nodeAddress,
                    tokenStrategies[asset]
                ),
                1e18
            );
    }
}