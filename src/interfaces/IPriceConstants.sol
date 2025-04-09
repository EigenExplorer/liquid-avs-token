// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPriceConstants
 * @notice Constants for token addresses, sources and function selectors
 */
interface IPriceConstants {
    // Token addresses
    function ETH() external pure returns (address);
    function ETHx() external pure returns (address);
    function OSETH() external pure returns (address);
    function OETH() external pure returns (address);
    function SFRxETH() external pure returns (address);
    function RETH() external pure returns (address);
    function STETH() external pure returns (address);
    function CBETH() external pure returns (address);
    function METH() external pure returns (address);
    function LSETH() external pure returns (address);
    function SWETH() external pure returns (address);
    function ANKR_ETH() external pure returns (address);
    function WSTETH() external pure returns (address);
    function UNIBTC() external pure returns (address);
    function STBTC() external pure returns (address);
    function WBETH() external pure returns (address);

    // Primary source types (for gas-efficient lookups)
    function SOURCE_TYPE_CHAINLINK() external pure returns (uint8);
    function SOURCE_TYPE_CURVE() external pure returns (uint8);
    function SOURCE_TYPE_BTC_CHAINED() external pure returns (uint8);
    function SOURCE_TYPE_PROTOCOL() external pure returns (uint8);

    // Primary source addresses
    function CHAINLINK_RETH_ETH() external pure returns (address);
    function CHAINLINK_STETH_ETH() external pure returns (address);
    function CHAINLINK_CBETH_ETH() external pure returns (address);
    function CHAINLINK_METH_ETH() external pure returns (address);
    function CHAINLINK_OETH_ETH() external pure returns (address);
    function CHAINLINK_BTC_ETH() external pure returns (address);
    function CHAINLINK_UNIBTC_BTC() external pure returns (address);
    function CHAINLINK_STBTC_BTC() external pure returns (address);

    // Curve pool addresses
    function LSETH_CURVE_POOL() external pure returns (address);
    function ETHx_CURVE_POOL() external pure returns (address);
    function ANKR_ETH_CURVE_POOL() external pure returns (address);
    function OSETH_CURVE_POOL() external pure returns (address);
    function SWETH_CURVE_POOL() external pure returns (address);

    // Protocol addresses for fallbacks
    function RETH_CONTRACT() external pure returns (address);
    function STETH_CONTRACT() external pure returns (address);
    function CBETH_CONTRACT() external pure returns (address);
    function ETHx_CONTRACT() external pure returns (address);
    function OSETH_CONTRACT() external pure returns (address);
    function SFRxETH_CONTRACT() external pure returns (address);
    function SWETH_CONTRACT() external pure returns (address);
    function WSTETH_CONTRACT() external pure returns (address);
    function ANKR_ETH_CONTRACT() external pure returns (address);
    function LSETH_CONTRACT() external pure returns (address);
    function OETH_CONTRACT() external pure returns (address);
    function METH_CONTRACT() external pure returns (address);
    function UNIBTC_CONTRACT() external pure returns (address);
    function STBTC_ACCOUNTANT_CONTRACT() external pure returns (address);
    function WBETH_CONTRACT() external pure returns (address);

    // Function selectors for protocol rate functions
    function SELECTOR_GET_EXCHANGE_RATE() external pure returns (bytes4);
    function SELECTOR_GET_POOLED_ETH_BY_SHARES() external pure returns (bytes4);
    function SELECTOR_EXCHANGE_RATE() external pure returns (bytes4);
    function SELECTOR_CONVERT_TO_ASSETS() external pure returns (bytes4);
    function SELECTOR_SWETH_TO_ETH_RATE() external pure returns (bytes4);
    function SELECTOR_STETH_PER_TOKEN() external pure returns (bytes4);
    function SELECTOR_RATIO() external pure returns (bytes4);
    function SELECTOR_UNDERLYING_BALANCE_FROM_SHARES()
        external
        pure
        returns (bytes4);
    function SELECTOR_METH_TO_ETH() external pure returns (bytes4);
    function SELECTOR_GET_RATE() external pure returns (bytes4);

    // Arguments for functions that require them (standardized to 1e18)
    function DEFAULT_AMOUNT() external pure returns (uint256);
}