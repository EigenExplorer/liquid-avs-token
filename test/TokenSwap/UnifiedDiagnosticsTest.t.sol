// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

interface ICurvePool {
    function exchange(
        int128 i, // Changed from uint256 to int128
        int128 j, // Changed from uint256 to int128
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);

    function get_dy(
        int128 i, // Changed from uint256 to int128
        int128 j, // Changed from uint256 to int128
        uint256 dx
    ) external view returns (uint256);

    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
}

interface IFrxETHMinter {
    function submitAndDeposit(
        address recipient
    ) external payable returns (uint256 shares);
    function submitPaused() external view returns (bool);
    function submit() external payable returns (uint256 shares);
    function withholdRatio() external view returns (uint256);
    function owner() external view returns (address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function symbol() external view returns (string memory);
}

contract UnifiedDiagnosticsTest is Test {
    uint256 constant FORK_BLOCK = 19500000;
    uint256 constant TEST_AMOUNT = 1e18;

    // Tokens
    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    address constant FRXETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;

    // Pools
    address constant ETHX_POOL = 0x59Ab5a5b5d617E478a2479B0cAD80DA7e2831492;
    address constant FRXETH_POOL = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address constant STETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant ANKRETH_POOL = 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;

    // Contracts
    address constant FRXETH_MINTER = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
    address constant WHALE = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;

    function setUp() public {
        vm.createSelectFork("https://core.gashawk.io/rpc", FORK_BLOCK);
        vm.deal(WHALE, 10e18);
    }

    function testAllDiagnostics() public {
        console.log("=== UNIFIED DIAGNOSTICS TEST ===");
        console.log("Fork Block:", FORK_BLOCK);
        console.log("Test Amount:", TEST_AMOUNT);
        console.log("Test User:", WHALE);
        console.log("");

        testCurvePools();
        testDirectMint();
        testContractBehaviorMimic();

        console.log("=== DIAGNOSTICS COMPLETE ===");
    }

    function testCurvePools() internal {
        console.log("=== CURVE POOL DIAGNOSTICS ===");
        console.log("");

        console.log("--- Testing ETHx Pool ---");
        _testCurvePool("ETHx", ETHX_POOL, ETHX);

        console.log("--- Testing frxETH Pool ---");
        _testCurvePool("frxETH", FRXETH_POOL, FRXETH);

        console.log("--- Testing stETH Pool ---");
        _testCurvePool("stETH", STETH_POOL, STETH);

        console.log("--- Testing ankrETH Pool (WORKING REFERENCE) ---");
        _testCurvePool("ankrETH", ANKRETH_POOL, ANKRETH);

        console.log("");
    }

    function _testCurvePool(
        string memory name,
        address pool,
        address targetToken
    ) internal {
        console.log("Pool Name:", name);
        console.log("Pool Address:", pool);
        console.log("Target Token:", targetToken);

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(pool)
        }
        console.log("Pool Code Size:", codeSize);

        if (codeSize == 0) {
            console.log("ERROR: Pool has no code");
            console.log("");
            return;
        }

        console.log("Checking pool tokens...");
        address token0;
        address token1;
        bool hasToken0 = false;
        bool hasToken1 = false;

        try ICurvePool(pool).coins(0) returns (address t0) {
            token0 = t0;
            hasToken0 = true;
            console.log("Token 0:", token0);
        } catch {
            console.log("ERROR: Cannot read token 0");
        }

        try ICurvePool(pool).coins(1) returns (address t1) {
            token1 = t1;
            hasToken1 = true;
            console.log("Token 1:", token1);
        } catch {
            console.log("ERROR: Cannot read token 1");
        }

        if (hasToken0 && hasToken1) {
            bool hasETH = (token0 == ETH_ADDRESS || token1 == ETH_ADDRESS);
            bool hasTarget = (token0 == targetToken || token1 == targetToken);
            console.log("Has ETH:", hasETH);
            console.log("Has Target Token:", hasTarget);

            if (!hasETH || !hasTarget) {
                console.log("ERROR: Pool tokens don't match expected");
            }
        }

        console.log("Checking pool balances...");
        try ICurvePool(pool).balances(0) returns (uint256 bal0) {
            console.log("Balance 0:", bal0);
            if (bal0 == 0) console.log("WARNING: Balance 0 is zero");
        } catch {
            console.log("ERROR: Cannot read balance 0");
        }

        try ICurvePool(pool).balances(1) returns (uint256 bal1) {
            console.log("Balance 1:", bal1);
            if (bal1 == 0) console.log("WARNING: Balance 1 is zero");
        } catch {
            console.log("ERROR: Cannot read balance 1");
        }

        console.log("Testing get_dy quote...");
        try ICurvePool(pool).get_dy(int128(0), int128(1), TEST_AMOUNT) returns (
            uint256 quote
        ) {
            console.log("Quote Result:", quote);
            if (quote == 0) console.log("ERROR: Zero quote returned");
        } catch Error(string memory reason) {
            console.log("ERROR: get_dy failed");
            console.log("Reason:", reason);
        } catch {
            console.log("ERROR: get_dy failed with low-level revert");
        }

        console.log("Testing actual swap...");
        vm.startPrank(WHALE);
        uint256 initialEth = address(WHALE).balance;
        uint256 initialTarget = IERC20(targetToken).balanceOf(WHALE);

        uint256 gasBefore = gasleft();
        try
            ICurvePool(pool).exchange{value: TEST_AMOUNT}(
                int128(0),
                int128(1),
                TEST_AMOUNT,
                0
            )
        returns (uint256 result) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("SUCCESS: Swap completed");
            console.log("Output Amount:", result);
            console.log("Gas Used:", gasUsed);

            // Verify balances
            uint256 finalEth = address(WHALE).balance;
            uint256 finalTarget = IERC20(targetToken).balanceOf(WHALE);

            console.log("ETH Balance Change:", initialEth - finalEth);
            console.log(
                "Target Token Balance Change:",
                finalTarget - initialTarget
            );
        } catch Error(string memory reason) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("ERROR: Swap failed");
            console.log("Reason:", reason);
            console.log("Gas Used:", gasUsed);
        } catch (bytes memory lowLevelData) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("ERROR: Swap failed with low-level revert");
            console.log("Gas Used:", gasUsed);
            if (lowLevelData.length > 0) {
                console.log("Revert Data:");
                console.logBytes(lowLevelData);
            }
        }
        vm.stopPrank();
        console.log("");
    }

    function testDirectMint() internal {
        console.log("=== DIRECT MINT DIAGNOSTICS ===");
        console.log("");

        console.log("frxETH Minter:", FRXETH_MINTER);
        console.log("sfrxETH:", SFRXETH);
        console.log("frxETH:", FRXETH);

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(FRXETH_MINTER)
        }
        console.log("Minter Code Size:", codeSize);

        if (codeSize == 0) {
            console.log("ERROR: Minter has no code");
            return;
        }

        console.log("Checking minter state...");
        try IFrxETHMinter(FRXETH_MINTER).submitPaused() returns (bool paused) {
            console.log("Submit Paused:", paused);
            if (paused) {
                console.log("ERROR: Minter is paused");
                return;
            }
        } catch {
            console.log("ERROR: Cannot check paused state");
        }

        try IFrxETHMinter(FRXETH_MINTER).withholdRatio() returns (
            uint256 ratio
        ) {
            console.log("Withhold Ratio:", ratio);
        } catch {
            console.log("ERROR: Cannot check withhold ratio");
        }

        try IFrxETHMinter(FRXETH_MINTER).owner() returns (address owner) {
            console.log("Minter Owner:", owner);
        } catch {
            console.log("ERROR: Cannot check owner");
        }

        console.log("Balances before mint:");
        console.log("ETH Balance:", address(WHALE).balance); // Fixed address reference
        console.log("sfrxETH Balance:", IERC20(SFRXETH).balanceOf(WHALE));
        console.log("frxETH Balance:", IERC20(FRXETH).balanceOf(WHALE));

        vm.startPrank(WHALE);
        console.log("Testing submitAndDeposit...");
        uint256 gasBefore = gasleft();

        try
            IFrxETHMinter(FRXETH_MINTER).submitAndDeposit{value: TEST_AMOUNT}(
                WHALE
            )
        returns (uint256 shares) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("SUCCESS: submitAndDeposit completed");
            console.log("Shares Received:", shares);
            console.log("Gas Used:", gasUsed);
        } catch Error(string memory reason) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("ERROR: submitAndDeposit failed");
            console.log("Reason:", reason);
            console.log("Gas Used:", gasUsed);

            console.log("Testing submit only...");
            gasBefore = gasleft();
            try
                IFrxETHMinter(FRXETH_MINTER).submit{value: TEST_AMOUNT}()
            returns (uint256 frxShares) {
                gasUsed = gasBefore - gasleft();
                console.log("SUCCESS: submit completed");
                console.log("frxETH Received:", frxShares);
                console.log("Gas Used:", gasUsed);
            } catch Error(string memory reason2) {
                gasUsed = gasBefore - gasleft();
                console.log("ERROR: submit also failed");
                console.log("Reason:", reason2);
                console.log("Gas Used:", gasUsed);
            } catch {
                gasUsed = gasBefore - gasleft();
                console.log("ERROR: submit failed with low-level revert");
                console.log("Gas Used:", gasUsed);
            }
        } catch (bytes memory lowLevelData) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("ERROR: submitAndDeposit failed with low-level revert");
            console.log("Gas Used:", gasUsed);
            if (lowLevelData.length > 0) {
                console.log("Revert Data:");
                console.logBytes(lowLevelData);
            }
        }
        vm.stopPrank();

        console.log("Balances after mint attempt:");
        console.log("ETH Balance:", address(WHALE).balance); // Fixed address reference
        console.log("sfrxETH Balance:", IERC20(SFRXETH).balanceOf(WHALE));
        console.log("frxETH Balance:", IERC20(FRXETH).balanceOf(WHALE));
        console.log("");
    }

    function testContractBehaviorMimic() internal {
        console.log("=== CONTRACT BEHAVIOR MIMIC ===");
        console.log("");

        vm.startPrank(WHALE);
        console.log("--- Mimicking Curve Calls ---");

        console.log("ETHx Pool Call:");
        _mimicCurveCall(ETHX_POOL, "ETHx");

        console.log("frxETH Pool Call:");
        _mimicCurveCall(FRXETH_POOL, "frxETH");

        console.log("stETH Pool Call:");
        _mimicCurveCall(STETH_POOL, "stETH");

        console.log("--- Mimicking DirectMint Call ---");
        _mimicDirectMintCall();

        vm.stopPrank();
        console.log("");
    }

    function _mimicCurveCall(address pool, string memory name) internal {
        uint256 gasBefore = gasleft();
        try
            ICurvePool(pool).exchange{value: TEST_AMOUNT}(
                int128(0),
                int128(1),
                TEST_AMOUNT,
                0
            )
        returns (uint256 result) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("Pool:", name);
            console.log("Status: SUCCESS");
            console.log("Output:", result);
            console.log("Gas Used:", gasUsed);
        } catch Error(string memory reason) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("Pool:", name);
            console.log("Status: FAILED");
            console.log("Error:", reason);
            console.log("Gas Used:", gasUsed);
        } catch {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("Pool:", name);
            console.log("Status: FAILED");
            console.log("Error: Low-level revert");
            console.log("Gas Used:", gasUsed);
        }
        console.log("");
    }

    function _mimicDirectMintCall() internal {
        uint256 gasBefore = gasleft();
        try
            IFrxETHMinter(FRXETH_MINTER).submitAndDeposit{value: TEST_AMOUNT}(
                WHALE
            )
        returns (uint256 result) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("DirectMint Status: SUCCESS");
            console.log("Output:", result);
            console.log("Gas Used:", gasUsed);
        } catch Error(string memory reason) {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("DirectMint Status: FAILED");
            console.log("Error:", reason);
            console.log("Gas Used:", gasUsed);
        } catch {
            uint256 gasUsed = gasBefore - gasleft();
            console.log("DirectMint Status: FAILED");
            console.log("Error: Low-level revert");
            console.log("Gas Used:", gasUsed);
        }
    }
}
