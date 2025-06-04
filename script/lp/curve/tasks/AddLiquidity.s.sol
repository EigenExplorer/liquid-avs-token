// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev 2 token plain pool:
// forge script script/lp/curve/tasks/AddLiquidity.s.sol:AddLiquidity --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(address,address[],uint256[],bool)" -- "0xPoolAddress" "[0xToken1,0xToken2]" "[1000000000000000000,1000000000000000000]" false -vvvv

/// @dev 2 token metapool:
// forge script script/lp/curve/tasks/AddLiquidity.s.sol:AddLiquidity --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(address,address[],uint256[],bool)" -- "0xMetapoolAddress" "[0xToken,0xBaseLPToken]" "[1000000000000000000,1000000000000000000]" true -vvvv

/// @dev 3 token plain pool with automatic minLP calculation:
// forge script script/lp/curve/tasks/AddLiquidity.s.sol:AddLiquidity --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "runWithMinLP(address,address[],uint256[],bool,uint256)" -- "0xPoolAddress" "[0xToken1,0xToken2,0xToken3]" "[1000000000000000000,2000000000000000000,1500000000000000000]" false 0 -vvvv

/// @dev 4 token plain pool:
// forge script script/lp/curve/tasks/AddLiquidity.s.sol:AddLiquidity --rpc-url http://localhost:8545 --broadcast --private-key $ADMIN_PRIVATE_KEY --sig "run(address,address[],uint256[],bool)" -- "0xPoolAddress" "[0xToken1,0xToken2,0xToken3,0xToken4]" "[1000000000000000000,2000000000000000000,1500000000000000000,500000000000000000]" false -vvvv

interface ICurvePool2 {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external returns (uint256);
}

interface ICurvePool3 {
    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external returns (uint256);
}

interface ICurvePool4 {
    function add_liquidity(uint256[4] calldata amounts, uint256 min_mint_amount) external returns (uint256);
}

interface IMetaPool {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external returns (uint256);
}

contract AddLiquidity is Script {
    function run(
        address pool,
        address[] memory tokens,
        uint256[] memory amounts,
        bool isMetapool
    ) external returns (uint256 lpTokens) {
        // Validation
        require(pool != address(0), "Pool address cannot be zero");
        require(tokens.length == amounts.length, "Tokens and amounts length mismatch");
        require(tokens.length >= 2 && tokens.length <= 4, "Pool must have 2-4 tokens");
        require(!isMetapool || tokens.length == 2, "Metapools only support 2 tokens");

        console.log("[LP][Curve][Liquidity] Adding liquidity to pool:", pool);
        console.log("[LP][Curve][Liquidity] Number of tokens:", tokens.length);
        console.log("[LP][Curve][Liquidity] Is Metapool:", isMetapool);

        for (uint i = 0; i < tokens.length; i++) {
            console.log("[LP][Curve][Liquidity] Token", i, ":", tokens[i]);
            console.log("[LP][Curve][Liquidity] Amount", i, ":", amounts[i]);
        }

        // Calculate minimum LP tokens out for 3% slippage tolerance
        uint256 minLpTokens = _calculateMinLpTokens(amounts);

        // Add liquidity
        vm.startBroadcast();
        lpTokens = _addLiquidity(pool, tokens, amounts, isMetapool, minLpTokens);
        vm.stopBroadcast();

        return lpTokens;
    }

    function _addLiquidity(
        address pool,
        address[] memory tokens,
        uint256[] memory amounts,
        bool isMetapool,
        uint256 minLpTokens
    ) internal returns (uint256 lpTokens) {
        // Approve all tokens
        _approveTokens(pool, tokens, amounts);

        // Add liquidity based on pool type and number of tokens
        if (isMetapool) {
            lpTokens = _addLiquidityToMetapool(pool, amounts, minLpTokens);
        } else {
            lpTokens = _addLiquidityToPlainPool(pool, amounts, minLpTokens);
        }

        console.log("[LP][Curve][Liquidity] LP Tokens received:", lpTokens);

        return lpTokens;
    }

    function _approveTokens(address pool, address[] memory tokens, uint256[] memory amounts) internal {
        for (uint i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).approve(pool, amounts[i]);
                console.log("[LP][Curve][Liquidity] Approved", amounts[i], "of token", tokens[i]);
            }
        }
    }

    function _addLiquidityToMetapool(
        address pool,
        uint256[] memory amounts,
        uint256 minLpTokens
    ) internal returns (uint256 lpTokens) {
        require(amounts.length == 2, "Metapools require exactly 2 amounts");

        uint256[2] memory amountsFixed = [amounts[0], amounts[1]];
        return IMetaPool(pool).add_liquidity(amountsFixed, minLpTokens);
    }

    function _addLiquidityToPlainPool(
        address pool,
        uint256[] memory amounts,
        uint256 minLpTokens
    ) internal returns (uint256 lpTokens) {
        if (amounts.length == 2) {
            uint256[2] memory amountsFixed = [amounts[0], amounts[1]];
            return ICurvePool2(pool).add_liquidity(amountsFixed, minLpTokens);
        } else if (amounts.length == 3) {
            uint256[3] memory amountsFixed = [amounts[0], amounts[1], amounts[2]];
            return ICurvePool3(pool).add_liquidity(amountsFixed, minLpTokens);
        } else if (amounts.length == 4) {
            uint256[4] memory amountsFixed = [amounts[0], amounts[1], amounts[2], amounts[3]];
            return ICurvePool4(pool).add_liquidity(amountsFixed, minLpTokens);
        } else {
            revert("Unsupported number of tokens for plain pool");
        }
    }

    function _calculateMinLpTokens(uint256[] memory amounts) internal pure returns (uint256) {
        // Sum all token amounts
        uint256 totalValue = 0;
        for (uint i = 0; i < amounts.length; i++) {
            totalValue += amounts[i];
        }

        // 3% slippage tolerance
        return (totalValue * 97) / 100;
    }
}
