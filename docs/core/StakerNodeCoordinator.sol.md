# StakerNodeCoordinator

[Git Source](https://github.com/EigenExplorer/liquid-avs-token/blob/5327ad163b4824431dc106b6e260de3ac2542f2f/src/core/StakerNodeCoordinator.sol)

**Inherits:**
[IStakerNodeCoordinator](/src/interfaces/IStakerNodeCoordinator.sol/interface.IStakerNodeCoordinator.md), AccessControlUpgradeable

Coordinates the creation and management of staker nodes

_Manages the upgradeability and initialization of staker nodes_

## State Variables

### liquidTokenManager

```solidity
ILiquidTokenManager public override liquidTokenManager;
```

### strategyManager

```solidity
IStrategyManager public override strategyManager;
```

### delegationManager

```solidity
IDelegationManager public override delegationManager;
```

### maxNodes

```solidity
uint256 public override maxNodes;
```

### upgradeableBeacon

```solidity
UpgradeableBeacon public upgradeableBeacon;
```

### stakerNodes

```solidity
IStakerNode[] private stakerNodes;
```

### STAKER_NODES_DELEGATOR_ROLE

```solidity
bytes32 public constant STAKER_NODES_DELEGATOR_ROLE = keccak256("STAKER_NODES_DELEGATOR_ROLE");
```

### STAKER_NODE_CREATOR_ROLE

```solidity
bytes32 public constant STAKER_NODE_CREATOR_ROLE = keccak256("STAKER_NODE_CREATOR_ROLE");
```

## Functions

### constructor

_Disables initializers for the implementation contract_

```solidity
constructor();
```

### initialize

Initializes the StakerNodeCoordinator contract

_This function can only be called once due to the initializer modifier_

```solidity
function initialize(Init calldata init) external override initializer;
```

**Parameters**

| Name   | Type   | Description                                 |
| ------ | ------ | ------------------------------------------- |
| `init` | `Init` | Struct containing initialization parameters |

### createStakerNode

Creates a new staker node

_Only callable by accounts with STAKER_NODE_CREATOR_ROLE_

```solidity
function createStakerNode()
    public
    override
    notZeroAddress(address(upgradeableBeacon))
    onlyRole(STAKER_NODE_CREATOR_ROLE)
    returns (IStakerNode);
```

**Returns**

| Name     | Type          | Description                                                |
| -------- | ------------- | ---------------------------------------------------------- |
| `<none>` | `IStakerNode` | The IStakerNode interface of the newly created staker node |

### initializeStakerNode

Initializes a staker node

_This function is internal and called during node creation and upgrades_

```solidity
function initializeStakerNode(IStakerNode node, uint256 nodeId) internal;
```

**Parameters**

| Name     | Type          | Description                   |
| -------- | ------------- | ----------------------------- |
| `node`   | `IStakerNode` | The staker node to initialize |
| `nodeId` | `uint256`     | The ID of the staker node     |

### upgradeStakerNodeImplementation

Upgrades the staker node implementation

_Can only be called by an account with DEFAULT_ADMIN_ROLE_

```solidity
function upgradeStakerNodeImplementation(address _implementationContract)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    notZeroAddress(_implementationContract);
```

**Parameters**

| Name                      | Type      | Description                                |
| ------------------------- | --------- | ------------------------------------------ |
| `_implementationContract` | `address` | Address of the new implementation contract |

### setMaxNodes

Sets the maximum number of staker nodes

_Can only be called by an account with DEFAULT_ADMIN_ROLE_

```solidity
function setMaxNodes(uint256 _maxNodes) public override onlyRole(DEFAULT_ADMIN_ROLE);
```

**Parameters**

| Name        | Type      | Description                 |
| ----------- | --------- | --------------------------- |
| `_maxNodes` | `uint256` | New maximum number of nodes |

### hasStakerNodeDelegatorRole

Checks if an address has the STAKER_NODES_DELEGATOR_ROLE

```solidity
function hasStakerNodeDelegatorRole(address _address) public view override returns (bool);
```

**Parameters**

| Name       | Type      | Description      |
| ---------- | --------- | ---------------- |
| `_address` | `address` | Address to check |

**Returns**

| Name     | Type   | Description                                            |
| -------- | ------ | ------------------------------------------------------ |
| `<none>` | `bool` | bool True if the address has the role, false otherwise |

### hasLiquidTokenManagerRole

Checks if a caller is the liquid token manager

```solidity
function hasLiquidTokenManagerRole(address caller) public view override returns (bool);
```

**Parameters**

| Name     | Type      | Description      |
| -------- | --------- | ---------------- |
| `caller` | `address` | Address to check |

**Returns**

| Name     | Type   | Description                                                          |
| -------- | ------ | -------------------------------------------------------------------- |
| `<none>` | `bool` | bool True if the caller is the liquid token manager, false otherwise |

### getAllNodes

Retrieves all staker nodes

```solidity
function getAllNodes() public view override returns (IStakerNode[] memory);
```

**Returns**

| Name     | Type            | Description                            |
| -------- | --------------- | -------------------------------------- |
| `<none>` | `IStakerNode[]` | An array of all IStakerNode interfaces |

### getStakerNodesCount

Gets the total number of staker nodes

```solidity
function getStakerNodesCount() public view override returns (uint256);
```

**Returns**

| Name     | Type      | Description                        |
| -------- | --------- | ---------------------------------- |
| `<none>` | `uint256` | uint256 The number of staker nodes |

### getNodeById

Retrieves a staker node by its ID

```solidity
function getNodeById(uint256 nodeId) public view override returns (IStakerNode);
```

**Parameters**

| Name     | Type      | Description               |
| -------- | --------- | ------------------------- |
| `nodeId` | `uint256` | The ID of the staker node |

**Returns**

| Name     | Type          | Description                                  |
| -------- | ------------- | -------------------------------------------- |
| `<none>` | `IStakerNode` | The IStakerNode interface of the staker node |

### notZeroAddress

_Reverts if the address is zero_

```solidity
modifier notZeroAddress(address _address);
```

**Parameters**

| Name       | Type      | Description          |
| ---------- | --------- | -------------------- |
| `_address` | `address` | The address to check |
