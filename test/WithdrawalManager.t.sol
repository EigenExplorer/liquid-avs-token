// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import "forge-std/console.sol";

import "forge-std/Test.sol";
import "./common/BaseTest.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
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
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {MockAVSRegistrar} from "./mocks/MockAVSRegistrar.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IAllocationManagerTypes} from "@eigenlayer/contracts/interfaces/IAllocationManager.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/interfaces/IPauserRegistry.sol";
import {OperatorSet} from "@eigenlayer/contracts/libraries/OperatorSetLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct StrategySlashPair {
    address strategy;
    uint256 wadToSlash;
}

struct ExpectedBalances {
    uint256 totalAssets;
    uint256[4] assetBalances; // [testToken, testToken2, token3, token4]
    uint256[4] queuedAssetBalances;
    uint256[4] nodeBalances;
    string description;
}

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
        _rebaseRate = 0; // 5e16; // 5% annually
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
    address public avs = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp + 1, block.prevrandao)))));
    MockAVSRegistrar public mockAVSRegistrar;

    // ------------------------------------------------------------------------------
    // Setup environment
    // ------------------------------------------------------------------------------

    function setUp() public override {
        super.setUp();
        _setupAdditionalTokens();
        _setupAvs();
        _setupStakerNodeAndOperator();
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

    function _setupAvs() internal {
        // Deploy MockAVSRegistrar and set avs address
        mockAVSRegistrar = new MockAVSRegistrar();
        avs = address(mockAVSRegistrar);

        vm.startPrank(avs);
        // Register metadata
        allocationManager.updateAVSMetadataURI(address(avs), "test");

        // Create an Operator Set
        IStrategy[] memory strategies = new IStrategy[](4);
        strategies[0] = IStrategy(address(mockStrategy));
        strategies[1] = IStrategy(address(mockStrategy2));
        strategies[2] = IStrategy(address(token3Strategy));
        strategies[3] = IStrategy(address(token4Strategy));

        IAllocationManagerTypes.CreateSetParams[]
            memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0].operatorSetId = uint32(1);
        createSetParams[0].strategies = strategies;

        allocationManager.createOperatorSets(address(avs), createSetParams);
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

        // Register a new Operator and register for Operator Set 1
        vm.startPrank(operator);
        delegationManager.registerAsOperator(address(0), uint32(0), "ipfs://");
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = uint32(1);
        allocationManager.registerForOperatorSets(
            address(operator),
            IAllocationManagerTypes.RegisterParams({avs: address(avs), operatorSetIds: operatorSetIds, data: "0x"})
        );
        vm.stopPrank();

        // Allocate equal magnitudes of full amounts for all strategies
        vm.startPrank(operator);
        allocationManager.setAllocationDelay(address(operator), uint32(0));
        vm.stopPrank();

        vm.roll(block.number + 127000); // EL accepts the allocation delay change after 126k blocks (17.5 days) on mainnet
        vm.warp(18 days);

        vm.startPrank(operator);
        uint64[] memory magnitudes = new uint64[](4);
        magnitudes[0] = 1e18;
        magnitudes[1] = 1e18;
        magnitudes[2] = 1e18;
        magnitudes[3] = 1e18;
        IAllocationManagerTypes.AllocateParams[] memory params = new IAllocationManagerTypes.AllocateParams[](1);
        params[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: OperatorSet({avs: address(avs), id: uint32(1)}),
            strategies: strategiesToWhitelist,
            newMagnitudes: magnitudes
        });
        allocationManager.modifyAllocations(address(operator), params);
        vm.stopPrank();

        // Delegate Staker Node to new Operator
        vm.startPrank(admin);
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        stakerNode = stakerNodeCoordinator.createStakerNode();
        stakerNode.delegate(operator, signature, bytes32(0));
        vm.stopPrank();

        vm.roll(block.number + 127000);
        vm.warp(18 days);
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
        assertTrue(testToken2Convert == 0.5 ether, "testToken2 convert should be 0.5e18");
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
                totalAssets: 3.5 ether - 1, // 3.5 ETH - 1 wei (1 testToken + 0.5 testToken2 + 1 token3 + 1 token4 - transfer loss)
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
                totalAssets: 3.5 ether - 4, // Same as deposits minus another 3 wei for token4 transfer during staking
                assetBalances: [uint256(0), 0, 0, 0], // Everything staked
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [uint256(1 ether), 0.5 ether, 1 ether, 1 ether - 4], // Everything now staked to node
                description: "after staking"
            })
        );

        // --- Simulate EigenLayer slashing across different tokens ---
        // Creates realistic slashing scenario with varying percentages per token type
        // TestToken1: 100% slash, TestToken2: 50% slash
        // Token3: 15% slash (rebasing ), Token4: 10% slash (transfer-loss token)
        uint256 strategy1BalanceBefore = IStrategy(address(mockStrategy)).userUnderlyingView(address(stakerNode));
        uint256 strategy2BalanceBefore = IStrategy(address(mockStrategy2)).userUnderlyingView(address(stakerNode));
        uint256 strategy3BalanceBefore = IStrategy(address(token3Strategy)).userUnderlyingView(address(stakerNode));
        uint256 strategy4BalanceBefore = IStrategy(address(token4Strategy)).userUnderlyingView(address(stakerNode));

        IStrategy[] memory allStrategies = new IStrategy[](4);
        allStrategies[0] = mockStrategy;
        allStrategies[1] = mockStrategy2;
        allStrategies[2] = token3Strategy;
        allStrategies[3] = token4Strategy;

        StrategySlashPair[4] memory strategyPairs = [
            StrategySlashPair(address(mockStrategy), 1e18),
            StrategySlashPair(address(mockStrategy2), 5e17),
            StrategySlashPair(address(token3Strategy), 15e16),
            StrategySlashPair(address(token4Strategy), 10e16)
        ];

        // EL requires strategies in ascending order
        // Create pairs of strategy addresses and their slash percentages
        for (uint i = 0; i < 3; i++) {
            for (uint j = 0; j < 3 - i; j++) {
                if (uint160(strategyPairs[j].strategy) > uint160(strategyPairs[j + 1].strategy)) {
                    StrategySlashPair memory temp = strategyPairs[j];
                    strategyPairs[j] = strategyPairs[j + 1];
                    strategyPairs[j + 1] = temp;
                }
            }
        }

        // Extract sorted arrays
        IStrategy[] memory strategiesToSlash = new IStrategy[](4);
        uint256[] memory wadsToSlash = new uint256[](4);

        for (uint i = 0; i < 4; i++) {
            strategiesToSlash[i] = IStrategy(strategyPairs[i].strategy);
            wadsToSlash[i] = strategyPairs[i].wadToSlash;
        }

        vm.prank(avs);
        allocationManager.slashOperator(
            address(avs),
            IAllocationManagerTypes.SlashingParams({
                operator: address(operator),
                operatorSetId: uint32(1),
                strategies: strategiesToSlash,
                wadsToSlash: wadsToSlash,
                description: "test"
            })
        );

        (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(
            address(stakerNode),
            allStrategies
        );
        uint256 strategy1BalanceAfter = IStrategy(address(mockStrategy)).sharesToUnderlyingView(withdrawableShares[0]);
        uint256 strategy2BalanceAfter = IStrategy(address(mockStrategy2)).sharesToUnderlyingView(withdrawableShares[1]);
        uint256 strategy3BalanceAfter = IStrategy(address(token3Strategy)).sharesToUnderlyingView(
            withdrawableShares[2]
        );
        uint256 strategy4BalanceAfter = IStrategy(address(token4Strategy)).sharesToUnderlyingView(
            withdrawableShares[3]
        );

        assertEq(strategy1BalanceAfter, uint256(0), "Strategy 1 should be slashed completely");
        assertLt(strategy2BalanceAfter, strategy2BalanceBefore, "Strategy 2 should be slashed");
        assertLt(strategy3BalanceAfter, strategy3BalanceBefore, "Strategy 3 should be slashed");
        assertLt(strategy4BalanceAfter, strategy4BalanceBefore, "Strategy 4 should be slashed");

        uint256 token1Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken)), false);
        uint256 token2Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken2)), false);
        uint256 token3Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token3)), false);
        uint256 token4Remaining = liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token4)), false);

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: token1Remaining + token2Remaining / 2 + token3Remaining + token4Remaining,
                assetBalances: [uint256(0), 0, 0, 0], // Everything remains staked
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [token1Remaining, token2Remaining / 2, token3Remaining, token4Remaining], // Slashed amounts
                description: "after slashing"
            })
        );

        /*

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
        withdrawAmounts3[0] = user3OriginalDeposit;
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

        uint256 expectedUser2Shares = liquidToken.calculateShares(IERC20(address(testToken2)), 0.25 ether);
        uint256 expectedUser3Shares = liquidToken.calculateShares(IERC20(address(token3)), token3Remaining);
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
            0.25 ether
        );
        assertEq(
            requests[0].elWithdrawableShares[0],
            expectedUser2WithdrawableShares,
            "User 2 withdrawable shares should reflect 50% slashing"
        );

        // User 3 (token3) - requested 1 ETH, should get 85% slashed + rebased amount
        assertEq(requests[1].requestedAmounts[0], 1 ether, "User 3 requested amount should be 1 ETH");
        uint256 expectedUser3WithdrawableAmount = token3Remaining;
        uint256 expectedUser3WithdrawableShares = liquidTokenManager.assetUnderlyingToShares(
            IERC20(address(token3)),
            expectedUser3WithdrawableAmount
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

        // TODO: _assertExpectedBalances

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
        */
    }

    // ------------------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------------------

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
            uint256 actualNodeBalance = liquidTokenManager.getWithdrawableAssetBalanceNode(
                allAssets[i],
                stakerNode.getId(),
                false
            );
            assertEq(
                liquidTokenManager.convertToUnitOfAccount(allAssets[i], actualNodeBalance),
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

        uint256 currentPrice = token3.getCurrentPrice();

        // Update oracle mock
        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(token3)),
            abi.encode(currentPrice)
        );

        // Update stored pricePerUnit in LiquidTokenManager for full consistency
        vm.prank(admin);
        liquidTokenManager.updatePrice(IERC20(address(token3)), currentPrice);
    }
}
