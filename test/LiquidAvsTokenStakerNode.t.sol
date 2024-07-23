// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LiquidAvsToken.sol";
import "../src/LiquidAvsStakerNode.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

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

contract MockEigenlayerStrategy is IEigenlayerStrategy {
    IERC20 public avsToken;
    mapping(address => uint256) public deposits;

    constructor(address _avsToken) {
        avsToken = IERC20(_avsToken);
    }

    function deposit(uint256 amount) external override {
        avsToken.transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
    }
}

contract MockEigenlayerOperator is IEigenlayerOperator {
    mapping(address => address) public delegations;

    function delegate(address operator) external override {
        delegations[msg.sender] = operator;
    }
}

contract LiquidAvsStakerNodeTest is Test {
    LiquidAvsStakerNode public stakerNode;
    MockAvsToken public mockAvsToken;
    MockEigenlayerStrategy public mockStrategy;
    MockEigenlayerOperator public mockOperator;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        mockAvsToken = new MockAvsToken();
        mockStrategy = new MockEigenlayerStrategy(address(mockAvsToken));
        mockOperator = new MockEigenlayerOperator();

        stakerNode = new LiquidAvsStakerNode(
            address(mockAvsToken),
            address(mockStrategy),
            address(mockOperator)
        );

        // Mint some tokens to the staker node
        mockAvsToken.mint(address(stakerNode), 1000 ether);
    }

    function testInitialState() public {
        assertEq(address(stakerNode.avsToken()), address(mockAvsToken));
        assertEq(address(stakerNode.strategy()), address(mockStrategy));
        assertEq(
            address(stakerNode.eigenlayerOperator()),
            address(mockOperator)
        );
        assertEq(stakerNode.owner(), owner);
    }

    function testDelegateToOperator() public {
        address operator = address(0x2);

        vm.prank(owner);
        stakerNode.delegateToOperator(operator);

        assertEq(mockOperator.delegations(address(stakerNode)), operator);
    }

    function testFailDelegateToOperatorNotOwner() public {
        address operator = address(0x2);

        vm.prank(user);
        stakerNode.delegateToOperator(operator);
    }

    function testDepositToStrategy() public {
        uint256 depositAmount = 100 ether;

        vm.prank(owner);
        stakerNode.depositToStrategy(depositAmount);

        assertEq(mockStrategy.deposits(address(stakerNode)), depositAmount);
        assertEq(mockAvsToken.balanceOf(address(stakerNode)), 900 ether);
    }

    function testFailDepositToStrategyNotOwner() public {
        uint256 depositAmount = 100 ether;

        vm.prank(user);
        stakerNode.depositToStrategy(depositAmount);
    }

    function testFailDepositToStrategyInsufficientBalance() public {
        uint256 depositAmount = 1001 ether;

        vm.prank(owner);
        stakerNode.depositToStrategy(depositAmount);
    }

    function testWithdrawTokens() public {
        uint256 withdrawAmount = 100 ether;

        vm.prank(owner);
        stakerNode.withdrawTokens(user, withdrawAmount);

        assertEq(mockAvsToken.balanceOf(user), withdrawAmount);
        assertEq(mockAvsToken.balanceOf(address(stakerNode)), 900 ether);
    }

    function testFailWithdrawTokensNotOwner() public {
        uint256 withdrawAmount = 100 ether;

        vm.prank(user);
        stakerNode.withdrawTokens(user, withdrawAmount);
    }

    function testFailWithdrawTokensInsufficientBalance() public {
        uint256 withdrawAmount = 1001 ether;

        vm.prank(owner);
        stakerNode.withdrawTokens(user, withdrawAmount);
    }

    function testFailWithdrawTokensToZeroAddress() public {
        uint256 withdrawAmount = 100 ether;

        vm.prank(owner);
        stakerNode.withdrawTokens(address(0), withdrawAmount);
    }
}
