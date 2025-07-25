// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IFrxETHMinter} from "../../src/interfaces/IFrxETHMinter.sol";

contract MockFrxETHMinter is IFrxETHMinter {
    uint256 public mockShares = 1e18; // Default 1:1 ratio

    function setMockShares(uint256 _shares) external {
        mockShares = _shares;
    }

    function submitAndDeposit(address recipient) external payable override returns (uint256 shares) {
        // Mock implementation - return shares based on msg.value
        shares = (msg.value * mockShares) / 1e18;
        return shares;
    }
}