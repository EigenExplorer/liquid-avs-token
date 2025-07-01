/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

interface IERC20Extended {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function totalSupply() external view returns (uint256);
}

// Check if token has pause functionality
interface IPausable {
    function paused() external view returns (bool);
}

// Check if token has whitelist
interface IWhitelist {
    function whitelisted(address account) external view returns (bool);
    function isWhitelisted(address account) external view returns (bool);
}

// Owner/admin functions
interface IOwnable {
    function owner() external view returns (address);
    function admin() external view returns (address);
}

interface IWETH {
    function deposit() external payable;
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

contract StBTCTokenAnalysis is Test {
    IERC20Extended public constant WBTC =
        IERC20Extended(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20Extended public constant stBTC =
        IERC20Extended(0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3);
    IWETH public constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV3Router public constant router =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address constant UNISWAP_POOL = 0x242017eE869bF0734Bc5E4feb086A52e6391Dd0d;

    function setUp() public {
        vm.createFork("https://ethereum-rpc.publicnode.com");
        vm.deal(address(this), 10 ether);
    }

    function testTokenRestrictions() public {
        console.log("=== ANALYZING stBTC TOKEN RESTRICTIONS ===");

        // Basic info
        console.log("Name:", stBTC.name());
        console.log("Symbol:", stBTC.symbol());
        console.log("Decimals:", stBTC.decimals());
        console.log("Total Supply:", stBTC.totalSupply());

        // Check if token is pausable
        try IPausable(address(stBTC)).paused() returns (bool paused) {
            console.log("Token is pausable. Currently paused:", paused);
        } catch {
            console.log(
                "Token is not pausable or paused() function doesn't exist"
            );
        }

        // Check ownership
        try IOwnable(address(stBTC)).owner() returns (address owner) {
            console.log("Token owner:", owner);
        } catch {
            try IOwnable(address(stBTC)).admin() returns (address admin) {
                console.log("Token admin:", admin);
            } catch {
                console.log("No owner/admin function found");
            }
        }

        // Check if we're whitelisted
        try IWhitelist(address(stBTC)).whitelisted(address(this)) returns (
            bool whitelisted
        ) {
            console.log("Are we whitelisted?", whitelisted);
        } catch {
            try
                IWhitelist(address(stBTC)).isWhitelisted(address(this))
            returns (bool whitelisted) {
                console.log("Are we whitelisted?", whitelisted);
            } catch {
                console.log("No whitelist function found");
            }
        }

        // Check router whitelist
        try IWhitelist(address(stBTC)).whitelisted(address(router)) returns (
            bool whitelisted
        ) {
            console.log("Is Uniswap router whitelisted?", whitelisted);
        } catch {
            console.log("Router whitelist check failed");
        }
    }

    function testDirectTransfer() public {
        console.log("=== TESTING DIRECT TOKEN TRANSFERS ===");

        // Get some stBTC from the pool (impersonate pool)
        vm.startPrank(UNISWAP_POOL);

        uint256 poolBalance = stBTC.balanceOf(UNISWAP_POOL);
        console.log("Pool stBTC balance:", poolBalance);

        if (poolBalance > 0) {
            uint256 transferAmount = 1e17; // 0.1 stBTC
            console.log(
                "Attempting to transfer",
                transferAmount,
                "stBTC from pool to us"
            );

            try stBTC.transfer(address(this), transferAmount) returns (
                bool success
            ) {
                console.log("Direct transfer successful:", success);
                console.log(
                    "Our stBTC balance:",
                    stBTC.balanceOf(address(this))
                );
            } catch Error(string memory reason) {
                console.log("Direct transfer failed:", reason);
            } catch {
                console.log("Direct transfer failed with unknown error");
            }
        }

        vm.stopPrank();
    }

    function testApprovalMechanism() public {
        console.log("=== TESTING APPROVAL MECHANISM ===");

        // Get WBTC first
        WETH.deposit{value: 1 ether}();
        IERC20Extended(address(WETH)).approve(
            address(router),
            type(uint256).max
        );

        IUniswapV3Router.ExactInputSingleParams
            memory wbtcParams = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(WBTC),
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(wbtcParams);
        uint256 wbtcBalance = WBTC.balanceOf(address(this));
        console.log("WBTC balance:", wbtcBalance);

        // Test different approval methods for stBTC swap
        console.log("\n--- Testing WBTC approval for stBTC swap ---");

        // Method 1: Standard approval
        console.log(
            "Current WBTC allowance:",
            WBTC.allowance(address(this), address(router))
        );
        WBTC.approve(address(router), 0); // Reset
        WBTC.approve(address(router), 100000); // Small amount
        console.log(
            "After small approval:",
            WBTC.allowance(address(this), address(router))
        );

        // Try swap with correct fee (500)
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: address(WBTC),
                tokenOut: address(stBTC),
                fee: 500, // Correct fee from pool analysis
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 50000, // 0.0005 WBTC
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        console.log("Attempting swap with fee 500...");
        try router.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("SUCCESS! Amount out:", amountOut);
        } catch Error(string memory reason) {
            console.log("Failed with reason:", reason);
        } catch (bytes memory lowLevel) {
            console.log("Failed with low-level error");
            console.logBytes(lowLevel);
        }
    }

    function testWithWhale() public {
        console.log("=== TESTING WITH KNOWN stBTC HOLDER ===");

        // Try to find a real stBTC holder
        address[] memory potentialHolders = new address[](3);
        potentialHolders[0] = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // Vitalik (might have some)
        potentialHolders[1] = 0x28C6c06298d514Db089934071355E5743bf21d60; // Binance
        potentialHolders[2] = 0x742D35cC6634c0532925A3B8D8Cc4a45b2d2C7EA; // Another known holder

        for (uint i = 0; i < potentialHolders.length; i++) {
            address holder = potentialHolders[i];
            uint256 balance = stBTC.balanceOf(holder);
            console.log("Holder", i, "balance:", balance);

            if (balance > 1e18) {
                // More than 1 stBTC
                console.log("Found whale! Testing with", holder);

                vm.startPrank(holder);

                // Test approval
                try stBTC.approve(address(router), 1e18) returns (
                    bool success
                ) {
                    console.log("Whale approval successful:", success);

                    // Test swap stBTC -> WBTC
                    IUniswapV3Router.ExactInputSingleParams
                        memory params = IUniswapV3Router
                            .ExactInputSingleParams({
                                tokenIn: address(stBTC),
                                tokenOut: address(WBTC),
                                fee: 500,
                                recipient: holder,
                                deadline: block.timestamp + 300,
                                amountIn: 1e17, // 0.1 stBTC
                                amountOutMinimum: 0,
                                sqrtPriceLimitX96: 0
                            });

                    try router.exactInputSingle(params) returns (
                        uint256 amountOut
                    ) {
                        console.log(
                            "Whale swap successful! WBTC out:",
                            amountOut
                        );
                        break; // Success, no need to try other whales
                    } catch {
                        console.log("Whale swap failed");
                    }
                } catch {
                    console.log("Whale approval failed");
                }

                vm.stopPrank();
            }
        }
    }

    function testContractBytecode() public view {
        console.log("=== ANALYZING CONTRACT BYTECODE ===");

        // Check if it's a proxy
        bytes32 implementationSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );
        bytes32 implementation = vm.load(address(stBTC), implementationSlot);

        if (implementation != bytes32(0)) {
            console.log("stBTC is a proxy!");
            console.log(
                "Implementation:",
                address(uint160(uint256(implementation)))
            );
        } else {
            console.log("stBTC is not a proxy or uses different pattern");
        }

        // Check contract size
        uint256 size;
        assembly {
            size := extcodesize(0xf6718b2701D4a6498eF77D7c152b2137Ab28b8A3)
        }
        console.log("Contract size:", size, "bytes");

        if (size == 0) {
            console.log("WARNING: Contract has no code!");
        }
    }

    function testSimpleSwapWithCorrectFee() public {
        console.log("=== TESTING WITH CORRECT FEE AND MINIMAL SETUP ===");

        // Get WBTC
        WETH.deposit{value: 2 ether}();
        IERC20Extended(address(WETH)).approve(
            address(router),
            type(uint256).max
        );

        IUniswapV3Router.ExactInputSingleParams
            memory wbtcParams = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(WBTC),
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 2 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(wbtcParams);
        console.log("WBTC received:", WBTC.balanceOf(address(this)));

        // Approve WBTC
        WBTC.approve(address(router), type(uint256).max);

        // Try with correct fee (500 not 3000)
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: address(WBTC),
                tokenOut: address(stBTC),
                fee: 500, // CORRECT FEE!
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: 100000, // 0.001 WBTC
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        console.log("Trying swap with correct fee (500)...");
        try router.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("SUCCESS! stBTC received:", amountOut);
            console.log("Our stBTC balance:", stBTC.balanceOf(address(this)));
        } catch Error(string memory reason) {
            console.log("Still failed with reason:", reason);
        } catch (bytes memory data) {
            console.log("Still failed with data:");
            console.logBytes(data);
        }
    }

    receive() external payable {}
}
*/