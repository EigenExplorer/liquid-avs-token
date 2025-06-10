// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract MockProtocolToken {
    uint256 private _exchangeRate = 1e18;
    uint256 public updatedAt;

    function exchangeRate() external view returns (uint256) {
        return _exchangeRate;
    }

    function convertToAssets(uint256 amount) external view returns (uint256) {
        return (amount * _exchangeRate) / 1e18;
    }

    function mETHToETH(uint256 amount) external view returns (uint256) {
        return (amount * _exchangeRate) / 1e18;
    }
    function getPooledEthByShares(uint256 shares) external view returns (uint256) {
        return (shares * _exchangeRate) / 1e18;
    }

    // Test helpers
    function setExchangeRate(uint256 newRate) external {
        _exchangeRate = newRate;
    }
    function setUpdatedAt(uint256 newUpdatedAt) external {
        updatedAt = newUpdatedAt;
    }
}
