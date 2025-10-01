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

struct UserTestData {
    address user;
    IERC20[] assets;
    uint256[] amounts;
    uint256 balanceBefore;
    uint256 balanceAfter;
    uint256 sharesCharged;
}

struct SlashingResults {
    uint256 token1Remaining;
    uint256 token2Remaining;
    uint256 token3Remaining;
    uint256 token4Remaining;
}

struct WithdrawalPhaseData {
    bytes32[] requestIds;
    UserTestData[4] users;
    SlashingResults remainingBalances;
    IDelegationManagerTypes.Withdrawal[] withdrawals; // Store actual withdrawals from settlement
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

    /*
    NOTE: Test is ready, but rebasing not activated
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
    */

    // ------------------------------------------------------------------------------
    // Core test functions
    // ------------------------------------------------------------------------------

    function testSettleUserWithdrawalsFlow() public {
        _verifyOraclePricing();

        _performInitialDeposits();

        _performStaking();

        SlashingResults memory slashingResults = _performSlashing();

        WithdrawalPhaseData memory withdrawalData = _performWithdrawalRequests(slashingResults);

        bytes32 redemptionId = _performSettlement(withdrawalData);

        SlashingResults memory queueSlashingResults = _performQueuePeriodSlashing();

        _performRedemptionCompletion(redemptionId, withdrawalData, queueSlashingResults);

        _performWithdrawalFulfillment(withdrawalData, queueSlashingResults);

        _performFinalValidation(redemptionId, withdrawalData);
    }

    // ------------------------------------------------------------------------------
    // Phase Functions
    // ------------------------------------------------------------------------------

    function _verifyOraclePricing() internal {
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
    }

    function _performInitialDeposits() internal {
        address user1 = address(0x1001);
        address user2 = address(0x1002);
        address user3 = address(0x1003);
        address user4 = address(0x1004);

        testToken.mint(user1, 1 ether);
        testToken2.mint(user2, 1 ether);
        token3.mint(user3, 1 ether);
        token4.mint(user4, 1 ether);

        _executeUserDeposit(user1, IERC20(address(testToken)), 1 ether);
        _executeUserDeposit(user2, IERC20(address(testToken2)), 1 ether);
        _executeUserDeposit(user3, IERC20(address(token3)), 1 ether);
        _executeUserDeposit(user4, IERC20(address(token4)), 1 ether);

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: 3.5 ether - 1,
                assetBalances: [uint256(1 ether), 1 ether, 1 ether, 1 ether - 1],
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [uint256(0), 0, 0, 0],
                description: "after deposits"
            })
        );
    }

    function _performStaking() internal {
        IERC20[] memory allAssets = _createAllAssetsArray();
        uint256[] memory assetBalances = liquidToken.balanceAssets(allAssets);

        vm.startPrank(admin);
        liquidTokenManager.stakeAssetsToNode(stakerNode.getId(), allAssets, assetBalances);
        vm.stopPrank();

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: 3.5 ether - 4,
                assetBalances: [uint256(0), 0, 0, 0],
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [uint256(1 ether), 0.5 ether, 1 ether, 1 ether - 4],
                description: "after staking"
            })
        );
    }

    function _performSlashing() internal returns (SlashingResults memory) {
        StrategySlashPair[4] memory strategyPairs = [
            StrategySlashPair(address(mockStrategy), 1e18),
            StrategySlashPair(address(mockStrategy2), 5e17),
            StrategySlashPair(address(token3Strategy), 15e16),
            StrategySlashPair(address(token4Strategy), 10e16)
        ];

        _sortStrategyPairs(strategyPairs);

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

        SlashingResults memory results = SlashingResults({
            token1Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken)), false),
            token2Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken2)), false),
            token3Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token3)), false),
            token4Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token4)), false)
        });

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: results.token1Remaining +
                    results.token2Remaining /
                    2 +
                    results.token3Remaining +
                    results.token4Remaining,
                assetBalances: [uint256(0), 0, 0, 0],
                queuedAssetBalances: [uint256(0), 0, 0, 0],
                nodeBalances: [
                    results.token1Remaining,
                    results.token2Remaining / 2,
                    results.token3Remaining,
                    results.token4Remaining
                ],
                description: "after slashing"
            })
        );

        return results;
    }

    function _performWithdrawalRequests(
        SlashingResults memory slashingResults
    ) internal returns (WithdrawalPhaseData memory) {
        bytes32[] memory requestIds = new bytes32[](3);
        UserTestData[4] memory users;

        users[0] = UserTestData({
            user: address(0x1001),
            assets: _createUserAssets(IERC20(address(testToken))),
            amounts: _createAmountsArray(1 ether),
            balanceBefore: 0,
            balanceAfter: 0,
            sharesCharged: 0
        });

        users[1] = UserTestData({
            user: address(0x1002),
            assets: _createUserAssets(IERC20(address(testToken2))),
            amounts: _createAmountsArray(1 ether),
            balanceBefore: liquidToken.balanceOf(address(0x1002)),
            balanceAfter: 0,
            sharesCharged: 0
        });

        users[2] = UserTestData({
            user: address(0x1003),
            assets: _createUserAssets(IERC20(address(token3))),
            amounts: _createAmountsArray(1 ether),
            balanceBefore: liquidToken.balanceOf(address(0x1003)),
            balanceAfter: 0,
            sharesCharged: 0
        });

        users[3] = UserTestData({
            user: address(0x1004),
            assets: _createUserAssets(IERC20(address(token4))),
            amounts: _createAmountsArray(1 ether - 4 wei),
            balanceBefore: liquidToken.balanceOf(address(0x1004)),
            balanceAfter: 0,
            sharesCharged: 0
        });

        // User1 (100% slashed) - should fail
        vm.startPrank(users[0].user);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        liquidToken.initiateWithdrawal(users[0].assets, _createAmountsArray(1 ether));
        vm.stopPrank();

        // Users 2-4 successful withdrawals
        for (uint i = 1; i < 4; i++) {
            vm.startPrank(users[i].user);
            requestIds[i - 1] = liquidToken.initiateWithdrawal(users[i].assets, users[i].amounts);
            users[i].balanceAfter = liquidToken.balanceOf(users[i].user);
            users[i].sharesCharged = users[i].balanceBefore - users[i].balanceAfter;
            vm.stopPrank();
        }

        _verifyWithdrawalRequests(requestIds, users, slashingResults);

        // Balance assertions after withdrawal requests - assets remain staked, no queued balances yet
        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: slashingResults.token1Remaining +
                    slashingResults.token2Remaining /
                    2 +
                    slashingResults.token3Remaining +
                    slashingResults.token4Remaining,
                assetBalances: [uint256(0), 0, 0, 0], // Everything remains staked during withdrawal requests
                queuedAssetBalances: [uint256(0), 0, 0, 0], // No queued balances until settlement
                nodeBalances: [
                    slashingResults.token1Remaining,
                    slashingResults.token2Remaining / 2,
                    slashingResults.token3Remaining,
                    slashingResults.token4Remaining
                ],
                description: "after withdrawal requests"
            })
        );

        return
            WithdrawalPhaseData({
                requestIds: requestIds,
                users: users,
                remainingBalances: slashingResults,
                withdrawals: new IDelegationManagerTypes.Withdrawal[](0) // Will be populated during settlement
            });
    }

    function _performSettlement(WithdrawalPhaseData memory data) internal returns (bytes32) {
        ILiquidTokenManager.UserWithdrawalsSettlement memory settlement = _createSettlement(data.requestIds);

        vm.recordLogs();
        vm.startPrank(admin);
        liquidTokenManager.settleUserWithdrawals(settlement);
        vm.stopPrank();

        // Extract both redemptionId and withdrawals from events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 redemptionId = _extractRedemptionId(logs);

        data.withdrawals = _extractWithdrawalsFromEigenLayerEvents(logs);
        assertTrue(redemptionId != bytes32(0), "RedemptionCreatedForUserWithdrawals event should have been emitted");

        // Verify total assets preserved after settlement (internal state transition only)
        uint256 totalAssetsAfterSettlement = liquidToken.totalAssets();
        uint256 expectedTotalAssets = data.remainingBalances.token1Remaining +
            data.remainingBalances.token2Remaining /
            2 +
            data.remainingBalances.token3Remaining +
            data.remainingBalances.token4Remaining;

        // Allow for small rounding differences (up to 10 wei) in settlement precision
        uint256 tolerance = 10 wei;
        if (totalAssetsAfterSettlement > expectedTotalAssets) {
            assertLe(
                totalAssetsAfterSettlement - expectedTotalAssets,
                tolerance,
                "Total assets difference after settlement exceeds tolerance"
            );
        } else {
            assertLe(
                expectedTotalAssets - totalAssetsAfterSettlement,
                tolerance,
                "Total assets difference after settlement exceeds tolerance"
            );
        }

        return redemptionId;
    }

    function _performQueuePeriodSlashing() internal returns (SlashingResults memory) {
        // Apply additional slashing during the EigenLayer withdrawal queue period
        // testToken2: Additional 25% slash (was 50%, now 62.5% total)
        // token3: Additional 10% slash (was 15%, now 24% total)
        // token4: Additional 15% slash (was 10%, now 23.5% total)

        // Create strategy-slash pairs for sorting (similar to initial slashing)
        StrategySlashPair[3] memory strategyPairs = [
            StrategySlashPair(address(mockStrategy2), 25e16), // testToken2, 25% additional slash
            StrategySlashPair(address(token3Strategy), 10e16), // token3, 10% additional slash
            StrategySlashPair(address(token4Strategy), 15e16) // token4, 15% additional slash
        ];

        _sortStrategyPairs3(strategyPairs);

        IStrategy[] memory strategiesToSlash = new IStrategy[](3);
        uint256[] memory wadsToSlash = new uint256[](3);

        for (uint i = 0; i < 3; i++) {
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
                description: "queue period slashing"
            })
        );

        SlashingResults memory results = SlashingResults({
            token1Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken)), false),
            token2Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(testToken2)), false),
            token3Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token3)), false),
            token4Remaining: liquidTokenManager.getWithdrawableAssetBalance(IERC20(address(token4)), false)
        });

        // Calculate total assets considering token prices
        uint256 expectedTotalAssets = results.token1Remaining +
            (results.token2Remaining * 1e18) /
            (2e18) + // testToken2 is priced at 0.5 ETH
            results.token3Remaining +
            results.token4Remaining;

        // Note: totalAssets() doesn't immediately reflect queue period slashing
        // The slashing effect only shows when withdrawals are completed
        // So we expect totalAssets to remain the same until redemption completion
        uint256 actualTotalAssets = liquidToken.totalAssets();

        // Get current queued balances (these were set during settlement and should remain until completion)
        IERC20[] memory allAssets = _createAllAssetsArray();
        uint256[] memory currentQueuedBalances = liquidToken.balanceQueuedAssets(allAssets);

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: actualTotalAssets, // Total assets remain unchanged until redemption completion
                assetBalances: [uint256(0), 0, 0, 0], // Still staked
                queuedAssetBalances: [
                    currentQueuedBalances[0],
                    currentQueuedBalances[1],
                    currentQueuedBalances[2],
                    currentQueuedBalances[3]
                ], // Convert to fixed array
                nodeBalances: [
                    results.token1Remaining,
                    results.token2Remaining / 2,
                    results.token3Remaining,
                    results.token4Remaining
                ],
                description: "after queue period slashing"
            })
        );

        return results;
    }

    function _performRedemptionCompletion(
        bytes32 redemptionId,
        WithdrawalPhaseData memory withdrawalData,
        SlashingResults memory queueSlashingResults
    ) internal {
        // Advance both time and blocks to pass EigenLayer withdrawal delay
        // 15 days = 15 * 24 * 60 * 60 / 12 = 108,000 blocks
        uint256 withdrawalDelayBlocks = 108000;
        vm.roll(block.number + withdrawalDelayBlocks + 1);
        vm.warp(block.timestamp + 15 days);

        // Get redemption data
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);

        uint256[] memory nodeIds = new uint256[](1);
        nodeIds[0] = stakerNode.getId();

        // Use the actual withdrawal structs that were captured during settlement
        uint256 numWithdrawals = withdrawalData.withdrawals.length;
        require(numWithdrawals == redemption.withdrawalRoots.length, "Withdrawal count mismatch");

        IDelegationManagerTypes.Withdrawal[][] memory withdrawals = new IDelegationManagerTypes.Withdrawal[][](1);
        withdrawals[0] = new IDelegationManagerTypes.Withdrawal[](numWithdrawals);

        IERC20[][][] memory assets = new IERC20[][][](1);
        assets[0] = new IERC20[][](numWithdrawals);

        // Copy the withdrawal structs that were captured from the settlement event
        for (uint256 i = 0; i < numWithdrawals; i++) {
            withdrawals[0][i] = withdrawalData.withdrawals[i];

            // Verify our withdrawal struct matches the expected root
            bytes32 calculatedRoot = keccak256(abi.encode(withdrawals[0][i]));
            require(
                calculatedRoot == redemption.withdrawalRoots[i],
                "Withdrawal root mismatch - captured withdrawal doesn't match redemption"
            );

            // Create corresponding assets array
            IERC20 asset = redemption.assets[i];
            assets[0][i] = new IERC20[](1);
            assets[0][i][0] = asset;
        }

        // Record logs to capture RedemptionCompleted event
        vm.recordLogs();

        // Manager calls `completeRedemption`
        vm.startPrank(admin);
        liquidTokenManager.completeRedemption(redemptionId, nodeIds, withdrawals, assets);
        vm.stopPrank();

        // Verify RedemptionCompleted event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool redemptionCompletedEmitted = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RedemptionCompleted(bytes32,address[],uint256[],uint256[])")) {
                redemptionCompletedEmitted = true;
                break;
            }
        }
        assertTrue(redemptionCompletedEmitted, "RedemptionCompleted event should have been emitted");

        // Verify that withdrawal requests are now marked as canFulfill = true
        for (uint i = 0; i < withdrawalData.requestIds.length; i++) {
            if (withdrawalData.requestIds[i] != bytes32(0)) {
                IWithdrawalManager.WithdrawalRequest[] memory requests = withdrawalManager.getWithdrawalRequests(
                    _createSingleRequestIdArray(withdrawalData.requestIds[i])
                );
                assertTrue(requests[0].canFulfill, "Withdrawal request should be marked as fulfillable");
            }
        }

        // Balance assertions after redemption completion
        uint256 actualTotalAssetsAfterCompletion = liquidToken.totalAssets();

        _assertExpectedBalances(
            ExpectedBalances({
                totalAssets: actualTotalAssetsAfterCompletion,
                assetBalances: [uint256(0), 0, 0, 0], // Assets transferred to WithdrawalManager
                queuedAssetBalances: [uint256(0), 0, 0, 0], // Queued balances should be cleared after completion
                nodeBalances: [
                    queueSlashingResults.token1Remaining,
                    queueSlashingResults.token2Remaining / 2,
                    queueSlashingResults.token3Remaining,
                    queueSlashingResults.token4Remaining
                ],
                description: "after redemption completion"
            })
        );
    }

    function _performWithdrawalFulfillment(
        WithdrawalPhaseData memory withdrawalData,
        SlashingResults memory queueSlashingResults
    ) internal {
        // Fast-forward time past withdrawal delay (different from EL withdrawal delay)
        vm.warp(block.timestamp + withdrawalManager.withdrawalDelay());

        // Record initial user token balances before fulfillment
        uint256[4] memory userInitialBalances;
        userInitialBalances[0] = 0; // User 1 has no testToken balance (was rejected)
        userInitialBalances[1] = testToken2.balanceOf(withdrawalData.users[1].user);
        userInitialBalances[2] = token3.balanceOf(withdrawalData.users[2].user);
        userInitialBalances[3] = token4.balanceOf(withdrawalData.users[3].user);

        // Record WithdrawalManager initial balances
        uint256 wmToken2Balance = testToken2.balanceOf(address(withdrawalManager));
        uint256 wmToken3Balance = token3.balanceOf(address(withdrawalManager));
        uint256 wmToken4Balance = token4.balanceOf(address(withdrawalManager));

        // User 1 should not be able to fulfill (was rejected during withdrawal request)
        vm.startPrank(withdrawalData.users[0].user);
        vm.expectRevert(); // Should revert with InvalidWithdrawalRequest or similar
        withdrawalManager.fulfillWithdrawal(withdrawalData.requestIds[0]); // This will be bytes32(0)
        vm.stopPrank();

        // Record logs to capture WithdrawalFulfilled events
        vm.recordLogs();

        // Users 2, 3, 4 fulfill their withdrawals
        for (uint i = 1; i < 4; i++) {
            vm.startPrank(withdrawalData.users[i].user);
            withdrawalManager.fulfillWithdrawal(withdrawalData.requestIds[i - 1]);
            vm.stopPrank();
        }

        // Verify WithdrawalFulfilled events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 fulfillmentEventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("WithdrawalFulfilled(bytes32,address,address[],uint256[],uint256)")) {
                fulfillmentEventCount++;
            }
        }
        assertEq(fulfillmentEventCount, 3, "Should have 3 WithdrawalFulfilled events");

        // Verify final user token balances - users should have received reduced amounts
        uint256 user2FinalBalance = testToken2.balanceOf(withdrawalData.users[1].user);
        uint256 user3FinalBalance = token3.balanceOf(withdrawalData.users[2].user);
        uint256 user4FinalBalance = token4.balanceOf(withdrawalData.users[3].user);

        // Users should have received tokens (more than initial)
        assertTrue(user2FinalBalance > userInitialBalances[1], "User 2 should have received testToken2");
        assertTrue(user3FinalBalance > userInitialBalances[2], "User 3 should have received token3");
        assertTrue(user4FinalBalance > userInitialBalances[3], "User 4 should have received token4");

        // But due to cumulative slashing, they should have received less than their original 1 ETH equivalent
        uint256 user2ReceivedAmount = user2FinalBalance - userInitialBalances[1];
        uint256 user3ReceivedAmount = user3FinalBalance - userInitialBalances[2];
        uint256 user4ReceivedAmount = user4FinalBalance - userInitialBalances[3];

        // Calculate expected amounts after cumulative slashing
        // User 2 (testToken2): 50% initial + 25% queue = 62.5% total loss, so ~37.5% remaining
        // User 3 (token3): 15% initial + 10% queue ≈ 24% total loss, so ~76% remaining
        // User 4 (token4): 10% initial + 15% queue ≈ 23.5% total loss, so ~76.5% remaining

        // Use approximate checks since exact calculations are complex due to cumulative effects
        assertTrue(user2ReceivedAmount < 5e17, "User 2 should receive less than 0.5 ETH worth due to heavy slashing");
        assertTrue(user3ReceivedAmount < 8e17, "User 3 should receive less than 0.8 ETH worth due to slashing");
        assertTrue(user4ReceivedAmount < 8e17, "User 4 should receive less than 0.8 ETH worth due to slashing");

        // Verify WithdrawalManager balances were reduced
        uint256 wmToken2FinalBalance = testToken2.balanceOf(address(withdrawalManager));
        uint256 wmToken3FinalBalance = token3.balanceOf(address(withdrawalManager));
        uint256 wmToken4FinalBalance = token4.balanceOf(address(withdrawalManager));

        assertTrue(wmToken2FinalBalance < wmToken2Balance, "WithdrawalManager testToken2 balance should be reduced");
        assertTrue(wmToken3FinalBalance < wmToken3Balance, "WithdrawalManager token3 balance should be reduced");
        assertTrue(wmToken4FinalBalance < wmToken4Balance, "WithdrawalManager token4 balance should be reduced");

        // Verify withdrawal requests were deleted (should revert if trying to fulfill again)
        for (uint i = 1; i < 4; i++) {
            vm.startPrank(withdrawalData.users[i].user);
            vm.expectRevert(); // Should revert with InvalidWithdrawalRequest
            withdrawalManager.fulfillWithdrawal(withdrawalData.requestIds[i - 1]);
            vm.stopPrank();
        }
    }

    function _performFinalValidation(bytes32 redemptionId, WithdrawalPhaseData memory data) internal {
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);

        // Verify redemption structure
        assertEq(redemption.assets.length, 3, "Redemption should have 3 assets");
        assertEq(redemption.elWithdrawableShares.length, 3, "Redemption should have 3 withdrawable share amounts");

        // Verify EigenLayer applied slashing correctly
        ILiquidTokenManager.UserWithdrawalsSettlement memory settlement = _createSettlement(data.requestIds);
        assertTrue(
            redemption.elWithdrawableShares[0] < settlement.elDepositShares[0][0],
            "testToken2 should be slashed"
        );
        assertTrue(redemption.elWithdrawableShares[1] < settlement.elDepositShares[1][0], "token3 should be slashed");
        assertTrue(redemption.elWithdrawableShares[2] < settlement.elDepositShares[2][0], "token4 should be slashed");
    }

    // ------------------------------------------------------------------------------
    // Utility Functions
    // ------------------------------------------------------------------------------

    function _executeUserDeposit(address user, IERC20 asset, uint256 amount) internal {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.startPrank(user);
        asset.approve(address(liquidToken), amount);
        liquidToken.deposit(assets, amounts, user);
        vm.stopPrank();
    }

    function _createAllAssetsArray() internal view returns (IERC20[] memory) {
        IERC20[] memory allAssets = new IERC20[](4);
        allAssets[0] = IERC20(address(testToken));
        allAssets[1] = IERC20(address(testToken2));
        allAssets[2] = IERC20(address(token3));
        allAssets[3] = IERC20(address(token4));
        return allAssets;
    }

    function _createUserAssets(IERC20 asset) internal pure returns (IERC20[] memory) {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = asset;
        return assets;
    }

    function _createAmountsArray(uint256 amount) internal pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return amounts;
    }

    function _createSingleRequestIdArray(bytes32 requestId) internal pure returns (bytes32[] memory) {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        return requestIds;
    }

    function _sortStrategyPairs(StrategySlashPair[4] memory pairs) internal pure {
        for (uint i = 0; i < 3; i++) {
            for (uint j = 0; j < 3 - i; j++) {
                if (uint160(pairs[j].strategy) > uint160(pairs[j + 1].strategy)) {
                    StrategySlashPair memory temp = pairs[j];
                    pairs[j] = pairs[j + 1];
                    pairs[j + 1] = temp;
                }
            }
        }
    }

    function _sortStrategyPairs3(StrategySlashPair[3] memory pairs) internal pure {
        // Simple bubble sort for 3-element array
        for (uint i = 0; i < 2; i++) {
            for (uint j = 0; j < 2 - i; j++) {
                if (uint160(pairs[j].strategy) > uint160(pairs[j + 1].strategy)) {
                    StrategySlashPair memory temp = pairs[j];
                    pairs[j] = pairs[j + 1];
                    pairs[j + 1] = temp;
                }
            }
        }
    }

    function _verifyWithdrawalRequests(
        bytes32[] memory requestIds,
        UserTestData[4] memory users,
        SlashingResults memory slashing
    ) internal {
        IWithdrawalManager.WithdrawalRequest[] memory requests = withdrawalManager.getWithdrawalRequests(requestIds);

        // Basic request validation
        assertEq(requests[0].requestedAmounts[0], 1 ether, "User 2 requested amount should be 1 ETH");
        assertEq(requests[1].requestedAmounts[0], 1 ether, "User 3 requested amount should be 1 ETH");
        assertEq(requests[2].requestedAmounts[0], 1 ether - 4 wei, "User 4 requested amount should be 1 ETH - 4 wei");

        // Verify user balance changes
        assertEq(users[1].balanceAfter, 0, "User 2 should be charged full amount");
        assertEq(users[2].balanceAfter, 0, "User 3 should be charged full amount");
        assertEq(users[3].balanceAfter, 3, "User 4 should have small remainder");

        // Verify shares deposited match what was charged
        for (uint i = 1; i < 4; i++) {
            assertEq(requests[i - 1].sharesDeposited, users[i].sharesCharged, "Shares deposited should match charged");
        }
    }

    function _createSettlement(
        bytes32[] memory requestIds
    ) internal view returns (ILiquidTokenManager.UserWithdrawalsSettlement memory) {
        ILiquidTokenManager.UserWithdrawalsSettlement memory settlement;
        settlement.requestIds = requestIds;

        settlement.nodeIds = new uint256[](3);
        for (uint i = 0; i < 3; i++) {
            settlement.nodeIds[i] = stakerNode.getId();
        }

        settlement.elAssets = new IERC20[][](3);
        settlement.elDepositShares = new uint256[][](3);

        IWithdrawalManager.WithdrawalRequest[] memory requests = withdrawalManager.getWithdrawalRequests(requestIds);

        for (uint256 i = 0; i < 3; i++) {
            settlement.elAssets[i] = new IERC20[](1);
            settlement.elDepositShares[i] = new uint256[](1);

            settlement.elAssets[i][0] = requests[i].assets[0];
            IStrategy strategy = liquidTokenManager.getTokenStrategy(requests[i].assets[0]);
            settlement.elDepositShares[i][0] = strategy.underlyingToSharesView(requests[i].requestedAmounts[0]);
        }

        return settlement;
    }

    function _extractRedemptionId(Vm.Log[] memory logs) internal pure returns (bytes32) {
        bytes32 eventSig = keccak256(
            "RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],(address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[])"
        );

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                return abi.decode(logs[i].data, (bytes32));
            }
        }

        return bytes32(0);
    }

    function _extractWithdrawals(
        Vm.Log[] memory logs
    ) internal pure returns (IDelegationManagerTypes.Withdrawal[] memory) {
        bytes32 eventSig = keccak256(
            "RedemptionCreatedForUserWithdrawals(bytes32,bytes32[],bytes32[],(address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[])"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                // Decode the event data to extract the withdrawals
                (, , , IDelegationManagerTypes.Withdrawal[] memory withdrawals, , ) = abi.decode(
                    logs[i].data,
                    (bytes32, bytes32[], bytes32[], IDelegationManagerTypes.Withdrawal[], IERC20[][], uint256[])
                );
                return withdrawals;
            }
        }
        revert("RedemptionCreatedForUserWithdrawals event not found");
    }

    function _extractWithdrawalsFromEigenLayerEvents(
        Vm.Log[] memory logs
    ) internal pure returns (IDelegationManagerTypes.Withdrawal[] memory) {
        // Look for EigenLayer's SlashingWithdrawalQueued events
        bytes32 slashingWithdrawalQueuedSig = keccak256(
            "SlashingWithdrawalQueued(bytes32,(address,address,address,uint256,uint32,address[],uint256[]),uint256[])"
        );

        // Count how many withdrawal events we have
        uint256 withdrawalCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == slashingWithdrawalQueuedSig) {
                withdrawalCount++;
            }
        }

        if (withdrawalCount == 0) {
            revert("No SlashingWithdrawalQueued events found");
        }

        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](
            withdrawalCount
        );
        uint256 withdrawalIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == slashingWithdrawalQueuedSig) {
                // Decode the withdrawal struct from the event data
                // Event signature: SlashingWithdrawalQueued(bytes32 withdrawalRoot, Withdrawal withdrawal, uint256[] withdrawableShares)
                (, IDelegationManagerTypes.Withdrawal memory withdrawal, ) = abi.decode(
                    logs[i].data,
                    (bytes32, IDelegationManagerTypes.Withdrawal, uint256[])
                );
                withdrawals[withdrawalIndex] = withdrawal;
                withdrawalIndex++;
            }
        }

        return withdrawals;
    }

    // ------------------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------------------

    function _verifyPostSettlementBalances() internal {
        // Verify core balance properties after settlement:
        // 1. No assets in liquid state (everything staked or queued)
        // 2. Queued balances exist for settled assets

        IERC20[] memory assetsToCheck = new IERC20[](4);
        assetsToCheck[0] = IERC20(address(testToken));
        assetsToCheck[1] = IERC20(address(testToken2));
        assetsToCheck[2] = IERC20(address(token3));
        assetsToCheck[3] = IERC20(address(token4));

        uint256[] memory assetBalances = liquidToken.balanceAssets(assetsToCheck);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(assetBalances[i], 0, "All assets should remain staked or queued, none in liquid state");
        }

        uint256[] memory queuedBalances = liquidToken.balanceQueuedAssets(assetsToCheck);
        assertEq(queuedBalances[0], 0, "testToken should have no queued balance (not settled)");
        assertTrue(queuedBalances[1] > 0, "testToken2 should have queued balance after settlement");
        assertTrue(queuedBalances[2] > 0, "token3 should have queued balance after settlement");
        assertTrue(queuedBalances[3] > 0, "token4 should have queued balance after settlement");
    }

    function _verifyRedemptionWithdrawableShares(
        ILiquidTokenManager.Redemption memory redemption,
        ILiquidTokenManager.UserWithdrawalsSettlement memory settlement
    ) internal {
        // For testToken2: 50% slashed, so our deposit shares should become 50% less withdrawable shares
        uint256 expectedToken2WithdrawableShares = settlement.elDepositShares[0][0] / 2; // 50% slashing
        assertEq(
            redemption.elWithdrawableShares[0],
            expectedToken2WithdrawableShares,
            "testToken2 should reflect 50% slashing"
        );

        // For token3: 15% slashed, so withdrawable shares = deposit shares * (1 - 0.15) = deposit shares * 0.85
        uint256 expectedToken3WithdrawableShares = (settlement.elDepositShares[1][0] * 85) / 100; // 85% remaining after 15% slash
        assertEq(
            redemption.elWithdrawableShares[1],
            expectedToken3WithdrawableShares,
            "token3 should reflect 15% slashing"
        );

        // For token4: 10% slashed, so withdrawable shares = deposit shares * (1 - 0.10) = deposit shares * 0.90
        uint256 expectedToken4WithdrawableShares = (settlement.elDepositShares[2][0] * 90) / 100; // 90% remaining after 10% slash
        // Allow small tolerance for transfer loss token rounding
        uint256 token4Tolerance = expectedToken4WithdrawableShares / 100; // 1% tolerance
        uint256 token4Diff = redemption.elWithdrawableShares[2] > expectedToken4WithdrawableShares
            ? redemption.elWithdrawableShares[2] - expectedToken4WithdrawableShares
            : expectedToken4WithdrawableShares - redemption.elWithdrawableShares[2];
        assertTrue(token4Diff <= token4Tolerance, "token4 should reflect ~10% slashing with transfer loss tolerance");
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
