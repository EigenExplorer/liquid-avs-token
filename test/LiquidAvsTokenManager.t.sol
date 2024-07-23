// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LiquidAvsTokenManager.sol";
import "../src/LiquidAvsToken.sol";
import "../src/LiquidAvsStakerNode.sol";

contract MockAvsToken is ERC20 {
    constructor() ERC20("Mock AVS Token", "mAVS") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockLiquidAvsToken is LiquidAvsToken {
    constructor(
        string memory name,
        string memory symbol,
        IERC20 _avsToken
    ) LiquidAvsToken(name, symbol, _avsToken) {}
}

contract MockEigenlayerStrategy {
    function deposit(uint256 amount) external {}
}

contract MockEigenlayerOperator {
    function delegate(address operator) external {}
}

contract LiquidAVSTokenManagerTest is Test {
    LiquidAVSTokenManager public manager;
    MockAvsToken public mockAvsToken;
    MockLiquidAvsToken public mockLAvsToken;
    MockEigenlayerStrategy public mockStrategy;
    MockEigenlayerOperator public mockOperator;
    address public owner;
    address public user;
    LiquidAvsStakerNode public node1;
    LiquidAvsStakerNode public node2;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        // Deploy mock contracts
        mockAvsToken = new MockAvsToken();
        mockLAvsToken = new MockLiquidAvsToken(
            "Liquid AVS Token",
            "lAVS",
            mockAvsToken
        );
        mockStrategy = new MockEigenlayerStrategy();
        mockOperator = new MockEigenlayerOperator();

        // Deploy LiquidAVSTokenManager
        manager = new LiquidAVSTokenManager(address(mockLAvsToken));

        // Set the LiquidAVSTokenManager as the strategy manager in the mock token
        mockLAvsToken.setStrategyManager(address(manager));

        mockAvsToken.mint(owner, 1000 ether);
        mockAvsToken.approve(owner, 100 ether);

        mockLAvsToken.deposit(100 ether);

        // Deploy LiquidAvsStakerNode instances
        node1 = new LiquidAvsStakerNode(
            address(mockLAvsToken),
            address(mockStrategy),
            address(mockOperator)
        );
        node2 = new LiquidAvsStakerNode(
            address(mockLAvsToken),
            address(mockStrategy),
            address(mockOperator)
        );
    }

    function testInitialState() public {
        assertEq(address(manager.lAvsToken()), address(mockLAvsToken));
        assertEq(manager.owner(), owner);
        assertEq(manager.getStakerNodesCount(), 0);
    }

    function testAddStakerNode() public {
        vm.prank(owner);
        manager.addStakerNode(address(node1));

        assertTrue(manager.isStakerNode(address(node1)));
        assertEq(manager.getStakerNodesCount(), 1);
    }

    function testFailAddStakerNodeNotOwner() public {
        vm.prank(user);
        manager.addStakerNode(address(node1));
    }

    function testFailAddZeroAddressStakerNode() public {
        vm.prank(owner);
        manager.addStakerNode(address(0));
    }

    function testWithdrawToNode() public {
        vm.startPrank(owner);
        manager.addStakerNode(address(node1));
        manager.withdrawToNode(address(node1), 100);
        vm.stopPrank();

        // Note: We can't assert the actual withdrawal here because we're using a mock
        // In a real scenario, you'd want to check the balance changes
    }

    function testFailWithdrawToNodeNotOwner() public {
        vm.prank(owner);
        manager.addStakerNode(address(node1));

        vm.prank(user);
        manager.withdrawToNode(address(node1), 100);
    }

    function testFailWithdrawToNonRegisteredNode() public {
        vm.prank(owner);
        manager.withdrawToNode(address(node2), 100);
    }

    function testIsStakerNode() public {
        assertFalse(manager.isStakerNode(address(node1)));

        vm.prank(owner);
        manager.addStakerNode(address(node1));

        assertTrue(manager.isStakerNode(address(node1)));
        assertFalse(manager.isStakerNode(address(node2)));
    }

    function testGetStakerNodesCount() public {
        assertEq(manager.getStakerNodesCount(), 0);

        vm.startPrank(owner);
        manager.addStakerNode(address(node1));
        manager.addStakerNode(address(node2));
        vm.stopPrank();

        assertEq(manager.getStakerNodesCount(), 2);
    }
}
