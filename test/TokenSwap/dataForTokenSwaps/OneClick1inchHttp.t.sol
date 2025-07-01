/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "solidity-http/HTTP.sol"; // solidity-http library

interface IWETH {
    function deposit() external payable;
    function approve(address, uint256) external returns (bool);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

// Updated to V6 interface (your router address is V6)
interface IAggregationRouterV6 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }
    function swap(
        address caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount);
}

// Simplified 1inch wrapper
contract OneClick1inch {
    IAggregationRouterV6 public constant ROUTER =
        IAggregationRouterV6(0x111111125421cA6dc452d289314280a0f8842A65);

    function swap(
        IAggregationRouterV6.SwapDescription calldata desc,
        bytes calldata callData
    ) external payable {
        require(
            IERC20(desc.srcToken).transferFrom(
                msg.sender,
                address(this),
                desc.amount
            ),
            "transferFrom failed"
        );
        require(
            IERC20(desc.srcToken).approve(address(ROUTER), desc.amount),
            "approve failed"
        );

        // V6 requires caller parameter
        address caller = 0x0000000000000000000000000000000000000000;
        uint256 returnedAmount = ROUTER.swap{value: msg.value}(
            caller,
            desc,
            callData
        );
        require(returnedAmount >= desc.minReturnAmount, "slippage");
    }

    receive() external payable {}
}

contract OneClick1inchHttpTest is Test {
    using stdJson for string;
    using HTTP for HTTP.Client;
    using HTTP for HTTP.Request;

    HTTP.Client http;
    OneClick1inch public wrapper;
    address public user = address(1);

    function setUp() public {
        // fork mainnet
        uint fork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(fork);

        wrapper = new OneClick1inch();
        vm.deal(user, 10 ether);
    }

    function test_swapViaHttp() public {
        console.log("=== test_swapViaHttp start ===");
        vm.startPrank(user);

        // Wrap 1 ETH
        console.log("Depositing 1 ETH into WETH");
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).deposit{
            value: 1 ether
        }();
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).approve(
            address(wrapper),
            1 ether
        );

        // FIXED: Proper URL with /swap endpoint and correct parameters
        string memory url = string(
            abi.encodePacked(
                "https://api.1inch.dev/swap/v6.0/1/swap?", // FIXED: Added '?' and changed to /swap
                "src=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&", // FIXED: src instead of fromTokenAddress
                "dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&", // FIXED: dst instead of toTokenAddress
                "amount=1000000000000000000&",
                "from=",
                vm.toString(address(wrapper)),
                "&slippage=1"
            )
        );

        // FIXED: Add API key header (REPLACE WITH YOUR ACTUAL API KEY)
        HTTP.Response memory res = http
        .initialize(url)
        .GET()
        .withHeader("Authorization", "Bearer YOUR_API_KEY_HERE") // FIXED: Add your API key
            .withHeader("Accept", "application/json")
            .request();

        console.log("HTTP GET URL: %s", url);
        console.log("HTTP status: %s", res.status);
        console.log("HTTP data: %s", res.data);
        assertEq(res.status, 200);
        string memory json = res.data;

        // FIXED: Parse JSON fields for /swap response structure
        bytes memory callData = json.readBytes(".tx.data");
        console.log("callData length: %s", callData.length);

        uint256 ethValue = json.readUint(".tx.value");
        console.log("ethValue: %s", ethValue);

        // FIXED: Parse from root level, not .description
        address srcToken = json.readAddress(".fromToken.address");
        console.log("srcToken: %s", srcToken);

        address dstToken = json.readAddress(".toToken.address");
        console.log("dstToken: %s", dstToken);

        uint256 amount = 1 ether; // We know this
        console.log("amount: %s", amount);

        uint256 minOut = json.readUint(".toAmount");
        console.log("minOut: %s", minOut);

        // FIXED: Updated struct for V6
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6
            .SwapDescription({
                srcToken: srcToken,
                dstToken: dstToken,
                srcReceiver: user, // FIXED: No payable needed in V6
                dstReceiver: user, // FIXED: No payable needed in V6
                amount: amount,
                minReturnAmount: minOut,
                flags: 0,
                permit: ""
            });

        // Execute the swap
        wrapper.swap{value: ethValue}(desc, callData);

        // Verify
        uint256 daiBal = IERC20(dstToken).balanceOf(user);
        assertGt(daiBal, 0, "Swap failed");

        vm.stopPrank();
    }
}
*/