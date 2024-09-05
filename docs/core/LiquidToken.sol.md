# LiquidToken
[Git Source](https://github.com/EigenExplorer/liquid-avs-token/blob/5327ad163b4824431dc106b6e260de3ac2542f2f/src/core/LiquidToken.sol)

**Inherits:**
[ILiquidToken](/src/interfaces/ILiquidToken.sol/interface.ILiquidToken.md), AccessControlUpgradeable, ERC20Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable

Implements a liquid staking token with deposit, withdrawal, and asset management functionalities

*Interacts with TokenRegistry and LiquidTokenManager to manage assets and handle user requests*


## State Variables
### tokenRegistry

```solidity
ITokenRegistry public tokenRegistry;
```


### liquidTokenManager

```solidity
ILiquidTokenManager public liquidTokenManager;
```


### WITHDRAWAL_DELAY

```solidity
uint256 public constant WITHDRAWAL_DELAY = 14 days;
```


### assets

```solidity
mapping(address => uint256) public assetBalances;
```


### withdrawalRequests

```solidity
mapping(bytes32 => WithdrawalRequest) public withdrawalRequests;
```


### userWithdrawalRequests

```solidity
mapping(address => bytes32[]) public userWithdrawalRequests;
```


### PAUSER_ROLE

```solidity
bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
```


## Functions
### constructor

*Disables initializers for the implementation contract*


```solidity
constructor();
```

### initialize

Initializes the LiquidToken contract


```solidity
function initialize(Init calldata init) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`init`|`Init`|The initialization parameters|


### deposit

Allows users to deposit an asset and receive shares


```solidity
function deposit(IERC20 asset, uint256 amount, address receiver)
    external
    nonReentrant
    whenNotPaused
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`IERC20`|The ERC20 asset to deposit|
|`amount`|`uint256`|The amount of the asset to deposit|
|`receiver`|`address`|The address to receive the minted shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|shares The number of shares minted|


### requestWithdrawal

Allows users to request a withdrawal of their shares


```solidity
function requestWithdrawal(IERC20[] memory withdrawAssets, uint256[] memory shareAmounts)
    external
    nonReentrant
    whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`withdrawAssets`|`IERC20[]`|The ERC20 assets to withdraw|
|`shareAmounts`|`uint256[]`|The number of shares to withdraw for each asset|


### fulfillWithdrawal

Allows users to fulfill a withdrawal request after the delay period


```solidity
function fulfillWithdrawal(bytes32 requestId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|The unique identifier of the withdrawal request|


### transferAssets

Allows the LiquidTokenManager to transfer assets from this contract


```solidity
function transferAssets(IERC20[] calldata assetsToRetrieve, uint256[] calldata amounts) external whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetsToRetrieve`|`IERC20[]`|The ERC20 assets to transfer|
|`amounts`|`uint256[]`|The amounts of each asset to transfer|


### calculateShares

Calculates the number of shares that correspond to a given amount of an asset


```solidity
function calculateShares(IERC20 asset, uint256 amount) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`IERC20`|The ERC20 asset|
|`amount`|`uint256`|The amount of the asset|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of shares|


### calculateAmount

Calculates the amount of an asset that corresponds to a given number of shares


```solidity
function calculateAmount(IERC20 asset, uint256 shares) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`IERC20`|The ERC20 asset|
|`shares`|`uint256`|The number of shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of the asset|


### getUserWithdrawalRequests


```solidity
function getUserWithdrawalRequests(address user) external view returns (bytes32[] memory);
```

### getWithdrawalRequest


```solidity
function getWithdrawalRequest(bytes32 requestId) external view returns (WithdrawalRequest memory);
```

### totalAssets

Returns the total value of assets managed by the contract


```solidity
function totalAssets() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total value of assets in the unit of account|


### _convertToShares


```solidity
function _convertToShares(uint256 amount) internal view returns (uint256);
```

### _convertToAssets


```solidity
function _convertToAssets(uint256 shares) internal view returns (uint256);
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

