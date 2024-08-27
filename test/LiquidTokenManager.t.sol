// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {BaseTest} from "./BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {LiquidTokenManager} from "../src/core/LiquidTokenManager.sol";
import {ILiquidTokenManager} from "../src/interfaces/ILiquidTokenManager.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";

contract LiquidTokenManagerTest is BaseTest {
    IStakerNode public stakerNode;

    function setUp() public override {
        super.setUp();
        // Create a staker node for testing
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();
        stakerNode = stakerNodeCoordinator.getAllNodes()[0];
    }

    function testInitialize() public {
        assertEq(
            address(liquidTokenManager.liquidToken()),
            address(liquidToken)
        );
        assertEq(
            address(liquidTokenManager.strategies(IERC20(address(testToken)))),
            address(mockStrategy)
        );
        assertEq(
            address(liquidTokenManager.strategies(IERC20(address(testToken2)))),
            address(mockStrategy)
        );
        assertTrue(
            liquidTokenManager.hasRole(
                liquidTokenManager.DEFAULT_ADMIN_ROLE(),
                admin
            )
        );
        assertTrue(
            liquidTokenManager.hasRole(
                liquidTokenManager.STRATEGY_CONTROLLER_ROLE(),
                admin
            )
        );
    }

    function testSetStrategy() public {
        MockStrategy newStrategy = new MockStrategy(strategyManager);
        vm.prank(admin);
        liquidTokenManager.setStrategy(
            IERC20(address(testToken)),
            IStrategy(address(newStrategy))
        );
        assertEq(
            address(liquidTokenManager.strategies(IERC20(address(testToken)))),
            address(newStrategy)
        );
    }

    function testSetStrategyUnauthorized() public {
        MockStrategy newStrategy = new MockStrategy(strategyManager);
        vm.prank(user1);
        vm.expectRevert(); // TODO: Check if this is the correct revert message
        liquidTokenManager.setStrategy(
            IERC20(address(testToken)),
            IStrategy(address(newStrategy))
        );
    }

    function testStakeAssetsToNode() public {
        uint256 nodeId = 0;

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        testToken.mint(address(liquidToken), 1 ether);

        vm.prank(admin);
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);

        assertEq(testToken.balanceOf(address(stakerNode)), 1 ether);
    }

    function testStakeAssetsToNodeUnauthorized() public {
        uint256 nodeId = 1;
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(testToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.prank(user1);
        vm.expectRevert(); // TODO: Check if this is the correct revert message
        liquidTokenManager.stakeAssetsToNode(nodeId, assets, amounts);
    }

    function testGetStakedAssetBalanceInvalidStrategy() public {
        uint256 nodeId = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILiquidTokenManager.StrategyNotFound.selector,
                address(0x123)
            )
        );
        liquidTokenManager.getStakedAssetBalance(
            IERC20(address(0x123)),
            nodeId
        );
    }
}
