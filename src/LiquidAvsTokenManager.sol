// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./LiquidAvsToken.sol";
import "./LiquidAvsStakerNode.sol";

contract LiquidAVSTokenManager is Ownable {
    LiquidAvsToken public lAvsToken;
    address[] public stakerNodes;

    event StakerNodeAdded(address indexed nodeAddress);
    event TokensWithdrawnToNode(address indexed nodeAddress, uint256 amount);

    constructor(address _lAvsToken) Ownable(msg.sender) {
        lAvsToken = LiquidAvsToken(_lAvsToken);
    }

    function addStakerNode(address _nodeAddress) external onlyOwner {
        require(_nodeAddress != address(0), "Invalid node address");
        stakerNodes.push(_nodeAddress);
        emit StakerNodeAdded(_nodeAddress);
    }

    function withdrawToNode(address _nodeAddress, uint256 _amount) external onlyOwner {
        require(_nodeAddress != address(0), "Invalid node address");
        require(isStakerNode(_nodeAddress), "Not a registered staker node");
        
        lAvsToken.withdrawToNode(_nodeAddress, _amount);
        emit TokensWithdrawnToNode(_nodeAddress, _amount);
    }

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