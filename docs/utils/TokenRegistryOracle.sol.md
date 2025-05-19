# TokenRegistryOracle

[Git Source](https://github.com/EigenExplorer/liquid-avs-token/src/utils/TokenRegistryOracle.sol)

**Inherits:**
[ITokenRegistryOracle](/src/interfaces/ITokenRegistryOracle.sol), Initializable, AccessControlUpgradeable

Gas-optimized price oracle with primary/fallback lookup

_Uses static lookup tables for maximum gas efficiency_

## State Variables

### RATE_UPDATER_ROLE

```solidity
bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");
```

### ORACLE_ADMIN_ROLE

```solidity
bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
```

### TOKEN_CONFIGURATOR_ROLE

```solidity
bytes32 public constant TOKEN_CONFIGURATOR_ROLE = keccak256("TOKEN_CONFIGURATOR_ROLE");
```

### PRECISION

```solidity
uint256 private constant PRECISION = 1e18;
```

### STALENESS_PERIOD

```solidity
uint256 private constant STALENESS_PERIOD = 24 hours;
```

### SOURCE_TYPE_CHAINLINK

```solidity
uint8 public constant SOURCE_TYPE_CHAINLINK = 1;
```

### SOURCE_TYPE_CURVE

```solidity
uint8 public constant SOURCE_TYPE_CURVE = 2;
```

### SOURCE_TYPE_PROTOCOL

```solidity
uint8 public constant SOURCE_TYPE_PROTOCOL = 3;
```

### liquidTokenManager

```solidity
ILiquidTokenManager public liquidTokenManager;
```

### \_priceUpdateInterval

```solidity
uint64 private _priceUpdateInterval = 12 hours;
```

### lastGlobalPriceUpdate

```solidity
uint64 public lastGlobalPriceUpdate;
```

### tokenConfigs

```solidity
mapping(address => TokenConfig) public tokenConfigs;
```

### configuredTokens

```solidity
address[] public configuredTokens;
```

### isConfigured

```solidity
mapping(address => bool) public isConfigured;
```

## Functions

### initialize

Initialize the contract

```solidity
function initialize(Init memory init) public initializer;
```

**Parameters**

| Name   | Type   | Description               |
| ------ | ------ | ------------------------- |
| `init` | `Init` | Initialization parameters |

### configureToken

Configure a token with its primary and fallback sources

```solidity
function configureToken(address token, uint8 primaryType, address primarySource, uint8 needsArg, address fallbackSource, bytes4 fallbackFn) external onlyRole(TOKEN_CONFIGURATOR_ROLE);
```

**Parameters**

| Name             | Type      | Description                                                   |
| ---------------- | --------- | ------------------------------------------------------------- |
| `token`          | `address` | Token address                                                 |
| `primaryType`    | `uint8`   | Source type (1=Chainlink, 2=Curve, 3=BTC-chained, 4=Protocol) |
| `primarySource`  | `address` | Primary source address                                        |
| `needsArg`       | `uint8`   | Whether fallback fn needs args                                |
| `fallbackSource` | `address` | Address of the fallback source contract                       |
| `fallbackFn`     | `bytes4`  | Function selector for fallback                                |

### removeToken

Remove a token configuration from the registry

```solidity
function removeToken(address token) external onlyRole(TOKEN_CONFIGURATOR_ROLE);
```

**Parameters**

| Name    | Type      | Description                    |
| ------- | --------- | ------------------------------ |
| `token` | `address` | Address of the token to remove |

### updateRate

Updates a token's rate manually

```solidity
function updateRate(IERC20 token, uint256 newRate) external onlyRole(RATE_UPDATER_ROLE);
```

**Parameters**

| Name      | Type      | Description                |
| --------- | --------- | -------------------------- |
| `token`   | `IERC20`  | The token to update        |
| `newRate` | `uint256` | The new rate for the token |

### batchUpdateRates

Updates rates for multiple tokens manually

```solidity
function batchUpdateRates(IERC20[] calldata tokens, uint256[] calldata newRates) external onlyRole(RATE_UPDATER_ROLE);
```

**Parameters**

| Name       | Type        | Description                  |
| ---------- | ----------- | ---------------------------- |
| `tokens`   | `IERC20[]`  | The tokens to update         |
| `newRates` | `uint256[]` | The new rates for the tokens |

### setPriceUpdateInterval

Sets price update interval

```solidity
function setPriceUpdateInterval(uint256 interval) external onlyRole(ORACLE_ADMIN_ROLE);
```

**Parameters**

| Name       | Type      | Description                 |
| ---------- | --------- | --------------------------- |
| `interval` | `uint256` | The new interval in seconds |

### getRate

Get current token rate

```solidity
function getRate(IERC20 token) external view returns (uint256);
```

**Parameters**

| Name    | Type     | Description               |
| ------- | -------- | ------------------------- |
| `token` | `IERC20` | The token to get rate for |

**Returns**

| Name     | Type      | Description                    |
| -------- | --------- | ------------------------------ |
| `<none>` | `uint256` | The current rate for the token |

### priceUpdateInterval

Gets configured update interval

```solidity
function priceUpdateInterval() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description         |
| -------- | --------- | ------------------- |
| `<none>` | `uint256` | Interval in seconds |

### arePricesStale

Check if prices are stale

```solidity
function arePricesStale() public view override(ITokenRegistryOracle) returns (bool);
```

**Returns**

| Name     | Type   | Description              |
| -------- | ------ | ------------------------ |
| `<none>` | `bool` | Whether prices are stale |

### lastPriceUpdate

Get last price update timestamp

```solidity
function lastPriceUpdate() external view returns (uint256);
```

**Returns**

| Name     | Type      | Description                        |
| -------- | --------- | ---------------------------------- |
| `<none>` | `uint256` | Timestamp of the last price update |

### updateAllPricesIfNeeded

Update all token prices if stale

```solidity
function updateAllPricesIfNeeded() external override(ITokenRegistryOracle) returns (bool);
```

**Returns**

| Name     | Type   | Description                 |
| -------- | ------ | --------------------------- |
| `<none>` | `bool` | Whether prices were updated |

### \_updateAllPrices

Fetch and update prices for all configured tokens

```solidity
function _updateAllPrices() internal;
```

### \_updateTokenRate

Internal function to update token rate

```solidity
function _updateTokenRate(IERC20 token, uint256 newRate) internal;
```

**Parameters**

| Name      | Type      | Description                |
| --------- | --------- | -------------------------- |
| `token`   | `IERC20`  | The token to update        |
| `newRate` | `uint256` | The new rate for the token |

### \_getTokenPrice

Get token price from primary source

```solidity
function _getTokenPrice(address token) internal view returns (uint256 price, bool success);
```

**Parameters**

| Name    | Type      | Description                |
| ------- | --------- | -------------------------- |
| `token` | `address` | The token to get price for |

**Returns**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `price`   | `uint256` | The price of the token               |
| `success` | `bool`    | Whether the operation was successful |

### \_getFallbackPrice

Get token price from fallback source (protocol call)

```solidity
function _getFallbackPrice(address token) internal view returns (uint256 price, bool success);
```

**Parameters**

| Name    | Type      | Description                |
| ------- | --------- | -------------------------- |
| `token` | `address` | The token to get price for |

**Returns**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `price`   | `uint256` | The fallback price of the token      |
| `success` | `bool`    | Whether the operation was successful |

### \_getChainlinkPrice

Get price from Chainlink with maximum gas efficiency

```solidity
function _getChainlinkPrice(address feed) internal view returns (uint256 price, bool success);
```

**Parameters**

| Name   | Type      | Description                      |
| ------ | --------- | -------------------------------- |
| `feed` | `address` | The Chainlink price feed address |

**Returns**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `price`   | `uint256` | The price from Chainlink             |
| `success` | `bool`    | Whether the operation was successful |

### \_getCurvePrice

Get price from Curve with maximum gas efficiency

```solidity
function _getCurvePrice(address pool) internal view returns (uint256 price, bool success);
```

**Parameters**

| Name   | Type      | Description            |
| ------ | --------- | ---------------------- |
| `pool` | `address` | The Curve pool address |

**Returns**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `price`   | `uint256` | The price from Curve                 |
| `success` | `bool`    | Whether the operation was successful |

### \_getContractCallPrice

Get price from contract call with maximum gas efficiency

```solidity
function _getContractCallPrice(address token, address contractAddr, bytes4 selector, uint8 needsArg) internal view returns (uint256 price, bool success);
```

**Parameters**

| Name           | Type      | Description                            |
| -------------- | --------- | -------------------------------------- |
| `token`        | `address` | The token address                      |
| `contractAddr` | `address` | The contract to call                   |
| `selector`     | `bytes4`  | The function selector                  |
| `needsArg`     | `uint8`   | Whether the function needs an argument |

**Returns**

| Name      | Type      | Description                          |
| --------- | --------- | ------------------------------------ |
| `price`   | `uint256` | The price from the contract call     |
| `success` | `bool`    | Whether the operation was successful |

### getTokenPrice

Get token price directly (for external calls)

```solidity
function getTokenPrice(address token) external view override(ITokenRegistryOracle) returns (uint256);
```

**Parameters**

| Name    | Type      | Description                            |
| ------- | --------- | -------------------------------------- |
| `token` | `address` | The token address to get the price for |

**Returns**

| Name     | Type      | Description                          |
| -------- | --------- | ------------------------------------ |
| `<none>` | `uint256` | The price in ETH terms (18 decimals) |

### \_getTokenPrice_exposed

TEST ONLY: Get token price from primary source

_This function exposes the internal \_getTokenPrice for testing purposes_

```solidity
function _getTokenPrice_exposed(address token) external view returns (uint256 price, bool success);
```

**Parameters**

| Name    | Type      | Description                            |
| ------- | --------- | -------------------------------------- |
| `token` | `address` | The token address to get the price for |

**Returns**

| Name      | Type      | Description                            |
| --------- | --------- | -------------------------------------- |
| `price`   | `uint256` | The price in ETH terms (18 decimals)   |
| `success` | `bool`    | Whether the price fetch was successful |

### \_getFallbackPrice_exposed

TEST ONLY: Get token price from fallback source

_This function exposes the internal \_getFallbackPrice for testing purposes_

```solidity
function _getFallbackPrice_exposed(address token) external view returns (uint256 price, bool success);
```

**Parameters**

| Name    | Type      | Description                                     |
| ------- | --------- | ----------------------------------------------- |
| `token` | `address` | The token address to get the fallback price for |

**Returns**

| Name      | Type      | Description                                     |
| --------- | --------- | ----------------------------------------------- |
| `price`   | `uint256` | The fallback price in ETH terms (18 decimals)   |
| `success` | `bool`    | Whether the fallback price fetch was successful |

### \_getChainlinkPrice_exposed

TEST ONLY: Get Chainlink price

_This function exposes the internal \_getChainlinkPrice for testing purposes_

```solidity
function _getChainlinkPrice_exposed(address feed) external view returns (uint256 price, bool success);
```

**Parameters**

| Name   | Type      | Description                      |
| ------ | --------- | -------------------------------- |
| `feed` | `address` | The Chainlink price feed address |

**Returns**

| Name      | Type      | Description                            |
| --------- | --------- | -------------------------------------- |
| `price`   | `uint256` | The price from Chainlink (18 decimals) |
| `success` | `bool`    | Whether the price fetch was successful |

### \_getCurvePrice_exposed

TEST ONLY: Get Curve price

_This function exposes the internal \_getCurvePrice for testing purposes_

```solidity
function _getCurvePrice_exposed(address pool) external view returns (uint256 price, bool success);
```

**Parameters**

| Name   | Type      | Description            |
| ------ | --------- | ---------------------- |
| `pool` | `address` | The Curve pool address |

**Returns**

| Name      | Type      | Description                            |
| --------- | --------- | -------------------------------------- |
| `price`   | `uint256` | The price from Curve (18 decimals)     |
| `success` | `bool`    | Whether the price fetch was successful |

### \_getContractCallPrice_exposed

TEST ONLY: Get price from contract call

_This function exposes the internal \_getContractCallPrice for testing purposes_

```solidity
function _getContractCallPrice_exposed(address token, address contractAddr, bytes4 selector, uint8 needsArg) external view returns (uint256 price, bool success);
```

**Parameters**

| Name           | Type      | Description                            |
| -------------- | --------- | -------------------------------------- |
| `token`        | `address` | The token address                      |
| `contractAddr` | `address` | The contract to call                   |
| `selector`     | `bytes4`  | The function selector                  |
| `needsArg`     | `uint8`   | Whether the function needs an argument |

**Returns**

| Name      | Type      | Description                                    |
| --------- | --------- | ---------------------------------------------- |
| `price`   | `uint256` | The price from the contract call (18 decimals) |
| `success` | `bool`    | Whether the price fetch was successful         |
