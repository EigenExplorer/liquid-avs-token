// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICurvePool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);

    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);

    function get_dy(int128 i, int128 j, uint256 amount) external view returns (uint256);
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external returns (uint256 out);
}