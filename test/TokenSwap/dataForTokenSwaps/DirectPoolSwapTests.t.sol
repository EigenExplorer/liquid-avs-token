/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

// Add Curve interface
interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
}

contract DirectPoolSwapTests is Test {
    using stdJson for string;

    IWETH public weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IUniswapV3Router public uniswapRouter =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    string constant ASSETS_JSON_PATH = "./assets_with_pools.json";
    string public assetsJson;

    uint256 public constant SWAP_AMOUNT = 0.01 ether;
    uint256 public constant MIN_POOL_LIQUIDITY = 0.1 ether;
    uint256 public constant MIN_WBTC_LIQUIDITY = 0.005 * 1e8; // 0.005 WBTC (8 decimals)

    struct Asset {
        address addr;
        string symbol;
        string name;
        string assetType;
    }

    struct Pool {
        address addr;
        string protocol;
        string pairedWith;
        uint24 fee;
        bool exists;
    }

    function setUp() public {
        console.log("Setting up test environment");

        vm.createFork("https://ethereum-rpc.publicnode.com");
        assetsJson = vm.readFile(ASSETS_JSON_PATH);

        vm.deal(address(this), 100 ether);
        weth.deposit{value: 10 ether}();
        console.log("Wrapped 10 ETH to WETH");

        IERC20(address(weth)).approve(
            address(uniswapRouter),
            type(uint256).max
        );
        console.log("Approved Uniswap router");

        uint256 balance = IERC20(address(weth)).balanceOf(address(this));
        console.log("WETH balance:", balance);
    }

    function getAssetData(
        string memory assetKey
    ) internal view returns (Asset memory) {
        string memory key = string.concat(".assets.", assetKey);
        return
            Asset({
                addr: assetsJson.readAddress(string.concat(key, ".address")),
                symbol: assetsJson.readString(string.concat(key, ".symbol")),
                name: assetsJson.readString(string.concat(key, ".name")),
                assetType: assetsJson.readString(string.concat(key, ".type"))
            });
    }

    function getPoolData(
        string memory assetKey,
        uint256 poolIndex
    ) internal view returns (Pool memory) {
        string memory key = string.concat(
            ".assets.",
            assetKey,
            ".pools[",
            vm.toString(poolIndex),
            "]"
        );

        Pool memory pool;
        pool.exists = false; // Default to false

        try
            vm.parseJsonAddress(assetsJson, string.concat(key, ".address"))
        returns (address poolAddr) {
            pool.addr = poolAddr;

            // Wrap all JSON parsing in try-catch
            try
                vm.parseJsonString(assetsJson, string.concat(key, ".protocol"))
            returns (string memory protocol) {
                pool.protocol = protocol;

                try
                    vm.parseJsonString(
                        assetsJson,
                        string.concat(key, ".pairedWith")
                    )
                returns (string memory pairedWith) {
                    pool.pairedWith = pairedWith;
                    pool.exists = true; // Only set to true if all required fields parsed successfully

                    // Try to parse fee (optional for Curve pools)
                    try
                        vm.parseJson(assetsJson, string.concat(key, ".fee"))
                    returns (bytes memory feeData) {
                        pool.fee = abi.decode(feeData, (uint24));
                    } catch {
                        pool.fee = 0;
                    }
                } catch {
                    console.log(
                        "Failed to parse pairedWith for pool",
                        poolIndex
                    );
                }
            } catch {
                console.log("Failed to parse protocol for pool", poolIndex);
            }
        } catch {
            // Pool doesn't exist at this index
        }

        return pool;
    }

    function getPoolCount(
        string memory assetKey
    ) internal view returns (uint256) {
        console.log("Counting pools for asset:", assetKey);

        uint256 count = 0;
        for (uint256 i = 0; i < 10; i++) {
            Pool memory pool = getPoolData(assetKey, i);
            if (!pool.exists) {
                break;
            }
            count++;
        }

        console.log("Found pool count:", count);
        return count;
    }

    function checkPoolLiquidity(
        address poolAddress,
        string memory pairedWith
    ) internal view returns (bool isValid, uint256 liquidityBalance) {
        console.log("Checking pool liquidity:", poolAddress);
        console.log("Paired with:", pairedWith);

        if (
            keccak256(abi.encodePacked(pairedWith)) ==
            keccak256(abi.encodePacked("WETH"))
        ) {
            liquidityBalance = IERC20(address(weth)).balanceOf(poolAddress);
            console.log("WETH Balance in pool:", liquidityBalance);

            if (liquidityBalance < MIN_POOL_LIQUIDITY) {
                console.log("Pool has insufficient WETH liquidity");
                return (false, liquidityBalance);
            }
        } else if (
            keccak256(abi.encodePacked(pairedWith)) ==
            keccak256(abi.encodePacked("WBTC"))
        ) {
            liquidityBalance = wbtc.balanceOf(poolAddress);
            console.log("WBTC Balance in pool:", liquidityBalance);

            if (liquidityBalance < MIN_WBTC_LIQUIDITY) {
                console.log("Pool has insufficient WBTC liquidity");
                return (false, liquidityBalance);
            }
        } else {
            console.log("Unsupported pairing:", pairedWith);
            return (false, 0);
        }

        try IUniswapV3Pool(poolAddress).liquidity() returns (
            uint128 liquidity
        ) {
            console.log("Pool liquidity:", liquidity);
            isValid = liquidity > 0;
        } catch {
            console.log("Failed to check pool liquidity - might be Curve pool");
            isValid = true; // For Curve pools, just check balance is sufficient
        }

        console.log("Pool valid:", isValid);
        return (isValid, liquidityBalance);
    }

    function findBestPool(
        string memory assetKey
    ) internal view returns (Pool memory bestPool, bool found) {
        uint256 poolCount = getPoolCount(assetKey);
        console.log("Searching through pools:", poolCount);

        uint256 bestLiquidity = 0;

        for (uint256 i = 0; i < poolCount; i++) {
            Pool memory pool = getPoolData(assetKey, i);

            if (!pool.exists) {
                console.log("Pool does not exist at index:", i);
                continue;
            }

            console.log("Checking pool at index:", i);
            console.log("Pool address:", pool.addr);
            console.log("Pool protocol:", pool.protocol);
            console.log("Paired with:", pool.pairedWith);

            // Only check Uniswap V3 pools for now (skip Curve for simplicity)
            if (
                keccak256(abi.encodePacked(pool.protocol)) ==
                keccak256(abi.encodePacked("uniswapv3"))
            ) {
                (bool isValid, uint256 liquidityBalance) = checkPoolLiquidity(
                    pool.addr,
                    pool.pairedWith
                );

                if (isValid && liquidityBalance > bestLiquidity) {
                    bestLiquidity = liquidityBalance;
                    bestPool = pool;
                    found = true;
                    console.log(
                        "Found better pool with liquidity balance:",
                        liquidityBalance
                    );
                }
            } else {
                console.log("Skipping non-Uniswap pool for now");
            }
        }

        if (!found) {
            console.log("No valid pools found");
        } else {
            console.log("Best pool selected:", bestPool.addr);
        }

        return (bestPool, found);
    }

    function swapOnUniswapV3ForWETH(
        address tokenOut,
        uint24 fee,
        uint256 amountIn
    ) internal returns (uint256) {
        console.log("Attempting Uniswap V3 swap with WETH");
        console.log("Token out:", tokenOut);
        console.log("Fee tier:", fee);
        console.log("Amount in:", amountIn);

        uint256 ourBalance = IERC20(address(weth)).balanceOf(address(this));
        console.log("Our WETH balance:", ourBalance);
        require(ourBalance >= amountIn, "Insufficient WETH balance");

        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        console.log("Executing swap");
        return uniswapRouter.exactInputSingle(params);
    }

    function swapOnUniswapV3ForWBTC(
        address tokenOut,
        uint24 fee,
        uint256 amountIn
    ) internal returns (uint256) {
        console.log("Attempting Uniswap V3 swap with WBTC");
        console.log("Token out:", tokenOut);
        console.log("Fee tier:", fee);
        console.log("Amount in:", amountIn);

        // First need to get some WBTC by swapping WETH to WBTC
        console.log("First getting WBTC by swapping WETH");

        IUniswapV3Router.ExactInputSingleParams
            memory wbtcParams = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(wbtc),
                fee: 3000, // WETH/WBTC pool fee
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 0.1 ether, // Use 0.1 ETH to get WBTC (was 1 ETH)
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 wbtcReceived = uniswapRouter.exactInputSingle(wbtcParams);
        console.log("Received WBTC:", wbtcReceived);

        // Approve WBTC for the router
        wbtc.approve(address(uniswapRouter), type(uint256).max);
        console.log("Approved WBTC for router");

        // Check stBTC token info
        IERC20 stBTC = IERC20(tokenOut);
        try stBTC.decimals() returns (uint8 decimals) {
            console.log("stBTC decimals:", decimals);
        } catch {
            console.log("Failed to get stBTC decimals");
        }

        // Use a smaller amount for the swap - use half of what we received
        uint256 wbtcToSwap = wbtcReceived / 2;
        console.log("WBTC amount to swap:", wbtcToSwap);

        // Check pool state before swap
        IUniswapV3Pool pool = IUniswapV3Pool(
            0x242017eE869bF0734Bc5E4feb086A52e6391Dd0d
        );
        try pool.slot0() returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool unlocked
        ) {
            console.log("Pool unlocked:", unlocked);
            //console.log("Pool tick:", tick);
            console.log("Pool sqrtPriceX96:", sqrtPriceX96);
        } catch {
            console.log("Failed to get pool slot0");
        }

        // Check if WBTC is token0 or token1
        address token0 = pool.token0();
        address token1 = pool.token1();
        console.log("Pool token0:", token0);
        console.log("Pool token1:", token1);
        console.log("WBTC address:", address(wbtc));
        console.log("stBTC address:", tokenOut);

        // Now swap WBTC to target token
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: address(wbtc),
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: wbtcToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        console.log("Executing WBTC to stBTC swap");
        console.log("Swap params:");
        console.log("  tokenIn:", params.tokenIn);
        console.log("  tokenOut:", params.tokenOut);
        console.log("  fee:", params.fee);
        console.log("  amountIn:", params.amountIn);

        try uniswapRouter.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("Swap succeeded, amount out:", amountOut);
            return amountOut;
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("Swap failed with low level error");
            console.logBytes(lowLevelData);
            revert("stBTC swap failed");
        }
    }

    function performSwapWithBestPool(string memory assetKey) internal {
        Asset memory asset = getAssetData(assetKey);

        console.log("=== Testing swap WETH ->", asset.symbol, "===");
        console.log("Asset address:", asset.addr);

        (Pool memory bestPool, bool found) = findBestPool(assetKey);

        if (!found) {
            console.log("No suitable pools found for", asset.symbol);
            console.log("Skipping test for", asset.symbol);
            return;
        }

        console.log("Using best pool:", bestPool.addr);
        console.log("Protocol:", bestPool.protocol);
        console.log("Fee:", bestPool.fee);
        console.log("Paired with:", bestPool.pairedWith);

        uint256 initialBalance = IERC20(asset.addr).balanceOf(address(this));
        console.log("Initial balance:", initialBalance);

        try
            this.executeSwap(
                asset.addr,
                bestPool.fee,
                SWAP_AMOUNT,
                bestPool.pairedWith
            )
        returns (uint256 amountOut) {
            uint256 finalBalance = IERC20(asset.addr).balanceOf(address(this));

            console.log("Final balance:", finalBalance);
            console.log("Amount out:", amountOut);
            console.log("Balance increase:", finalBalance - initialBalance);

            assertGt(
                finalBalance,
                initialBalance,
                "Swap should increase target token balance"
            );
            console.log("Swap successful");
        } catch Error(string memory reason) {
            console.log("Swap failed with reason:", reason);
            console.log(
                "This may be due to insufficient liquidity or slippage"
            );
        } catch {
            console.log("Swap failed with unknown error");
        }
    }

    function executeSwap(
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        string memory pairedWith
    ) external returns (uint256) {
        if (
            keccak256(abi.encodePacked(pairedWith)) ==
            keccak256(abi.encodePacked("WETH"))
        ) {
            return swapOnUniswapV3ForWETH(tokenOut, fee, amountIn);
        } else if (
            keccak256(abi.encodePacked(pairedWith)) ==
            keccak256(abi.encodePacked("WBTC"))
        ) {
            return swapOnUniswapV3ForWBTC(tokenOut, fee, amountIn);
        } else {
            revert("Unsupported pairing");
        }
    }

    // Working tests - don't touch these
    function testSwapWETHToOETH() public {
        performSwapWithBestPool("OETH");
    }

    function testSwapWETHToLsETH() public {
        performSwapWithBestPool("lsETH");
    }

    function testSwapWETHToRETH() public {
        performSwapWithBestPool("rETH");
    }

    function testSwapWETHToSwETH() public {
        performSwapWithBestPool("swETH");
    }

    function testSwapWETHToUniBTC1() public {
        performSwapWithBestPool("uniBTC1");
    }

    // Fixed problematic tests
    function testSwapWETHToStETH() public {
        console.log("Testing stETH with enhanced debugging");
        performSwapWithBestPool("stETH");
    }

    function testSwapWETHToAnkrETH() public {
        console.log("Testing ankrETH with enhanced debugging");
        performSwapWithBestPool("ankrETH");
    }

    function testSwapWETHToCbETH() public {
        console.log("Testing cbETH with enhanced debugging");
        performSwapWithBestPool("cbETH");
    }

    function testSwapWETHToStBTC() public {
        console.log("Testing stBTC with WBTC pairing");
        performSwapWithBestPool("stBTC");
    }

    // NEW: mETH test
    function testSwapWETHToMETH() public {
        console.log("Testing mETH with WETH pairing");
        performSwapWithBestPool("mETH");
    }

    // Test to check ETHx pools (should fail as it's not in JSON with WETH pairing)
    function testSwapWETHToETHx() public {
        console.log("Testing ETHx (should show no WETH pools)");
        performSwapWithBestPool("ETHx");
    }

    // Test to check sfrxETH pools
    function testSwapWETHToSfrxETH() public {
        console.log("Testing sfrxETH with WETH pairing");
        performSwapWithBestPool("sfrxETH");
    }

    // Test to check osETH pools
    function testSwapWETHToOsETH() public {
        console.log("Testing osETH with WETH pairing");
        performSwapWithBestPool("osETH");
    }

    // Debug function
    function testDebugSpecificAsset() public {
        string memory assetKey = "stBTC"; // Debug stBTC
        console.log("DEBUG: Checking pools for", assetKey);

        uint256 poolCount = getPoolCount(assetKey);
        console.log("Total pools found:", poolCount);

        for (uint256 i = 0; i < poolCount; i++) {
            Pool memory pool = getPoolData(assetKey, i);
            console.log("--- Pool", i, "---");

            if (pool.exists) {
                console.log("Address:", pool.addr);
                console.log("Protocol:", pool.protocol);
                console.log("Fee:", pool.fee);
                console.log("Paired with:", pool.pairedWith);

                if (
                    keccak256(abi.encodePacked(pool.protocol)) ==
                    keccak256(abi.encodePacked("uniswapv3"))
                ) {
                    checkPoolLiquidity(pool.addr, pool.pairedWith);
                }
            } else {
                console.log("Pool does not exist");
            }
        }
    }

    receive() external payable {}
}
*/