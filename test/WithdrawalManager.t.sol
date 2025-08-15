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
    /// @dev Default to 1:1 ETH for all tokens except the rebasing tokens which will be prices according to its `getCurrentPrice()`
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

        vm.mockCall(
            address(tokenRegistryOracle),
            abi.encodeWithSelector(ITokenRegistryOracle.getTokenPrice.selector, address(token3)),
            abi.encode(token3.getCurrentPrice())
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

    /// @dev LiquidToken `assetBalances` does not account for rebasing however that should not interfere in user withdrawals
    function testSettleUserWithdrawalsFlow() public {
        // Set up 4 test users
        address user1 = address(0x1001);
        address user2 = address(0x1002);
        address user3 = address(0x1003);
        address user4 = address(0x1004);

        // Mint 1 ETH worth of tokens to each user
        testToken.mint(user1, 1 ether);
        testToken2.mint(user2, 1 ether);
        token3.mint(user3, 1 ether);
        token4.mint(user4, 1 ether);

        // Set up token arrays for each user's deposit
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

        // User 1 deposits testToken
        vm.startPrank(user1);
        testToken.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets1, amounts1, user1);
        vm.stopPrank();

        // User 2 deposits testToken2
        vm.startPrank(user2);
        testToken2.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets2, amounts2, user2);
        vm.stopPrank();

        // User 3 deposits token3 (rebasing token)
        vm.startPrank(user3);
        token3.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets3, amounts3, user3);
        vm.stopPrank();

        // User 4 deposits token4 (transfer loss token)
        vm.startPrank(user4);
        token4.approve(address(liquidToken), 1 ether);
        liquidToken.deposit(assets4, amounts4, user4);
        vm.stopPrank();

        // Check totalAssets and assetBalances after deposits
        uint256 totalAssetsAfterDeposits = liquidToken.totalAssets();
        assertTrue(totalAssetsAfterDeposits > 0, "Total assets should be greater than 0 after deposits");

        IERC20[] memory allAssets = new IERC20[](4);
        allAssets[0] = IERC20(address(testToken));
        allAssets[1] = IERC20(address(testToken2));
        allAssets[2] = IERC20(address(token3));
        allAssets[3] = IERC20(address(token4));

        // Stake assets to node - prepare arrays for all assets
        IERC20[] memory allAssetsToStake = new IERC20[](4);
        allAssetsToStake[0] = IERC20(address(testToken));
        allAssetsToStake[1] = IERC20(address(testToken2));
        allAssetsToStake[2] = IERC20(address(token3));
        allAssetsToStake[3] = IERC20(address(token4));

        uint256[] memory assetBalancesAfterDeposits = liquidToken.balanceAssets(allAssets);
        uint256[] memory allAmountsToStake = new uint256[](4);
        allAmountsToStake[0] = assetBalancesAfterDeposits[0];
        allAmountsToStake[1] = assetBalancesAfterDeposits[1];
        allAmountsToStake[2] = assetBalancesAfterDeposits[2];
        allAmountsToStake[3] = assetBalancesAfterDeposits[3];

        // Stake all funds to the staker node
        vm.startPrank(admin);
        liquidTokenManager.stakeAssetsToNode(stakerNode.getId(), allAssetsToStake, allAmountsToStake);
        vm.stopPrank();

        // CHECK totalAssets and assetBalances after staking
        uint256 totalAssetsAfterStaking = liquidToken.totalAssets();
        assertTrue(totalAssetsAfterStaking > 0, "Total assets should be greater than 0 after staking");

        // Verify assets have been moved from unstaked to staked state
        uint256[] memory assetBalancesAfterStaking = liquidToken.balanceAssets(allAssets);
        assertLt(assetBalancesAfterStaking[0], 1 ether, "testToken should be staked");
        assertLt(assetBalancesAfterStaking[1], 1 ether, "testToken2 should be staked");
        assertLt(assetBalancesAfterStaking[2], 1 ether, "token3 should be staked");
        assertLt(assetBalancesAfterStaking[3], 1 ether, "token4 should be staked");

        // SIMULATE EIGENLAYER SLASHING
        uint256 strategy1BalanceBefore = testToken.balanceOf(address(mockStrategy));
        uint256 strategy2BalanceBefore = testToken2.balanceOf(address(mockStrategy2));
        uint256 strategy3BalanceBefore = token3.balanceOf(address(token3Strategy));
        uint256 strategy4BalanceBefore = token4.balanceOf(address(token4Strategy));

        // Slash tokens by burning/reducing strategy balances:
        // token1: 100% slash = reduce balance to 0
        vm.prank(address(mockStrategy));
        testToken.transfer(address(0xdead), strategy1BalanceBefore); // Burn all tokens

        // token2: 50% slash = reduce balance by 50%
        uint256 slashAmount2 = (strategy2BalanceBefore * 50) / 100;
        vm.prank(address(mockStrategy2));
        testToken2.transfer(address(0xdead), slashAmount2); // Burn tokens

        // token3: 15% slash = reduce balance by 15%
        uint256 slashAmount3 = (strategy3BalanceBefore * 15) / 100;
        vm.prank(address(token3Strategy));
        token3.transfer(address(0xdead), slashAmount3); // Burn tokens

        // token4: 10% slash = reduce balance by 10%
        uint256 slashAmount4 = (strategy4BalanceBefore * 10) / 100;
        vm.prank(address(token4Strategy));
        token4.transfer(address(0xdead), slashAmount4); // Burn tokens

        // Verify slashing occurred by checking strategy balances
        uint256 strategy1BalanceAfter = testToken.balanceOf(address(mockStrategy));
        uint256 strategy2BalanceAfter = testToken2.balanceOf(address(mockStrategy2));
        uint256 strategy3BalanceAfter = token3.balanceOf(address(token3Strategy));
        uint256 strategy4BalanceAfter = token4.balanceOf(address(token4Strategy));

        assertEq(strategy1BalanceAfter, 0, "testToken should be slashed 100%");
        assertEq(strategy2BalanceAfter, strategy2BalanceBefore - slashAmount2, "testToken2 should be slashed 50%");
        assertEq(strategy3BalanceAfter, strategy3BalanceBefore - slashAmount3, "token3 should be slashed 15%");
        assertEq(strategy4BalanceAfter, strategy4BalanceBefore - slashAmount4, "token4 should be slashed 10%");

        // Total assets should be less than before staking due to slashing
        uint256 totalAssetsAfterSlashing = liquidToken.totalAssets();
        assertTrue(totalAssetsAfterSlashing < totalAssetsAfterStaking, "Total assets should decrease due to slashing");

        // 4 new users deposit 0.5 ETH worth of token1, 2, 3, 4 respectively
        address newUser1 = address(0x2001);
        address newUser2 = address(0x2002);
        address newUser3 = address(0x2003);
        address newUser4 = address(0x2004);

        // Mint 0.5 ETH worth of tokens to each new user
        testToken.mint(newUser1, 0.5 ether);
        testToken2.mint(newUser2, 0.5 ether);
        token3.mint(newUser3, 0.5 ether);
        token4.mint(newUser4, 0.5 ether);

        // Set up deposit amounts for new users
        uint256[] memory newAmounts1 = new uint256[](1);
        newAmounts1[0] = 0.5 ether;
        uint256[] memory newAmounts2 = new uint256[](1);
        newAmounts2[0] = 0.5 ether;
        uint256[] memory newAmounts3 = new uint256[](1);
        newAmounts3[0] = 0.5 ether;
        uint256[] memory newAmounts4 = new uint256[](1);
        newAmounts4[0] = 0.5 ether;

        // New user 1 deposits testToken
        vm.startPrank(newUser1);
        testToken.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets1, newAmounts1, newUser1);
        vm.stopPrank();

        // New user 2 deposits testToken2
        vm.startPrank(newUser2);
        testToken2.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets2, newAmounts2, newUser2);
        vm.stopPrank();

        // New user 3 deposits token3
        vm.startPrank(newUser3);
        token3.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets3, newAmounts3, newUser3);
        vm.stopPrank();

        // New user 4 deposits token4
        vm.startPrank(newUser4);
        token4.approve(address(liquidToken), 0.5 ether);
        liquidToken.deposit(assets4, newAmounts4, newUser4);
        vm.stopPrank();

        // Warp 1 year to allow rebasing token (token3) to rebase
        vm.warp(block.timestamp + 365 days);
        console.log("Warped 1 year forward - rebasing token should have increased in value");

        // The first 4 users submit withdrawal requests for all their funds
        bytes32[] memory withdrawalRequestIds = new bytes32[](3); // Only 3 successful withdrawals

        // User 1 tries to withdraw but should fail due to 100% slashing
        vm.startPrank(user1);
        uint256 user1Balance = liquidToken.balanceOf(user1);
        uint256[] memory withdrawAmounts1 = new uint256[](1);
        withdrawAmounts1[0] = liquidToken.calculateAmount(IERC20(address(testToken)), user1Balance);

        // Expect this to revert due to InvalidWithdrawalRequest (100% slashed = no funds available)
        vm.expectRevert(abi.encodeWithSignature("InvalidWithdrawalRequest()"));
        liquidToken.initiateWithdrawal(assets1, withdrawAmounts1);
        vm.stopPrank();

        // User 2 withdraws all their LAT tokens for testToken2
        vm.startPrank(user2);
        uint256 user2Balance = liquidToken.balanceOf(user2);
        uint256[] memory withdrawAmounts2 = new uint256[](1);
        withdrawAmounts2[0] = liquidToken.calculateAmount(IERC20(address(testToken2)), user2Balance);
        withdrawalRequestIds[0] = liquidToken.initiateWithdrawal(assets2, withdrawAmounts2);
        vm.stopPrank();

        // User 3 withdraws all their LAT tokens for token3
        vm.startPrank(user3);
        uint256 user3Balance = liquidToken.balanceOf(user3);
        uint256[] memory withdrawAmounts3 = new uint256[](1);
        withdrawAmounts3[0] = liquidToken.calculateAmount(IERC20(address(token3)), user3Balance);
        withdrawalRequestIds[1] = liquidToken.initiateWithdrawal(assets3, withdrawAmounts3);
        vm.stopPrank();

        // User 4 withdraws all their LAT tokens for token4
        vm.startPrank(user4);
        uint256 user4Balance = liquidToken.balanceOf(user4);
        uint256[] memory withdrawAmounts4 = new uint256[](1);
        withdrawAmounts4[0] = liquidToken.calculateAmount(IERC20(address(token4)), user4Balance);
        withdrawalRequestIds[2] = liquidToken.initiateWithdrawal(assets4, withdrawAmounts4);
        vm.stopPrank();

        // Check requestedAmounts vs actual withdrawable amounts (should show slashing impact)
        // Get withdrawal requests for users 2, 3, and 4 (the successful ones)
        if (withdrawalRequestIds.length > 0) {
            IWithdrawalManager.WithdrawalRequest[] memory requests = withdrawalManager.getWithdrawalRequests(
                withdrawalRequestIds
            );

            for (uint256 i = 0; i < 3; i++) {
                IWithdrawalManager.WithdrawalRequest memory request = requests[i];

                // Get the asset for this request
                IERC20 asset = request.assets[0];
                uint256 requestedAmount = request.requestedAmounts[0];
                uint256 elWithdrawableShares = request.elWithdrawableShares[0];

                // Calculate actual withdrawable amount based on current strategy state (post-slashing)
                uint256 actualWithdrawableAmount = liquidTokenManager.assetSharesToUnderlying(
                    asset,
                    elWithdrawableShares
                );

                // Verify that withdrawable amount is less than requested due to slashing
                if (i == 0) {
                    // User 2 (testToken2): 50% slashed, should get ~50% of requested
                    assertTrue(
                        actualWithdrawableAmount < requestedAmount,
                        "User 2 should get less due to 50% slashing"
                    );
                    assertTrue(
                        actualWithdrawableAmount > requestedAmount / 3,
                        "User 2 should get roughly 50% of requested"
                    );
                } else if (i == 1) {
                    // User 3 (token3): 15% slashed, should get ~85% of requested
                    assertTrue(
                        actualWithdrawableAmount < requestedAmount,
                        "User 3 should get less due to 15% slashing"
                    );
                    assertTrue(
                        actualWithdrawableAmount > (requestedAmount * 80) / 100,
                        "User 3 should get roughly 85% of requested"
                    );
                } else {
                    // User 4 (token4): 10% slashed, should get ~90% of requested
                    assertTrue(
                        actualWithdrawableAmount < requestedAmount,
                        "User 4 should get less due to 10% slashing"
                    );
                    assertTrue(
                        actualWithdrawableAmount > (requestedAmount * 85) / 100,
                        "User 4 should get roughly 90% of requested"
                    );
                }
            }
        }

        // Check that the shares of LAT collected from the users calc was correct and the correct token balance of LAT is in the contract
        // Check LAT token balance held by LiquidToken contract (escrowed from withdrawal requests)
        uint256 liquidTokenHeldByContract = liquidToken.balanceOf(address(liquidToken));

        // Verify this matches the sum of sharesDeposited from withdrawal requests
        uint256 totalExpectedEscrowedShares = 0;
        if (withdrawalRequestIds.length > 0) {
            IWithdrawalManager.WithdrawalRequest[] memory requests = withdrawalManager.getWithdrawalRequests(
                withdrawalRequestIds
            );

            for (uint256 i = 0; i < requests.length; i++) {
                totalExpectedEscrowedShares += requests[i].sharesDeposited;
            }
        }

        assertEq(
            liquidTokenHeldByContract,
            totalExpectedEscrowedShares,
            "LAT contract should hold exactly the escrowed withdrawal shares"
        );

        // Verify users' LAT balances decreased by the withdrawal amounts
        uint256 user2CurrentBalance = liquidToken.balanceOf(user2);
        uint256 user3CurrentBalance = liquidToken.balanceOf(user3);
        uint256 user4CurrentBalance = liquidToken.balanceOf(user4);

        // These should be ~0 since users withdrew all their funds
        assertLt(user2CurrentBalance, 5, "User 2 should have 0 LAT balance after full withdrawal request");
        assertLt(user3CurrentBalance, 5, "User 3 should have 0 LAT balance after full withdrawal request");
        assertLt(user4CurrentBalance, 5, "User 4 should have 0 LAT balance after full withdrawal request");

        // Stake all existing unstaked funds from new user deposits
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

        // Get total assets after second staking (includes all deposits from both sets of users)
        uint256 totalAssetsAfterSecondStaking = liquidToken.totalAssets();

        // Admin calls settleUserWithdrawals using staked funds
        // Get current queuedAssetElShares before settlement (should be 0)
        uint256[] memory queuedSharesBefore = liquidToken.balanceQueuedAssets(allAssets);

        // Check that all queuedAssetBalances are 0 before settlement
        for (uint256 i = 0; i < 4; i++) {
            assertEq(queuedSharesBefore[i], 0, "All queued shares should be 0 before settlement");
        }

        // Prepare settlement data
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

        // Admin calls settleUserWithdrawals and capture the redemption ID from events
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
                console.log("Captured redemption ID from event:", vm.toString(redemptionId));
                break;
            }
        }

        assertTrue(redemptionEventFound, "RedemptionCreatedForUserWithdrawals event should have been emitted");

        // CHECK totalAssets, queuedAssetElShares, and Redemption.withdrawableAmounts
        uint256[] memory queuedSharesAfter = liquidToken.balanceQueuedAssets(allAssets);
        uint256[] memory storedQueuedShares = new uint256[](4);
        storedQueuedShares[0] = queuedSharesAfter[0];
        storedQueuedShares[1] = queuedSharesAfter[1];
        storedQueuedShares[2] = queuedSharesAfter[2];
        storedQueuedShares[3] = queuedSharesAfter[3];

        // Track exact changes after settlement
        uint256 totalAssetsAfterSettlement = liquidToken.totalAssets();

        // Calculate expected changes from settlement
        // Settlement should move assets from staked to queued state, reducing totalAssets by slashed amounts
        IWithdrawalManager.WithdrawalRequest[] memory settlementRequests = withdrawalManager.getWithdrawalRequests(
            withdrawalRequestIds
        );

        uint256 totalRequestedValue = 0;
        uint256 totalWithdrawableValue = 0;

        for (uint256 i = 0; i < settlementRequests.length; i++) {
            for (uint256 j = 0; j < settlementRequests[i].assets.length; j++) {
                IERC20 asset = settlementRequests[i].assets[j];
                uint256 requestedAmount = settlementRequests[i].requestedAmounts[j];
                uint256 withdrawableShares = settlementRequests[i].elWithdrawableShares[j];
                uint256 withdrawableAmount = liquidTokenManager.assetSharesToUnderlying(asset, withdrawableShares);

                totalRequestedValue += liquidTokenManager.convertToUnitOfAccount(asset, requestedAmount);
                totalWithdrawableValue += liquidTokenManager.convertToUnitOfAccount(asset, withdrawableAmount);
            }
        }

        uint256 totalSlashedValue = totalRequestedValue - totalWithdrawableValue;

        // Calculate what the total should be based on initial deposits minus slashing
        uint256 expectedTotalAfterSlashing = totalAssetsAfterDeposits - totalSlashedValue;

        // Verify that totalAssets after slashing already accounted for the loss
        assertEq(
            totalAssetsAfterSlashing,
            expectedTotalAfterSlashing,
            "Total assets after slashing should equal deposits minus slashed amount"
        );

        // Verify that settlement doesn't change totalAssets (slashing was already accounted for)
        assertEq(
            totalAssetsAfterSettlement,
            totalAssetsAfterSlashing,
            "Settlement should not change total assets as slashing was already reflected"
        );

        // Convert queuedAssetBalances (in underlying amounts) to EL shares for comparison
        uint256[] memory queuedSharesInElShares = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            queuedSharesInElShares[i] = liquidTokenManager.assetUnderlyingToShares(allAssets[i], queuedSharesAfter[i]);
        }

        // Verify that queuedAssetElShares match the converted values
        for (uint256 i = 0; i < 4; i++) {
            assertEq(
                storedQueuedShares[i],
                queuedSharesInElShares[i],
                "Stored queued shares should match converted queued asset balances"
            );
        }

        // Verify that requested amounts minus queued amounts equal slashed amounts per asset
        for (uint256 i = 0; i < settlementRequests.length; i++) {
            for (uint256 j = 0; j < settlementRequests[i].assets.length; j++) {
                IERC20 asset = settlementRequests[i].assets[j];
                uint256 requestedAmount = settlementRequests[i].requestedAmounts[j];

                // Find corresponding queued balance for this asset
                uint256 queuedBalance = 0;
                for (uint256 k = 0; k < 4; k++) {
                    if (allAssets[k] == asset) {
                        queuedBalance = queuedSharesAfter[k];
                        break;
                    }
                }

                uint256 slashedAmount = requestedAmount - queuedBalance;
                uint256 withdrawableShares = settlementRequests[i].elWithdrawableShares[j];
                uint256 withdrawableAmount = liquidTokenManager.assetSharesToUnderlying(asset, withdrawableShares);

                // Verify slashed amount calculation
                assertEq(
                    slashedAmount,
                    requestedAmount - withdrawableAmount,
                    "Slashed amount should equal requested minus withdrawable"
                );
            }
        }

        // Get redemption details and verify withdrawable shares match queued shares
        ILiquidTokenManager.Redemption memory redemption = withdrawalManager.getRedemption(redemptionId);

        // Verify redemption withdrawable shares match queued asset EL shares
        for (uint256 i = 0; i < redemption.assets.length; i++) {
            IERC20 asset = redemption.assets[i];
            uint256 redemptionWithdrawableShares = redemption.elWithdrawableShares[i];

            // Find corresponding queued EL shares for this asset
            uint256 queuedElShares = 0;
            for (uint256 k = 0; k < 4; k++) {
                if (allAssets[k] == asset) {
                    queuedElShares = queuedSharesInElShares[k];
                    break;
                }
            }

            assertEq(
                redemptionWithdrawableShares,
                queuedElShares,
                "Redemption withdrawable shares should match queued asset EL shares"
            );
        }
    }
}
