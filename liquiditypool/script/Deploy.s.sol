// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenWithMint} from "../src/TokenWithMint.sol";
import {Vm} from "forge-std/Vm.sol";

// Interface definitions
interface ICurveFactory {
    function deploy_plain_pool(
        string calldata _name,
        string calldata _symbol,
        address[4] calldata _coins,
        uint256 _A,
        uint256 _fee,
        uint256 _asset_type,
        uint256 _implementation_idx
    ) external returns (address);

    function deploy_metapool(
        address _base_pool,
        string calldata _name,
        string calldata _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee,
        uint256 _implementation_idx
    ) external returns (address);

    function deploy_gauge(address _pool) external returns (address);
}

interface ICurvePool {
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external returns (uint256);
    function add_liquidity(
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
}

interface IMetaPool {
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract CurvePoolProductionDeployer is Script {
    // Constants - Mainnet contracts
    address constant CURVE_FACTORY = 0xB9fC157394Af804a3578134A6585C0dc9cc990d4;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant SBTC_POOL = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714;
    address constant EIGEN_TOKEN = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address constant ARPA_TOKEN = 0xBA50933C268F567BDC86E1aC131BE072C6B0b71a;
    address constant SBTC_LP_TOKEN = 0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3;

    // Pool configuration
    uint256 constant A_PARAM = 100;
    uint256 constant FEE = 4_000_000; // 4 bps
    uint256 constant INIT_SUPPLY = 10_000_000 ether;

    // Configurable liquidity amounts (will be loaded from environment)
    uint256 public ethPeggedLiquidity;
    uint256 public btcPeggedLiquidity;
    uint256 public eigenDALiquidity;
    uint256 public arpaLiquidity;

    // Deployed tokens
    address public xEigenDAETH;
    address public xEigenDABTC;
    address public xEigenDA;
    address public xARPA;

    // Deployed pools and gauges
    struct DeployedPool {
        address pool;
        address gauge;
        uint256 initialLP;
        string name;
    }

    DeployedPool public ethPeggedPool;
    DeployedPool public btcPeggedPool;
    DeployedPool public eigenDAPool;
    DeployedPool public arpaPool;

    // Main entry point
    function run() public payable {
        // Load environment variables for liquidity amounts
        loadLiquidityConfig();

        // Get deployer and show initial balance
        address deployer = msg.sender;
        console.log("\n=== CURVE DEPLOYMENT STARTING ===");
        console.log("Deployer address:", deployer);
        console.log("Initial ETH balance:", deployer.balance / 1e18, "ETH");
        console.log(
            "Contract received ETH:",
            address(this).balance / 1e18,
            "ETH"
        );

        // Calculate total ETH needed for ETH pools
        uint256 totalEthNeeded = ethPeggedLiquidity +
            eigenDALiquidity +
            arpaLiquidity;
        require(
            address(this).balance >= totalEthNeeded,
            "Insufficient ETH sent to contract for all pools"
        );

        // 1. Deploy tokens
        deployTokens();

        // 2. Deploy each pool and its gauge, adding initial liquidity
        deployETHPeggedPool();
        deployBTCPeggedPool();
        deployNativeLATPools();

        // 3. Final summary
        printSummary();

        // Return any remaining ETH
        recoverETH(deployer);
    }

    // Load configurable liquidity amounts from environment
    function loadLiquidityConfig() private {
        ethPeggedLiquidity = vm.envOr("ETH_PEGGED_LIQUIDITY", uint256(1 ether));
        btcPeggedLiquidity = vm.envOr("BTC_PEGGED_LIQUIDITY", uint256(1 ether));
        eigenDALiquidity = vm.envOr("XEIGENDA_ETH_LIQUIDITY", uint256(1 ether));
        arpaLiquidity = vm.envOr("XARPA_ETH_LIQUIDITY", uint256(1 ether));

        console.log("Liquidity configuration:");
        console.log("- ETH-pegged pool:", ethPeggedLiquidity / 1e18, "ETH");
        console.log(
            "- BTC-pegged pool:",
            btcPeggedLiquidity / 1e18,
            "BTC equivalent"
        );
        console.log("- xEigenDA/ETH pool:", eigenDALiquidity / 1e18, "ETH");
        console.log("- xARPA/ETH pool:", arpaLiquidity / 1e18, "ETH");
    }

    // ETH Recovery Function
    function recoverETH(address recipient) public {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            console.log("Returning remaining ETH to", recipient, ":");
            console.log(balance / 1e18, "ETH");
            (bool success, ) = recipient.call{value: balance}("");
            require(success, "ETH transfer failed");
        }
    }

    // -------- TOKEN DEPLOYMENT --------
    function deployTokens() public {
        console.log("\n=== DEPLOYING LAT TOKENS ===");

        // Deploy xEigenDA-ETH token
        TokenWithMint xEigenDAETHToken = new TokenWithMint(
            "xEigenDA-ETH",
            "xEDAE",
            address(this)
        );
        xEigenDAETHToken.mint(address(this), INIT_SUPPLY); // Mint to the contract
        xEigenDAETH = address(xEigenDAETHToken);
        console.log("xEigenDA-ETH deployed at:", xEigenDAETH);
        console.log(
            "Contract balance of xEigenDA-ETH:",
            IERC20(xEigenDAETH).balanceOf(address(this))
        );

        // Deploy xEigenDA-BTC token
        TokenWithMint xEigenDABTCToken = new TokenWithMint(
            "xEigenDA-BTC",
            "xEDAB",
            address(this)
        );
        xEigenDABTCToken.mint(address(this), INIT_SUPPLY); // Mint to the contract
        xEigenDABTC = address(xEigenDABTCToken);
        console.log("xEigenDA-BTC deployed at:", xEigenDABTC);

        // Deploy xEigenDA token
        TokenWithMint xEigenDAToken = new TokenWithMint(
            "xEigenDA",
            "xEDA",
            address(this)
        );
        xEigenDAToken.mint(address(this), INIT_SUPPLY); // Mint to the contract
        xEigenDA = address(xEigenDAToken);
        console.log("xEigenDA deployed at:", xEigenDA);

        // Deploy xARPA token
        TokenWithMint xARPAToken = new TokenWithMint(
            "xARPA",
            "xARPA",
            address(this)
        );
        xARPAToken.mint(address(this), INIT_SUPPLY); // Mint to the contract
        xARPA = address(xARPAToken);
        console.log("xARPA deployed at:", xARPA);
    }

    // -------- POOL DEPLOYMENTS --------
    function deployETHPeggedPool() public {
        console.log("\n=== DEPLOYING ETH-PEGGED POOL ===");

        // 1. Deploy pool
        address[4] memory coins = [xEigenDAETH, WETH, address(0), address(0)];

        address pool = ICurveFactory(CURVE_FACTORY).deploy_plain_pool(
            "xEigenDA-ETH/ETH Pool",
            "xEDAE-ETH",
            coins,
            A_PARAM,
            FEE,
            0, // ETH type
            0 // implementation idx
        );

        ethPeggedPool.pool = pool;
        ethPeggedPool.name = "ETH-pegged Pool";
        console.log("ETH-pegged Pool deployed at:", pool);

        // 2. Add initial liquidity
        // Check ETH balance before proceeding
        uint256 contractBalance = address(this).balance;
        console.log("Contract ETH balance:", contractBalance / 1e18, "ETH");
        require(
            contractBalance >= ethPeggedLiquidity,
            "Insufficient ETH for ETH-pegged pool liquidity"
        );

        // First get some WETH - carefully track ETH usage
        IWETH(WETH).deposit{value: ethPeggedLiquidity}();
        console.log("Converted", ethPeggedLiquidity / 1e18, "ETH to WETH");

        // Approve tokens
        IERC20(xEigenDAETH).approve(pool, ethPeggedLiquidity);
        IERC20(WETH).approve(pool, ethPeggedLiquidity);

        // Add balanced liquidity
        uint256[2] memory amounts = [ethPeggedLiquidity, ethPeggedLiquidity];
        uint256 lpTokens = ICurvePool(pool).add_liquidity(amounts, 0);

        ethPeggedPool.initialLP = lpTokens;
        console.log("Added initial liquidity:");
        console.log("- xEigenDA-ETH:", ethPeggedLiquidity / 1e18);
        console.log("- WETH:", ethPeggedLiquidity / 1e18);
        console.log("- LP tokens:", lpTokens);

        // 3. Deploy gauge
        address gauge = ICurveFactory(CURVE_FACTORY).deploy_gauge(pool);
        ethPeggedPool.gauge = gauge;
        console.log("ETH-pegged Gauge deployed at:", gauge);
    }

    function deployBTCPeggedPool() public {
        console.log("\n=== DEPLOYING BTC-PEGGED METAPOOL ===");

        // 1. Deploy metapool with our token and real sBTC LP token
        address metapool = ICurveFactory(CURVE_FACTORY).deploy_metapool(
            SBTC_POOL,
            "xEigenDA-BTC/BTC Pool",
            "xEDAB-BTC",
            xEigenDABTC,
            A_PARAM,
            FEE,
            0 // implementation idx
        );

        btcPeggedPool.pool = metapool;
        btcPeggedPool.name = "BTC-pegged Metapool";
        console.log("BTC-pegged Metapool deployed at:", metapool);

        // 2. Check for sBTC LP tokens in sender's wallet
        uint256 sbtcLPBalance = IERC20(SBTC_LP_TOKEN).balanceOf(msg.sender);
        console.log("Sender's sBTC LP token balance:", sbtcLPBalance);

        // 3. Add initial liquidity if we have sBTC LP tokens
        if (btcPeggedLiquidity > 0 && sbtcLPBalance > 0) {
            // Determine the amount of sBTC LP tokens to use
            uint256 lpAmount = btcPeggedLiquidity / 10; // Scale for BTC value

            if (sbtcLPBalance < lpAmount) {
                lpAmount = sbtcLPBalance; // Use what's available
            }

            // Transfer sBTC LP tokens from sender to this contract
            bool success = IERC20(SBTC_LP_TOKEN).transferFrom(
                msg.sender,
                address(this),
                lpAmount
            );
            require(success, "Failed to transfer sBTC LP tokens");
            console.log("Transferred sBTC LP tokens to contract:", lpAmount);

            // Approve tokens for metapool
            IERC20(xEigenDABTC).approve(metapool, btcPeggedLiquidity);
            IERC20(SBTC_LP_TOKEN).approve(metapool, lpAmount);

            // Add liquidity
            uint256[2] memory metaAmounts = [btcPeggedLiquidity, lpAmount];

            try IMetaPool(metapool).add_liquidity(metaAmounts, 0) returns (
                uint256 metaLpTokens
            ) {
                btcPeggedPool.initialLP = metaLpTokens;
                console.log("Added initial liquidity to BTC Metapool:");
                console.log("- xEigenDA-BTC:", btcPeggedLiquidity);
                console.log("- sBTC LP:", lpAmount);
                console.log("- LP tokens:", metaLpTokens);
            } catch {
                console.log("Failed to add liquidity to BTC metapool");
                console.log(
                    "You can add liquidity later using the add_liquidity function"
                );
            }
        } else {
            console.log("Note: No initial liquidity added to BTC metapool");
            console.log("sBTC LP token address:", SBTC_LP_TOKEN);
            console.log(
                "You'll need to acquire these tokens to add liquidity later"
            );
        }

        // 4. Deploy gauge
        address metaGauge = ICurveFactory(CURVE_FACTORY).deploy_gauge(metapool);
        btcPeggedPool.gauge = metaGauge;
        console.log("BTC-pegged Gauge deployed at:", metaGauge);
    }

    function deployNativeLATPool(
        address token,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 liquidityAmount,
        DeployedPool storage deployedPool
    ) internal {
        console.log("\n=== DEPLOYING", tokenName, "/ETH POOL ===");

        // 1. Deploy pool with proper naming
        address[4] memory coins = [token, WETH, address(0), address(0)];

        // Fix the name and symbol
        string memory poolName = string(
            abi.encodePacked(tokenName, "/ETH Pool")
        );
        string memory poolSymbol = string(
            abi.encodePacked(tokenSymbol, "-ETH")
        );

        console.log("Creating pool with name:", poolName);
        console.log("And symbol:", poolSymbol);

        address pool = ICurveFactory(CURVE_FACTORY).deploy_plain_pool(
            poolName,
            poolSymbol,
            coins,
            A_PARAM,
            FEE,
            0, // ETH type
            0 // implementation idx
        );

        deployedPool.pool = pool;
        deployedPool.name = poolName;
        console.log(tokenName, "/ETH Pool deployed at:", pool);

        // 2. Add initial liquidity if we have enough ETH
        uint256 contractBalance = address(this).balance;
        console.log(
            "Contract ETH balance before WETH conversion:",
            contractBalance / 1e18,
            "ETH"
        );

        if (contractBalance >= liquidityAmount && liquidityAmount > 0) {
            // Get some WETH with careful error handling
            try IWETH(WETH).deposit{value: liquidityAmount}() {
                console.log(
                    "Converted",
                    liquidityAmount / 1e18,
                    "ETH to WETH for"
                );
                console.log(tokenName, "pool");

                // Approve tokens
                IERC20(token).approve(pool, liquidityAmount);
                IERC20(WETH).approve(pool, liquidityAmount);

                // Add balanced liquidity
                uint256[2] memory amounts = [liquidityAmount, liquidityAmount];
                uint256 lpTokens = ICurvePool(pool).add_liquidity(amounts, 0);

                deployedPool.initialLP = lpTokens;
                console.log("Added initial liquidity to", tokenName, "pool:");
                console.log("-", tokenName, ":", liquidityAmount / 1e18);
                console.log("- WETH:", liquidityAmount / 1e18);
                console.log("- LP tokens:", lpTokens);
            } catch {
                console.log("Failed to add liquidity to", tokenName, "pool");
            }
        } else {
            console.log(
                "Insufficient ETH to add liquidity to",
                tokenName,
                "pool"
            );
        }

        // 3. Deploy gauge
        address gauge = ICurveFactory(CURVE_FACTORY).deploy_gauge(pool);
        deployedPool.gauge = gauge;
        console.log(tokenName, "/ETH Gauge deployed at:", gauge);
    }

    function deployNativeLATPools() public {
        console.log("\n=== DEPLOYING NATIVE LAT POOLS ===");
        console.log(
            "Contract ETH balance:",
            address(this).balance / 1e18,
            "ETH"
        );
        console.log(
            "Required ETH for both pools:",
            (eigenDALiquidity + arpaLiquidity) / 1e18,
            "ETH"
        );

        // Deploy xEigenDA/ETH pool with configurable liquidity
        deployNativeLATPool(
            xEigenDA,
            "xEigenDA",
            "xEDA",
            eigenDALiquidity,
            eigenDAPool
        );

        // Deploy xARPA/ETH pool with configurable liquidity
        deployNativeLATPool(xARPA, "xARPA", "xARPA", arpaLiquidity, arpaPool);
    }

    // -------- SUMMARY --------
    function printSummary() public view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");

        console.log("\n--- DEPLOYED TOKENS ---");
        console.log("xEigenDA-ETH:", xEigenDAETH);
        console.log("xEigenDA-BTC:", xEigenDABTC);
        console.log("xEigenDA:", xEigenDA);
        console.log("xARPA:", xARPA);

        console.log("\n--- DEPLOYED POOLS AND GAUGES ---");
        logPoolDetails(ethPeggedPool);
        logPoolDetails(btcPeggedPool);
        logPoolDetails(eigenDAPool);
        logPoolDetails(arpaPool);

        console.log("\n=== DEPLOYMENT COMPLETE ===");
    }

    function logPoolDetails(DeployedPool memory pool) internal view {
        console.log("- ", pool.name, ":");
        console.log("  Pool:", pool.pool);
        console.log("  Gauge:", pool.gauge);
        console.log("  Initial LP:", pool.initialLP);
        if (pool.pool != address(0)) {
            try ICurvePool(pool.pool).get_virtual_price() returns (uint256 vp) {
                console.log("  Virtual Price:", vp);
            } catch {
                console.log("  Virtual Price: Unable to fetch");
            }
        }
    }

    receive() external payable {}
    fallback() external payable {}
}