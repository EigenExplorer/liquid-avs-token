// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseTest} from "./common/BaseTest.sol";
import {TokenRegistryOracle} from "../src/utils/TokenRegistryOracle.sol";
import {ITokenRegistryOracle} from "../src/interfaces/ITokenRegistryOracle.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";

contract TokenRateProviderTest is BaseTest {
    function setUp() public override {
        super.setUp();
        liquidTokenManager.setVolatilityThreshold(testToken, 0); // Disable volatility check
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
            address(tokenRegistryOracle.liquidTokenManager()),
            address(liquidTokenManager)
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

    function testUpdatePriceSuccess() public {
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);
        uint256 newPrice = 2e18;
        liquidTokenManager.updatePrice(testToken, newPrice);
        // Verify the price has been updated correctly
        assertEq(
            liquidTokenManager.getTokenInfo(testToken).pricePerUnit,
            newPrice,
            "Price should be updated successfully"
        );
    }

    function testUpdatePriceFailsForUnsupportedToken() public {
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);
        // Attempt to update the price of a token that hasn't been added to the registry
        IERC20 newToken = IERC20(address(new MockERC20("New Token", "NEW")));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.TokenNotSupported.selector,
                address(newToken)
            )
        );
        liquidTokenManager.updatePrice(newToken, 2e18);
    }

    function testUpdatePriceFailsForZeroPrice() public {
        liquidTokenManager.grantRole(liquidTokenManager.PRICE_UPDATER_ROLE(), admin);
        // Attempt to set the price to zero
        vm.expectRevert(ILiquidTokenManager.InvalidPrice.selector);
        liquidTokenManager.updatePrice(testToken, 0);
    }

    function testUpdatePriceFailsForNonUpdater() public {
        vm.prank(user1);
        vm.expectRevert();
        liquidTokenManager.updatePrice(testToken, 2e18);
    }
}
