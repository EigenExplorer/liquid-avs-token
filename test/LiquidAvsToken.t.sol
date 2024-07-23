// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LiquidAvsToken.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// Mock AVS Token for testing purposes
contract MockAvsToken is ERC20 {
    constructor() ERC20("Mock AVS Token", "mAVS") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract LiquidAvsTokenTest is Test {
    LiquidAvsToken public liquidAvsToken;
    MockAvsToken public mockAvsToken;
    address public owner;
    address public user1;
    address public user2;
    address public strategyManager;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        strategyManager = address(0x3);

        // Deploy mock AVS token
        mockAvsToken = new MockAvsToken();

        // Deploy LiquidAvsToken
        liquidAvsToken = new LiquidAvsToken(
            "Liquid AVS Token",
            "lAVS",
            IERC20(address(mockAvsToken))
        );

        // Set strategy manager
        liquidAvsToken.setStrategyManager(strategyManager);

        // Mint some mock AVS tokens to users
        mockAvsToken.mint(user1, 1000 ether);
        mockAvsToken.mint(user2, 1000 ether);
    }

    function testInitialState() public {
        assertEq(liquidAvsToken.name(), "Liquid AVS Token");
        assertEq(liquidAvsToken.symbol(), "lAVS");
        assertEq(address(liquidAvsToken.avsToken()), address(mockAvsToken));
        assertEq(liquidAvsToken.strategyManager(), strategyManager);
        assertEq(liquidAvsToken.owner(), owner);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        mockAvsToken.approve(address(liquidAvsToken), depositAmount);
        uint256 shares = liquidAvsToken.deposit(depositAmount);
        vm.stopPrank();

        assertEq(liquidAvsToken.balanceOf(user1), shares);
        assertEq(
            mockAvsToken.balanceOf(address(liquidAvsToken)),
            depositAmount
        );
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        mockAvsToken.approve(address(liquidAvsToken), depositAmount);
        uint256 shares = liquidAvsToken.deposit(depositAmount);

        uint256 withdrawAmount = liquidAvsToken.withdraw(shares);
        vm.stopPrank();

        assertEq(liquidAvsToken.balanceOf(user1), 0);
        assertEq(mockAvsToken.balanceOf(user1), 1000 ether);
        assertEq(mockAvsToken.balanceOf(address(liquidAvsToken)), 0);
    }

    function testWithdrawToNode() public {
        uint256 depositAmount = 100 ether;
        address node = address(0x4);

        // User1 deposits AVS tokens
        vm.startPrank(user1);
        mockAvsToken.approve(address(liquidAvsToken), depositAmount);
        liquidAvsToken.deposit(depositAmount);
        vm.stopPrank();

        // Approve LiquidAvsToken to spend mockAvsToken
        vm.prank(address(liquidAvsToken));
        mockAvsToken.approve(address(liquidAvsToken), depositAmount);

        // Strategy manager withdraws to node
        vm.prank(strategyManager);
        liquidAvsToken.withdrawToNode(node, depositAmount);

        assertEq(mockAvsToken.balanceOf(node), depositAmount);
    }

    function testCalculateShares() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(user1);
        mockAvsToken.approve(address(liquidAvsToken), depositAmount);
        uint256 shares1 = liquidAvsToken.deposit(depositAmount);
        vm.stopPrank();

        assertEq(shares1, depositAmount);

        vm.startPrank(user2);
        mockAvsToken.approve(address(liquidAvsToken), depositAmount);
        uint256 shares2 = liquidAvsToken.deposit(depositAmount);
        vm.stopPrank();

        assertEq(shares2, shares1);
    }

    function testFailDepositZero() public {
        vm.prank(user1);
        liquidAvsToken.deposit(0);
    }

    function testFailWithdrawZero() public {
        vm.prank(user1);
        liquidAvsToken.withdraw(0);
    }

    function testFailWithdrawInsufficientBalance() public {
        vm.prank(user1);
        liquidAvsToken.withdraw(1 ether);
    }

    function testFailWithdrawToNodeNotStrategyManager() public {
        vm.prank(user1);
        liquidAvsToken.withdrawToNode(address(0x4), 1 ether);
    }

    function testFailWithdrawToNodeInsufficientBalance() public {
        vm.prank(strategyManager);
        liquidAvsToken.withdrawToNode(address(0x4), 1 ether);
    }
}
