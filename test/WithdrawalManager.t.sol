// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import "forge-std/console.sol";

import "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WithdrawalManager} from "../src/core/WithdrawalManager.sol";
import {IWithdrawalManager} from "../src/interfaces/IWithdrawalManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ITokenRegistryOracle} from "../src/interfaces/ITokenRegistryOracle.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./common/BaseTest.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/interfaces/IPauserRegistry.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ------------------------------------------------------------------------------
// Custom mocking
// ------------------------------------------------------------------------------

/// @notice Token that simulates rebasing ie, increase in user balances over time
/// @dev To mock LSTs like stETH, rRETH
/// @dev Use like any ERC20 token, warp time to increase user balance
contract MockRebasingToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalShares;
    uint256 private _totalPooledEther;
    uint256 private _lastRebaseTime;
    uint256 private _rebaseRate;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        _totalPooledEther = 1e18;
        _totalShares = 1e18;
        _lastRebaseTime = block.timestamp;
        _rebaseRate = 5e16; // 5% annually
    }

    function totalSupply() external view returns (uint256) {
        return _getCurrentTotalPooledEther();
    }

    function balanceOf(address account) external view returns (uint256) {
        uint256 currentPooled = _getCurrentTotalPooledEther();
        if (_totalShares == 0) return 0;
        return (_shares[account] * currentPooled) / _totalShares;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");

        if (currentAllowance != type(uint256).max) {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }

        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        uint256 currentBalance = this.balanceOf(from);
        require(currentBalance >= amount, "ERC20: transfer amount exceeds balance");

        // Convert amount to shares
        uint256 currentPooled = _getCurrentTotalPooledEther();
        uint256 sharesToTransfer = _totalShares > 0 ? (amount * _totalShares) / currentPooled : amount;

        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;

        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        uint256 currentPooled = _getCurrentTotalPooledEther();
        uint256 sharesToMint = _totalShares > 0 ? (amount * _totalShares) / currentPooled : amount;

        _shares[to] += sharesToMint;
        _totalShares += sharesToMint;

        emit Transfer(address(0), to, amount);
    }

    function _getCurrentTotalPooledEther() internal view returns (uint256) {
        if (_rebaseRate == 0) return _totalPooledEther;

        uint256 timeElapsed = block.timestamp - _lastRebaseTime;
        uint256 growth = (_totalPooledEther * _rebaseRate * timeElapsed) / (365 days * 1e18);
        return _totalPooledEther + growth;
    }
}

/// @notice Token that simulates rounding errors during transfer causing 1 wei loss for recepient
/// @dev To mock LSTs like stETH
contract MockTransferLossToken is MockERC20 {
    constructor(string memory name, string memory symbol) MockERC20(name, symbol) {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(this.balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Apply 1 wei loss on transfers
        uint256 actualTransfer = amount > 0 ? amount - 1 : 0;

        // Burn the full amount from sender
        _burn(msg.sender, amount);

        // Mint only the reduced amount to recipient
        _mint(to, actualTransfer);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(this.balanceOf(from) >= amount, "Insufficient balance");
        require(this.allowance(from, msg.sender) >= amount, "Insufficient allowance");

        uint256 actualTransfer = amount > 0 ? amount - 1 : 0;
        uint256 allowed = this.allowance(from, msg.sender);

        if (allowed != type(uint256).max) {
            // Call parent transferFrom for the full amount
            bool success = super.transferFrom(from, to, amount);
            require(success, "Transfer failed");

            // Burn the 1 wei loss from recipient
            if (amount > 0) {
                _burn(to, 1);
            }

            return true;
        } else {
            // Unlimited allowance case
            _burn(from, amount);
            _mint(to, actualTransfer);
            return true;
        }
    }
}

// ------------------------------------------------------------------------------
// Testing
// ------------------------------------------------------------------------------

contract WithdrawalManagerTest is BaseTest {
    IStakerNode public stakerNode;
    MockStrategy public token3Strategy;
    MockStrategy public token4Strategy;
    MockRebasingToken public token3 = new MockRebasingToken("Mock rebasing", "R");
    MockTransferLossToken public token4 = new MockTransferLossToken("Mock transfer loss", "TL");
    address public operator = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)))));

    // ------------------------------------------------------------------------------
    // Setup environment
    // ------------------------------------------------------------------------------

    function setUp() public override {
        super.setUp();
        _setupOracleMocks();
        _setupAdditionalTokens();
        _setupStakerNodeAndOperator();
    }

    /// @notice Isolate TRO such it is never actually used -- price discovery is hardcoded
    /// @dev Will be called by LiquidToken's `deposit()`
    function _setupOracleMocks() internal {
        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.arePricesStale.selector),
            abi.encode(false)
        );

        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector),
            abi.encode(1e18)
        );
    }

    /// @notice Register additional tokens for testing withdrawal scenarios
    function _setupAdditionalTokens() internal {
        token3Strategy = new MockStrategy(strategyManager, IERC20(address(token3)));
        token4Strategy = new MockStrategy(strategyManager, IERC20(address(token4)));

        vm.startPrank(admin);
        liquidTokenManager.addToken(
            IERC20(address(token3)),
            18,
            0,
            IStrategy(address(token3Strategy)),
            SOURCE_TYPE_CHAINLINK,
            address(new MockChainlinkFeed(int256(1e8), 8)),
            0,
            address(0),
            bytes4(0)
        );

        liquidTokenManager.addToken(
            IERC20(address(token4)),
            18,
            0,
            IStrategy(address(token4Strategy)),
            SOURCE_TYPE_CHAINLINK,
            address(new MockChainlinkFeed(int256(1e8), 8)),
            0,
            address(0),
            bytes4(0)
        );
        vm.stopPrank();
    }

    function _setupStakerNodeAndOperator() internal {
        // Whitelist all strategies
        vm.prank(strategyManager.strategyWhitelister());
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](4);
        strategiesToWhitelist[0] = IStrategy(address(mockStrategy));
        strategiesToWhitelist[1] = IStrategy(address(mockStrategy2));
        strategiesToWhitelist[2] = IStrategy(address(token3Strategy));
        strategiesToWhitelist[3] = IStrategy(address(token4Strategy));
        strategyManager.addStrategiesToDepositWhitelist(strategiesToWhitelist);
        vm.stopPrank();

        // Register a new Operator
        vm.prank(operator);
        delegationManager.registerAsOperator(address(0), uint32(0), "ipfs://");
        vm.stopPrank();

        // Delegate Staker Node to new Operator
        vm.startPrank(admin);
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        stakerNode = stakerNodeCoordinator.createStakerNode();
        stakerNode.delegate(operator, signature, bytes32(0));
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------------
    // Test the environment setup
    // ------------------------------------------------------------------------------

    /// @notice Test rebasing behavior with EigenLayer's `sharesToUnderlying` accuracy
    function testRebasingTokenAccuracy() public {
        address testUser = address(0x123456);
        MockRebasingToken rebasingToken = token3;
        MockStrategy rebasingStrategy = token3Strategy;

        // Deal tokens to user
        rebasingToken.mint(testUser, 100e18);
        uint256 depositAmount = rebasingToken.balanceOf(testUser);

        // Test user delegates to the operator and deposits
        vm.startPrank(testUser);

        rebasingToken.approve(address(rebasingStrategy), depositAmount);
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        delegationManager.delegateTo(operator, signature, bytes32(0));
        rebasingToken.approve(address(strategyManager), depositAmount);

        strategyManager.depositIntoStrategy(
            IStrategy(address(rebasingStrategy)),
            IERC20(address(rebasingToken)),
            depositAmount
        );

        vm.stopPrank();

        // Track conversion after real deposits
        uint256 userShares = rebasingStrategy.shares(testUser);
        uint256 initialUnderlying = rebasingStrategy.sharesToUnderlyingView(userShares);

        // Simulate time passing for automatic rebasing (1 year = 5% growth)
        vm.warp(block.timestamp + 365 days);

        // Now the same shares should convert to more underlying tokens due to time-based rebasing
        uint256 rebasedUnderlying = rebasingStrategy.sharesToUnderlyingView(userShares);

        assertTrue(userShares > 0, "User must have been given shares");
        assertTrue(rebasedUnderlying > initialUnderlying, "Rebasing should increase underlying value");

        // Verify the rebase is reflected in LiquidTokenManager conversion too
        uint256 ltmUnderlying = liquidTokenManager.assetSharesToUnderlying(IERC20(address(rebasingToken)), userShares);
        assertEq(ltmUnderlying, rebasedUnderlying, "LTM should use strategy's sharesToUnderlying");
    }

    // ------------------------------------------------------------------------------
    // Core test functions
    // ------------------------------------------------------------------------------
}
