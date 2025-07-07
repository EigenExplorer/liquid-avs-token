// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../src/FinalAutoRoutingLib.sol";
import "../../src/interfaces/IWETH.sol";

contract MockLTM is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FinalAutoRoutingLib for FinalAutoRoutingLib.FullConfig;

    address public constant ETH_ADDRESS = FinalAutoRoutingLib.ETH_ADDRESS;
    address public immutable WETH_ADDRESS;
    FinalAutoRoutingLib.FullConfig public config;

    // Import token constants from library
    address public constant CBETH = FinalAutoRoutingLib.CBETH;
    address public constant LSETH = FinalAutoRoutingLib.LSETH;
    address public constant METH = FinalAutoRoutingLib.METH;
    address public constant OETH = FinalAutoRoutingLib.OETH;
    address public constant RETH = FinalAutoRoutingLib.RETH;
    address public constant STETH = FinalAutoRoutingLib.STETH;
    address public constant SWETH = FinalAutoRoutingLib.SWETH;
    address public constant ANKRETH = FinalAutoRoutingLib.ANKRETH;
    address public constant ETHX = FinalAutoRoutingLib.ETHX;
    address public constant FRXETH = FinalAutoRoutingLib.FRXETH;
    address public constant SFRXETH = FinalAutoRoutingLib.SFRXETH;
    address public constant OSETH = FinalAutoRoutingLib.OSETH;
    address public constant WBTC = FinalAutoRoutingLib.WBTC;
    address public constant STBTC = FinalAutoRoutingLib.STBTC;
    address public constant UNIBTC = FinalAutoRoutingLib.UNIBTC;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint8 strategy
    );

    constructor(address weth) {
        WETH_ADDRESS = weth;
        _setupDefaultConfig();
        _setupComprehensiveRoutingConfig();
    }

    function _setupComprehensiveRoutingConfig() internal {
        // ===== CRITICAL: Enable ALL possible routes for auto routing =====

        // 1. ANKRETH ↔ WETH (for ANKRETH → CBETH bridge routing)
        config.slippages[ANKRETH][WETH_ADDRESS] = 2000; // ANKRETH → WETH
        config.slippages[WETH_ADDRESS][ANKRETH] = 2000; // WETH → ANKRETH

        // 2. CBETH ↔ WETH (for ANKRETH → CBETH bridge routing)
        config.slippages[CBETH][WETH_ADDRESS] = 2000; // CBETH → WETH
        config.slippages[WETH_ADDRESS][CBETH] = 2000; // WETH → CBETH

        // 3. rETH ↔ WETH (for osETH bridge routing) - INCREASED FOR OSETH ROUTES
        config.slippages[RETH][WETH_ADDRESS] = 2500; // rETH → WETH (was 2000)
        config.slippages[WETH_ADDRESS][RETH] = 2500; // WETH → rETH (was 2000)

        // 4. osETH ↔ rETH (for osETH multi-step) - INCREASED
        config.slippages[OSETH][RETH] = 2000; // osETH → rETH (was 1500)
        config.slippages[RETH][OSETH] = 2000; // rETH → osETH (was 1500)

        // 5. Additional ETH LST routes for comprehensive coverage
        config.slippages[STETH][WETH_ADDRESS] = 500; // stETH → WETH
        config.slippages[WETH_ADDRESS][STETH] = 500; // WETH → stETH
        config.slippages[FRXETH][WETH_ADDRESS] = 800; // frxETH → WETH
        config.slippages[WETH_ADDRESS][FRXETH] = 800; // WETH → frxETH
        config.slippages[SFRXETH][WETH_ADDRESS] = 1000; // sfrxETH → WETH
        config.slippages[WETH_ADDRESS][SFRXETH] = 1000; // WETH → sfrxETH
        config.slippages[ETHX][WETH_ADDRESS] = 600; // ETHX → WETH
        config.slippages[WETH_ADDRESS][ETHX] = 600; // WETH → ETHX

        // 6. Direct ETH routes (for quoter failures)
        config.slippages[ETH_ADDRESS][STETH] = 300; // ETH → stETH
        config.slippages[ETH_ADDRESS][ANKRETH] = 500; // ETH → ankrETH
        config.slippages[ETH_ADDRESS][ETHX] = 500; // ETH → ETHX
        config.slippages[ETH_ADDRESS][FRXETH] = 500; // ETH → frxETH
        config.slippages[ETH_ADDRESS][SFRXETH] = 500; // ETH → sfrxETH

        // 7. Reverse routes
        config.slippages[STETH][ETH_ADDRESS] = 300; // stETH → ETH
        config.slippages[ANKRETH][ETH_ADDRESS] = 500; // ankrETH → ETH
        config.slippages[ETHX][ETH_ADDRESS] = 500; // ETHX → ETH
        config.slippages[FRXETH][ETH_ADDRESS] = 500; // frxETH → ETH
        config.slippages[SFRXETH][ETH_ADDRESS] = 500; // sfrxETH → ETH
    }

    receive() external payable {}

    function _setupDefaultConfig() internal {
        // Setup ETH_LST tokens
        _setupToken(ETH_ADDRESS, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(
            WETH_ADDRESS,
            FinalAutoRoutingLib.AssetCategory.ETH_LST,
            18
        );
        _setupToken(STETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(RETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(CBETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(FRXETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(SFRXETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(ANKRETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(ETHX, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(SWETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(OSETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(OETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(METH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);
        _setupToken(LSETH, FinalAutoRoutingLib.AssetCategory.ETH_LST, 18);

        // Setup BTC_WRAPPED tokens
        _setupToken(WBTC, FinalAutoRoutingLib.AssetCategory.BTC_WRAPPED, 8);
        _setupToken(STBTC, FinalAutoRoutingLib.AssetCategory.BTC_WRAPPED, 18);
        _setupToken(UNIBTC, FinalAutoRoutingLib.AssetCategory.BTC_WRAPPED, 18);

        // Whitelist Curve pools
        _setupCurvePool(
            0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, // stETH/ETH
            2,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            false
        );
        _setupCurvePool(
            0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577, // frxETH/ETH
            2,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            false
        );
        _setupCurvePool(
            0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2, // ankrETH/ETH
            2,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            false
        );
        _setupCurvePool(
            0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492, // ETHx/ETH
            2,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            false
        );
        _setupCurvePool(
            0xe080027Bd47353b5D1639772b4a75E9Ed3658A0d,
            2,
            FinalAutoRoutingLib.CurveInterface.Exchange,
            false
        );
    }

    function _setupToken(
        address token,
        FinalAutoRoutingLib.AssetCategory category,
        uint8 decimals
    ) internal {
        config.tokens[token].category = category;
        config.tokens[token].decimals = decimals;
        config.tokens[token].supported = true;
    }

    function setupToken(
        address token,
        FinalAutoRoutingLib.AssetCategory category,
        uint8 decimals
    ) public {
        config.tokens[token].category = category;
        config.tokens[token].decimals = decimals;
        config.tokens[token].supported = true;
    }

    function setupCurvePool(
        address pool,
        uint256 tokenCount,
        FinalAutoRoutingLib.CurveInterface curveInterface,
        bool paused
    ) public {
        config.pools[pool].whitelisted = true;
        config.pools[pool].tokenCount = tokenCount;
        config.pools[pool].curveInterface = curveInterface;
        config.pools[pool].paused = paused;
    }

    function _setupCurvePool(
        address pool,
        uint256 tokenCount,
        FinalAutoRoutingLib.CurveInterface curveInterface,
        bool paused
    ) internal {
        config.pools[pool].whitelisted = true;
        config.pools[pool].tokenCount = tokenCount;
        config.pools[pool].curveInterface = curveInterface;
        config.pools[pool].paused = paused;
    }

    function swapAssets(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public payable nonReentrant returns (uint256 amountOut) {
        // Handle native ETH input
        if (tokenIn == ETH_ADDRESS) {
            require(msg.value == amountIn, "Incorrect ETH sent");
        } else {
            IERC20(tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                amountIn
            );
        }

        try
            FinalAutoRoutingLib.getSwapInstructions(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut,
                address(this),
                config
            )
        returns (FinalAutoRoutingLib.SwapInstructions memory instructions) {
            _executeInstructionsWithWrapHandling(
                tokenIn,
                tokenOut,
                amountIn,
                instructions
            );
        } catch (bytes memory) {
            return
                _executeMultiStepWithRelaxedSlippage(
                    tokenIn,
                    tokenOut,
                    amountIn,
                    minAmountOut
                );
        }

        amountOut = _getBalance(tokenOut);
        require(amountOut >= minAmountOut, "Insufficient output");
        _sendOutput(tokenOut, msg.sender, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, 0);
        return amountOut;
    }

    function swapAssetsMultiStep(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable nonReentrant returns (uint256) {
        // Handle input transfers
        if (tokenIn == ETH_ADDRESS) {
            require(msg.value == amountIn, "Incorrect ETH");
        } else {
            IERC20(tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                amountIn
            );
        }

        return
            _executeMultiStepWithRelaxedSlippage(
                tokenIn,
                tokenOut,
                amountIn,
                minAmountOut
            );
    }

    function _executeMultiStepWithRelaxedSlippage(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256) {
        // Convert ETH to WETH for multi-step if needed
        address processedTokenIn = tokenIn;
        if (tokenIn == ETH_ADDRESS) {
            IWETH(WETH_ADDRESS).deposit{value: amountIn}();
            processedTokenIn = WETH_ADDRESS;
        }

        // ✅ FIX 1: Less aggressive slippage relaxation for OSETH routes
        uint256 relaxedMinimum;
        if (tokenOut == OSETH || tokenIn == OSETH) {
            relaxedMinimum = (minAmountOut * 7000) / 10000; // 70% for OSETH routes
        } else {
            relaxedMinimum = (minAmountOut * 8500) / 10000; // 85% for other routes
        }

        FinalAutoRoutingLib.MultiStepInstructions
            memory plan = FinalAutoRoutingLib.getMultiStepInstructions(
                processedTokenIn,
                tokenOut,
                amountIn,
                relaxedMinimum,
                address(this),
                config
            );

        // ✅ FIX 2: Execute multi-step instructions with proper tracking
        address[] memory intermediateTokens = _getIntermediateTokens(
            processedTokenIn,
            tokenOut
        );

        for (uint i = 0; i < plan.steps.length; i++) {
            FinalAutoRoutingLib.SwapInstructions memory step = plan.steps[i];

            // ✅ KEY FIX: For steps after the first, update calldata with actual balance
            if (i > 0) {
                // Get the intermediate token address for this step
                address currentToken = intermediateTokens[i - 1];
                uint256 actualBalance = _getBalance(currentToken);

                // Update calldata based on target
                if (step.target == 0xE592427A0AEce92De3Edee1F18E0157C05861564) {
                    // UniswapV3 Router
                    step.callData = _updateUniswapV3CallData(
                        step.callData,
                        actualBalance
                    );
                } else if (_isCurvePool(step.target)) {
                    // Curve Pool
                    step.callData = _updateCurveCallData(
                        step.callData,
                        actualBalance
                    );
                }
            }

            _executeInstructions(step);
        }

        uint256 amountOut = _getBalance(tokenOut);
        require(amountOut >= minAmountOut, "Insufficient output");
        _sendOutput(tokenOut, msg.sender, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, 2);
        return amountOut;
    }

    // ✅ NEW: Get intermediate tokens for multi-step swaps
    function _getIntermediateTokens(
        address tokenIn,
        address tokenOut
    ) internal view returns (address[] memory) {
        address[] memory tokens = new address[](2);

        // For most ETH LST swaps, WETH is the bridge
        if (tokenIn != WETH_ADDRESS && tokenOut != WETH_ADDRESS) {
            tokens[0] = WETH_ADDRESS;
            tokens[1] = tokenOut;
        }
        // For OSETH routes, rETH might be intermediate
        else if (tokenOut == OSETH || tokenIn == OSETH) {
            tokens[0] = RETH;
            tokens[1] = tokenOut;
        } else {
            tokens[0] = WETH_ADDRESS;
            tokens[1] = tokenOut;
        }

        return tokens;
    }

    // ✅ NEW: Check if address is a Curve pool
    function _isCurvePool(address target) internal view returns (bool) {
        return config.pools[target].whitelisted;
    }

    // ✅ FIXED: Update Curve calldata with actual amount
    function _updateCurveCallData(
        bytes memory originalCallData,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        // Get selector using assembly
        bytes4 selector;
        assembly {
            selector := mload(add(originalCallData, 0x20))
        }
        require(selector == 0x3df02124, "Invalid Curve selector");

        // Extract parameters from original calldata
        uint256 i;
        uint256 j;
        uint256 min_dy;

        assembly {
            let dataPtr := add(originalCallData, 0x24) // Skip length + selector
            i := mload(dataPtr)
            j := mload(add(dataPtr, 0x20))
            // Skip dx at 0x40
            min_dy := mload(add(dataPtr, 0x60))
        }

        // Re-encode with new amount
        return abi.encodeWithSelector(selector, i, j, newAmount, min_dy);
    }

    // ✅ FIXED: Helper to update UniswapV3 calldata with actual amount
    function _updateUniswapV3CallData(
        bytes memory originalCallData,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        // Get selector using assembly
        bytes4 selector;
        assembly {
            selector := mload(add(originalCallData, 0x20))
        }
        require(selector == 0x414bf389, "Invalid selector");

        // Extract parameters from original calldata using assembly
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;

        assembly {
            let dataPtr := add(originalCallData, 0x24) // Skip length + selector
            tokenIn := mload(dataPtr)
            tokenOut := mload(add(dataPtr, 0x20))
            fee := mload(add(dataPtr, 0x40))
            recipient := mload(add(dataPtr, 0x60))
            deadline := mload(add(dataPtr, 0x80))
            // Skip amountIn at 0xA0
            amountOutMinimum := mload(add(dataPtr, 0xC0))
            sqrtPriceLimitX96 := mload(add(dataPtr, 0xE0))
        }

        // Re-encode with new amount
        return
            abi.encodeWithSelector(
                selector,
                tokenIn,
                tokenOut,
                fee,
                recipient,
                deadline,
                newAmount,
                amountOutMinimum,
                sqrtPriceLimitX96
            );
    }

    function _executeInstructionsWithWrapHandling(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        FinalAutoRoutingLib.SwapInstructions memory instructions
    ) internal {
        // Handle ETH input for direct swaps
        if (tokenIn == ETH_ADDRESS && instructions.value == amountIn) {
            // Direct ETH swap - execute as-is
            _executeInstructions(instructions);
        } else if (tokenIn == ETH_ADDRESS) {
            // Need to wrap first for non-ETH swaps
            IWETH(WETH_ADDRESS).deposit{value: amountIn}();
            _executeInstructions(instructions);
        } else {
            // Standard ERC20 swap
            _executeInstructions(instructions);
        }

        // Unwrap if output should be ETH
        if (tokenOut == ETH_ADDRESS) {
            uint256 wethBalance = IERC20(WETH_ADDRESS).balanceOf(address(this));
            if (wethBalance > 0) {
                IWETH(WETH_ADDRESS).withdraw(wethBalance);
            }
        }
    }

    function _executeInstructions(
        FinalAutoRoutingLib.SwapInstructions memory instructions
    ) internal {
        if (instructions.approvalToken != address(0)) {
            IERC20(instructions.approvalToken).safeApprove(
                instructions.approvalTarget,
                0
            );
            IERC20(instructions.approvalToken).safeApprove(
                instructions.approvalTarget,
                type(uint256).max
            );
        }

        (bool success, bytes memory data) = instructions.target.call{
            value: instructions.value
        }(instructions.callData);

        if (!success) {
            if (data.length > 0) {
                string memory errorStr = string(data);
                if (
                    _contains(errorStr, "fewer coins than expected") ||
                    _contains(errorStr, "Too little received")
                ) {
                    revert("Insufficient output");
                }
                assembly {
                    revert(add(32, data), mload(data))
                }
            } else {
                revert("Swap failed");
            }
        }

        if (instructions.approvalToken != address(0)) {
            IERC20(instructions.approvalToken).safeApprove(
                instructions.approvalTarget,
                0
            );
        }
    }

    function _contains(
        string memory source,
        string memory target
    ) internal pure returns (bool) {
        bytes memory sourceBytes = bytes(source);
        bytes memory targetBytes = bytes(target);

        if (targetBytes.length > sourceBytes.length) return false;

        for (uint i = 0; i <= sourceBytes.length - targetBytes.length; i++) {
            bool found = true;
            for (uint j = 0; j < targetBytes.length; j++) {
                if (sourceBytes[i + j] != targetBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function _sendOutput(
        address tokenOut,
        address recipient,
        uint256 amount
    ) internal {
        if (tokenOut == ETH_ADDRESS) {
            if (address(this).balance < amount) {
                uint256 unwrapAmount = amount - address(this).balance;
                if (
                    IERC20(WETH_ADDRESS).balanceOf(address(this)) >=
                    unwrapAmount
                ) {
                    IWETH(WETH_ADDRESS).withdraw(unwrapAmount);
                }
            }
            (bool sent, ) = recipient.call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(tokenOut).safeTransfer(recipient, amount);
        }
    }

    function _getBalance(address token) internal view returns (uint256) {
        if (token == ETH_ADDRESS) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }
}