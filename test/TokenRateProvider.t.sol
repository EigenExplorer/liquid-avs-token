// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {TokenRegistryOracle} from "../src/utils/TokenRegistryOracle.sol";
import {ITokenRegistryOracle} from "../src/interfaces/ITokenRegistryOracle.sol";
import {TokenRegistry} from "../src/utils/TokenRegistry.sol";
import {ITokenRegistry} from "../src/interfaces/ITokenRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TokenRateProviderTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testInitialize() public {
        assertTrue(
            tokenRegistryOracle.hasRole(
                tokenRegistryOracle.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
        assertTrue(
            tokenRegistryOracle.hasRole(
                tokenRegistryOracle.RATE_UPDATER_ROLE(),
                user2
            )
        );
        assertEq(
            address(tokenRegistryOracle.tokenRegistry()),
            address(tokenRegistry)
        );
    }

    function testUpdateRate() public {
        uint256 newRate = 2e18;

        vm.prank(user2);
        tokenRegistryOracle.updateRate(IERC20(address(testToken)), newRate);

        assertEq(
            tokenRegistryOracle.getRate(IERC20(address(testToken))),
            newRate
        );
    }

    function testBatchUpdateRates() public {
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(testToken));
        tokens[1] = IERC20(address(testToken2));

        uint256[] memory rates = new uint256[](2);
        rates[0] = 2e18;
        rates[1] = 3e18;

        vm.prank(user2);
        tokenRegistryOracle.batchUpdateRates(tokens, rates);

        assertEq(tokenRegistryOracle.getRate(IERC20(address(testToken))), 2e18);
        assertEq(
            tokenRegistryOracle.getRate(IERC20(address(testToken2))),
            3e18
        );
    }

    function testGetRate() public {
        uint256 newRate = 2e18;

        vm.prank(user2);
        tokenRegistryOracle.updateRate(IERC20(address(testToken)), newRate);

        assertEq(
            tokenRegistryOracle.getRate(IERC20(address(testToken))),
            newRate
        );
    }

    function testOnlyRateUpdaterCanUpdateRate() public {
        address nonUpdater = address(0x1);
        vm.prank(nonUpdater);
        vm.expectRevert(); // TODO: Check revert message
        tokenRegistryOracle.updateRate(IERC20(address(testToken)), 1000);
    }

    function testOnlyRateUpdaterCanBatchUpdateRates() public {
        address nonUpdater = address(0x1);
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory rates = new uint256[](1);

        vm.prank(nonUpdater);
        vm.expectRevert(); // TODO: Check revert message
        tokenRegistryOracle.batchUpdateRates(tokens, rates);
    }

    function testBatchUpdateRatesRequiresSameLength() public {
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory rates = new uint256[](1);

        vm.expectRevert(); // TODO: Check revert message
        tokenRegistryOracle.batchUpdateRates(tokens, rates);
    }

    function testRemoveTokenSuccess() public {
        tokenRegistry.removeToken(testToken);
        assertFalse(
            tokenRegistry.tokenIsSupported(testToken),
            "Token should be removed"
        );

        IERC20[] memory supportedTokens = tokenRegistry.getSupportedTokens();
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            assertFalse(
                supportedTokens[i] == testToken,
                "Token should be removed from the supported tokens array"
            );
        }
    }

    function testRemoveTokenFailsForUnsupportedToken() public {
        tokenRegistry.removeToken(testToken);
        assertFalse(
            tokenRegistry.tokenIsSupported(testToken),
            "Token should not be supported before attempting to remove"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenRegistry.TokenNotSupported.selector,
                address(testToken)
            )
        );
        tokenRegistry.removeToken(testToken);
    }

    function testRemoveTokenFailsForNonAdmin() public {
        assertTrue(
            tokenRegistry.tokenIsSupported(testToken),
            "Token should be supported before non-admin attempts to remove"
        );
        vm.prank(user1);
        vm.expectRevert();
        tokenRegistry.removeToken(testToken);
    }

    function testAddTokenSuccess() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint256 decimals = 18;
        uint256 initialPrice = 1e18;

        tokenRegistry.addToken(newToken, decimals, initialPrice);

        // Verify that the token was successfully added
        ITokenRegistry.TokenInfo memory tokenInfo = tokenRegistry.getTokenInfo(
            newToken
        );
        assertEq(tokenInfo.decimals, decimals, "Incorrect decimals");
        assertEq(
            tokenInfo.pricePerUnit,
            initialPrice,
            "Incorrect initial price"
        );

        // Verify that the token is now supported
        assertTrue(
            tokenRegistry.tokenIsSupported(newToken),
            "Token should be supported"
        );

        // Verify that the token is included in the supportedTokens array
        IERC20[] memory supportedTokens = tokenRegistry.getSupportedTokens();
        bool isTokenInArray = false;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == newToken) {
                isTokenInArray = true;
                break;
            }
        }
        assertTrue(
            isTokenInArray,
            "Token should be in the supportedTokens array"
        );
    }

    function testAddTokenFailsIfAlreadySupported() public {
        uint256 decimals = 18;
        uint256 initialPrice = 1e18;

        // Attempt to add the same token again and expect a revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenRegistry.TokenAlreadySupported.selector,
                address(testToken)
            )
        );
        tokenRegistry.addToken(testToken, decimals, initialPrice);
    }

    function testAddTokenFailsForZeroDecimals() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint256 zeroDecimals = 0;
        uint256 price = 1e18;

        // Attempt to add the token with zero dedcimals and expect a revert
        vm.expectRevert(ITokenRegistry.InvalidDecimals.selector);
        tokenRegistry.addToken(newToken, zeroDecimals, price);
    }

    function testAddTokenFailsForZeroInitialPrice() public {
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        uint256 decimals = 18;
        uint256 zeroPrice = 0;

        // Attempt to add the token with zero initial price and expect a revert
        vm.expectRevert(ITokenRegistry.InvalidPrice.selector);
        tokenRegistry.addToken(newToken, decimals, zeroPrice);
    }

    function testUpdatePriceSuccess() public {
        tokenRegistry.grantRole(tokenRegistry.PRICE_UPDATER_ROLE(), admin);
        uint256 newPrice = 2e18;
        tokenRegistry.updatePrice(testToken, newPrice);
        // Verify the price has been updated correctly
        assertEq(
            tokenRegistry.getTokenInfo(testToken).pricePerUnit,
            newPrice,
            "Price should be updated successfully"
        );
    }

    function testUpdatePriceFailsForUnsupportedToken() public {
        tokenRegistry.grantRole(tokenRegistry.PRICE_UPDATER_ROLE(), admin);
        // Attempt to update the price of a token that hasn't been added to the registry
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        vm.expectRevert(
            abi.encodeWithSelector(
                ITokenRegistry.TokenNotSupported.selector,
                address(newToken)
            )
        );
        tokenRegistry.updatePrice(newToken, 2e18);
    }

    function testUpdatePriceFailsForZeroPrice() public {
        tokenRegistry.grantRole(tokenRegistry.PRICE_UPDATER_ROLE(), admin);
        // Attempt to set the price to zero
        vm.expectRevert(ITokenRegistry.InvalidPrice.selector);
        tokenRegistry.updatePrice(testToken, 0);
    }

    function testUpdatePriceFailsForNonUpdater() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenRegistry.updatePrice(testToken, 2e18);
    }
}
