// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LiquidToken} from "./LiquidToken.sol";
import {StakerNode} from "./StakerNode.sol";
import {IStakerNodeCoordinator} from "../interfaces/IStakerNodeCoordinator.sol";

contract StakerNodeCoordinator is IStakerNodeCoordinator, Ownable {
    LiquidToken public lToken;
    address[] public stakerNodes;

    constructor(address _lToken) Ownable(msg.sender) {
        lToken = LiquidToken(_lToken);
    }

    function addStakerNode(address _nodeAddress) external onlyOwner {
        require(_nodeAddress != address(0), "Invalid node address");
        stakerNodes.push(_nodeAddress);
        emit StakerNodeAdded(_nodeAddress);
    }

    // function withdrawToNode(
    //     address _nodeAddress,
    //     uint256 _amount
    // ) external onlyOwner {
    //     require(_nodeAddress != address(0), "Invalid node address");
    //     require(isStakerNode(_nodeAddress), "Not a registered staker node");

    //     lToken.withdrawToNode(_nodeAddress, _amount);
    //     emit TokensWithdrawnToNode(_nodeAddress, _amount);
    // }

    function isStakerNode(address _nodeAddress) public view returns (bool) {
        for (uint i = 0; i < stakerNodes.length; i++) {
            if (stakerNodes[i] == _nodeAddress) {
                return true;
            }
        }
        return false;
    }

    function getStakerNodesCount() external view returns (uint256) {
        return stakerNodes.length;
    }
}
