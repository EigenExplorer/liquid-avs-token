# LiquidTokenManager
[Git Source](https://github.com/EigenExplorer/liquid-avs-token/blob/5327ad163b4824431dc106b6e260de3ac2542f2f/src/core/LiquidTokenManager.sol)

**Inherits:**
[ILiquidTokenManager](/src/interfaces/ILiquidTokenManager.sol/interface.ILiquidTokenManager.md), Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable

Manages liquid tokens and their staking to EigenLayer strategies

*Implements ILiquidTokenManager and uses OpenZeppelin's upgradeable contracts*


## State Variables
### STRATEGY_CONTROLLER_ROLE

```solidity
bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256("STRATEGY_CONTROLLER_ROLE");
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


### strategies
Mapping of assets to their corresponding EigenLayer strategies


```solidity
mapping(IERC20 => IStrategy) public strategies;
```


## Functions
### constructor

*Disables initializers for the implementation contract*


```solidity
constructor();
```

### initialize

Initializes the contract


```solidity
function initialize(Init memory init) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`init`|`Init`|Initialization parameters|


### stakeAssetsToNode

Stakes assets to a specific node


```solidity
function stakeAssetsToNode(uint256 nodeId, IERC20[] memory assets, uint256[] memory amounts)
    external
    onlyRole(STRATEGY_CONTROLLER_ROLE)
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeId`|`uint256`|The ID of the node to stake to|
|`assets`|`IERC20[]`|Array of asset addresses to stake|
|`amounts`|`uint256[]`|Array of amounts to stake for each asset|


### stakeAssetsToNodes

Stakes assets to multiple nodes


```solidity
function stakeAssetsToNodes(NodeAllocation[] calldata allocations)
    external
    onlyRole(STRATEGY_CONTROLLER_ROLE)
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`allocations`|`NodeAllocation[]`|Array of NodeAllocation structs containing staking information|


### _stakeAssetsToNode

Internal function to stake assets to a node


```solidity
function _stakeAssetsToNode(uint256 nodeId, IERC20[] memory assets, uint256[] memory amounts) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nodeId`|`uint256`|The ID of the node to stake to|
|`assets`|`IERC20[]`|Array of asset addresses to stake|
|`amounts`|`uint256[]`|Array of amounts to stake for each asset|


### setStrategy

Sets or updates the strategy for a given asset


```solidity
function setStrategy(IERC20 asset, IStrategy strategy) external onlyRole(STRATEGY_CONTROLLER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`IERC20`|The asset token address|
|`strategy`|`IStrategy`|The strategy contract address|


### getStakedAssetBalance

Gets the staked balance of an asset for a specific node


```solidity
function getStakedAssetBalance(IERC20 asset, uint256 nodeId) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`IERC20`|The asset token address|
|`nodeId`|`uint256`|The ID of the node|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The staked balance of the asset for the node|


