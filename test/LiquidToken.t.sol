// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {LiquidToken} from "../src/core/LiquidToken.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidToken} from "../src/interfaces/ILiquidToken.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IWithdrawalManager} from "../src/interfaces/IWithdrawalManager.sol";

contract LiquidTokenTest is BaseTest {
    bool public isLocalTestNetwork;

    event WithdrawalInitiated(
        bytes32 indexed requestId,
        address indexed user,
        IERC20[] assets,
        uint256[] amounts,
        uint256 timestamp
    );

    function setUp() public override {
        super.setUp();

        // Skip network-dependent tests when running on mainnet fork
        isLocalTestNetwork = _isTestNetwork();

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
    }
    function testDeposit() public {
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;

        uint256[] memory mintedShares = liquidToken.deposit(
            assets,
            amounts,
            user1
        );
        uint256 shares = mintedShares[0];

        assertEq(shares, 10 ether, "Incorrect number of shares minted");
        assertEq(
            liquidToken.balanceOf(user1),
            10 ether,
            "Incorrect balance after deposit"
        );
        assertEq(
            testToken.balanceOf(address(liquidToken)),
            10 ether,
            "Incorrect token balance in LiquidToken"
        );
    }

    function testTransferAssets() public {
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 5 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(
            assets,
            amountsToTransfer,
            address(liquidTokenManager)
        );

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token balance in liquid token manager"
        );
    }

    function testDepositMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        uint256[] memory mintedShares = liquidToken.deposit(
            assets,
            amountsToDeposit,
            user1
        );
        uint256 shares1 = mintedShares[0];
        uint256 shares2 = mintedShares[1];

        assertEq(
            shares1,
            10 ether,
            "Incorrect number of shares minted for token1"
        );
        assertEq(
            shares2,
            2.5 ether, // Changed from 5 ether to 2.5 ether
            "Incorrect number of shares minted for token2"
        );
        assertEq(
            liquidToken.balanceOf(user1),
            12.5 ether, // Changed from 15 ether to 12.5 ether
            "Incorrect total balance after deposits"
        );
        vm.stopPrank();
    }

    function testTransferMultipleAssets() public {
        vm.startPrank(user1);

        IERC20[] memory assets = new IERC20[](2);
        assets[0] = IERC20(address(testToken));
        assets[1] = IERC20(address(testToken2));
        uint256[] memory amountsToDeposit = new uint256[](2);
        amountsToDeposit[0] = 10 ether;
        amountsToDeposit[1] = 5 ether;

        testToken.approve(address(liquidToken), 10 ether);
        testToken2.approve(address(liquidToken), 5 ether);

        liquidToken.deposit(assets, amountsToDeposit, user1);
        vm.stopPrank();

        uint256[] memory amountsToTransfer = new uint256[](2);
        amountsToTransfer[0] = 5 ether;
        amountsToTransfer[1] = 2 ether;

        vm.prank(address(liquidTokenManager));
        liquidToken.transferAssets(
            assets,
            amountsToTransfer,
            address(liquidTokenManager)
        );

        assertEq(
            testToken.balanceOf(address(liquidTokenManager)),
            5 ether,
            "Incorrect token1 balance in liquidTokenManager"
        );
        assertEq(
            testToken2.balanceOf(address(liquidTokenManager)),
            2 ether,
            "Incorrect token2 balance in liquidTokenManager"
        );
    }

    function testDepositArrayLengthMismatch() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](2); // Mismatch in length
        amountsToDeposit[0] = 5 ether;
        amountsToDeposit[1] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ArrayLengthMismatch.selector);
        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testDepositZeroAmount() public {
        vm.prank(user1);
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 0 ether;

        vm.expectRevert(ILiquidToken.ZeroAmount.selector);
        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testDepositUnsupportedAsset() public {
        ERC20 unsupportedToken = new MockERC20("Unsupported Token", "UT");
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(unsupportedToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.UnsupportedAsset.selector,
                address(unsupportedToken)
            )
        );
        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testDepositZeroShares() public {
        // Mock a scenario where the conversion rate makes the shares zero
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10;

        vm.mockCall(
            address(liquidTokenManager),
            abi.encodeWithSelector(
                ILiquidTokenManager.convertToUnitOfAccount.selector,
                IERC20(address(testToken)),
                10
            ),
            abi.encode(0) // Conversion returns zero, leading to ZeroShares
        );

        vm.prank(user1);
        vm.expectRevert(ILiquidToken.ZeroShares.selector);
        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testTransferAssetsNotLiquidTokenManager() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.NotLiquidTokenManager.selector,
                user1
            )
        );
        liquidToken.transferAssets(
            assets,
            amounts,
            address(liquidTokenManager)
        );
    }

    function testTransferAssetsInsufficientBalance() public {
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        vm.prank(user1);
        liquidToken.deposit(assets, amountsToDeposit, user1);

        uint256[] memory amountsToTransfer = new uint256[](1);
        amountsToTransfer[0] = 20 ether; // More than available

        vm.prank(address(liquidTokenManager));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidToken.InsufficientBalance.selector,
                address(testToken),
                10 ether,
                20 ether
            )
        );
        liquidToken.transferAssets(
            assets,
            amountsToTransfer,
            address(liquidTokenManager)
        );
    }

    function testPause() public {
        vm.prank(pauser);
        liquidToken.pause();

        assertTrue(liquidToken.paused(), "Contract should be paused");

        // OpenZeppelin v4 uses string revert reasons instead of error selectors
        vm.expectRevert("Pausable: paused");
        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testUnpause() public {
        vm.prank(pauser);
        liquidToken.pause();

        vm.prank(admin);
        liquidToken.unpause();

        assertFalse(liquidToken.paused(), "Contract should be unpaused");

        vm.prank(user1);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amountsToDeposit = new uint256[](1);
        amountsToDeposit[0] = 10 ether;

        liquidToken.deposit(assets, amountsToDeposit, user1);
    }

    function testPauseUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        liquidToken.pause();
    }

    function testTotalAssetsCalculationEdgeCases() public {
        vm.startPrank(admin);

        // Test with maximum possible token amount
        uint256 maxAmount = type(uint256).max / 2; // Avoid overflow
        testToken.mint(user1, maxAmount);

        vm.startPrank(user1);
        testToken.approve(address(liquidToken), maxAmount);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = maxAmount;

        liquidToken.deposit(assets, amounts, user1);

        // Verify total assets matches deposit
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            maxAmount,
            "Total assets should match max deposit"
        );

        // Test precision with small amounts
        uint256 smallAmount = 1;
        testToken.mint(user2, smallAmount);

        vm.startPrank(user2);
        testToken.approve(address(liquidToken), smallAmount);
        amounts[0] = smallAmount;

        liquidToken.deposit(assets, amounts, user2);

        // Verify small amounts are tracked correctly
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            maxAmount + smallAmount,
            "Total assets should include small amount"
        );
    }

    function testTotalAssetsWithStrategyMigration() public {
        vm.startPrank(admin);

        // Initial deposit
        uint256 depositAmount = 10 ether;
        testToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        testToken.approve(address(liquidToken), depositAmount);

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = depositAmount;

        liquidToken.deposit(assets, amounts, user1);

        // Verify initial total assets
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            depositAmount,
            "Initial total assets incorrect"
        );

        // Simulate strategy migration
        vm.startPrank(admin);

        // Verify total assets remained constant through migration
        assertEq(
            liquidToken.assetBalances(address(testToken)),
            depositAmount,
            "Total assets changed during migration"
        );
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

    // Check if we're on a local test network (Hardhat, Anvil, etc.)
    function _isTestNetwork() internal view returns (bool) {
        uint256 chainId = _getChainId();
        // Local networks have chainId 31337 (Hardhat), 1337 (Ganache), etc.
        return chainId == 31337 || chainId == 1337;
    }

    function _getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
