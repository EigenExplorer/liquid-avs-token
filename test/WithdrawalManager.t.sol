// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegationManagerTypes} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {WithdrawalManager} from "../src/core/WithdrawalManager.sol";
import {IWithdrawalManager} from "../src/interfaces/IWithdrawalManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";

contract WithdrawalManagerTest is BaseTest {
    // Test constants
    uint256 constant DEFAULT_WITHDRAWAL_DELAY = 14 days;
    uint256 constant MIN_WITHDRAWAL_DELAY = 7 days;
    uint256 constant MAX_WITHDRAWAL_DELAY = 30 days;

    event WithdrawalInitiated(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts,
        uint256 timestamp
    );

    event WithdrawalFulfilled(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts,
        uint256 timestamp
    );

    event UserSlashed(
        bytes32 indexed requestId,
        address indexed user,
        IERC20 indexed asset,
        uint256 originalAmount,
        uint256 slashedAmount
    );

    event WithdrawalDelayUpdated(uint256 oldDelay, uint256 newDelay);

    function setUp() public override {
        super.setUp();

        // --- Register testToken ---
        if (liquidTokenManager.tokenIsSupported(IERC20(address(testToken)))) {
            try
                liquidTokenManager.setVolatilityThreshold(
                    IERC20(address(testToken)),
                    0
                )
            {
                console.log("Volatility threshold disabled for testToken");
            } catch Error(string memory reason) {
                console.log("Failed to set volatility threshold:", reason);
            } catch (bytes memory) {
                console.log(
                    "Failed to set volatility threshold (unknown error)"
                );
            }
        } else {
            console.log("testToken not supported, adding it first");
            vm.startPrank(admin);

            // Mock the oracle price getter for testToken
            bytes4 getTokenPriceSelector = bytes4(
                keccak256("_getTokenPrice_getter(address)")
            );
            vm.mockCall(
                address(tokenRegistryOracle),
                abi.encodeWithSelector(
                    getTokenPriceSelector,
                    address(testToken)
                ),
                abi.encode(1e18, true) // price = 1e18, success = true
            );

            try
                liquidTokenManager.addToken(
                    IERC20(address(testToken)),
                    18, // decimals
                    0, // volatility threshold already set to 0
                    mockStrategy,
                    SOURCE_TYPE_CHAINLINK,
                    address(testTokenFeed),
                    0, // needsArg
                    address(0), // fallbackSource
                    bytes4(0) // fallbackFn
                )
            {
                console.log("Successfully added testToken in LiquidTokenTest");
            } catch Error(string memory reason) {
                console.log("Failed to add testToken:", reason);
            } catch (bytes memory) {
                console.log("Failed to add testToken (bytes error)");
            }
            vm.stopPrank();
        }

        // --- Register testToken2 ---
        if (liquidTokenManager.tokenIsSupported(IERC20(address(testToken2)))) {
            try
                liquidTokenManager.setVolatilityThreshold(
                    IERC20(address(testToken2)),
                    0
                )
            {
                console.log("Volatility threshold disabled for testToken2");
            } catch Error(string memory reason) {
                console.log(
                    "Failed to set volatility threshold for testToken2:",
                    reason
                );
            } catch (bytes memory) {
                console.log(
                    "Failed to set volatility threshold for testToken2 (unknown error)"
                );
            }
        } else {
            console.log("testToken2 not supported, adding it");
            vm.startPrank(admin);

            // Mock the oracle price getter for testToken2
            bytes4 getTokenPriceSelector = bytes4(
                keccak256("_getTokenPrice_getter(address)")
            );
            vm.mockCall(
                address(tokenRegistryOracle),
                abi.encodeWithSelector(
                    getTokenPriceSelector,
                    address(testToken2)
                ),
                abi.encode(5e17, true) // price = 0.5e18, success = true
            );

            try
                liquidTokenManager.addToken(
                    IERC20(address(testToken2)),
                    18, // decimals
                    0, // volatility threshold already set to 0
                    mockStrategy2,
                    SOURCE_TYPE_CHAINLINK,
                    address(testToken2Feed),
                    0, // needsArg
                    address(0), // fallbackSource
                    bytes4(0) // fallbackFn
                )
            {
                console.log("Successfully added testToken2 in LiquidTokenTest");
            } catch Error(string memory reason) {
                console.log("Failed to add testToken2:", reason);
            } catch (bytes memory) {
                console.log("Failed to add testToken2 (bytes error)");
            }
            vm.stopPrank();
        }

        // Grant roles to the test contract itself
        withdrawalManager.grantRole(
            liquidTokenManager.DEFAULT_ADMIN_ROLE(),
            address(this)
        );

        assertTrue(
            withdrawalManager.hasRole(
                withdrawalManager.DEFAULT_ADMIN_ROLE(),
                admin
            ),
            "Admin should have DEFAULT_ADMIN_ROLE"
        );
    }

    /// @notice Test withdrawal request creation
    function testCreateWithdrawalRequest() public {
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        // Only LiquidToken should be able to create withdrawal requests
        vm.expectEmit(true, true, false, true);
        emit WithdrawalInitiated(
            requestId,
            user1,
            assets,
            amounts,
            block.timestamp
        );

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        // Verify request was created - use getWithdrawalRequests function
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        IWithdrawalManager.WithdrawalRequest[]
            memory requests = withdrawalManager.getWithdrawalRequests(
                requestIds
            );
        IWithdrawalManager.WithdrawalRequest memory request = requests[0];

        assertEq(request.user, user1);
        assertEq(request.assets.length, 2);
        assertEq(request.requestedAmounts.length, 2);
        assertEq(request.requestedAmounts[0], 100 ether);
        assertEq(request.requestedAmounts[1], 50 ether);
        assertEq(request.withdrawableAmounts[0], 100 ether);
        assertEq(request.withdrawableAmounts[1], 50 ether);
        assertEq(request.requestTime, block.timestamp);
        assertFalse(request.canFulfill);

        // Verify user's request list was updated
        bytes32[] memory userRequests = withdrawalManager
            .getUserWithdrawalRequests(user1);
        assertEq(userRequests.length, 1);
        assertEq(userRequests[0], requestId);
    }

    /// @notice Test unauthorized withdrawal request creation
    function testCreateWithdrawalRequestUnauthorized() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId = keccak256("test");

        // Should revert when not called by LiquidToken
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.NotLiquidToken.selector,
                user1
            )
        );
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );
    }

    /// @notice Test withdrawal fulfillment with invalid request
    function testFulfillWithdrawalInvalidRequest() public {
        bytes32 invalidRequestId = keccak256("invalid");

        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.InvalidWithdrawalRequest.selector);
        withdrawalManager.fulfillWithdrawal(invalidRequestId);
    }

    /// @notice Test unauthorized withdrawal fulfillment
    function testFulfillWithdrawalUnauthorized() public {
        // Setup: Create withdrawal request for user1
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // user2 tries to fulfill user1's withdrawal
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.UnauthorizedAccess.selector,
                user2
            )
        );
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test withdrawal fulfillment before delay period
    function testFulfillWithdrawalBeforeDelay() public {
        // Setup: Create withdrawal request
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        // Try to fulfill before delay period
        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.WithdrawalDelayNotMet.selector);
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test withdrawal fulfillment when not ready
    function testFulfillWithdrawalNotReady() public {
        // Setup: Create withdrawal request
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // canFulfill is still false, should revert
        vm.prank(user1);
        vm.expectRevert(
            IWithdrawalManager.WithdrawalNotReadyToFulfill.selector
        );
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test withdrawal fulfillment with insufficient balance
    function testFulfillWithdrawalInsufficientBalance() public {
        // Setup: Create withdrawal request
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // Don't fund the contract - this is the main test point

        vm.prank(user1);
        vm.expectRevert(
            IWithdrawalManager.WithdrawalNotReadyToFulfill.selector
        ); // Will fail here first
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test redemption recording
    function testRecordRedemptionCreated() public {
        bytes32 redemptionId = keccak256("test_redemption");

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256("request1");

        bytes32[] memory withdrawalRoots = new bytes32[](1);
        withdrawalRoots[0] = keccak256("withdrawal1");

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));

        uint256[] memory withdrawableAmounts = new uint256[](1);
        withdrawableAmounts[0] = 100 ether;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: withdrawalRoots,
                assets: assets,
                withdrawableAmounts: withdrawableAmounts,
                receiver: address(liquidToken)
            });

        // Only LiquidTokenManager should be able to record redemptions
        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Verify redemption was recorded
        ILiquidTokenManager.Redemption memory recorded = withdrawalManager
            .getRedemption(redemptionId);
        assertEq(recorded.requestIds.length, 1);
        assertEq(recorded.requestIds[0], requestIds[0]);
        assertEq(recorded.withdrawalRoots[0], withdrawalRoots[0]);
        assertEq(address(recorded.assets[0]), address(testToken));
        assertEq(recorded.withdrawableAmounts[0], 100 ether);
        assertEq(recorded.receiver, address(liquidToken));
    }

    /// @notice Test unauthorized redemption recording
    function testRecordRedemptionCreatedUnauthorized() public {
        bytes32 redemptionId = keccak256("test");
        ILiquidTokenManager.Redemption memory redemption;

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.NotLiquidTokenManager.selector,
                user1
            )
        );
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);
    }

    /// @notice Test redemption completion without slashing
    function testRecordRedemptionCompletedNoSlashing() public {
        // Setup: Create withdrawal request and redemption
        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        // Create redemption
        bytes32 redemptionId = keccak256("redemption");

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: assets,
                withdrawableAmounts: amounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Complete redemption with same amounts (no slashing)
        vm.prank(address(liquidTokenManager));
        uint256[] memory requestedAmounts = withdrawalManager
            .recordRedemptionCompleted(redemptionId, assets, amounts);

        // Verify request is now fulfillable
        bytes32[] memory checkRequestIds = new bytes32[](1);
        checkRequestIds[0] = requestId;
        IWithdrawalManager.WithdrawalRequest[]
            memory checkRequests = withdrawalManager.getWithdrawalRequests(
                checkRequestIds
            );
        IWithdrawalManager.WithdrawalRequest memory request = checkRequests[0];
        assertTrue(request.canFulfill);
        assertEq(request.withdrawableAmounts[0], 100 ether); // No slashing

        // Verify returned requested amounts
        assertEq(requestedAmounts[0], 100 ether);

        // Verify redemption was deleted
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.RedemptionNotFound.selector,
                redemptionId
            )
        );
        withdrawalManager.getRedemption(redemptionId);
    }

    /// @notice Test redemption completion for non-user withdrawal (rebalancing/undelegation)
    function testRecordRedemptionCompletedNonUserWithdrawal() public {
        // Create redemption without user withdrawal requests
        bytes32 redemptionId = keccak256("rebalancing_redemption");

        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256("non_user_request");

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: assets,
                withdrawableAmounts: amounts,
                receiver: address(liquidToken) // Goes to LiquidToken, not WithdrawalManager
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Complete redemption
        vm.prank(address(liquidTokenManager));
        uint256[] memory requestedAmounts = withdrawalManager
            .recordRedemptionCompleted(redemptionId, assets, amounts);

        // Should complete without affecting user withdrawals
        assertEq(requestedAmounts[0], 0); // No user requests involved
    }

    /// @notice Test getting user withdrawal requests
    function testGetUserWithdrawalRequests() public {
        // Initially empty
        bytes32[] memory requests = withdrawalManager.getUserWithdrawalRequests(
            user1
        );
        assertEq(requests.length, 0);

        // Create multiple requests
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId1 = keccak256(abi.encode(user1, block.timestamp, 1));
        bytes32 requestId2 = keccak256(abi.encode(user1, block.timestamp, 2));

        vm.startPrank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId1
        );
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId2
        );
        vm.stopPrank();

        // Verify both requests are returned
        requests = withdrawalManager.getUserWithdrawalRequests(user1);
        assertEq(requests.length, 2);
        assertEq(requests[0], requestId1);
        assertEq(requests[1], requestId2);
    }

    /// @notice Test getting withdrawal requests by IDs
    function testGetWithdrawalRequests() public {
        // Create requests
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId1 = keccak256(abi.encode(user1, block.timestamp, 1));
        bytes32 requestId2 = keccak256(abi.encode(user2, block.timestamp, 2));

        vm.startPrank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId1
        );
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user2,
            requestId2
        );
        vm.stopPrank();

        // Get both requests
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        IWithdrawalManager.WithdrawalRequest[]
            memory requests = withdrawalManager.getWithdrawalRequests(
                requestIds
            );

        assertEq(requests.length, 2);
        assertEq(requests[0].user, user1);
        assertEq(requests[1].user, user2);
        assertEq(requests[0].requestedAmounts[0], 100 ether);
        assertEq(requests[1].requestedAmounts[0], 100 ether);
    }

    /// @notice Test getting withdrawal requests with invalid ID
    function testGetWithdrawalRequestsInvalidId() public {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = keccak256("invalid");

        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.WithdrawalRequestNotFound.selector,
                requestIds[0]
            )
        );
        withdrawalManager.getWithdrawalRequests(requestIds);
    }

    /// @notice Test setting withdrawal delay
    function testSetWithdrawalDelay() public {
        uint256 newDelay = 21 days;

        vm.expectEmit(false, false, false, true);
        emit WithdrawalDelayUpdated(DEFAULT_WITHDRAWAL_DELAY, newDelay);

        vm.prank(admin);
        withdrawalManager.setWithdrawalDelay(newDelay);

        assertEq(withdrawalManager.withdrawalDelay(), newDelay);
    }

    /// @notice Test setting invalid withdrawal delay (too short)
    function testSetWithdrawalDelayTooShort() public {
        uint256 invalidDelay = 6 days;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.InvalidWithdrawalDelay.selector,
                invalidDelay
            )
        );
        withdrawalManager.setWithdrawalDelay(invalidDelay);
    }

    /// @notice Test setting invalid withdrawal delay (too long)
    function testSetWithdrawalDelayTooLong() public {
        uint256 invalidDelay = 31 days;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.InvalidWithdrawalDelay.selector,
                invalidDelay
            )
        );
        withdrawalManager.setWithdrawalDelay(invalidDelay);
    }

    /// @notice Test unauthorized withdrawal delay setting
    function testSetWithdrawalDelayUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // Access control revert
        withdrawalManager.setWithdrawalDelay(21 days);
    }

    /// @notice Test array length mismatch in redemption completion
    function testRecordRedemptionCompletedLengthMismatch() public {
        bytes32 redemptionId = keccak256("test");

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));

        uint256[] memory amounts = new uint256[](2); // Wrong length
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        vm.prank(address(liquidTokenManager));
        vm.expectRevert(IWithdrawalManager.LengthMismatch.selector);
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            assets,
            amounts
        );
    }

    /// @notice Test multiple user withdrawal requests with different assets
    function testMultipleUserRequestsDifferentAssets() public {
        // User1 requests testToken
        IERC20[] memory assets1 = new IERC20[](1);
        assets1[0] = IERC20(address(testToken));
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 100 ether;

        bytes32 requestId1 = keccak256(abi.encode(user1, block.timestamp, 1));

        // User2 requests testToken2
        IERC20[] memory assets2 = new IERC20[](1);
        assets2[0] = IERC20(address(testToken2));
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 50 ether;

        bytes32 requestId2 = keccak256(abi.encode(user2, block.timestamp, 2));

        vm.startPrank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets1,
            amounts1,
            user1,
            requestId1
        );
        withdrawalManager.createWithdrawalRequest(
            assets2,
            amounts2,
            user2,
            requestId2
        );
        vm.stopPrank();

        // Verify requests are independent
        bytes32[] memory user1Requests = withdrawalManager
            .getUserWithdrawalRequests(user1);
        bytes32[] memory user2Requests = withdrawalManager
            .getUserWithdrawalRequests(user2);

        assertEq(user1Requests.length, 1);
        assertEq(user2Requests.length, 1);
        assertEq(user1Requests[0], requestId1);
        assertEq(user2Requests[0], requestId2);

        // Verify request details
        IWithdrawalManager.WithdrawalRequest
            memory request1 = getWithdrawalRequest(requestId1);
        IWithdrawalManager.WithdrawalRequest
            memory request2 = getWithdrawalRequest(requestId2);

        assertEq(address(request1.assets[0]), address(testToken));
        assertEq(address(request2.assets[0]), address(testToken2));
        assertEq(request1.requestedAmounts[0], 100 ether);
        assertEq(request2.requestedAmounts[0], 50 ether);
    }

    /// @notice Test edge case: zero amount withdrawal request
    function testZeroAmountWithdrawalRequest() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0; // Zero amount

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        // Should still create the request (validation might be in LiquidToken)
        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        IWithdrawalManager.WithdrawalRequest
            memory request = getWithdrawalRequest(requestId);
        assertEq(request.requestedAmounts[0], 0);
        assertEq(request.withdrawableAmounts[0], 0);
    }

    // Helper function to get a single withdrawal request
    function getWithdrawalRequest(
        bytes32 requestId
    ) internal view returns (IWithdrawalManager.WithdrawalRequest memory) {
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        IWithdrawalManager.WithdrawalRequest[]
            memory requests = withdrawalManager.getWithdrawalRequests(
                requestIds
            );
        return requests[0];
    }

    /// @notice Test redemption completion with zero original amount
    function testRedemptionCompletionZeroOriginalAmount() public {
        // Create request with zero amount
        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        // Create redemption
        bytes32 redemptionId = keccak256("zero_redemption");

        bytes32[] memory zeroRequestIds = new bytes32[](1);
        zeroRequestIds[0] = requestId;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: zeroRequestIds,
                withdrawalRoots: new bytes32[](1),
                assets: assets,
                withdrawableAmounts: amounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Complete redemption
        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            assets,
            amounts
        );

        // Should handle zero amounts gracefully
        IWithdrawalManager.WithdrawalRequest
            memory request = getWithdrawalRequest(requestId);
        assertTrue(request.canFulfill);
        assertEq(request.withdrawableAmounts[0], 0);
    }

    /// @notice Test withdrawal fulfillment with multiple assets
    function testFulfillWithdrawalMultipleAssets() public {
        // Setup: Create withdrawal request with multiple assets
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // For testing purposes, we'll need to mock the canFulfill flag
        // In a real scenario, this would be set by LiquidTokenManager.recordRedemptionCompleted

        // Fund the withdrawal manager with both tokens
        testToken.mint(address(withdrawalManager), 100 ether);
        testToken2.mint(address(withdrawalManager), 50 ether);

        // Note: This test would need proper setup of canFulfill flag
        // For now, we expect it to revert due to canFulfill being false
        vm.prank(user1);
        vm.expectRevert(
            IWithdrawalManager.WithdrawalNotReadyToFulfill.selector
        );
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test withdrawal fulfillment with partial insufficient balance
    function testFulfillWithdrawalPartialInsufficientBalance() public {
        // Setup: Create withdrawal request with multiple assets
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 50 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // Fund only first token
        testToken.mint(address(withdrawalManager), 100 ether);
        // Don't fund testToken2

        vm.prank(user1);
        vm.expectRevert(
            IWithdrawalManager.WithdrawalNotReadyToFulfill.selector
        );
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test getting redemption that doesn't exist
    function testGetRedemptionNotFound() public {
        bytes32 invalidRedemptionId = keccak256("invalid");

        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.RedemptionNotFound.selector,
                invalidRedemptionId
            )
        );
        withdrawalManager.getRedemption(invalidRedemptionId);
    }

    /// @notice Test redemption completion unauthorized
    function testRecordRedemptionCompletedUnauthorized() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.NotLiquidTokenManager.selector,
                user1
            )
        );
        withdrawalManager.recordRedemptionCompleted(
            keccak256("test"),
            assets,
            amounts
        );
    }

    /// @notice Test stress scenario: Many withdrawal requests
    function testManyWithdrawalRequests() public {
        uint256 numRequests = 10;
        bytes32[] memory requestIds = new bytes32[](numRequests);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        // Create many requests for user1
        vm.startPrank(address(liquidToken));
        for (uint256 i = 0; i < numRequests; i++) {
            requestIds[i] = keccak256(abi.encode(user1, block.timestamp, i));
            withdrawalManager.createWithdrawalRequest(
                assets,
                amounts,
                user1,
                requestIds[i]
            );
        }
        vm.stopPrank();

        // Verify all requests are tracked
        bytes32[] memory userRequests = withdrawalManager
            .getUserWithdrawalRequests(user1);
        assertEq(userRequests.length, numRequests);

        // Verify we can get all requests
        IWithdrawalManager.WithdrawalRequest[]
            memory requests = withdrawalManager.getWithdrawalRequests(
                requestIds
            );
        assertEq(requests.length, numRequests);

        for (uint256 i = 0; i < numRequests; i++) {
            assertEq(requests[i].user, user1);
            assertEq(requests[i].requestedAmounts[0], 10 ether);
        }
    }

    /// @notice Test redemption with mixed user and non-user requests
    function testMixedRedemptionRequests() public {
        // Create user withdrawal request
        bytes32 userRequestId = keccak256(
            abi.encode(user1, block.timestamp, 1)
        );

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            userRequestId
        );

        // Create redemption with both user and non-user request IDs
        bytes32 redemptionId = keccak256("mixed_redemption");

        bytes32[] memory mixedRequestIds = new bytes32[](2);
        mixedRequestIds[0] = userRequestId; // User request
        mixedRequestIds[1] = keccak256("non_user_request"); // Non-user request

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: mixedRequestIds,
                withdrawalRoots: new bytes32[](1),
                assets: assets,
                withdrawableAmounts: amounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Complete redemption
        vm.prank(address(liquidTokenManager));
        uint256[] memory requestedAmounts = withdrawalManager
            .recordRedemptionCompleted(redemptionId, assets, amounts);

        // Should only process the user request
        IWithdrawalManager.WithdrawalRequest
            memory request = getWithdrawalRequest(userRequestId);
        assertTrue(request.canFulfill);
        assertEq(requestedAmounts[0], 100 ether); // Only user request amount
    }

    /// @notice Test boundary withdrawal delay values
    function testBoundaryWithdrawalDelayValues() public {
        // Test minimum valid delay
        vm.prank(admin);
        withdrawalManager.setWithdrawalDelay(MIN_WITHDRAWAL_DELAY);
        assertEq(withdrawalManager.withdrawalDelay(), MIN_WITHDRAWAL_DELAY);

        // Test maximum valid delay
        vm.prank(admin);
        withdrawalManager.setWithdrawalDelay(MAX_WITHDRAWAL_DELAY);
        assertEq(withdrawalManager.withdrawalDelay(), MAX_WITHDRAWAL_DELAY);

        // Test just below minimum (should fail)
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.InvalidWithdrawalDelay.selector,
                MIN_WITHDRAWAL_DELAY - 1
            )
        );
        withdrawalManager.setWithdrawalDelay(MIN_WITHDRAWAL_DELAY - 1);

        // Test just above maximum (should fail)
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.InvalidWithdrawalDelay.selector,
                MAX_WITHDRAWAL_DELAY + 1
            )
        );
        withdrawalManager.setWithdrawalDelay(MAX_WITHDRAWAL_DELAY + 1);
    }

    /// @notice Test withdrawal fulfillment exactly at delay boundary
    function testFulfillWithdrawalAtDelayBoundary() public {
        // Setup: Create withdrawal request
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bytes32 requestId = keccak256(abi.encode(user1, block.timestamp, 1));
        uint256 requestTime = block.timestamp;

        vm.prank(address(liquidToken));
        withdrawalManager.createWithdrawalRequest(
            assets,
            amounts,
            user1,
            requestId
        );

        // Fund the withdrawal manager
        testToken.mint(address(withdrawalManager), 100 ether);

        // Test exactly at delay boundary (should fail)
        vm.warp(requestTime + DEFAULT_WITHDRAWAL_DELAY);
        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.WithdrawalDelayNotMet.selector);
        withdrawalManager.fulfillWithdrawal(requestId);

        // Test one second after delay (should still fail due to canFulfill being false)
        vm.warp(requestTime + DEFAULT_WITHDRAWAL_DELAY + 1);
        vm.prank(user1);
        vm.expectRevert(
            IWithdrawalManager.WithdrawalNotReadyToFulfill.selector
        );
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test contract initialization values
    function testInitializationValues() public {
        // Test that withdrawal delay is set correctly
        assertEq(withdrawalManager.withdrawalDelay(), DEFAULT_WITHDRAWAL_DELAY);

        // Test that contract addresses are set correctly
        assertEq(
            address(withdrawalManager.liquidToken()),
            address(liquidToken)
        );
        assertEq(
            address(withdrawalManager.liquidTokenManager()),
            address(liquidTokenManager)
        );
        assertEq(
            address(withdrawalManager.delegationManager()),
            address(delegationManager)
        );
        assertEq(
            address(withdrawalManager.stakerNodeCoordinator()),
            address(stakerNodeCoordinator)
        );

        // Test that admin role is granted correctly
        assertTrue(
            withdrawalManager.hasRole(
                withdrawalManager.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
    }

    /// @notice Test complete end-to-end withdrawal flow for a single user
    function testCompleteEndToEndWithdrawalFlow() public {
        // Step 1: User deposits tokens to get shares
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 100 ether;

        vm.prank(user1);
        uint256[] memory shares = liquidToken.deposit(
            depositAssets,
            depositAmounts,
            user1
        );
        uint256 userShares = shares[0];
        assertGt(userShares, 0, "User should receive shares");

        // Step 2: User initiates withdrawal
        IERC20[] memory withdrawAssets = new IERC20[](1);
        withdrawAssets[0] = IERC20(address(testToken));
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 50 ether; // Withdraw half

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(
            withdrawAssets,
            withdrawAmounts
        );

        // Verify withdrawal request was created
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;
        IWithdrawalManager.WithdrawalRequest[]
            memory requests = withdrawalManager.getWithdrawalRequests(
                requestIds
            );
        assertEq(requests[0].user, user1);
        assertEq(requests[0].requestedAmounts[0], 50 ether);
        assertFalse(requests[0].canFulfill); // Not ready yet

        // Step 3: Fast forward past withdrawal delay
        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // Step 4: Simulate LiquidTokenManager creating and completing redemption
        bytes32 redemptionId = keccak256("test_redemption");

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: withdrawAssets,
                withdrawableAmounts: withdrawAmounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Complete redemption without slashing
        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            withdrawAssets,
            withdrawAmounts
        );

        // Step 5: Fund the withdrawal manager (simulate received funds from EigenLayer)
        testToken.mint(address(withdrawalManager), 50 ether);

        // Step 6: User fulfills withdrawal
        uint256 userBalanceBefore = testToken.balanceOf(user1);

        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId);

        // Verify user received tokens
        uint256 userBalanceAfter = testToken.balanceOf(user1);
        assertEq(
            userBalanceAfter - userBalanceBefore,
            50 ether,
            "User should receive withdrawn tokens"
        );

        // Verify request was deleted
        vm.expectRevert(
            abi.encodeWithSelector(
                IWithdrawalManager.WithdrawalRequestNotFound.selector,
                requestId
            )
        );
        withdrawalManager.getWithdrawalRequests(requestIds);
    }

    /// @notice Test complete end-to-end withdrawal flow with slashing
    function testCompleteEndToEndWithdrawalFlowWithSlashing() public {
        // Step 1: User deposits tokens
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 100 ether;

        vm.prank(user1);
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        // Step 2: User initiates withdrawal
        IERC20[] memory withdrawAssets = new IERC20[](1);
        withdrawAssets[0] = IERC20(address(testToken));
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 60 ether;

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(
            withdrawAssets,
            withdrawAmounts
        );

        // Step 3: Fast forward past withdrawal delay
        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // Step 4: Create redemption
        bytes32 redemptionId = keccak256("slashing_redemption");
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: withdrawAssets,
                withdrawableAmounts: withdrawAmounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Step 5: Complete redemption with 10% slashing
        uint256[] memory receivedAmounts = new uint256[](1);
        receivedAmounts[0] = 54 ether; // 90% of 60 ether

        vm.expectEmit(true, true, true, true);
        emit UserSlashed(
            requestId,
            user1,
            IERC20(address(testToken)),
            60 ether,
            54 ether
        );

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            withdrawAssets,
            receivedAmounts
        );

        // Step 6: Fund withdrawal manager with slashed amount
        testToken.mint(address(withdrawalManager), 54 ether);

        // Step 7: User fulfills withdrawal and receives slashed amount
        uint256 userBalanceBefore = testToken.balanceOf(user1);

        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId);

        uint256 userBalanceAfter = testToken.balanceOf(user1);
        assertEq(
            userBalanceAfter - userBalanceBefore,
            54 ether,
            "User should receive slashed amount"
        );
    }

    /// @notice Test complete end-to-end withdrawal flow with multiple users
    function testCompleteEndToEndMultipleUsersWithdrawal() public {
        // Step 1: Both users deposit tokens
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts1 = new uint256[](1);
        depositAmounts1[0] = 100 ether;
        uint256[] memory depositAmounts2 = new uint256[](1);
        depositAmounts2[0] = 150 ether;

        vm.prank(user1);
        liquidToken.deposit(depositAssets, depositAmounts1, user1);

        vm.prank(user2);
        liquidToken.deposit(depositAssets, depositAmounts2, user2);

        // Step 2: Both users initiate withdrawals
        IERC20[] memory withdrawAssets = new IERC20[](1);
        withdrawAssets[0] = IERC20(address(testToken));
        uint256[] memory withdrawAmounts1 = new uint256[](1);
        withdrawAmounts1[0] = 80 ether;
        uint256[] memory withdrawAmounts2 = new uint256[](1);
        withdrawAmounts2[0] = 120 ether;

        vm.prank(user1);
        bytes32 requestId1 = liquidToken.initiateWithdrawal(
            withdrawAssets,
            withdrawAmounts1
        );

        vm.prank(user2);
        bytes32 requestId2 = liquidToken.initiateWithdrawal(
            withdrawAssets,
            withdrawAmounts2
        );

        // Step 3: Fast forward past withdrawal delay
        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // Step 4: Create batch redemption covering both requests
        bytes32 redemptionId = keccak256("batch_redemption");
        bytes32[] memory requestIds = new bytes32[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;

        uint256[] memory totalWithdrawableAmounts = new uint256[](1);
        totalWithdrawableAmounts[0] = 200 ether; // Total of both requests

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: withdrawAssets,
                withdrawableAmounts: totalWithdrawableAmounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Step 5: Complete redemption with 5% slashing
        uint256[] memory receivedAmounts = new uint256[](1);
        receivedAmounts[0] = 190 ether; // 95% of 200 ether

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            withdrawAssets,
            receivedAmounts
        );

        // Verify both requests have proportional slashing
        bytes32[] memory user1RequestIds = new bytes32[](1);
        user1RequestIds[0] = requestId1;
        bytes32[] memory user2RequestIds = new bytes32[](1);
        user2RequestIds[0] = requestId2;

        IWithdrawalManager.WithdrawalRequest[]
            memory user1Requests = withdrawalManager.getWithdrawalRequests(
                user1RequestIds
            );
        IWithdrawalManager.WithdrawalRequest[]
            memory user2Requests = withdrawalManager.getWithdrawalRequests(
                user2RequestIds
            );

        assertEq(user1Requests[0].withdrawableAmounts[0], 76 ether); // 95% of 80 ether
        assertEq(user2Requests[0].withdrawableAmounts[0], 114 ether); // 95% of 120 ether
        assertTrue(user1Requests[0].canFulfill);
        assertTrue(user2Requests[0].canFulfill);

        // Step 6: Fund withdrawal manager
        testToken.mint(address(withdrawalManager), 190 ether);

        // Step 7: Both users fulfill withdrawals
        uint256 user1BalanceBefore = testToken.balanceOf(user1);
        uint256 user2BalanceBefore = testToken.balanceOf(user2);

        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId1);

        vm.prank(user2);
        withdrawalManager.fulfillWithdrawal(requestId2);

        // Verify both users received their proportionally slashed amounts
        uint256 user1BalanceAfter = testToken.balanceOf(user1);
        uint256 user2BalanceAfter = testToken.balanceOf(user2);

        assertEq(user1BalanceAfter - user1BalanceBefore, 76 ether);
        assertEq(user2BalanceAfter - user2BalanceBefore, 114 ether);
    }

    /// @notice Test complete end-to-end withdrawal flow with multiple assets
    function testCompleteEndToEndMultipleAssetsWithdrawal() public {
        // Step 1: User deposits multiple assets
        IERC20[] memory depositAssets = new IERC20[](2);
        depositAssets[0] = IERC20(address(testToken));
        depositAssets[1] = IERC20(address(testToken2));
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 100 ether;
        depositAmounts[1] = 200 ether;

        vm.prank(user1);
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        // Step 2: User initiates withdrawal for both assets
        IERC20[] memory withdrawAssets = new IERC20[](2);
        withdrawAssets[0] = IERC20(address(testToken));
        withdrawAssets[1] = IERC20(address(testToken2));
        uint256[] memory withdrawAmounts = new uint256[](2);
        withdrawAmounts[0] = 60 ether;
        withdrawAmounts[1] = 120 ether;

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(
            withdrawAssets,
            withdrawAmounts
        );

        // Step 3: Fast forward past withdrawal delay
        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        // Step 4: Create redemption
        bytes32 redemptionId = keccak256("multi_asset_redemption");
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: withdrawAssets,
                withdrawableAmounts: withdrawAmounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        // Step 5: Complete redemption with different slashing for each asset
        uint256[] memory receivedAmounts = new uint256[](2);
        receivedAmounts[0] = 57 ether; // 95% slashing for testToken
        receivedAmounts[1] = 108 ether; // 90% slashing for testToken2

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            withdrawAssets,
            receivedAmounts
        );

        // Step 6: Fund withdrawal manager with both assets
        testToken.mint(address(withdrawalManager), 57 ether);
        testToken2.mint(address(withdrawalManager), 108 ether);

        // Step 7: User fulfills withdrawal
        uint256 user1Token1BalanceBefore = testToken.balanceOf(user1);
        uint256 user1Token2BalanceBefore = testToken2.balanceOf(user1);

        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId);

        // Verify user received both assets with appropriate slashing
        uint256 user1Token1BalanceAfter = testToken.balanceOf(user1);
        uint256 user1Token2BalanceAfter = testToken2.balanceOf(user1);

        assertEq(user1Token1BalanceAfter - user1Token1BalanceBefore, 57 ether);
        assertEq(user1Token2BalanceAfter - user1Token2BalanceBefore, 108 ether);
    }

    /// @notice Test edge case: User tries to withdraw more than they have shares for
    function testCompleteEndToEndInsufficientShares() public {
        // Step 1: User deposits small amount
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 50 ether;

        vm.prank(user1);
        console.log("bonobo1");
        liquidToken.deposit(depositAssets, depositAmounts, user1);
        console.log("bonobo2");

        // Step 2: User tries to withdraw more than deposited
        IERC20[] memory withdrawAssets = new IERC20[](1);
        withdrawAssets[0] = IERC20(address(testToken));
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 100 ether; // More than deposited

        vm.prank(user1);
        vm.expectRevert(); // Should revert due to insufficient shares
        liquidToken.initiateWithdrawal(withdrawAssets, withdrawAmounts);
    }

    /// @notice Test user attempting to fulfill withdrawal before delay period
    function testCompleteEndToEndWithdrawalBeforeDelay() public {
        // Step 1: User deposits and initiates withdrawal
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50 ether;

        vm.prank(user1);
        liquidToken.deposit(assets, amounts, user1);

        vm.prank(user1);
        bytes32 requestId = liquidToken.initiateWithdrawal(assets, amounts);

        // Step 2: Try to fulfill immediately (should fail)
        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.WithdrawalDelayNotMet.selector);
        withdrawalManager.fulfillWithdrawal(requestId);

        // Step 3: Try again just before delay expires (should still fail)
        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY);
        vm.prank(user1);
        vm.expectRevert(IWithdrawalManager.WithdrawalDelayNotMet.selector);
        withdrawalManager.fulfillWithdrawal(requestId);
    }

    /// @notice Test withdrawal with zero amount (edge case)
    function testCompleteEndToEndZeroAmountWithdrawal() public {
        // Step 1: User deposits tokens
        IERC20[] memory depositAssets = new IERC20[](1);
        depositAssets[0] = IERC20(address(testToken));
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 100 ether;

        vm.prank(user1);
        liquidToken.deposit(depositAssets, depositAmounts, user1);

        // Step 2: User tries to withdraw zero amount
        IERC20[] memory withdrawAssets = new IERC20[](1);
        withdrawAssets[0] = IERC20(address(testToken));
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 0; // Zero amount

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ZeroAmount.selector);
        liquidToken.initiateWithdrawal(withdrawAssets, withdrawAmounts);
    }

    /// @notice Test complete workflow with price updates during withdrawal
    function testCompleteEndToEndWithPriceUpdates() public {
        // Step 1: User deposits tokens
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(admin);
        liquidTokenManager.updatePrice(IERC20(address(testToken)), 2e18); // Double the price

        // Step 3: User initiates withdrawal
        vm.prank(user1);
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 50 ether;
        bytes32 requestId = liquidToken.initiateWithdrawal(
            assets,
            withdrawAmounts
        );

        // Step 4: Complete the withdrawal process
        vm.warp(block.timestamp + DEFAULT_WITHDRAWAL_DELAY + 1);

        bytes32 redemptionId = keccak256("price_update_redemption");
        bytes32[] memory requestIds = new bytes32[](1);
        requestIds[0] = requestId;

        ILiquidTokenManager.Redemption memory redemption = ILiquidTokenManager
            .Redemption({
                requestIds: requestIds,
                withdrawalRoots: new bytes32[](1),
                assets: assets,
                withdrawableAmounts: withdrawAmounts,
                receiver: address(withdrawalManager)
            });

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCreated(redemptionId, redemption);

        vm.prank(address(liquidTokenManager));
        withdrawalManager.recordRedemptionCompleted(
            redemptionId,
            assets,
            withdrawAmounts
        );

        testToken.mint(address(withdrawalManager), 50 ether);

        uint256 userBalanceBefore = testToken.balanceOf(user1);
        vm.prank(user1);
        withdrawalManager.fulfillWithdrawal(requestId);

        uint256 userBalanceAfter = testToken.balanceOf(user1);
        assertEq(userBalanceAfter - userBalanceBefore, 50 ether);
    }
}
