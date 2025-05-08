# LiquidTokenManager

[Git Source](https://github.com/EigenExplorer/liquid-avs-token/src/core/LiquidTokenManager.sol)

**Inherits:**
[ILiquidTokenManager](/src/interfaces/ILiquidTokenManager.sol), Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable

Manages liquid tokens and their staking to EigenLayer strategies

_Implements ILiquidTokenManager and uses OpenZeppelin's upgradeable contracts_

## State Variables

### STRATEGY_CONTROLLER_ROLE

Role identifier for strategy control operations

```solidity
bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256("STRATEGY_CONTROLLER_ROLE");
```

### PRICE_UPDATER_ROLE

Role identifier for price update operations

```solidity
bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
```

### strategyManager

The EigenLayer StrategyManager contract

```solidity
IStrategyManager public strategyManager;
```

### delegationManager

The EigenLayer DelegationManager contract

```solidity
IDelegationManager public delegationManager;
```

### stakerNodeCoordinator

The StakerNodeCoordinator contract

```solidity
IStakerNodeCoordinator public stakerNodeCoordinator;
```

### liquidToken

The LiquidToken contract

```solidity
ILiquidToken public liquidToken;
```

### tokenRegistryOracle

The TokenRegistryOracle contract

```solidity
ITokenRegistryOracle public tokenRegistryOracle;
```

### tokens

Mapping of tokens to their corresponding token info

```solidity
mapping(IERC20 => TokenInfo) public tokens;
```

### tokenStrategies

Mapping of tokens to their corresponding strategies

```solidity
mapping(IERC20 => IStrategy) public tokenStrategies;
```

### supportedTokens

Array of supported token addresses

```solidity
IERC20[] public supportedTokens;
```

### PRICE_DECIMALS

Number of decimal places used for price representation

```solidity
uint256 public constant PRICE_DECIMALS = 18;
```

## Functions

### constructor

_Disables initializers for the implementation contract_

```solidity
constructor();
```

### initialize

Initializes the contract

```solidity
function initialize(Init memory init) public initializer;
```

**Parameters**

| Name   | Type   | Description               |
| ------ | ------ | ------------------------- |
| `init` | `Init` | Initialization parameters |

### addToken

Adds a new token to the registry and configures its price sources

```solidity
function addToken(IERC20 token, uint8 decimals, uint256 initialPrice, uint256 volatilityThreshold, IStrategy strategy, uint8 primaryType, address primarySource, uint8 needsArg, address fallbackSource, bytes4 fallbackFn) external onlyRole(DEFAULT_ADMIN_ROLE);
```

**Parameters**

| Name                  | Type        | Description                                                   |
| --------------------- | ----------- | ------------------------------------------------------------- |
| `token`               | `IERC20`    | Address of the token to add                                   |
| `decimals`            | `uint8`     | Number of decimals for the token                              |
| `initialPrice`        | `uint256`   | Initial price for the token                                   |
| `volatilityThreshold` | `uint256`   | Volatility threshold for price updates                        |
| `strategy`            | `IStrategy` | Strategy corresponding to the token                           |
| `primaryType`         | `uint8`     | Source type (1=Chainlink, 2=Curve, 3=BTC-chained, 4=Protocol) |
| `primarySource`       | `address`   | Primary source address                                        |
| `needsArg`            | `uint8`     | Whether fallback fn needs args                                |
| `fallbackSource`      | `address`   | Address of the fallback source contract                       |
| `fallbackFn`          | `bytes4`    | Function selector for fallback                                |

### removeToken

Removes a token from the registry

```solidity
function removeToken(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE);
```

**Parameters**

| Name    | Type     | Description                    |
| ------- | -------- | ------------------------------ |
| `token` | `IERC20` | Address of the token to remove |

### updatePrice

Updates the price of a token

```solidity
function updatePrice(IERC20 token, uint256 newPrice) external onlyRole(PRICE_UPDATER_ROLE);
```

**Parameters**

| Name       | Type      | Description                    |
| ---------- | --------- | ------------------------------ |
| `token`    | `IERC20`  | Address of the token to update |
| `newPrice` | `uint256` | New price for the token        |

### tokenIsSupported

Checks if a token is supported

```solidity
function tokenIsSupported(IERC20 token) external view returns (bool);
```

**Parameters**

| Name    | Type     | Description                   |
| ------- | -------- | ----------------------------- |
| `token` | `IERC20` | Address of the token to check |

**Returns**

| Name     | Type   | Description                                    |
| -------- | ------ | ---------------------------------------------- |
| `<none>` | `bool` | bool indicating whether the token is supported |

### convertToUnitOfAccount

Converts a token amount to the unit of account

```solidity
function convertToUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);
```

**Parameters**

| Name     | Type      | Description                     |
| -------- | --------- | ------------------------------- |
| `token`  | `IERC20`  | Address of the token to convert |
| `amount` | `uint256` | Amount of tokens to convert     |

**Returns**

| Name     | Type      | Description                                 |
| -------- | --------- | ------------------------------------------- |
| `<none>` | `uint256` | The converted amount in the unit of account |

### convertFromUnitOfAccount

Converts an amount in the unit of account to a token amount

```solidity
function convertFromUnitOfAccount(IERC20 token, uint256 amount) external view returns (uint256);
```

**Parameters**

| Name     | Type      | Description                              |
| -------- | --------- | ---------------------------------------- |
| `token`  | `IERC20`  | Address of the token to convert to       |
| `amount` | `uint256` | Amount in the unit of account to convert |

**Returns**

| Name     | Type      | Description                                 |
| -------- | --------- | ------------------------------------------- |
| `<none>` | `uint256` | The converted amount in the specified token |

### getSupportedTokens

Retrieves the list of supported tokens

```solidity
function getSupportedTokens() external view returns (IERC20[] memory);
```

**Returns**

| Name     | Type              | Description                               |
| -------- | ----------------- | ----------------------------------------- |
| `<none>` | `IERC20[] memory` | An array of addresses of supported tokens |

### getTokenInfo

Retrieves the information for a specific token

```solidity
function getTokenInfo(IERC20 token) external view returns (TokenInfo memory);
```

**Parameters**

| Name    | Type     | Description                                 |
| ------- | -------- | ------------------------------------------- |
| `token` | `IERC20` | Address of the token to get information for |

**Returns**

| Name     | Type               | Description                                         |
| -------- | ------------------ | --------------------------------------------------- |
| `<none>` | `TokenInfo memory` | TokenInfo struct containing the token's information |

### getTokenStrategy

Returns the strategy for a given asset

```solidity
function getTokenStrategy(IERC20 asset) external view returns (IStrategy);
```

**Parameters**

| Name    | Type     | Description                   |
| ------- | -------- | ----------------------------- |
| `asset` | `IERC20` | Asset to get the strategy for |

**Returns**

| Name     | Type        | Description                                        |
| -------- | ----------- | -------------------------------------------------- |
| `<none>` | `IStrategy` | IStrategy Interface for the corresponding strategy |

### stakeAssetsToNode

Stakes assets to a specific node

```solidity
function stakeAssetsToNode(uint256 nodeId, IERC20[] memory assets, uint256[] memory amounts) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant;
```

**Parameters**

| Name      | Type        | Description                              |
| --------- | ----------- | ---------------------------------------- |
| `nodeId`  | `uint256`   | The ID of the node to stake to           |
| `assets`  | `IERC20[]`  | Array of asset addresses to stake        |
| `amounts` | `uint256[]` | Array of amounts to stake for each asset |

### stakeAssetsToNodes

Stakes assets to multiple nodes

```solidity
function stakeAssetsToNodes(NodeAllocation[] calldata allocations) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant;
```

**Parameters**

| Name          | Type               | Description                                                    |
| ------------- | ------------------ | -------------------------------------------------------------- |
| `allocations` | `NodeAllocation[]` | Array of NodeAllocation structs containing staking information |

### \_stakeAssetsToNode

Internal function to stake assets to a node

```solidity
function _stakeAssetsToNode(uint256 nodeId, IERC20[] memory assets, uint256[] memory amounts) internal;
```

**Parameters**

| Name      | Type        | Description                              |
| --------- | ----------- | ---------------------------------------- |
| `nodeId`  | `uint256`   | The ID of the node to stake to           |
| `assets`  | `IERC20[]`  | Array of asset addresses to stake        |
| `amounts` | `uint256[]` | Array of amounts to stake for each asset |

### delegateNodes

Delegate a set of staker nodes to a corresponding set of operators

```solidity
function delegateNodes(uint256[] memory nodeIds, address[] memory operators, ISignatureUtilsMixinTypes.SignatureWithExpiry[] calldata approverSignatureAndExpiries, bytes32[] calldata approverSalts) external onlyRole(STRATEGY_CONTROLLER_ROLE);
```

**Parameters**

| Name                           | Type                                              | Description                                |
| ------------------------------ | ------------------------------------------------- | ------------------------------------------ |
| `nodeIds`                      | `uint256[]`                                       | The IDs of the staker nodes                |
| `operators`                    | `address[]`                                       | The addresses of the operators             |
| `approverSignatureAndExpiries` | `ISignatureUtilsMixinTypes.SignatureWithExpiry[]` | The signatures authorizing the delegations |
| `approverSalts`                | `bytes32[]`                                       | The salts used in the signatures           |

### getStakedAssetBalance

Gets the staked balance of an asset for all nodes

```solidity
function getStakedAssetBalance(IERC20 asset) external view returns (uint256);
```

**Parameters**

| Name    | Type     | Description             |
| ------- | -------- | ----------------------- |
| `asset` | `IERC20` | The asset token address |

**Returns**

| Name     | Type      | Description                                   |
| -------- | --------- | --------------------------------------------- |
| `<none>` | `uint256` | The staked balance of the asset for all nodes |

### getStakedAssetBalanceNode

Gets the staked balance of an asset for a specific node

```solidity
function getStakedAssetBalanceNode(IERC20 asset, uint256 nodeId) public view returns (uint256);
```

**Parameters**

| Name     | Type      | Description             |
| -------- | --------- | ----------------------- |
| `asset`  | `IERC20`  | The asset token address |
| `nodeId` | `uint256` | The ID of the node      |

**Returns**

| Name     | Type      | Description                                  |
| -------- | --------- | -------------------------------------------- |
| `<none>` | `uint256` | The staked balance of the asset for the node |

### \_getStakedAssetBalanceNode

Gets the staked balance of an asset for a specific node

```solidity
function _getStakedAssetBalanceNode(IERC20 asset, IStakerNode node) internal view returns (uint256);
```

**Parameters**

| Name    | Type          | Description                            |
| ------- | ------------- | -------------------------------------- |
| `asset` | `IERC20`      | The asset token address                |
| `node`  | `IStakerNode` | The node to get the staked balance for |

**Returns**

| Name     | Type      | Description                                  |
| -------- | --------- | -------------------------------------------- |
| `<none>` | `uint256` | The staked balance of the asset for the node |

### \_getAllStakedAssetBalancesNode

Gets the staked balance of all assets for a specific node

```solidity
function _getAllStakedAssetBalancesNode(IStakerNode node) internal view returns (uint256[] memory);
```

**Parameters**

| Name   | Type          | Description                            |
| ------ | ------------- | -------------------------------------- |
| `node` | `IStakerNode` | The node to get the staked balance for |

**Returns**

| Name     | Type               | Description                                    |
| -------- | ------------------ | ---------------------------------------------- |
| `<none>` | `uint256[] memory` | The staked balances of all assets for the node |

### setVolatilityThreshold

Sets the volatility threshold for a given asset

```solidity
function setVolatilityThreshold(IERC20 asset, uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE);
```

**Parameters**

| Name           | Type      | Description                                     |
| -------------- | --------- | ----------------------------------------------- |
| `asset`        | `IERC20`  | The asset token address                         |
| `newThreshold` | `uint256` | The new volatility threshold value to update to |
