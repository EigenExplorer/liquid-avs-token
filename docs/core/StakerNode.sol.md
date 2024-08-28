# StakerNode
[Git Source](https://github.com/EigenExplorer/liquid-avs-token/blob/5327ad163b4824431dc106b6e260de3ac2542f2f/src/core/StakerNode.sol)

**Inherits:**
[IStakerNode](/src/interfaces/IStakerNode.sol/interface.IStakerNode.md), Initializable, ReentrancyGuardUpgradeable

Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management

*Interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards*


## State Variables
### coordinator

```solidity
IStakerNodeCoordinator public coordinator;
```


### id

```solidity
uint256 public id;
```


### LIQUID_TOKEN_MANAGER_ROLE

```solidity
bytes32 public constant LIQUID_TOKEN_MANAGER_ROLE = keccak256("LIQUID_TOKEN_MANAGER_ROLE");
```


### STAKER_NODES_DELEGATOR_ROLE

```solidity
bytes32 public constant STAKER_NODES_DELEGATOR_ROLE = keccak256("STAKER_NODES_DELEGATOR_ROLE");
```


## Functions
### constructor

*Disables initializers for the implementation contract*


```solidity
constructor();
```

### initialize

Initializes the StakerNode contract


```solidity
function initialize(Init memory init) public notZeroAddress(address(init.coordinator)) initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`init`|`Init`|Initialization parameters including coordinator address and node ID|


### depositAssets

Deposits assets into Eigenlayer strategies


```solidity
function depositAssets(IERC20[] calldata assets, uint256[] calldata amounts, IStrategy[] calldata strategies)
    external
    override
    nonReentrant
    onlyRole(LIQUID_TOKEN_MANAGER_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`IERC20[]`|Array of ERC20 token addresses to deposit|
|`amounts`|`uint256[]`|Array of amounts to deposit for each asset|
|`strategies`|`IStrategy[]`|Array of Eigenlayer strategies to deposit into|


### delegate

Delegates the StakerNode's assets to an operator


```solidity
function delegate(address operator, ISignatureUtils.SignatureWithExpiry memory signature, bytes32 approverSalt)
    public
    override
    onlyRole(STAKER_NODES_DELEGATOR_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|Address of the operator to delegate to|
|`signature`|`ISignatureUtils.SignatureWithExpiry`|Signature authorizing the delegation|
|`approverSalt`|`bytes32`|Salt used in the signature|


### undelegate

Undelegates the StakerNode's assets from the current operator


```solidity
function undelegate() public override onlyRole(STAKER_NODES_DELEGATOR_ROLE);
```

### implementation

Returns the address of the current implementation contract


```solidity
function implementation() public view override returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the implementation contract|


### getInitializedVersion

Returns the version of the contract that was last initialized


```solidity
function getInitializedVersion() external view override returns (uint64);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint64`|The initialized version as a uint64|


### onlyRole

*Reverts if the caller doesn't have the required role*


```solidity
modifier onlyRole(bytes32 role);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`role`|`bytes32`|The role to check for|


### notZeroAddress

*Reverts if the address is zero*


```solidity
modifier notZeroAddress(address _address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_address`|`address`|The address to check|


