// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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
        require(amount > 0, "Transfer amount must be positive");

        // Convert amount to shares first, then check if user has enough shares
        uint256 currentPooled = _getCurrentTotalPooledEther();
        uint256 sharesToTransfer = _totalShares > 0 ? (amount * _totalShares) / currentPooled : amount;

        require(_shares[from] >= sharesToTransfer, "ERC20: transfer amount exceeds balance");

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
        _totalPooledEther = currentPooled + amount;

        emit Transfer(address(0), to, amount);
    }

    function _getCurrentTotalPooledEther() internal view returns (uint256) {
        if (_rebaseRate == 0) return _totalPooledEther;

        uint256 timeElapsed = block.timestamp - _lastRebaseTime;
        uint256 growth = (_totalPooledEther * _rebaseRate * timeElapsed) / (365 days * 1e18);
        return _totalPooledEther + growth;
    }

    function getCurrentPrice() external view returns (uint256) {
        return _getCurrentTotalPooledEther();
    }
}

/// @notice Token that simulates rounding errors during transfer causing 1 wei loss for recepient
/// @dev To mock LSTs like stETH
/// @dev For simplicity there is no loss on minting, only on further transfers
contract MockTransferLossToken is MockERC20 {
    constructor(string memory name, string memory symbol) MockERC20(name, symbol) {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Apply 1 wei loss on transfers
        uint256 actualTransfer = amount > 0 ? amount - 1 : 0;

        // Burn the full amount from sender
        _burn(msg.sender, amount);

        // Mint only the reduced amount to recipient
        _mint(to, actualTransfer);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(balanceOf(from) >= amount, "Insufficient balance");
        require(allowance(from, msg.sender) >= amount, "Insufficient allowance");

        // Apply 1 wei loss on transfers
        uint256 actualTransfer = amount > 0 ? amount - 1 : 0;

        // Burn the full amount from sender
        _burn(from, amount);

        // Mint only the reduced amount to recipient
        _mint(to, actualTransfer);

        return true;
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
    /// @dev Default to 1:1 ETH for all tokens except the rebasing tokens which will be priced according to its `getCurrentPrice()`
    function _setupOracleMocks() internal {
        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.arePricesStale.selector),
            abi.encode(false)
        );

        // Mock each token explicitly
        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(testToken)),
            abi.encode(1e18)
        );

        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(testToken2)),
            abi.encode(1e18)
        );

        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(token3)),
            abi.encode(token3.getCurrentPrice())
        );

        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(token4)),
            abi.encode(1e18)
        );

        vm.mockCall(
            address(liquidTokenManager), // or wherever this function lives
            abi.encodeCall(ILiquidTokenManager.convertToUnitOfAccount, (IERC20(address(testToken)), 1e18)),
            abi.encode(1e18)
        );

        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.convertToUnitOfAccount, (IERC20(address(testToken2)), 1e18)),
            abi.encode(1e18)
        );

        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.convertToUnitOfAccount, (IERC20(address(token3)), 1e18)),
            abi.encode(token3.getCurrentPrice())
        );

        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.convertToUnitOfAccount, (IERC20(address(token4)), 1e18)),
            abi.encode(1e18)
        );
    }

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
        _warpAndUpdateToken3Oracle(365 days);

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

    function testSettleUserWithdrawalsFlow() public {
        // --- Oracle pricing verification and setup ---
        // Validates that all token price conversions work correctly before starting the test
        // Ensures 1:1 ETH equivalent pricing for all tokens to establish baseline
        // Verifies strategy share calculations are functioning properly
        // Critical for accurate withdrawal calculations later in the test
        uint256 testTokenConvert = liquidTokenManager.convertToUnitOfAccount(IERC20(address(testToken)), 1 ether);
        uint256 testToken2Convert = liquidTokenManager.convertToUnitOfAccount(IERC20(address(testToken2)), 1 ether);
        uint256 token3Convert = liquidTokenManager.convertToUnitOfAccount(IERC20(address(token3)), 1 ether);
        uint256 token4Convert = liquidTokenManager.convertToUnitOfAccount(IERC20(address(token4)), 1 ether);

        uint256 testTokenShares = mockStrategy.sharesToUnderlying(1 ether);
        uint256 testToken2Shares = mockStrategy2.sharesToUnderlying(1 ether);
        assertTrue(testTokenConvert == 1 ether, "testToken convert should be 1e18");
        assertTrue(testToken2Convert == 1 ether, "testToken2 convert should be 1e18 (NOT 0.5e18)");
        assertTrue(token3Convert == 1 ether, "token3 convert should be 1e18");
        assertTrue(token4Convert == 1 ether, "token4 convert should be 1e18");

        assertTrue(testTokenShares == 1 ether, "testToken strategy shares should be 1:1");
        assertTrue(testToken2Shares == 1 ether, "testToken2 strategy shares should be 1:1");

        //  --- Initial user deposits with diverse token types ---
        // Creates 4 users each depositing 1 ETH worth of different token types
        // Tests deposit functionality across: standard ERC20, rebasing token, transfer-loss token
        // Establishes baseline user balances and LAT share positions for withdrawal testing
        // Validates that all token types can be deposited successfully into the system
        address user1 = address(0x1001);
        address user2 = address(0x1002);
        address user3 = address(0x1003);
        address user4 = address(0x1004);

        testToken.mint(user1, 1 ether);
        testToken2.mint(user2, 1 ether);
        token3.mint(user3, 1 ether);
        token4.mint(user4, 1 ether);

        IERC20[] memory assets1 = new IERC20[](1);
        assets1[0] = IERC20(address(testToken));
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 1 ether;

        IERC20[] memory assets2 = new IERC20[](1);
        assets2[0] = IERC20(address(testToken2));
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 1 ether;

        IERC20[] memory assets3 = new IERC20[](1);
        assets3[0] = IERC20(address(token3));
        uint256[] memory amounts3 = new uint256[](1);
        amounts3[0] = 1 ether;

        IERC20[] memory assets4 = new IERC20[](1);
        assets4[0] = IERC20(address(token4));
        uint256[] memory amounts4 = new uint256[](1);
        amounts4[0] = 1 ether;

        vm.startPrank(user1);
        testToken.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets1, amounts1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        testToken2.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets2, amounts2, user2);
        vm.stopPrank();

        vm.startPrank(user3);
        token3.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets3, amounts3, user3);
        vm.stopPrank();

        vm.startPrank(user4);
        token4.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets4, amounts4, user4);
        vm.stopPrank();

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: 4 ether - 1, // 4 ETH - 1 wei (transfer loss)
                assetBalances: [uint256(1 ether), 1 ether, 1 ether, 1 ether - 1],
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [uint256(0), 0, 0, 0], // Nothing staked yet
                description: "after deposits"
            })
        );

        // --- Stake deposited funds to EigenLayer ---
        // Transitions all deposited funds from unstaked to staked state via staker node
        // Tests the integration with EigenLayer staking mechanism
        // Verifies that funds move correctly from liquid state to EigenLayer delegation
        // Ensures total assets remain consistent while changing fund location
        // Validates that transfer-loss tokens lose additional wei during staking operation
        IERC20[] memory allAssets = new IERC20[](4);
        allAssets[0] = IERC20(address(testToken));
        allAssets[1] = IERC20(address(testToken2));
        allAssets[2] = IERC20(address(token3));
        allAssets[3] = IERC20(address(token4));

        IERC20[] memory allAssetsToStake = new IERC20[](4);
        allAssetsToStake[0] = IERC20(address(testToken));
        allAssetsToStake[1] = IERC20(address(testToken2));
        allAssetsToStake[2] = IERC20(address(token3));
        allAssetsToStake[3] = IERC20(address(token4));

        uint256[] memory assetBalancesForStaking = liquidToken.balanceAssets(allAssets);
        uint256[] memory allAmountsToStake = new uint256[](4);
        allAmountsToStake[0] = assetBalancesForStaking[0];
        allAmountsToStake[1] = assetBalancesForStaking[1];
        allAmountsToStake[2] = assetBalancesForStaking[2];
        allAmountsToStake[3] = assetBalancesForStaking[3];

        vm.startPrank(admin);
        liquidTokenManager.stakeAssetsToNode(stakerNode.getId(), allAssetsToStake, allAmountsToStake);
        vm.stopPrank();

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: 4 ether - 4, // Same as deposits minus another 3 wei for token4 transfer during staking
                assetBalances: [uint256(0), 0, 0, 0], // Everything staked
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [uint256(1 ether), 1 ether, 1 ether, 1 ether - 4], // Everything now staked to node
                description: "after staking"
            })
        );

        // --- Simulate EigenLayer slashing across different tokens ---
        // Creates realistic slashing scenario with varying percentages per token type
        // TestToken1: 100% slash (total loss), TestToken2: 50% slash (moderate loss)
        // Token3: 15% slash (rebasing token, minor loss), Token4: 10% slash (transfer-loss token, minimal loss)
        // Tests system's ability to handle partial and total asset losses
        // Validates that slashing calculations are accurate and properly reflected in strategy balances
        // Sets up complex withdrawal scenarios where users have different recovery rates
        uint256 strategy1BalanceBefore = testToken.balanceOf(address(mockStrategy));
        uint256 strategy2BalanceBefore = testToken2.balanceOf(address(mockStrategy2));
        uint256 strategy3BalanceBefore = token3.balanceOf(address(token3Strategy));
        uint256 strategy4BalanceBefore = token4.balanceOf(address(token4Strategy));

        vm.prank(address(mockStrategy));
        testToken.transfer(address(0xdead), strategy1BalanceBefore);

        uint256 slashAmount2 = (strategy2BalanceBefore * 50) / 100;
        vm.prank(address(mockStrategy2));
        testToken2.transfer(address(0xdead), slashAmount2);

        uint256 slashAmount3 = (strategy3BalanceBefore * 15) / 100;
        vm.prank(address(token3Strategy));
        token3.transfer(address(0xdead), slashAmount3);

        uint256 slashAmount4 = (strategy4BalanceBefore * 10) / 100;
        vm.prank(address(token4Strategy));
        token4.transfer(address(0xdead), slashAmount4);

        uint256 strategy1BalanceAfter = testToken.balanceOf(address(mockStrategy));
        uint256 strategy2BalanceAfter = testToken2.balanceOf(address(mockStrategy2));
        uint256 strategy3BalanceAfter = token3.balanceOf(address(token3Strategy));
        uint256 strategy4BalanceAfter = token4.balanceOf(address(token4Strategy));

        assertEq(strategy1BalanceAfter, 0, "testToken should be slashed 100%");
        assertEq(strategy2BalanceAfter, strategy2BalanceBefore - slashAmount2, "testToken2 should be slashed 50%");
        assertEq(strategy3BalanceAfter, strategy3BalanceBefore - slashAmount3, "token3 should be slashed 15%");
        assertEq(strategy4BalanceAfter, strategy4BalanceBefore - slashAmount4, "token4 should be slashed 10%");

        // --- Mock system state to reflect slashing impact on withdrawable balances ---
        // Simulates the end result of AllocationManager slashing by updating system state
        // Updates both withdrawable asset balances and node deposit balances to reflect losses
        // Accounts for rebasing token behavior where slashed amounts continue to accrue rewards
        // Creates realistic post-slashing environment for testing withdrawal calculations
        // Ensures that liquid token system accurately reflects reduced asset availability

        vm.clearMockedCalls();
        _setupOracleMocks();
        _updateToken3OraclePrice();

        uint256 token3SlashedAndRebased = (strategy3BalanceAfter * token3.getCurrentPrice()) / 1e18;
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getWithdrawableAssetBalance, (IERC20(address(testToken)), false)),
            abi.encode(0) // 100% slashed = 0 withdrawable
        );
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getWithdrawableAssetBalance, (IERC20(address(testToken2)), false)),
            abi.encode(strategy2BalanceAfter) // 50% slashed
        );
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getWithdrawableAssetBalance, (IERC20(address(token3)), false)),
            abi.encode(token3SlashedAndRebased) // 15% slashed but continues rebasing
        );
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getWithdrawableAssetBalance, (IERC20(address(token4)), false)),
            abi.encode(strategy4BalanceAfter) // 10% slashed
        );

        uint256 nodeId = stakerNode.getId();
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getDepositAssetBalanceNode, (IERC20(address(testToken)), nodeId, false)),
            abi.encode(0) // 100% slashed = 0 remaining on node
        );
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(
                ILiquidTokenManager.getDepositAssetBalanceNode,
                (IERC20(address(testToken2)), nodeId, false)
            ),
            abi.encode(strategy2BalanceAfter) // 50% slashed
        );
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getDepositAssetBalanceNode, (IERC20(address(token3)), nodeId, false)),
            abi.encode(token3SlashedAndRebased) // 15% slashed but continues rebasing
        );
        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeCall(ILiquidTokenManager.getDepositAssetBalanceNode, (IERC20(address(token4)), nodeId, false)),
            abi.encode(strategy4BalanceAfter) // 10% slashed
        );

        uint256 token1Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken)), false);
        uint256 token2Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken2)), false);
        uint256 token3Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token3)), false);
        uint256 token4Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token4)), false);

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: token1Remaining + token2Remaining + token3Remaining + token4Remaining,
                assetBalances: [uint256(0), 0, 0, 0], // Everything remains staked
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [token1Remaining, token2Remaining, token3Remaining, token4Remaining], // Slashed amounts
                description: "after slashing"
            })
        );

        // --- Add new deposits and simulate time-based rebasing ---
        // Creates new deposits after slashing to establish mixed staked/unstaked state
        // Tests system behavior when new funds are added to a partially slashed system
        // Simulates 1 year time passage to trigger rebasing token growth on staked positions only
        // Validates that rebasing affects staked assets but not newly deposited unstaked balances
        // Creates complex state where old staked assets have rebased, new deposits have not
        address newUser1 = address(0x2001);
        address newUser2 = address(0x2002);
        address newUser3 = address(0x2003);
        address newUser4 = address(0x2004);

        testToken.mint(newUser1, 0.5 ether);
        testToken2.mint(newUser2, 0.5 ether);
        token3.mint(newUser3, 0.5 ether);
        token4.mint(newUser4, 0.5 ether);

        uint256[] memory newAmounts1 = new uint256[](1);
        newAmounts1[0] = 0.5 ether;
        uint256[] memory newAmounts2 = new uint256[](1);
        newAmounts2[0] = 0.5 ether;
        uint256[] memory newAmounts3 = new uint256[](1);
        newAmounts3[0] = 0.5 ether;
        uint256[] memory newAmounts4 = new uint256[](1);
        newAmounts4[0] = 0.5 ether;

        vm.startPrank(newUser1);
        testToken.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets1, newAmounts1, newUser1);
        vm.stopPrank();

        vm.startPrank(newUser2);
        testToken2.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets2, newAmounts2, newUser2);
        vm.stopPrank();

        vm.startPrank(newUser3);
        token3.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets3, newAmounts3, newUser3);
        vm.stopPrank();

        vm.startPrank(newUser4);
        token4.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets4, newAmounts4, newUser4);
        vm.stopPrank();

        _warpAndUpdateToken3Oracle(365 days);

        uint256 nodeBalanceToken3AfterRebase = liquidTokenManager.getDepositAssetBalanceNode(
            IERC20(address(token3)),
            stakerNode.getId(),
            false
        );
        assertGt(
            nodeBalanceToken3AfterRebase,
            ((1 ether * 85) / 100),
            "Token3 staked balance should have rebased upward from 0.85 ETH"
        );

        uint256 totalAssetsAfterRebase = liquidToken.totalAssets();
        uint256 expectedTotalAfterSlashing = token1Remaining + token2Remaining + token3Remaining + token4Remaining;
        assertGt(
            totalAssetsAfterRebase,
            expectedTotalAfterSlashing,
            "Total assets should increase due to token3 rebase in staked position"
        );
        uint256 expectedToken1Balance = liquidTokenManager.getWithdrawableAssetBalance(
            IERC20(address(testToken)),
            false
        );
        uint256 expectedToken2Balance = liquidTokenManager.getWithdrawableAssetBalance(
            IERC20(address(testToken2)),
            false
        );
        uint256 expectedToken3Balance = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token3)), false);
        uint256 expectedToken4Balance = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token4)), false);

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: liquidToken.totalAssets(), // Accept actual value due to complex rebasing calculations
                assetBalances: [uint256(0.5 ether), 0.5 ether, 0.5 ether, 0.5 ether - 1], // New unstaked deposits
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [
                    expectedToken1Balance,
                    expectedToken2Balance,
                    expectedToken3Balance,
                    expectedToken4Balance
                ], // Previous staked amounts after rebase
                description: "after new deposits with rebase"
            })
        );

        // --- Stake new deposits and consolidate all funds ---
        // Moves the newly deposited funds from unstaked to staked state
        // Creates fully consolidated staked position before testing withdrawal functionality
        // Ensures all user funds are subject to EigenLayer delegation and potential slashing
        // Validates that mixed staked/unstaked state can be successfully consolidated
        uint256[] memory unstakedBalances = liquidToken.balanceAssets(allAssets);
        IERC20[] memory assetsToStake = new IERC20[](4);
        uint256[] memory amountsToStake = new uint256[](4);
        uint256 assetsCount = 0;

        for (uint256 i = 0; i < 4; i++) {
            if (unstakedBalances[i] > 0) {
                assetsToStake[assetsCount] = allAssets[i];
                amountsToStake[assetsCount] = unstakedBalances[i];
                assetsCount++;
            }
        }

        if (assetsCount > 0) {
            IERC20[] memory finalAssetsToStake = new IERC20[](assetsCount);
            uint256[] memory finalAmountsToStake = new uint256[](assetsCount);
            for (uint256 i = 0; i < assetsCount; i++) {
                finalAssetsToStake[i] = assetsToStake[i];
                finalAmountsToStake[i] = amountsToStake[i];
            }

            vm.startPrank(admin);
            liquidTokenManager.stakeAssetsToNode(stakerNode.getId(), finalAssetsToStake, finalAmountsToStake);
            vm.stopPrank();
        }

        // Verify final staked state before withdrawal testing
        // All funds now consolidated on staker node, ready for withdrawal operations
        uint256 expectedToken1AfterSecondStaking = 0.5 ether + expectedToken1Balance;
        uint256 expectedToken2AfterSecondStaking = 0.5 ether + expectedToken2Balance;
        uint256 currentToken3Balance = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token3)), false);
        uint256 currentToken4Balance = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token4)), false);

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: liquidToken.totalAssets(), // Accept actual value and use for downstream calculations
                assetBalances: [uint256(0), 0, 0, 0], // Everything staked again
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [
                    expectedToken1AfterSecondStaking,
                    expectedToken2AfterSecondStaking,
                    currentToken3Balance,
                    currentToken4Balance
                ], // Previous + new funds
                description: "after second staking"
            })
        );

        // --- Test withdrawal requests from original users affected by slashing ---
        // Tests withdrawal system behavior with slashed asset positions
        // User1 (100% slashed) should fail withdrawal due to insufficient assets
        // Users 2-4 can request original deposit amounts despite slashing losses
        // Validates user-friendly UX where system auto-adjusts to available post-slashing amounts
        // Verifies proper LAT share calculation and withdrawal request data integrity
        bytes32[] memory withdrawalRequestIds = new bytes32[](3);

        vm.startPrank(user1);
        uint256 user1Balance = liquidToken.balanceOf(user1);
        uint256[] memory withdrawAmounts1 = new uint256[](1);
        withdrawAmounts1[0] = liquidToken.calculateAmount(IERC20(address(testToken)), user1Balance);

        vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalRequest()"));
        liquidToken.initiateWithdrawal(assets1, withdrawAmounts1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 user2BalanceBefore = liquidToken.balanceOf(user2);
        uint256[] memory withdrawAmounts2 = new uint256[](1);
        withdrawAmounts2[0] = 1 ether;
        withdrawalRequestIds[0] = liquidToken.initiateWithdrawal(assets2, withdrawAmounts2);
        uint256 user2BalanceAfter = liquidToken.balanceOf(user2);
        vm.stopPrank();

        vm.startPrank(user3);
        uint256 user3BalanceBefore = liquidToken.balanceOf(user3);
        uint256[] memory withdrawAmounts3 = new uint256[](1);
        withdrawAmounts3[0] = 1 ether;
        withdrawalRequestIds[1] = liquidToken.initiateWithdrawal(assets3, withdrawAmounts3);
        uint256 user3BalanceAfter = liquidToken.balanceOf(user3);
        vm.stopPrank();

        vm.startPrank(user4);
        uint256 user4BalanceBefore = liquidToken.balanceOf(user4);
        uint256[] memory withdrawAmounts4 = new uint256[](1);
        withdrawAmounts4[0] = 1 ether;
        withdrawalRequestIds[2] = liquidToken.initiateWithdrawal(assets4, withdrawAmounts4);
        uint256 user4BalanceAfter = liquidToken.balanceOf(user4);
        vm.stopPrank();

        uint256 user2SharesCharged = user2BalanceBefore - user2BalanceAfter;
        uint256 user3SharesCharged = user3BalanceBefore - user3BalanceAfter;
        uint256 user4SharesCharged = user4BalanceBefore - user4BalanceAfter;

        uint256 expectedUser2Shares = liquidToken.calculateShares(IERC20(address(testToken2)), 0.5 ether);
        uint256 expectedUser3Shares = liquidToken.calculateShares(
            IERC20(address(token3)),
            nodeBalanceToken3AfterRebase
        );
        uint256 expectedUser4Shares = liquidToken.calculateShares(IERC20(address(token4)), token4Remaining);

        assertEq(user2SharesCharged, expectedUser2Shares, "User 2 should only be charged for 50% slashed amount");
        assertEq(
            user3SharesCharged,
            expectedUser3Shares,
            "User 3 should only be charged for 85% slashed + rebased amount"
        );
        assertEq(user4SharesCharged, expectedUser4Shares, "User 4 should only be charged for 90% slashed amount");

        IWithdrawalManager.WithdrawalRequest[] memory requests = withdrawalManager.getWithdrawalRequests(
            withdrawalRequestIds
        );
        assertEq(requests[0].requestedAmounts[0], 1 ether, "User 2 requested amount should be 1 ETH");
        uint256 expectedUser2WithdrawableShares = liquidTokenManager.assetUnderlyingToShares(
            IERC20(address(testToken2)),
            0.5 ether
        );
        assertEq(
            requests[0].elWithdrawableShares[0],
            expectedUser2WithdrawableShares,
            "User 2 withdrawable shares should reflect 50% slashing"
        );

        // User 3 (token3) - requested 1 ETH, should get 85% slashed + rebased amount
        assertEq(requests[1].requestedAmounts[0], 1 ether, "User 3 requested amount should be 1 ETH");
        uint256 expectedUser3WithdrawableShares = liquidTokenManager.assetUnderlyingToShares(
            IERC20(address(token3)),
            nodeBalanceToken3AfterRebase
        );
        assertEq(
            requests[1].elWithdrawableShares[0],
            expectedUser3WithdrawableShares,
            "User 3 withdrawable shares should reflect 85% slashing + rebase"
        );

        // User 4 (token4) - requested 1 ETH, should get 90% slashed amount
        assertEq(requests[2].requestedAmounts[0], 1 ether, "User 4 requested amount should be 1 ETH");
        uint256 expectedUser4WithdrawableAmount = token4Remaining;
        uint256 expectedUser4WithdrawableShares = liquidTokenManager.assetUnderlyingToShares(
            IERC20(address(token4)),
            expectedUser4WithdrawableAmount
        );
        assertEq(
            requests[2].elWithdrawableShares[0],
            expectedUser4WithdrawableShares,
            "User 4 withdrawable shares should reflect 90% slashing"
        );

        // Verify that users were charged the same amount as recorded in sharesDeposited
        assertEq(
            requests[0].sharesDeposited,
            user2SharesCharged,
            "User 2 shares deposited should match shares charged"
        );
        assertEq(
            requests[1].sharesDeposited,
            user3SharesCharged,
            "User 3 shares deposited should match shares charged"
        );
        assertEq(
            requests[2].sharesDeposited,
            user4SharesCharged,
            "User 4 shares deposited should match shares charged"
        );

        // --- Execute settleUserWithdrawals operation ---
        // Admin settles withdrawal requests by moving staked funds to queued EigenLayer withdrawals
        // Tests the core withdrawal settlement mechanism that bridges user requests to EigenLayer
        // Validates that settlement data correctly maps requested amounts to EigenLayer shares
        // Verifies that settlement moves funds from staked to queued state without changing total assets
        ILiquidTokenManager.UserWithdrawalsSettlement memory settlement;
        settlement.requestIds = withdrawalRequestIds;

        settlement.nodeIds = new uint256[](3);
        settlement.nodeIds[0] = stakerNode.getId();
        settlement.nodeIds[1] = stakerNode.getId();
        settlement.nodeIds[2] = stakerNode.getId();

        settlement.elAssets = new IERC20[][](3);
        settlement.elDepositShares = new uint256[][](3);

        // Get withdrawal requests to determine what to withdraw from staked funds
        IWithdrawalManager.WithdrawalRequest[] memory requestsForSettlement = withdrawalManager.getWithdrawalRequests(
            withdrawalRequestIds
        );

        for (uint256 i = 0; i < 3; i++) {
            settlement.elAssets[i] = new IERC20[](1);
            settlement.elDepositShares[i] = new uint256[](1);

            settlement.elAssets[i][0] = requestsForSettlement[i].assets[0];

            // `elDepositShares` should be the `underlyingToShares` of the FULL requested amount (pre-slashing)
            uint256 requestedAmount = requestsForSettlement[i].requestedAmounts[0];
            settlement.elDepositShares[i][0] = liquidTokenManager.assetUnderlyingToShares(
                settlement.elAssets[i][0],
                requestedAmount
            );
        }

        for (uint256 i = 0; i < 3; i++) {
            // Verify that elDepositShares is based on full requested amount (pre-slashing)
            uint256 expectedDepositShares = liquidTokenManager.assetUnderlyingToShares(
                settlement.elAssets[i][0],
                requestsForSettlement[i].requestedAmounts[0]
            );
            assertEq(
                settlement.elDepositShares[i][0],
                expectedDepositShares,
                "Settlement deposit shares should be based on full requested amount"
            );

            // Verify node has enough funds to cover the request
            uint256 nodeBalance = liquidTokenManager.getDepositAssetBalanceNode(
                settlement.elAssets[i][0],
                settlement.nodeIds[i],
                false
            );
            assertTrue(
                nodeBalance >= requestsForSettlement[i].requestedAmounts[0],
                "Node should have enough balance to cover request (pre-slashing check)"
            );
        }

        vm.recordLogs();
        vm.startPrank(admin);
        liquidTokenManager.settleUserWithdrawals(settlement);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 redemptionId;
        bool redemptionEventFound = false;

        for (uint256 i = 0; i < logs.length; i++) {
            bytes32 eventSig = keccak256(
                "RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],(address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[])"
            );
            if (logs[i].topics[0] == eventSig) {
                redemptionId = abi.decode(logs[i].data, (bytes32));
                redemptionEventFound = true;
                break;
            }
        }

        assertTrue(redemptionEventFound, "RedemptionCreatedForUserWithdrawals event should have been emitted");

        _updateToken3OraclePrice();

        // --- Verify final state after settlement operation ---
        // Validates that settlement correctly moved funds from staked to queued state
        // Total assets should remain unchanged as settlement is just an internal state transition
        // Staked node balances should decrease by amounts moved to queued EigenLayer withdrawals
        // Queued asset balances should reflect the withdrawable (post-slashing) amounts for each user
        // Confirms that the withdrawal settlement created proper EigenLayer redemption with correct parameters
        uint256 totalAssetsAfterSecondStaking = liquidToken.totalAssets();

        uint256 currentNodeBalanceToken3 = liquidTokenManager.getDepositAssetBalanceNode(
            IERC20(address(token3)),
            stakerNode.getId(),
            false
        );

        uint256 expectedNodeBalance1AfterSettlement = expectedToken1AfterSecondStaking; // unchanged (was 0)
        uint256 expectedNodeBalance2AfterSettlement = expectedToken2AfterSecondStaking - 0.5 ether;
        uint256 expectedNodeBalance3AfterSettlement = currentToken3Balance - currentNodeBalanceToken3;
        uint256 expectedNodeBalance4AfterSettlement = currentToken4Balance - token4Remaining;

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: totalAssetsAfterSecondStaking, // Should remain same after settlement
                assetBalances: [uint256(0), 0, 0, 0], // Nothing unstaked
                queuedAssetBalances: [uint256(0), 0.5 ether, currentNodeBalanceToken3, token4Remaining], // Post-slashing withdrawable amounts
                nodeBalances: [
                    expectedNodeBalance1AfterSettlement,
                    expectedNodeBalance2AfterSettlement,
                    expectedNodeBalance3AfterSettlement,
                    expectedNodeBalance4AfterSettlement
                ], // Reduced by queued amounts
                description: "after settlement"
            })
        );

        // Check that each user's redemption elWithdrawableShares is exactly as expected (post-slashing)
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);

        // Verify redemption has the right number of assets and shares
        assertEq(redemption.assets.length, 3, "Redemption should have 3 assets");
        assertEq(redemption.elWithdrawableShares.length, 3, "Redemption should have 3 withdrawable share amounts");

        // Check each asset's withdrawable shares in redemption matches expected post-slashing amounts
        for (uint256 i = 0; i < 3; i++) {
            uint256 redemptionWithdrawableShares = redemption.elWithdrawableShares[i];
            uint256 expectedWithdrawableShares = requestsForSettlement[i].elWithdrawableShares[0];

            assertEq(
                redemptionWithdrawableShares,
                expectedWithdrawableShares,
                "Redemption withdrawable shares should match request withdrawable shares"
            );
        }
    }

    // ------------------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------------------

    struct ExpectedBalances {
        uint256 totalAssets;
        uint256[4] assetBalances; // [testToken, testToken2, token3, token4]
        uint256[4] queuedAssetBalances;
        uint256[4] nodeBalances;
        string description;
    }

    function _assertExpectedBalances(ExpectedBalances memory expected) internal {
        IERC20[] memory allAssets = new IERC20[](4);
        allAssets[0] = IERC20(address(testToken));
        allAssets[1] = IERC20(address(testToken2));
        allAssets[2] = IERC20(address(token3));
        allAssets[3] = IERC20(address(token4));

        // Check total assets
        uint256 actualTotalAssets = liquidToken.totalAssets();
        assertEq(
            actualTotalAssets,
            expected.totalAssets,
            string.concat("Total assets mismatch - ", expected.description)
        );

        // Check asset balances
        uint256[] memory actualAssetBalances = liquidToken.balanceAssets(allAssets);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(
                actualAssetBalances[i],
                expected.assetBalances[i],
                string.concat("Asset balance mismatch for token ", Strings.toString(i), " - ", expected.description)
            );
        }

        // Check queued asset balances
        uint256[] memory actualQueuedBalances = liquidToken.balanceQueuedAssets(allAssets);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(
                actualQueuedBalances[i],
                expected.queuedAssetBalances[i],
                string.concat("Queued balance mismatch for token ", Strings.toString(i), " - ", expected.description)
            );
        }

        // Check node balances
        for (uint256 i = 0; i < 4; i++) {
            uint256 actualNodeBalance = liquidTokenManager.getDepositAssetBalanceNode(
                allAssets[i],
                stakerNode.getId(),
                false
            );
            assertEq(
                actualNodeBalance,
                expected.nodeBalances[i],
                string.concat("Node balance mismatch for token ", Strings.toString(i), " - ", expected.description)
            );
        }
    }

    /// @notice Helper function that warps time and updates token3 oracle price
    /// @dev Use this instead of vm.warp() when you need token3's oracle to reflect rebased value
    /// @param timeToAdd Number of seconds to add to current timestamp
    function _warpAndUpdateToken3Oracle(uint256 timeToAdd) internal {
        vm.warp(block.timestamp + timeToAdd);
        _updateToken3OraclePrice();
    }

    function _updateToken3OraclePrice() internal {
        // Update oracle mock to reflect current rebased price
        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(token3)),
            abi.encode(token3.getCurrentPrice())
        );
    }
}
