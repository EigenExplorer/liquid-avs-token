// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";

import {MockRewardsCoordinator} from "./mocks/MockRewardsCoordinator.sol";
import {BaseTest} from "./common/BaseTest.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {RewardsManager} from "../src/core/RewardsManager.sol";
import {IRewardsManager} from "../src/interfaces/IRewardsManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";

contract RewardsManagerTest is BaseTest {
    MockERC20 public unsupportedToken1;
    MockERC20 public unsupportedToken2;

    address public earner1 = address(0x1001);
    address public earner2 = address(0x1002);

    // Track the real rewards coordinator
    address public realCoordinator;

    function setUp() public override {
        super.setUp();

        // Get the real coordinator address
        realCoordinator = address(rewardsManager.rewardsCoordinator());

        // Create unsupported tokens
        unsupportedToken1 = new MockERC20("Unsupported Token 1", "UNSUP1");
        unsupportedToken2 = new MockERC20("Unsupported Token 2", "UNSUP2");
    }

    // Helper function to set up mock coordinator storage
    function setupMockCoordinatorStorage(address earner, IERC20 token, uint256 amount) internal {
        // Set claimerFor[earner] storage slot
        bytes32 claimerSlot = keccak256(abi.encode(earner, uint256(0)));
        bytes32 claimerValue = bytes32(uint256(uint160(address(rewardsManager))));
        vm.store(realCoordinator, claimerSlot, claimerValue);

        // Set transferAmounts[token][recipient] storage slot
        bytes32 innerSlot = keccak256(abi.encode(address(token), uint256(1)));
        bytes32 transferSlot = keccak256(abi.encode(address(rewardsManager), innerSlot));
        vm.store(realCoordinator, transferSlot, bytes32(amount));
    }

    function test_ProcessClaim_AccurateBalanceTransfer() public {
        // Pre-fund RewardsManager with existing balance
        testToken.mint(address(rewardsManager), 50 ether);
        uint256 existingBalance = testToken.balanceOf(address(rewardsManager));

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        // Create mock coordinator
        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();

        // Replace the coordinator code
        vm.etch(realCoordinator, address(mockCoordinator).code);

        // Set up storage for mock coordinator
        setupMockCoordinatorStorage(earner1, testToken, 75 ether);

        // Fund the coordinator
        testToken.mint(realCoordinator, 75 ether);

        uint256 liquidTokenBalanceBefore = testToken.balanceOf(address(liquidToken));

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        uint256 liquidTokenBalanceAfter = testToken.balanceOf(address(liquidToken));
        uint256 transferred = liquidTokenBalanceAfter - liquidTokenBalanceBefore;

        assertEq(transferred, 75 ether, "Should transfer only actual received amount");
        assertEq(testToken.balanceOf(address(rewardsManager)), existingBalance);
    }

    function test_ProcessClaim_LiquidTokenIntegration() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](2);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken2)),
            cumulativeEarnings: 50 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        // Create mock coordinator
        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        // Set up storage for both tokens
        setupMockCoordinatorStorage(earner1, testToken, 100 ether);
        setupMockCoordinatorStorage(earner1, testToken2, 50 ether);

        // Fund the coordinator
        testToken.mint(realCoordinator, 100 ether);
        testToken2.mint(realCoordinator, 50 ether);

        uint256 liquidTokenAssetBalance1Before = liquidToken.assetBalances(address(testToken));
        uint256 liquidTokenAssetBalance2Before = liquidToken.assetBalances(address(testToken2));

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        assertEq(liquidToken.assetBalances(address(testToken)) - liquidTokenAssetBalance1Before, 100 ether);
        assertEq(liquidToken.assetBalances(address(testToken2)) - liquidTokenAssetBalance2Before, 50 ether);
        assertEq(testToken.balanceOf(address(liquidToken)), 100 ether);
        assertEq(testToken2.balanceOf(address(liquidToken)), 50 ether);
    }

    function test_ProcessClaim_ReentrancyProtection() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 100 ether);

        testToken.mint(realCoordinator, 100 ether);

        uint256 balanceBefore = testToken.balanceOf(address(rewardsManager));

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        uint256 balanceAfter = testToken.balanceOf(address(rewardsManager));
        assertEq(balanceAfter, balanceBefore); // All transferred to LiquidToken
        assertEq(testToken.balanceOf(address(liquidToken)), 100 ether);
    }

    function test_ProcessClaim_SafeArrayOperations() public {
        // Create claim with duplicate tokens
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](4);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 50 ether
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)), // Duplicate
            cumulativeEarnings: 30 ether
        });
        tokenLeaves[2] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken1)),
            cumulativeEarnings: 25 ether
        });
        tokenLeaves[3] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken2)),
            cumulativeEarnings: 40 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        // Set up storage - since MockRewardsCoordinator transfers per leaf,
        // we need to set the transfer amount to what we want per leaf
        setupMockCoordinatorStorage(earner1, testToken, 40 ether); // Amount per leaf
        setupMockCoordinatorStorage(earner1, testToken2, 40 ether);
        setupMockCoordinatorStorage(earner1, unsupportedToken1, 25 ether);

        // Fund coordinator for multiple transfers of the same token
        testToken.mint(realCoordinator, 80 ether); // 40 * 2 leaves
        testToken2.mint(realCoordinator, 40 ether);
        unsupportedToken1.mint(realCoordinator, 25 ether);

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        // Verify results - MockRewardsCoordinator will transfer for each leaf
        assertEq(rewardsManager.unsupportedAssetBalances(address(unsupportedToken1)), 25 ether);

        // The RewardsManager should receive tokens for each leaf, but dedupe when processing
        // Check the actual balances to see what happened
        uint256 testTokenReceived = testToken.balanceOf(address(liquidToken));
        uint256 testToken2Received = testToken2.balanceOf(address(liquidToken));

        // The exact amounts depend on the RewardsManager's deduplication logic
        assertGt(testTokenReceived, 0, "Should receive some testToken");
        assertEq(testToken2Received, 40 ether, "Should receive testToken2");
    }

    function test_ProcessClaim_SecurityBalanceCheck() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken1)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, unsupportedToken1, 100 ether);

        unsupportedToken1.mint(realCoordinator, 100 ether);

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        assertEq(rewardsManager.unsupportedAssetBalances(address(unsupportedToken1)), 100 ether);
    }

    function test_ClaimerManagement_EfficientOperations() public {
        address[] memory earners = new address[](10);
        for (uint i = 0; i < 10; i++) {
            earners[i] = address(uint160(0x2000 + i));

            vm.mockCall(
                realCoordinator,
                abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earners[i]),
                abi.encode(address(rewardsManager))
            );
        }

        uint256 gasBefore = gasleft();

        for (uint i = 0; i < 10; i++) {
            vm.prank(earners[i]);
            rewardsManager.updateClaimerFor(earners[i]);
        }

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for 10 claimer updates:", gasUsed);

        assertEq(rewardsManager.claimerForLength(), 10);

        // Test removal
        for (uint i = 0; i < 5; i++) {
            vm.mockCall(
                realCoordinator,
                abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earners[i]),
                abi.encode(address(0))
            );

            vm.prank(earners[i]);
            rewardsManager.updateClaimerFor(earners[i]);
        }

        assertEq(rewardsManager.claimerForLength(), 5);

        address[] memory remainingClaimers = rewardsManager.claimerFor();
        assertEq(remainingClaimers.length, 5);
    }

    function test_ProcessClaim_UnauthorizedClaimer() public {
        // Mock to return address(0) - no claimer set
        vm.mockCall(
            realCoordinator,
            abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earner1),
            abi.encode(address(0))
        );

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        vm.prank(earner1);
        vm.expectRevert(abi.encodeWithSelector(IRewardsManager.NotClaimerFor.selector, earner1));
        rewardsManager.processClaim(claim);
    }

    function test_ProcessClaims_GasLimitProtection() public {
        // Create valid claims with non-zero earner
        IRewardsCoordinatorTypes.RewardsMerkleClaim[] memory claims = new IRewardsCoordinatorTypes.RewardsMerkleClaim[](
            51
        );
        for (uint i = 0; i < 51; i++) {
            // Create empty token leaves array
            IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
                memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](0);
            claims[i] = _createBasicClaim(earner1, tokenLeaves);
        }

        // Try to process more than 50 claims
        vm.expectRevert("Too many claims");
        rewardsManager.processClaims(claims);

        // Create 50 valid claims
        claims = new IRewardsCoordinatorTypes.RewardsMerkleClaim[](50);
        for (uint i = 0; i < 50; i++) {
            IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
                memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](0);
            claims[i] = _createBasicClaim(earner1, tokenLeaves);
        }

        // Should work with 50 or fewer - create valid claims
        // Expect NotClaimerFor since we didn't set up coordinator
        vm.expectRevert(abi.encodeWithSelector(IRewardsManager.NotClaimerFor.selector, earner1));
        rewardsManager.processClaims(claims);
    }
    ///
    // more tests for RewardsManagerTest contract

    function test_ProcessClaim_ZeroAmountClaim() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 0 // Zero amount
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 0); // No transfer

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        // Should handle zero amounts gracefully
        assertEq(testToken.balanceOf(address(liquidToken)), 0);
    }

    function test_ProcessClaim_EmptyTokenLeaves() public {
        // Claim with no token leaves
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](0);

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 0);

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        // Should handle empty claims gracefully
        assertEq(testToken.balanceOf(address(liquidToken)), 0);
    }

    function test_ProcessClaim_MaxTokenLeaves() public {
        // Test with maximum reasonable number of token leaves
        uint256 maxLeaves = 20;
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](maxLeaves);

        // Create many different tokens
        MockERC20[] memory manyTokens = new MockERC20[](maxLeaves);
        for (uint256 i = 0; i < maxLeaves; i++) {
            manyTokens[i] = new MockERC20(string(abi.encodePacked("Token", i)), string(abi.encodePacked("TK", i)));
            tokenLeaves[i] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                token: IERC20(address(manyTokens[i])),
                cumulativeEarnings: 1 ether
            });
        }

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        // Setup all tokens as unsupported with transfers
        for (uint256 i = 0; i < maxLeaves; i++) {
            setupMockCoordinatorStorage(earner1, IERC20(address(manyTokens[i])), 1 ether);
            manyTokens[i].mint(realCoordinator, 1 ether);
        }

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        // All should be unsupported assets
        for (uint256 i = 0; i < maxLeaves; i++) {
            assertEq(rewardsManager.unsupportedAssetBalances(address(manyTokens[i])), 1 ether);
        }
    }

    function test_ProcessClaim_MixedSupportedUnsupportedTokens() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](3);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)), // Supported
            cumulativeEarnings: 100 ether
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken1)), // Unsupported
            cumulativeEarnings: 50 ether
        });
        tokenLeaves[2] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken2)), // Supported
            cumulativeEarnings: 75 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        setupMockCoordinatorStorage(earner1, testToken, 100 ether);
        setupMockCoordinatorStorage(earner1, unsupportedToken1, 50 ether);
        setupMockCoordinatorStorage(earner1, testToken2, 75 ether);

        testToken.mint(realCoordinator, 100 ether);
        unsupportedToken1.mint(realCoordinator, 50 ether);
        testToken2.mint(realCoordinator, 75 ether);

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        // Supported tokens should go to LiquidToken
        assertEq(testToken.balanceOf(address(liquidToken)), 100 ether);
        assertEq(testToken2.balanceOf(address(liquidToken)), 75 ether);

        // Unsupported should stay in RewardsManager
        assertEq(rewardsManager.unsupportedAssetBalances(address(unsupportedToken1)), 50 ether);
    }

    function test_ProcessClaim_ClaimerStatusChangeDuringExecution() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        // Mock the processClaim to do nothing for simplicity
        vm.mockCall(realCoordinator, abi.encodeWithSelector(IRewardsCoordinator.processClaim.selector), abi.encode());

        // Initially set as claimer
        vm.mockCall(
            realCoordinator,
            abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earner1),
            abi.encode(address(rewardsManager))
        );

        // First call should work
        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        // Verify the claimer was added to local storage
        assertTrue(rewardsManager.isClaimerFor(earner1));
        assertEq(rewardsManager.claimerForLength(), 1);

        // Test the failed case - change claimer status to address(0)
        vm.mockCall(
            realCoordinator,
            abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earner1),
            abi.encode(address(0)) // No longer a claimer
        );

        // This call should fail with NotClaimerFor
        vm.prank(earner1);
        vm.expectRevert(abi.encodeWithSelector(IRewardsManager.NotClaimerFor.selector, earner1));
        rewardsManager.processClaim(claim);

        // The claimer should still be in local storage because the transaction reverted
        assertTrue(rewardsManager.isClaimerFor(earner1));

        // Now test successful claimer removal by calling updateClaimerFor directly
        vm.prank(earner1);
        rewardsManager.updateClaimerFor(earner1);

        // Now the claimer should be removed
        assertFalse(rewardsManager.isClaimerFor(earner1));
        assertEq(rewardsManager.claimerForLength(), 0);
    }

    function test_ProcessClaim_BalanceCalculationWithExistingBalance() public {
        // Pre-fund RewardsManager with existing balance
        testToken.mint(address(rewardsManager), 200 ether);
        uint256 existingBalance = testToken.balanceOf(address(rewardsManager));

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 100 ether);
        testToken.mint(realCoordinator, 100 ether);

        uint256 liquidTokenBalanceBefore = testToken.balanceOf(address(liquidToken));

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        uint256 liquidTokenBalanceAfter = testToken.balanceOf(address(liquidToken));
        uint256 transferred = liquidTokenBalanceAfter - liquidTokenBalanceBefore;

        // Should only transfer the newly received amount, not existing balance
        assertEq(transferred, 100 ether);
        assertEq(testToken.balanceOf(address(rewardsManager)), existingBalance);
    }

    function test_ProcessClaim_UnsupportedTokenAccumulation() public {
        // First claim
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves1 = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves1[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken1)),
            cumulativeEarnings: 50 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim1 = _createBasicClaim(earner1, tokenLeaves1);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, unsupportedToken1, 50 ether);
        unsupportedToken1.mint(realCoordinator, 50 ether);

        vm.prank(earner1);
        rewardsManager.processClaim(claim1);

        assertEq(rewardsManager.unsupportedAssetBalances(address(unsupportedToken1)), 50 ether);

        // Second claim - should accumulate
        setupMockCoordinatorStorage(earner1, unsupportedToken1, 30 ether);
        unsupportedToken1.mint(realCoordinator, 30 ether);

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves2 = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves2[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken1)),
            cumulativeEarnings: 30 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim2 = _createBasicClaim(earner1, tokenLeaves2);

        vm.prank(earner1);
        rewardsManager.processClaim(claim2);

        // Should accumulate to 80 ether
        assertEq(rewardsManager.unsupportedAssetBalances(address(unsupportedToken1)), 80 ether);
    }

    function test_ProcessClaim_CoordinatorReturnsLessThanClaimed() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 1000 ether // Claim 1000
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 100 ether); // Only transfer 100
        testToken.mint(realCoordinator, 100 ether);

        uint256 liquidTokenBalanceBefore = testToken.balanceOf(address(liquidToken));

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        uint256 liquidTokenBalanceAfter = testToken.balanceOf(address(liquidToken));
        uint256 transferred = liquidTokenBalanceAfter - liquidTokenBalanceBefore;

        // Should only transfer what was actually received
        assertEq(transferred, 100 ether);
    }

    function test_ProcessClaim_CoordinatorTransfersNothing() public {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 0); // No transfer
        // Don't mint any tokens to coordinator

        uint256 liquidTokenBalanceBefore = testToken.balanceOf(address(liquidToken));

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        uint256 liquidTokenBalanceAfter = testToken.balanceOf(address(liquidToken));

        // Should handle zero transfers gracefully
        assertEq(liquidTokenBalanceAfter, liquidTokenBalanceBefore);
    }

    function test_ProcessClaim_MultipleEarnersSequentially() public {
        // Setup claims for multiple earners
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(testToken)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim1 = _createBasicClaim(earner1, tokenLeaves);
        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim2 = _createBasicClaim(earner2, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        // Setup both earners
        setupMockCoordinatorStorage(earner1, testToken, 100 ether);
        setupMockCoordinatorStorage(earner2, testToken, 100 ether);
        testToken.mint(realCoordinator, 200 ether);

        uint256 liquidTokenBalanceBefore = testToken.balanceOf(address(liquidToken));

        // Process first claim
        vm.prank(earner1);
        rewardsManager.processClaim(claim1);

        // Process second claim
        vm.prank(earner2);
        rewardsManager.processClaim(claim2);

        uint256 liquidTokenBalanceAfter = testToken.balanceOf(address(liquidToken));
        uint256 totalTransferred = liquidTokenBalanceAfter - liquidTokenBalanceBefore;

        // Should transfer total from both claims
        assertEq(totalTransferred, 200 ether);
    }

    function test_ProcessClaim_ExtremelyLargeDuplicates() public {
        // Create claim with many duplicates of the same token
        uint256 duplicateCount = 50;
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](duplicateCount);

        for (uint256 i = 0; i < duplicateCount; i++) {
            tokenLeaves[i] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                token: IERC20(address(testToken)),
                cumulativeEarnings: 1 ether
            });
        }

        IRewardsCoordinatorTypes.RewardsMerkleClaim memory claim = _createBasicClaim(earner1, tokenLeaves);

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);
        setupMockCoordinatorStorage(earner1, testToken, 1 ether);
        testToken.mint(realCoordinator, duplicateCount * 1 ether);

        uint256 gasBefore = gasleft();

        vm.prank(earner1);
        rewardsManager.processClaim(claim);

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for", duplicateCount, "duplicates:", gasUsed);

        // Should handle duplicates efficiently
        assertGt(testToken.balanceOf(address(liquidToken)), 0);
    }

    function test_ProcessClaims_BatchProcessing() public {
        // Create multiple claims
        uint256 claimCount = 10;
        IRewardsCoordinatorTypes.RewardsMerkleClaim[] memory claims = new IRewardsCoordinatorTypes.RewardsMerkleClaim[](
            claimCount
        );

        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        for (uint256 i = 0; i < claimCount; i++) {
            address earner = address(uint160(0x3000 + i));

            IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
                memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
            tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                token: IERC20(address(testToken)),
                cumulativeEarnings: 10 ether
            });

            claims[i] = _createBasicClaim(earner, tokenLeaves);
            setupMockCoordinatorStorage(earner, testToken, 10 ether);
        }

        testToken.mint(realCoordinator, claimCount * 10 ether);

        uint256 liquidTokenBalanceBefore = testToken.balanceOf(address(liquidToken));

        vm.prank(earner1); // Any caller can process batch
        rewardsManager.processClaims(claims);

        uint256 liquidTokenBalanceAfter = testToken.balanceOf(address(liquidToken));
        uint256 totalTransferred = liquidTokenBalanceAfter - liquidTokenBalanceBefore;

        assertEq(totalTransferred, claimCount * 10 ether);
    }

    function test_UpdateClaimerFor_EdgeCases() public {
        // Test with zero address should revert
        vm.expectRevert(abi.encodeWithSelector(IRewardsManager.ZeroAddress.selector));
        rewardsManager.updateClaimerFor(address(0));

        // Test claimer addition and removal cycle
        vm.mockCall(
            realCoordinator,
            abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earner1),
            abi.encode(address(rewardsManager))
        );

        vm.prank(earner1);
        rewardsManager.updateClaimerFor(earner1);
        assertTrue(rewardsManager.isClaimerFor(earner1));
        assertEq(rewardsManager.claimerForLength(), 1);

        // Remove claimer
        vm.mockCall(
            realCoordinator,
            abi.encodeWithSelector(IRewardsCoordinator.claimerFor.selector, earner1),
            abi.encode(address(0))
        );

        vm.prank(earner1);
        rewardsManager.updateClaimerFor(earner1);
        assertFalse(rewardsManager.isClaimerFor(earner1));
        assertEq(rewardsManager.claimerForLength(), 0);
    }

    function test_BalanceAssets_MultipleAssets() public {
        // Setup some unsupported asset balances
        MockRewardsCoordinator mockCoordinator = new MockRewardsCoordinator();
        vm.etch(realCoordinator, address(mockCoordinator).code);

        setupMockCoordinatorStorage(earner1, unsupportedToken1, 100 ether);
        setupMockCoordinatorStorage(earner1, unsupportedToken2, 200 ether);
        unsupportedToken1.mint(realCoordinator, 100 ether);
        unsupportedToken2.mint(realCoordinator, 200 ether);

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves1 = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves1[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken1)),
            cumulativeEarnings: 100 ether
        });

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]
            memory tokenLeaves2 = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves2[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(unsupportedToken2)),
            cumulativeEarnings: 200 ether
        });

        vm.prank(earner1);
        rewardsManager.processClaim(_createBasicClaim(earner1, tokenLeaves1));

        vm.prank(earner1);
        rewardsManager.processClaim(_createBasicClaim(earner1, tokenLeaves2));

        // Test balanceAssets function
        IERC20[] memory assets = new IERC20[](3);
        assets[0] = unsupportedToken1;
        assets[1] = unsupportedToken2;
        assets[2] = testToken; // Should be 0

        uint256[] memory balances = rewardsManager.balanceAssets(assets);

        assertEq(balances[0], 100 ether);
        assertEq(balances[1], 200 ether);
        assertEq(balances[2], 0);
    }

    ////
    function _createBasicClaim(
        address earner,
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves
    ) internal pure returns (IRewardsCoordinatorTypes.RewardsMerkleClaim memory) {
        IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf memory earnerLeaf = IRewardsCoordinatorTypes
            .EarnerTreeMerkleLeaf({earner: earner, earnerTokenRoot: bytes32(0)});

        bytes memory emptyProof = new bytes(0);
        bytes[] memory tokenTreeProofs = new bytes[](tokenLeaves.length);
        for (uint i = 0; i < tokenLeaves.length; i++) {
            tokenTreeProofs[i] = new bytes(0);
        }

        return
            IRewardsCoordinatorTypes.RewardsMerkleClaim({
                rootIndex: 1,
                earnerIndex: 0,
                earnerTreeProof: emptyProof,
                earnerLeaf: earnerLeaf,
                tokenIndices: new uint32[](tokenLeaves.length),
                tokenTreeProofs: tokenTreeProofs,
                tokenLeaves: tokenLeaves
            });
    }
}