// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../src/interfaces/IFinalAutoRouting.sol";
import "../../src/FinalAutoRouting.sol";
import "forge-std/console.sol";

contract MockLiquidTokenManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State
    IFinalAutoRouting public finalAutoRouting;
    address public weth;
    mapping(uint256 => mapping(address => uint256)) public mockStakedBalances;

    // Constants
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Events
    event SwapAndStake(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 nodeId
    );

    event MultiStepSwapExecuted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 steps);

    // Structs
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

    // Initialize
    function initialize(Init memory init) external {
        require(address(finalAutoRouting) == address(0), "Already initialized");
        finalAutoRouting = IFinalAutoRouting(init.finalAutoRouting);
        weth = init.weth;
    }

    // Main swap and stake function
    function swapAndStake(
        address tokenIn,
        address targetAsset,
        uint256 amountIn,
        uint256 nodeId,
        uint256 minAmountOut
    ) external payable nonReentrant {
        require(amountIn > 0, "Zero amount");
        require(tokenIn != targetAsset, "Same token");

        console.log("\n[LTM] SwapAndStake called:");
        console.log("  Token In:", tokenIn);
        console.log("  Target Asset:", targetAsset);
        console.log("  Amount In:", amountIn);
        console.log("  Node ID:", nodeId);
        console.log("  Min Amount Out:", minAmountOut);

        // Handle ETH input
        if (tokenIn == ETH_ADDRESS) {
            require(msg.value == amountIn, "ETH value mismatch");
        } else {
            require(msg.value == 0, "Unexpected ETH");
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Get execution plan from FAR
        console.log("\n[LTM] Getting execution plan from FAR...");
        (uint256 quotedOutput, IFinalAutoRouting.MultiStepExecutionPlan memory plan) = finalAutoRouting
            .getCompleteMultiStepPlan(tokenIn, targetAsset, amountIn, address(this));

        console.log("[LTM] FAR returned plan with", plan.steps.length, "steps");
        console.log("[LTM] Expected final amount:", plan.expectedFinalAmount);

        // Validate minimum output
        require(plan.expectedFinalAmount >= minAmountOut, "Insufficient output");

        // Execute the swap plan
        uint256 finalAmount = _executeSwapPlan(plan, tokenIn);

        console.log("[LTM] Swap execution complete. Final amount:", finalAmount);

        // Mock staking - just track the balance
        mockStakedBalances[nodeId][targetAsset] += finalAmount;

        emit SwapAndStake(msg.sender, tokenIn, targetAsset, amountIn, finalAmount, nodeId);

        if (plan.steps.length > 1) {
            emit MultiStepSwapExecuted(tokenIn, targetAsset, amountIn, finalAmount, plan.steps.length);
        }
    }

    function _executeSwapPlan(
        IFinalAutoRouting.MultiStepExecutionPlan memory plan,
        address initialTokenIn
    ) internal returns (uint256) {
        uint256 currentBalance;

        for (uint256 i = 0; i < plan.steps.length; i++) {
            IFinalAutoRouting.SwapStep memory step = plan.steps[i];

            console.log("\n[LTM] Executing step", i + 1, "of", plan.steps.length);
            console.log("  From:", step.tokenIn);
            console.log("  To:", step.tokenOut);
            console.log("  Amount:", step.amountIn);
            console.log("  Min out:", step.minAmountOut);
            console.log("  Protocol:", uint8(step.protocol));

            // Handle approvals
            if (step.tokenIn != ETH_ADDRESS && step.target != address(0)) {
                IERC20(step.tokenIn).safeApprove(step.target, 0);
                IERC20(step.tokenIn).safeApprove(step.target, step.amountIn);
                console.log("  Approved", step.amountIn, "to", step.target);
            }

            // Get balance before
            uint256 balanceBefore = _getBalance(step.tokenOut);

            // Execute based on protocol
            if (step.protocol == IFinalAutoRouting.Protocol.UniswapV3) {
                _executeUniswapV3(step);
            } else if (step.protocol == IFinalAutoRouting.Protocol.Curve) {
                _executeCurve(step);
            } else if (step.protocol == IFinalAutoRouting.Protocol.DirectMint) {
                _executeDirectMint(step);
            } else {
                revert("Unsupported protocol in mock");
            }

            // Get balance after
            currentBalance = _getBalance(step.tokenOut) - balanceBefore;
            console.log("  Output received:", currentBalance);

            // Validate output
            require(currentBalance >= step.minAmountOut, "Step output too low");
        }

        return currentBalance;
    }

    function _executeUniswapV3(IFinalAutoRouting.SwapStep memory step) internal {
        // For mock, just simulate the swap with expected output
        console.log("  [Mock] Executing UniswapV3 swap");

        (bool success, ) = step.target.call{value: step.value}(step.data);
        require(success, "UniswapV3 swap failed");
    }

    function _executeCurve(IFinalAutoRouting.SwapStep memory step) internal {
        // For mock, simulate Curve swap
        console.log("  [Mock] Executing Curve swap");

        (bool success, ) = step.target.call{value: step.value}(step.data);
        require(success, "Curve swap failed");
    }

    function _executeDirectMint(IFinalAutoRouting.SwapStep memory step) internal {
        // For mock, simulate direct mint
        console.log("  [Mock] Executing DirectMint");

        (bool success, ) = step.target.call{value: step.value}(step.data);
        require(success, "DirectMint failed");
    }

    function _getBalance(address token) internal view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    // Receive ETH
    receive() external payable {}
}