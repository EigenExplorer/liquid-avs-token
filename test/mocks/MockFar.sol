// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Mock interfaces for FAR integration
interface IFinalAutoRouting {
    enum Protocol {
        UniswapV3,
        Curve,
        DirectMint,
        MultiHop,
        MultiStep
    }

    struct SwapStep {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address target;
        bytes data;
        uint256 value;
        Protocol protocol;
    }

    struct MultiStepExecutionPlan {
        SwapStep[] steps;
        uint256 expectedFinalAmount;
    }

    struct ExecutionStep {
        address target;
        uint256 value;
        bytes data;
        address tokenIn;
        address tokenOut;
        bool requiresApproval;
        bool isCurvePool;
    }

    function getQuoteAndExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        returns (
            uint256 quotedAmount,
            bytes memory executionData,
            Protocol protocol,
            address targetContract,
            uint256 value
        );

    function getCompleteExecutionPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        returns (
            uint256 quotedOutput,
            uint256 minAmountOut,
            ExecutionStep[] memory steps,
            uint256 totalGas,
            uint256 ethValue
        );

    function getCompleteMultiStepPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) external returns (uint256 totalQuotedAmount, MultiStepExecutionPlan memory plan);

    function getBridgeSecondLegData(
        address bridgeAsset,
        address finalToken,
        uint256 bridgeAmount,
        uint256 originalMinOut,
        address recipient
    ) external returns (bytes memory executionData, address targetContract, bool requiresApproval);

    function getNextStepExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata fullRouteData,
        uint256 stepIndex,
        address recipient
    ) external view returns (bytes memory executionData, address targetContract, bool isFinalStep);

    function validateSwapExecution(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address executor
    ) external view returns (bool isValid, string memory reason, uint256 estimatedOutput);

    function hasRoute(address tokenIn, address tokenOut) external view returns (bool);
}

// Mock FinalAutoRouting contract for testing
contract MockFinalAutoRouting is IFinalAutoRouting {
    using SafeERC20 for IERC20;

    // Mock storage for routes and rates
    mapping(address => mapping(address => uint256)) public mockRates;
    mapping(address => mapping(address => bool)) public routeExists;
    mapping(address => mapping(address => Protocol)) public routeProtocols;
    mapping(address => mapping(address => address)) public routeTargets;
    mapping(address => mapping(address => uint256)) public slippageSettings;
    mapping(address => bool) public supportedTokens;
    mapping(address => uint8) public tokenDecimals;

    // Mock balances for swaps
    mapping(address => uint256) public mockBalances;

    // Events
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event RouteConfigured(address indexed tokenIn, address indexed tokenOut, Protocol protocol, address target);

    // Errors
    error NoRouteFound();
    error TokenNotSupported();
    error ZeroAmount();
    error SameTokenSwap();
    error InsufficientOutput();
    error SwapFailed(string reason);

    // Constants
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor() {
        // Set up some default supported tokens
        supportedTokens[ETH_ADDRESS] = true;
        supportedTokens[WETH] = true;
        tokenDecimals[ETH_ADDRESS] = 18;
        tokenDecimals[WETH] = 18;
    }

    // Configuration functions
    function setMockRate(address tokenIn, address tokenOut, uint256 rate, Protocol protocol, address target) external {
        mockRates[tokenIn][tokenOut] = rate;
        routeExists[tokenIn][tokenOut] = true;
        routeProtocols[tokenIn][tokenOut] = protocol;
        routeTargets[tokenIn][tokenOut] = target;

        emit RouteConfigured(tokenIn, tokenOut, protocol, target);
    }

    function setSlippage(address tokenIn, address tokenOut, uint256 slippageBps) external {
        slippageSettings[tokenIn][tokenOut] = slippageBps;
    }

    function addSupportedToken(address token, uint8 decimals) external {
        supportedTokens[token] = true;
        tokenDecimals[token] = decimals;
    }

    function fundMockBalance(address token, uint256 amount) external {
        mockBalances[token] = amount;
        if (token != ETH_ADDRESS) {
            // For ERC20 tokens, we need actual balance
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    // Main integration functions
    function getQuoteAndExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        override
        returns (
            uint256 quotedAmount,
            bytes memory executionData,
            Protocol protocol,
            address targetContract,
            uint256 value
        )
    {
        _validateSwapInputs(tokenIn, tokenOut, amountIn);

        if (!routeExists[tokenIn][tokenOut]) {
            revert NoRouteFound();
        }

        // Calculate quoted amount
        quotedAmount = _calculateQuote(tokenIn, tokenOut, amountIn);

        // Get protocol and target
        protocol = routeProtocols[tokenIn][tokenOut];
        targetContract = routeTargets[tokenIn][tokenOut];

        // Generate execution data
        executionData = _generateExecutionData(tokenIn, tokenOut, amountIn, quotedAmount, recipient, protocol);

        // Set ETH value
        value = (tokenIn == ETH_ADDRESS) ? amountIn : 0;
    }

    function getCompleteExecutionPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    )
        external
        override
        returns (
            uint256 quotedOutput,
            uint256 minAmountOut,
            ExecutionStep[] memory steps,
            uint256 totalGas,
            uint256 ethValue
        )
    {
        _validateSwapInputs(tokenIn, tokenOut, amountIn);

        if (!routeExists[tokenIn][tokenOut]) {
            revert NoRouteFound();
        }

        quotedOutput = _calculateQuote(tokenIn, tokenOut, amountIn);
        minAmountOut = _calculateMinOutput(tokenIn, tokenOut, quotedOutput);

        // Create single step execution plan
        steps = new ExecutionStep[](1);
        steps[0] = ExecutionStep({
            target: routeTargets[tokenIn][tokenOut],
            value: (tokenIn == ETH_ADDRESS) ? amountIn : 0,
            data: _generateExecutionData(
                tokenIn,
                tokenOut,
                amountIn,
                quotedOutput,
                recipient,
                routeProtocols[tokenIn][tokenOut]
            ),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            requiresApproval: tokenIn != ETH_ADDRESS,
            isCurvePool: routeProtocols[tokenIn][tokenOut] == Protocol.Curve
        });

        totalGas = 150000; // Mock gas estimate
        ethValue = (tokenIn == ETH_ADDRESS) ? amountIn : 0;
    }

    function getCompleteMultiStepPlan(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) external override returns (uint256 totalQuotedAmount, MultiStepExecutionPlan memory plan) {
        _validateSwapInputs(tokenIn, tokenOut, amountIn);

        // For mock, create simple 2-step plan if direct route doesn't exist
        if (routeExists[tokenIn][tokenOut]) {
            // Single step
            totalQuotedAmount = _calculateQuote(tokenIn, tokenOut, amountIn);

            plan.steps = new SwapStep[](1);
            plan.steps[0] = SwapStep({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                minAmountOut: _calculateMinOutput(tokenIn, tokenOut, totalQuotedAmount),
                target: routeTargets[tokenIn][tokenOut],
                data: _generateExecutionData(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    totalQuotedAmount,
                    recipient,
                    routeProtocols[tokenIn][tokenOut]
                ),
                value: (tokenIn == ETH_ADDRESS) ? amountIn : 0,
                protocol: routeProtocols[tokenIn][tokenOut]
            });

            plan.expectedFinalAmount = totalQuotedAmount;
        } else {
            // Try bridge route through WETH
            address bridgeAsset = WETH;

            if (routeExists[tokenIn][bridgeAsset] && routeExists[bridgeAsset][tokenOut]) {
                uint256 bridgeAmount = _calculateQuote(tokenIn, bridgeAsset, amountIn);
                totalQuotedAmount = _calculateQuote(bridgeAsset, tokenOut, bridgeAmount);

                plan.steps = new SwapStep[](2);

                // First step
                plan.steps[0] = SwapStep({
                    tokenIn: tokenIn,
                    tokenOut: bridgeAsset,
                    amountIn: amountIn,
                    minAmountOut: _calculateMinOutput(tokenIn, bridgeAsset, bridgeAmount),
                    target: routeTargets[tokenIn][bridgeAsset],
                    data: _generateExecutionData(
                        tokenIn,
                        bridgeAsset,
                        amountIn,
                        bridgeAmount,
                        recipient,
                        routeProtocols[tokenIn][bridgeAsset]
                    ),
                    value: (tokenIn == ETH_ADDRESS) ? amountIn : 0,
                    protocol: routeProtocols[tokenIn][bridgeAsset]
                });

                // Second step
                plan.steps[1] = SwapStep({
                    tokenIn: bridgeAsset,
                    tokenOut: tokenOut,
                    amountIn: bridgeAmount,
                    minAmountOut: _calculateMinOutput(bridgeAsset, tokenOut, totalQuotedAmount),
                    target: routeTargets[bridgeAsset][tokenOut],
                    data: _generateExecutionData(
                        bridgeAsset,
                        tokenOut,
                        bridgeAmount,
                        totalQuotedAmount,
                        recipient,
                        routeProtocols[bridgeAsset][tokenOut]
                    ),
                    value: 0,
                    protocol: routeProtocols[bridgeAsset][tokenOut]
                });

                plan.expectedFinalAmount = totalQuotedAmount;
            } else {
                revert NoRouteFound();
            }
        }
    }

    function getBridgeSecondLegData(
        address bridgeAsset,
        address finalToken,
        uint256 bridgeAmount,
        uint256 originalMinOut,
        address recipient
    ) external override returns (bytes memory executionData, address targetContract, bool requiresApproval) {
        if (!routeExists[bridgeAsset][finalToken]) {
            revert NoRouteFound();
        }

        uint256 quotedAmount = _calculateQuote(bridgeAsset, finalToken, bridgeAmount);
        uint256 minAmountOut = _calculateMinOutput(bridgeAsset, finalToken, quotedAmount);

        // Use the higher of calculated min or original min
        if (originalMinOut > minAmountOut) {
            minAmountOut = originalMinOut;
        }

        targetContract = routeTargets[bridgeAsset][finalToken];
        executionData = _generateExecutionData(
            bridgeAsset,
            finalToken,
            bridgeAmount,
            quotedAmount,
            recipient,
            routeProtocols[bridgeAsset][finalToken]
        );
        requiresApproval = bridgeAsset != ETH_ADDRESS;
    }

    function getNextStepExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata fullRouteData,
        uint256 stepIndex,
        address recipient
    ) external view override returns (bytes memory executionData, address targetContract, bool isFinalStep) {
        if (!routeExists[tokenIn][tokenOut]) {
            revert NoRouteFound();
        }

        // For mock, assume single step
        isFinalStep = true;
        targetContract = routeTargets[tokenIn][tokenOut];

        uint256 quotedAmount = _calculateQuote(tokenIn, tokenOut, amountIn);
        executionData = _generateExecutionData(
            tokenIn,
            tokenOut,
            amountIn,
            quotedAmount,
            recipient,
            routeProtocols[tokenIn][tokenOut]
        );
    }

    function validateSwapExecution(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address executor
    ) external view override returns (bool isValid, string memory reason, uint256 estimatedOutput) {
        // Basic validation
        if (!supportedTokens[tokenIn]) {
            return (false, "Input token not supported", 0);
        }

        if (!supportedTokens[tokenOut]) {
            return (false, "Output token not supported", 0);
        }

        if (amountIn == 0) {
            return (false, "Zero amount", 0);
        }

        if (tokenIn == tokenOut) {
            return (false, "Same token swap", 0);
        }

        if (!routeExists[tokenIn][tokenOut]) {
            return (false, "No route found", 0);
        }

        estimatedOutput = _calculateQuote(tokenIn, tokenOut, amountIn);

        if (estimatedOutput < minAmountOut) {
            return (false, "Output below minimum", estimatedOutput);
        }

        return (true, "Valid", estimatedOutput);
    }

    function hasRoute(address tokenIn, address tokenOut) external view override returns (bool) {
        return routeExists[tokenIn][tokenOut];
    }

    // Mock swap execution for testing
    function mockSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external payable returns (uint256 amountOut) {
        _validateSwapInputs(tokenIn, tokenOut, amountIn);

        if (!routeExists[tokenIn][tokenOut]) {
            revert NoRouteFound();
        }

        amountOut = _calculateQuote(tokenIn, tokenOut, amountIn);

        if (amountOut < minAmountOut) {
            revert InsufficientOutput();
        }

        // Handle token transfers
        if (tokenIn == ETH_ADDRESS) {
            require(msg.value >= amountIn, "Insufficient ETH");
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Transfer output tokens
        if (tokenOut == ETH_ADDRESS) {
            (bool success, ) = payable(recipient).call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenOut).safeTransfer(recipient, amountOut);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    // Internal helper functions
    function _validateSwapInputs(address tokenIn, address tokenOut, uint256 amountIn) internal view {
        if (amountIn == 0) revert ZeroAmount();
        if (tokenIn == tokenOut) revert SameTokenSwap();
        if (!supportedTokens[tokenIn]) revert TokenNotSupported();
        if (!supportedTokens[tokenOut]) revert TokenNotSupported();
    }

    function _calculateQuote(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        uint256 rate = mockRates[tokenIn][tokenOut];
        if (rate == 0) {
            // Default 1:1 rate with decimal adjustment
            rate = _getDecimalAdjustedRate(tokenIn, tokenOut);
        }
        return (amountIn * rate) / 1e18;
    }

    function _calculateMinOutput(
        address tokenIn,
        address tokenOut,
        uint256 quotedAmount
    ) internal view returns (uint256) {
        uint256 slippage = slippageSettings[tokenIn][tokenOut];
        if (slippage == 0) {
            slippage = 50; // Default 0.5% slippage
        }
        return (quotedAmount * (10000 - slippage)) / 10000;
    }

    function _getDecimalAdjustedRate(address tokenIn, address tokenOut) internal view returns (uint256) {
        uint8 decimalsIn = tokenDecimals[tokenIn];
        uint8 decimalsOut = tokenDecimals[tokenOut];

        if (decimalsIn == decimalsOut) {
            return 1e18; // 1:1 rate
        } else if (decimalsIn > decimalsOut) {
            return 1e18 / (10 ** (decimalsIn - decimalsOut));
        } else {
            return 1e18 * (10 ** (decimalsOut - decimalsIn));
        }
    }

    function _generateExecutionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 quotedAmount,
        address recipient,
        Protocol protocol
    ) internal view returns (bytes memory) {
        // Generate execution data that calls the mock executor's executeSwap function
        return
            abi.encodeWithSelector(
                MockSwapExecutor.executeSwap.selector,
                tokenIn,
                tokenOut,
                amountIn,
                (quotedAmount * 9950) / 10000, // 0.5% slippage
                recipient
            );
    }

    // Allow contract to receive ETH
    receive() external payable {}
}

// Mock executor for testing actual swaps
contract MockSwapExecutor {
    using SafeERC20 for IERC20;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    // Mock balances for testing
    mapping(address => uint256) public mockBalances;

    function fundBalance(address token, uint256 amount) external {
        mockBalances[token] = amount;
        if (token != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external payable returns (uint256 amountOut) {
        // Simple 1:1 swap with 0.1% fee
        amountOut = (amountIn * 9990) / 10000;

        require(amountOut >= minAmountOut, "Insufficient output");

        // Handle input token
        if (tokenIn == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            require(msg.value >= amountIn, "Insufficient ETH");
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Handle output token
        if (tokenOut == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            (bool success, ) = payable(recipient).call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenOut).safeTransfer(recipient, amountOut);
        }

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    receive() external payable {}
}