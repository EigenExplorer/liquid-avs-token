// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "./common/BaseTest.sol";
import {StakerNodeCoordinator} from "../src/core/StakerNodeCoordinator.sol";
import {StakerNode} from "../src/core/StakerNode.sol";
import {IStakerNode} from "../src/interfaces/IStakerNode.sol";
import {IStakerNodeCoordinator} from "../src/interfaces/IStakerNodeCoordinator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract StakerNodeCoordinatorTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testCreateStakerNodeSuccess() public {
        // Create a new staker node
        vm.prank(admin);
        IStakerNode node = stakerNodeCoordinator.createStakerNode();

        assertEq(address(node) != address(0), true);
        assertEq(stakerNodeCoordinator.getStakerNodesCount(), 1);
        assertEq(address(node), address(stakerNodeCoordinator.getNodeById(0)));
    }

    function testUpgradeStakerNodeImplementationSuccess() public {
        // Retrieve the old implementation address from the UpgradeableBeacon
        address oldImplementation = UpgradeableBeacon(address(stakerNodeCoordinator.upgradeableBeacon()))
            .implementation();
        address newImplementation = address(new StakerNode());

        assertTrue(newImplementation != oldImplementation);

        // Upgrade to the new implementation
        vm.prank(admin);
        stakerNodeCoordinator.upgradeStakerNodeImplementation(newImplementation);

        // Retrieve the upgraded implementation address from the UpgradeableBeacon
        address upgradedImplementation = UpgradeableBeacon(address(stakerNodeCoordinator.upgradeableBeacon()))
            .implementation();

        // Check if the upgrade has succeeded
        assertEq(address(stakerNodeCoordinator.upgradeableBeacon()) != address(0), true);
        assertEq(upgradedImplementation, newImplementation);
        assertTrue(upgradedImplementation != oldImplementation);
    }

    function testUpgradeStakerNodeImplementationRevertsWhenNotContract() public {
        // Use an EOA address as implementation
        address nonContractAddress = makeAddr("nonContract");

        // Expect revert when trying to upgrade to non-contract address
        vm.prank(admin);
        vm.expectRevert(IStakerNodeCoordinator.NotAContract.selector);
        stakerNodeCoordinator.upgradeStakerNodeImplementation(nonContractAddress);
    }

    function testSetMaxNodesSuccess() public {
        vm.prank(admin);
        stakerNodeCoordinator.setMaxNodes(15);

        assertEq(stakerNodeCoordinator.maxNodes(), 15);
    }

    function testGetNodeByIdSuccess() public {
        vm.prank(admin);
        IStakerNode node = stakerNodeCoordinator.createStakerNode();

        IStakerNode retrievedNode = stakerNodeCoordinator.getNodeById(0);
        assertEq(address(retrievedNode), address(node));
    }

    function testGetAllNodesSuccess() public {
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        IStakerNode[] memory nodes = stakerNodeCoordinator.getAllNodes();
        assertEq(nodes.length, 2);
    }

    function testGetStakerNodesCountSuccess() public {
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        uint256 count = stakerNodeCoordinator.getStakerNodesCount();
        assertEq(count, 2);
    }

    function testSetMaxNodesRevertsWhenLowerThanCurrentNodes() public {
        // Set max nodes and create a node
        vm.prank(admin);
        stakerNodeCoordinator.setMaxNodes(1);
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        // Try to set maxNodes lower than the current number of nodes
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.MaxNodesLowerThanCurrent.selector, 1, 0));
        stakerNodeCoordinator.setMaxNodes(0);
    }

    function testGetNodeByIdRevertsWithOutOfRangeId() public {
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        // Accessing node ID that is out of range
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.NodeIdOutOfRange.selector, 1));
        stakerNodeCoordinator.getNodeById(1);
    }

    function testInitializeRevertsWithZeroMaxNodes() public {
        // Deploy new implementation
        StakerNodeCoordinator newCoordinator = new StakerNodeCoordinator();

        // Create a proxy with proxyAdminAddress instead of admin
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(newCoordinator),
            proxyAdminAddress, // Use proxyAdminAddress instead of admin
            ""
        );
        StakerNodeCoordinator proxiedCoordinator = StakerNodeCoordinator(address(proxy));

        // Initialize with zero maxNodes
        IStakerNodeCoordinator.Init memory init = IStakerNodeCoordinator.Init({
            liquidTokenManager: liquidTokenManager,
            delegationManager: delegationManager,
            strategyManager: strategyManager,
            maxNodes: 0, // Set maxNodes to 0
            initialOwner: admin,
            pauser: pauser,
            stakerNodeCreator: admin,
            stakerNodesDelegator: admin,
            stakerNodeImplementation: address(stakerNodeImplementation)
        });

        // Use deployer to call the function
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.ZeroAmount.selector));
        proxiedCoordinator.initialize(init);
    }

    function testCreateStakerNodeRevertsWhenMaxNodesReached() public {
        // Set max nodes to 1 and create a node
        vm.prank(admin);
        stakerNodeCoordinator.setMaxNodes(1);
        vm.prank(admin);
        stakerNodeCoordinator.createStakerNode();

        // Try to create another node, which exceeds the max node limit
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.TooManyStakerNodes.selector, 1));
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

    function testMaxNodesIsImportant() public {
        // 1. Deploy the implementation contracts
        StakerNode stakerNodeImplementation = new StakerNode();
        StakerNodeCoordinator newCoordinator = new StakerNodeCoordinator();

        // 2. Set up the beacon
        UpgradeableBeacon upgradeableBeacon = new UpgradeableBeacon(address(stakerNodeImplementation));

        // 3. Create and set up the proxy using proxyAdminAddress
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(newCoordinator),
            proxyAdminAddress, // Use proxyAdminAddress instead of admin
            ""
        );
        StakerNodeCoordinator proxiedCoordinator = StakerNodeCoordinator(address(proxy));

        // 4. Store the beacon in the coordinator
        vm.store(
            address(proxiedCoordinator),
            bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1),
            bytes32(uint256(uint160(address(upgradeableBeacon))))
        );

        // 5. Initialize with maxNodes = 1 (normal case) using deployer as caller
        IStakerNodeCoordinator.Init memory init = IStakerNodeCoordinator.Init({
            liquidTokenManager: liquidTokenManager,
            delegationManager: delegationManager,
            strategyManager: strategyManager,
            maxNodes: 1, // Allow 1 node
            initialOwner: deployer, // Initialize with deployer as owner
            pauser: pauser,
            stakerNodeCreator: deployer, // Use deployer for roles too
            stakerNodesDelegator: deployer,
            stakerNodeImplementation: address(stakerNodeImplementation)
        });

        vm.prank(deployer);
        proxiedCoordinator.initialize(init);

        // 6. We can create a node successfully using deployer
        vm.startPrank(deployer);
        IStakerNode node = proxiedCoordinator.createStakerNode();
        assertEq(address(node) != address(0), true);

        // 7. But we can't create more than maxNodes
        vm.expectRevert(abi.encodeWithSelector(IStakerNodeCoordinator.TooManyStakerNodes.selector, 1));
        proxiedCoordinator.createStakerNode();
        vm.stopPrank();
    }
}
