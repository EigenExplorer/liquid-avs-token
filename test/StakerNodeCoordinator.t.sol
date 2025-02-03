// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./common/BaseTest.sol";
import {StakerNodeCoordinator} from "../src/core/StakerNodeCoordinator.sol";
import {StakerNode} from "../src/core/StakerNode.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract StakerNodeCoordinatorTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testCreateStakerNodeSuccess() public {
        // Create a new staker node
        vm.prank(admin);
        IStakerNode node = stakerNodeCoordinator.createStakerNode();

        assertEq(address(node) != address(2), true);
        assertEq(stakerNodeCoordinator.getStakerNodesCount(), 3);
        assertEq(address(node), address(stakerNodeCoordinator.getNodeById(2)));
    }

    function testUpgradeStakerNodeImplementationSuccess() public {
        // Retrieve the old implementation address from the UpgradeableBeacon
        address oldImplementation = UpgradeableBeacon(address(stakerNodeCoordinator.upgradeableBeacon())).implementation();
        address newImplementation = address(new StakerNode());

        assertTrue(newImplementation != oldImplementation);

        // Upgrade to the new implementation
        vm.prank(admin);
        stakerNodeCoordinator.upgradeStakerNodeImplementation(newImplementation);

        // Retrieve the upgraded implementation address from the UpgradeableBeacon
        address upgradedImplementation = UpgradeableBeacon(address(stakerNodeCoordinator.upgradeableBeacon())).implementation();

        // Check if the upgrade has succeeded
        assertEq(address(stakerNodeCoordinator.upgradeableBeacon()) != address(0), true);
        assertEq(upgradedImplementation, newImplementation);
        assertTrue(upgradedImplementation != oldImplementation);
    }

    function testSetMaxNodesSuccess() public {
        vm.prank(admin);
        stakerNodeCoordinator.setMaxNodes(15);

        assertEq(stakerNodeCoordinator.maxNodes(), 15);
    }

    function testGetNodeByIdSuccess() public {
        vm.prank(admin);
        IStakerNode node = stakerNodeCoordinator.createStakerNode();

        IStakerNode retrievedNode = stakerNodeCoordinator.getNodeById(2);
        assertEq(address(retrievedNode), address(node));
    }

    function testGetAllNodesSuccess() public {
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        assertEq(nodes.length, 3);
    }

    function testGetStakerNodesCountSuccess() public {
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        uint256 count = stakerNodeCoordinator.getStakerNodesCount();
        assertEq(count, 3);
    }

    function testSetMaxNodesRevertsWhenLowerThanCurrentNodes() public {
        // Set max nodes and create a node
        vm.prank(admin);
        stakerNodeCoordinator.setMaxNodes(2);

        // Try to set maxNodes lower than the current number of nodes
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.MaxNodesLowerThanCurrent.selector, 2, 1));
        stakerNodeCoordinator.setMaxNodes(1);
    }

    function testGetNodeByIdRevertsWithOutOfRangeId() public {
        // Accessing node ID that is out of range
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.NodeIdOutOfRange.selector, 10));
        stakerNodeCoordinator.getNodeById(10);
    }

    function testCreateStakerNodeRevertsWhenMaxNodesReached() public {
        // Set max nodes to 1 and create a node
        vm.prank(admin);
        stakerNodeCoordinator.setMaxNodes(3);
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        // Try to create another node, which exceeds the max node limit
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.TooManyStakerNodes.selector, 3));
        stakerNodeCoordinator.createStakerNode();
    }

    function testSetMaxNodesRevertsWithMissingAdminRole() public {
        vm.prank(user1); // user1 does not have the admin role
        vm.expectRevert();
        stakerNodeCoordinator.setMaxNodes(15);
    }

    function testCreateStakerNodeRevertsWithMissingCreatorRole() public {
        vm.prank(user1); // user1 does not have the creator role
        vm.expectRevert();
        stakerNodeCoordinator.createStakerNode();
    }
}
