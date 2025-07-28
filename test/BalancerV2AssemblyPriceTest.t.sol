// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IBalancerV2Vault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        FundManagement calldata funds
    ) external returns (int256[] memory assetDeltas);

    function getPoolTokens(
        bytes32 poolId
    ) external view returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

// Minimal helper contract for delegatecall
contract QueryHelper {
    function querySwap(bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = 0xBA12222222228d8Ba445958a75a0704d566BF2C8.call(data);
        require(success, "Query failed");
        return result;
    }
}

contract BalancerV2GasOptimizedTest is Test {
    using Strings for uint256;

    address constant BALANCER_V2_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes32 constant WSTETH_WETH_POOL_ID = 0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    bytes32 constant RETH_WETH_POOL_ID = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    QueryHelper helper;

    function setUp() public {
        vm.createSelectFork("wss://eth.drpc.org");
        helper = new QueryHelper();

        console.log("=== Balancer V2 Gas Optimized Test Setup ===");
        console.log("Vault address:", BALANCER_V2_VAULT);
        console.log("");
    }

    function testDelegatecallApproach() public {
        console.log("=== Testing Delegatecall Approach ===");

        console.log("Testing wstETH price...");
        uint256 gasBefore = gasleft();
        (uint256 price, bool success) = _getBalancerV2PriceDelegatecall(WSTETH, WSTETH_WETH_POOL_ID);
        uint256 gasUsed = gasBefore - gasleft();

        if (success) {
            console.log("SUCCESS - wstETH price:", price);
            console.log("Price in ETH:", formatEther(price));
            console.log("Gas used:", gasUsed);
        } else {
            console.log("FAILED - wstETH price");
        }

        console.log("\nTesting rETH price...");
        gasBefore = gasleft();
        (price, success) = _getBalancerV2PriceDelegatecall(RETH, RETH_WETH_POOL_ID);
        gasUsed = gasBefore - gasleft();

        if (success) {
            console.log("SUCCESS - rETH price:", price);
            console.log("Price in ETH:", formatEther(price));
            console.log("Gas used:", gasUsed);
        } else {
            console.log("FAILED - rETH price");
        }
    }

    function testUltraOptimizedAssembly() public {
        console.log("=== Testing Ultra Optimized Assembly ===");

        uint256 gasBefore = gasleft();
        (uint256 price, bool success) = _getBalancerV2PriceUltraOptimized(WSTETH, WSTETH_WETH_POOL_ID);
        uint256 gasUsed = gasBefore - gasleft();

        if (success) {
            console.log("Assembly SUCCESS! wstETH price:", price);
            console.log("Price in ETH:", formatEther(price));
            console.log("Gas used:", gasUsed);
        } else {
            console.log("Assembly failed");
        }
    }

    // Delegatecall approach to bypass view restrictions
    function _getBalancerV2PriceDelegatecall(
        address token,
        bytes32 poolId
    ) internal returns (uint256 price, bool success) {
        if (poolId == bytes32(0)) return (0, false);

        // Get pool tokens first
        try IBalancerV2Vault(BALANCER_V2_VAULT).getPoolTokens(poolId) returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        ) {
            uint256 tokenIndex = type(uint256).max;
            uint256 wethIndex = type(uint256).max;

            for (uint i = 0; i < tokens.length; i++) {
                if (tokens[i] == token) tokenIndex = i;
                if (tokens[i] == WETH) wethIndex = i;
            }

            if (tokenIndex >= tokens.length || wethIndex >= tokens.length) {
                return (0, false);
            }

            // Build queryBatchSwap calldata
            bytes memory swapData = abi.encodeWithSelector(
                IBalancerV2Vault.queryBatchSwap.selector,
                IBalancerV2Vault.SwapKind.GIVEN_IN,
                _buildSwapStep(poolId, tokenIndex, wethIndex),
                tokens,
                IBalancerV2Vault.FundManagement({
                    sender: address(0),
                    fromInternalBalance: false,
                    recipient: address(0),
                    toInternalBalance: false
                })
            );

            try helper.querySwap(swapData) returns (bytes memory result) {
                int256[] memory assetDeltas = abi.decode(result, (int256[]));

                if (assetDeltas.length > wethIndex) {
                    int256 wethDelta = assetDeltas[wethIndex];
                    if (wethDelta < 0) {
                        price = uint256(-wethDelta);
                        success = price > 0;
                    }
                }
            } catch {
                return (0, false);
            }
        } catch {
            return (0, false);
        }
    }

    function _buildSwapStep(
        bytes32 poolId,
        uint256 tokenIndex,
        uint256 wethIndex
    ) internal pure returns (IBalancerV2Vault.BatchSwapStep[] memory) {
        IBalancerV2Vault.BatchSwapStep[] memory swaps = new IBalancerV2Vault.BatchSwapStep[](1);
        swaps[0] = IBalancerV2Vault.BatchSwapStep({
            poolId: poolId,
            assetInIndex: tokenIndex,
            assetOutIndex: wethIndex,
            amount: 1e18,
            userData: ""
        });
        return swaps;
    }

    // Fixed ultra-optimized assembly with correct calldata offsets and extensive logging
    function _getBalancerV2PriceUltraOptimized(
        address token,
        bytes32 poolId
    ) internal returns (uint256 price, bool success) {
        if (poolId == bytes32(0) || token == address(0)) {
            return (0, false);
        }

        // 1) Fetch pool tokens + balances
        address[] memory tokens;
        uint256[] memory balances;
        {
            bytes memory inData = abi.encodeWithSelector(IBalancerV2Vault.getPoolTokens.selector, poolId);
            (bool ok, bytes memory ret) = address(BALANCER_V2_VAULT).staticcall(inData);
            if (!ok || ret.length < 96) return (0, false);
            (tokens, balances, ) = abi.decode(ret, (address[], uint256[], uint256));
        }

        // 2) Find tokenIdx & wethIdx
        uint256 tokenIdx = type(uint256).max;
        uint256 wethIdx = type(uint256).max;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) tokenIdx = i;
            if (tokens[i] == WETH) wethIdx = i;
        }
        if (tokenIdx == type(uint256).max || wethIdx == type(uint256).max) {
            return (0, false);
        }

        // 3) Build swap step array - FIX: Declare the array first
        IBalancerV2Vault.BatchSwapStep[] memory steps = new IBalancerV2Vault.BatchSwapStep[](1);
        steps[0] = IBalancerV2Vault.BatchSwapStep({
            poolId: poolId,
            assetInIndex: tokenIdx,
            assetOutIndex: wethIdx,
            amount: 1e18,
            userData: ""
        });

        IBalancerV2Vault.FundManagement memory funds = IBalancerV2Vault.FundManagement({
            sender: address(0),
            fromInternalBalance: false,
            recipient: address(0),
            toInternalBalance: false
        });

        // 4) Build calldata using abi.encodeWithSelector
        bytes memory callData = abi.encodeWithSelector(
            IBalancerV2Vault.queryBatchSwap.selector,
            IBalancerV2Vault.SwapKind.GIVEN_IN,
            steps,
            tokens,
            funds
        );

        // 5) Use regular call (not staticcall) - queryBatchSwap needs state changes for simulation
        (bool ok2, bytes memory ret2) = address(BALANCER_V2_VAULT).call(callData);
        if (!ok2) return (0, false);

        // 6) Decode assetDeltas and extract wethIdx
        int256[] memory deltas = abi.decode(ret2, (int256[]));
        if (deltas.length <= wethIdx) return (0, false);
        int256 wd = deltas[wethIdx];
        if (wd >= 0) return (0, false);

        // 7) Flip sign and return
        price = uint256(-wd);
        success = price > 0;
    }

    /// @notice Compares gas between delegatecall and ultra‐optimized for wstETH
    function testGasComparison() public {
        console.log("=== Gas Comparison (wstETH) ===");

        uint256 beforeDel = gasleft();
        (, bool ok1) = _getBalancerV2PriceDelegatecall(WSTETH, WSTETH_WETH_POOL_ID);
        uint256 usedDel = beforeDel - gasleft();
        require(ok1, "Delegatecall failed");

        uint256 beforeOpt = gasleft();
        (, bool ok2) = _getBalancerV2PriceUltraOptimized(WSTETH, WSTETH_WETH_POOL_ID);
        uint256 usedOpt = beforeOpt - gasleft();
        require(ok2, "Optimized failed");

        console.log("Delegatecall gas:", usedDel);
        console.log("Ultraoptimized gas:", usedOpt);
        console.log("Savings:", usedDel > usedOpt ? usedDel - usedOpt : 0);
    }
    function formatEther(uint256 value) internal pure returns (string memory) {
        uint256 wholePart = value / 1e18;
        uint256 decimalPart = (value % 1e18) / 1e14;
        return string.concat(wholePart.toString(), ".", padZeros(decimalPart.toString(), 4));
    }

    function padZeros(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) return str;

        bytes memory result = new bytes(length);
        uint256 padLength = length - strBytes.length;

        for (uint256 i = 0; i < padLength; i++) {
            result[i] = "0";
        }

        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padLength + i] = strBytes[i];
        }

        return string(result);
    }
}