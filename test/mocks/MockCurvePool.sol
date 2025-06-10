// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract MockCurvePool {
    uint256 private _virtualPrice = 1000000000000000000; // 1e18
    uint256 private _priceOracle = 1000000000000000000; // 1e18
    uint256 private _dy = 1000000000000000000; // 1e18

    function get_virtual_price() external view returns (uint256) {
        return _virtualPrice;
    }

    function price_oracle() external view returns (uint256) {
        return _priceOracle;
    }

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256) {
        return _dy;
    }

    // Test helpers
    function setVirtualPrice(uint256 newPrice) external {
        _virtualPrice = newPrice;
    }

    function setPriceOracle(uint256 newPrice) external {
        _priceOracle = newPrice;
    }

    function setDy(uint256 newDy) external {
        _dy = newDy;
    }
}
