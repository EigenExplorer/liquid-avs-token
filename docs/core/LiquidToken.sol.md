# LiquidToken

[Git Source](https://github.com/EigenExplorer/liquid-avs-token/src/core/LiquidToken.sol)

**Inherits:**
[ILiquidToken](/src/interfaces/ILiquidToken.sol), AccessControlUpgradeable, ERC20Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable

Implements a liquid staking token with deposit, withdrawal, and asset management functionalities

_Interacts with TokenRegistryOracle and LiquidTokenManager to manage assets and handle user requests_

## State Variables

### liquidTokenManager

```solidity
ILiquidTokenManager public liquidTokenManager;
```

### tokenRegistryOracle

```solidity
ITokenRegistryOracle public tokenRegistryOracle;
```

### assetBalances

```solidity
mapping(address => uint256) public assetBalances;
```

### queuedAssetBalances

```solidity
mapping(address => uint256) public queuedAssetBalances;
```

### PAUSER_ROLE

```solidity
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
```

## Functions

### constructor

_Disables initializers for the implementation contract_

```solidity
constructor();
```

### initialize

Initializes the LiquidToken contract

```solidity
function initialize(Init calldata init) external initializer;
```

**Parameters**

| Name   | Type   | Description                   |
| ------ | ------ | ----------------------------- |
| `init` | `Init` | The initialization parameters |

### deposit

Allows users to deposit multiple assets and receive shares

```solidity
function deposit(
    IERC20Upgradeable[] calldata assets,
    uint256[] calldata amounts,
    address receiver
) external nonReentrant whenNotPaused returns (uint256[] memory);
```

**Parameters**

| Name       | Type                  | Description                                     |
| ---------- | --------------------- | ----------------------------------------------- |
| `assets`   | `IERC20Upgradeable[]` | The ERC20 assets to deposit                     |
| `amounts`  | `uint256[]`           | The amounts of the respective assets to deposit |
| `receiver` | `address`             | The address to receive the minted shares        |

**Returns**

| Name     | Type               | Description                                           |
| -------- | ------------------ | ----------------------------------------------------- |
| `<none>` | `uint256[] memory` | sharesArray The array of shares minted for each asset |

### creditQueuedAssetBalances

Credits queued balances for a given set of asset

```solidity
function creditQueuedAssetBalances(
    IERC20Upgradeable[] calldata assets,
    uint256[] calldata amounts
) external whenNotPaused;
```

**Parameters**

| Name      | Type                  | Description                                  |
| --------- | --------------------- | -------------------------------------------- |
| `assets`  | `IERC20Upgradeable[]` | The assets to credit                         |
| `amounts` | `uint256[]`           | The credit amounts expressed in native token |

### transferAssets

Allows the LiquidTokenManager to transfer assets from this contract

```solidity
function transferAssets(
    IERC20Upgradeable[] calldata assetsToRetrieve,
    uint256[] calldata amounts
) external whenNotPaused;
```

**Parameters**

| Name               | Type                  | Description                           |
| ------------------ | --------------------- | ------------------------------------- |
| `assetsToRetrieve` | `IERC20Upgradeable[]` | The ERC20 assets to transfer          |
| `amounts`          | `uint256[]`           | The amounts of each asset to transfer |

### calculateShares

Calculates the number of shares that correspond to a given amount of an asset

```solidity
function calculateShares(IERC20Upgradeable asset, uint256 amount) public view returns (uint256);
```

**Parameters**

| Name     | Type                | Description             |
| -------- | ------------------- | ----------------------- |
| `asset`  | `IERC20Upgradeable` | The ERC20 asset         |
| `amount` | `uint256`           | The amount of the asset |

**Returns**

| Name     | Type      | Description          |
| -------- | --------- | -------------------- |
| `<none>` | `uint256` | The number of shares |

### calculateAmount

Calculates the amount of an asset that corresponds to a given number of shares

```solidity
function calculateAmount(IERC20Upgradeable asset, uint256 shares) public view returns (uint256);
```

**Parameters**

| Name     | Type                | Description          |
| -------- | ------------------- | -------------------- |
| `asset`  | `IERC20Upgradeable` | The ERC20 asset      |
| `shares` | `uint256`           | The number of shares |

**Returns**

| Name     | Type      | Description             |
| -------- | --------- | ----------------------- |
| `<none>` | `uint256` | The amount of the asset |

### totalAssets

Returns the total value of assets managed by the contract

```solidity
function totalAssets() public view returns (uint256);
```

**Returns**

| Name     | Type      | Description                                      |
| -------- | --------- | ------------------------------------------------ |
| `<none>` | `uint256` | The total value of assets in the unit of account |

### balanceAssets

Returns the balances of multiple assets

```solidity
function balanceAssets(IERC20Upgradeable[] calldata assetList) public view returns (uint256[] memory);
```

**Parameters**

| Name        | Type                  | Description                            |
| ----------- | --------------------- | -------------------------------------- |
| `assetList` | `IERC20Upgradeable[]` | The list of assets to get balances for |

**Returns**

| Name     | Type               | Description                |
| -------- | ------------------ | -------------------------- |
| `<none>` | `uint256[] memory` | An array of asset balances |

### balanceQueuedAssets

Returns the queued balances of multiple assets

```solidity
function balanceQueuedAssets(IERC20Upgradeable[] calldata assetList) public view returns (uint256[] memory);
```

**Parameters**

| Name        | Type                  | Description                                   |
| ----------- | --------------------- | --------------------------------------------- |
| `assetList` | `IERC20Upgradeable[]` | The list of assets to get queued balances for |

**Returns**

| Name     | Type               | Description                       |
| -------- | ------------------ | --------------------------------- |
| `<none>` | `uint256[] memory` | An array of queued asset balances |

### \_convertToShares

```solidity
function _convertToShares(uint256 amount) internal view returns (uint256);
```

### \_convertToAssets

```solidity
function _convertToAssets(uint256 shares) internal view returns (uint256);
```

### \_balanceAsset

```solidity
function _balanceAsset(IERC20Upgradeable asset) internal view returns (uint256);
```

### \_balanceQueuedAsset

```solidity
function _balanceQueuedAsset(IERC20Upgradeable asset) internal view returns (uint256);
```

### pause

Pauses the contract

```solidity
function pause() external onlyRole(PAUSER_ROLE);
```

### unpause

Unpauses the contract

```solidity
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE);
```
