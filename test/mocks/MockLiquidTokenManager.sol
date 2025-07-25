// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../src/interfaces/IFinalAutoRouting.sol";
import "forge-std/console.sol";

contract MockLiquidTokenManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State
    IFinalAutoRouting public finalAutoRouting;
    address public weth;
    mapping(uint256 => mapping(address => uint256)) public mockStakedBalances;

    // Constants
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // Events - matching the interface
    event FinalAutoRoutingUpdated(address indexed oldFAR, address indexed newFAR, address updatedBy);
    event AssetsSwappedAndStakedToNode(
        uint256 indexed nodeId,
        IERC20[] assetsSwapped,
        uint256[] amountsSwapped,
        IERC20[] assetsStaked,
        uint256[] amountsStaked,
        address indexed initiator
    );
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 indexed nodeId
    );

    // Structs - matching the interface
    struct Init {
        address strategyManager;
        address delegationManager;
        address liquidToken;
        address stakerNodeCoordinator;
        address tokenRegistryOracle;
        address initialOwner;
        address strategyController;
        address priceUpdater;
        address finalAutoRouting;
        address weth;
    }

    struct NodeAllocationWithSwap {
        uint256 nodeId;
        IERC20[] assetsToSwap;
        uint256[] amountsToSwap;
        IERC20[] assetsToStake;
    }

    // Initialize
    function initialize(Init memory init) external {
        require(address(finalAutoRouting) == address(0), "Already initialized");
        finalAutoRouting = IFinalAutoRouting(init.finalAutoRouting);
        weth = init.weth;
    }

    // Admin function to update FAR
    function updateFinalAutoRouting(address newFinalAutoRouting) external {
        require(newFinalAutoRouting != address(0), "Zero address");
        address oldFAR = address(finalAutoRouting);
        finalAutoRouting = IFinalAutoRouting(newFinalAutoRouting);
        emit FinalAutoRoutingUpdated(oldFAR, newFinalAutoRouting, msg.sender);
    }

    // Main functions following the 3-function pattern from your colleague

    /// @notice Swaps multiple assets and stakes them to multiple nodes
    function swapAndStakeAssetsToNodes(NodeAllocationWithSwap[] calldata allocationsWithSwaps) external nonReentrant {
        for (uint256 i = 0; i < allocationsWithSwaps.length; i++) {
            NodeAllocationWithSwap memory allocationWithSwap = allocationsWithSwaps[i];
            _swapAndStakeAssetsToNode(
                allocationWithSwap.nodeId,
                allocationWithSwap.assetsToSwap,
                allocationWithSwap.amountsToSwap,
                allocationWithSwap.assetsToStake
            );
        }
    }

    /// @notice Swaps assets and stakes them to a single node
    function swapAndStakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assetsToSwap,
        uint256[] memory amountsToSwap,
        IERC20[] memory assetsToStake
    ) external nonReentrant {
        _swapAndStakeAssetsToNode(nodeId, assetsToSwap, amountsToSwap, assetsToStake);
    }

    /// @dev Called by `swapAndStakeAssetsToNode` and `swapAndStakeAssetsToNodes`
    /// @dev Flow: MockLTM >> DEX >> MockLTM (using FAR for routing data)
    function _swapAndStakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assetsToSwap,
        uint256[] memory amountsToSwap,
        IERC20[] memory assetsToStake
    ) internal {
        uint256 assetsLength = assetsToStake.length;

        require(assetsLength == assetsToSwap.length, "Assets length mismatch");
        require(assetsLength == amountsToSwap.length, "Amounts length mismatch");
        require(address(finalAutoRouting) != address(0), "FAR not configured");

        console.log("\n[MockLTM] SwapAndStakeAssetsToNode called:");
        console.log("Node ID:", nodeId);
        console.log("Assets to swap:", assetsLength);

        // Mock: Simulate bringing assets from LiquidToken
        console.log("[MockLTM] Simulating asset retrieval from LiquidToken...");

        uint256[] memory amountsToStake = new uint256[](assetsLength);

        // Swap using FAR - for every tokenIn swap to corresponding tokenOut
        for (uint256 i = 0; i < assetsLength; i++) {
            address tokenIn = address(assetsToSwap[i]);
            address tokenOut = address(assetsToStake[i]);
            uint256 amountIn = amountsToSwap[i];

            console.log("\n[MockLTM] Processing swap", i + 1, "of", assetsLength);
            console.log("Token In:", tokenIn);
            console.log("Token Out:", tokenOut);
            console.log("Amount In:", amountIn);

            require(amountIn > 0, "Invalid swap amount");

            if (tokenIn == tokenOut) {
                // No swap needed, direct stake
                amountsToStake[i] = amountIn;
                console.log("Direct stake (no swap needed)");
            } else {
                // Execute swap using FAR
                uint256 actualAmountOut = _executeFARSwapPlan(tokenIn, tokenOut, amountIn);
                amountsToStake[i] = actualAmountOut;

                emit SwapExecuted(tokenIn, tokenOut, amountIn, actualAmountOut, nodeId);
            }
        }

        // Mock: Simulate transferring assets to node and staking
        console.log("\n[MockLTM] Simulating asset transfer to node and staking...");
        for (uint256 i = 0; i < assetsLength; i++) {
            address tokenAddress = address(assetsToStake[i]);
            uint256 amount = amountsToStake[i];

            // Mock staking - just track the balance
            mockStakedBalances[nodeId][tokenAddress] += amount;

            console.log("Staked", amount, "of");
            console.log(tokenAddress, "to node", nodeId);
        }

        emit AssetsSwappedAndStakedToNode(
            nodeId,
            assetsToSwap,
            amountsToSwap,
            assetsToStake,
            amountsToStake,
            msg.sender
        );

        console.log("[MockLTM] SwapAndStakeAssetsToNode completed successfully");
    }

    /// @dev Executes a swap plan from FAR following MockLTM >> DEX >> MockLTM flow
    function _executeFARSwapPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 actualAmountOut) {
        console.log("\n[MockLTM] Executing FAR swap plan:");
        console.log("Token In:", tokenIn);
        console.log("Token Out:", tokenOut);
        console.log("Amount In:", amountIn);

        // Execute step by step with dynamic planning
        return _executeStepByStepSwap(tokenIn, tokenOut, amountIn);
    }

    /// @dev Execute swap step by step, regenerating execution data for each step
    function _executeStepByStepSwap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        console.log("\n[MockLTM] Starting step-by-step swap execution");

        address currentTokenIn = tokenIn;
        uint256 currentAmountIn = amountIn;
        uint256 totalSteps = 0;

        // Handle stETH input precision issue at the beginning
        if (currentTokenIn == STETH_ADDRESS) {
            // Measure actual balance after transfer
            uint256 actualBalance = IERC20(STETH_ADDRESS).balanceOf(address(this));
            console.log("stETH requested:", currentAmountIn);
            console.log("stETH actual balance:", actualBalance);

            // Use actual balance if it's less than requested (precision loss)
            if (actualBalance < currentAmountIn) {
                currentAmountIn = actualBalance;
                console.log("Adjusted stETH amount to:", currentAmountIn);
            }
        }

        while (currentTokenIn != tokenOut) {
            totalSteps++;
            console.log("\n[MockLTM] Step", totalSteps);
            console.log("Current token:", currentTokenIn);
            console.log("Target token:", tokenOut);
            console.log("Current amount:", currentAmountIn);

            // CRITICAL: Always get fresh execution plan with current amount
            // This ensures the swap data matches the actual amount we have
            (uint256 quotedOutput, IFinalAutoRouting.MultiStepExecutionPlan memory plan) = finalAutoRouting
                .getCompleteMultiStepPlan(currentTokenIn, tokenOut, currentAmountIn, address(this));

            require(plan.steps.length > 0, "No steps in plan");

            // Use the first step
            IFinalAutoRouting.SwapStep memory firstStep = plan.steps[0];

            console.log("Next token:", firstStep.tokenOut);
            console.log("Expected out:", firstStep.minAmountOut);
            console.log("Target contract:", firstStep.target);

            // Execute the step
            uint256 actualOut = _executeStep(
                firstStep.tokenIn,
                firstStep.tokenOut,
                firstStep.amountIn,
                firstStep.minAmountOut,
                firstStep.data,
                firstStep.target,
                firstStep.value
            );

            console.log("Actual output:", actualOut);

            // Update for next iteration
            currentTokenIn = firstStep.tokenOut;
            currentAmountIn = actualOut;

            // Safety check to prevent infinite loops
            require(totalSteps <= 5, "Too many steps");
        }

        console.log("[MockLTM] Step-by-step swap completed successfully");
        return currentAmountIn;
    }

    /// @dev Execute a single swap step
    function _executeStep(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory swapData,
        address targetContract,
        uint256 value
    ) internal returns (uint256) {
        console.log("\n[MockLTM] Executing step:");
        console.log("Token in:", tokenIn);
        console.log("Token out:", tokenOut);
        console.log("Amount in:", amountIn);
        console.log("Min amount out:", minAmountOut);
        console.log("Target:", targetContract);

        // Approve tokens if needed
        if (tokenIn != ETH_ADDRESS && targetContract != address(0)) {
            IERC20(tokenIn).safeApprove(targetContract, 0);
            IERC20(tokenIn).safeApprove(targetContract, amountIn);
            console.log("Approved tokens for swap");
        }

        // Get balance before swap
        uint256 balanceBefore = _getBalance(tokenOut);
        console.log("Balance before:", balanceBefore);

        // Execute the swap
        (bool success, bytes memory result) = targetContract.call{value: value}(swapData);

        if (!success) {
            if (result.length > 0) {
                assembly {
                    let size := mload(result)
                    revert(add(32, result), size)
                }
            } else {
                revert("Swap execution failed");
            }
        }

        // Reset approval
        if (tokenIn != ETH_ADDRESS && targetContract != address(0)) {
            IERC20(tokenIn).safeApprove(targetContract, 0);
        }

        // Calculate actual output
        uint256 balanceAfter = _getBalance(tokenOut);
        uint256 actualOutput = balanceAfter - balanceBefore;

        console.log("Balance after:", balanceAfter);
        console.log("Actual output:", actualOutput);

        // Verify minimum output with tolerance for rebasing tokens
        if (tokenOut == STETH_ADDRESS) {
            // For stETH, allow 2 wei tolerance
            require(actualOutput + 2 >= minAmountOut, "Step output too low");
        } else {
            require(actualOutput >= minAmountOut, "Step output too low");
        }

        console.log("Step executed successfully");
        return actualOutput;
    }

    // Legacy function for backward compatibility (if needed)
    function swapAndStake(
        address tokenIn,
        address targetAsset,
        uint256 amountIn,
        uint256 nodeId,
        uint256 minAmountOut
    ) external payable nonReentrant {
        require(amountIn > 0, "Zero amount");
        require(tokenIn != targetAsset, "Same token");

        // Convert to new format
        IERC20[] memory assetsToSwap = new IERC20[](1);
        uint256[] memory amountsToSwap = new uint256[](1);
        IERC20[] memory assetsToStake = new IERC20[](1);

        assetsToSwap[0] = IERC20(tokenIn);
        amountsToSwap[0] = amountIn;
        assetsToStake[0] = IERC20(targetAsset);

        // Handle ETH input
        if (tokenIn == ETH_ADDRESS) {
            require(msg.value == amountIn, "ETH value mismatch");
        } else {
            require(msg.value == 0, "Unexpected ETH");
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        _swapAndStakeAssetsToNode(nodeId, assetsToSwap, amountsToSwap, assetsToStake);
    }

    // Helper to get token balance
    function _getBalance(address token) internal view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    // Getter functions for testing
    function getStakedBalance(uint256 nodeId, address token) external view returns (uint256) {
        return mockStakedBalances[nodeId][token];
    }

    function getFinalAutoRouting() external view returns (address) {
        return address(finalAutoRouting);
    }

    // Receive ETH
    receive() external payable {}
}