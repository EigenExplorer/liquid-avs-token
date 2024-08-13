// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IToken.sol";

abstract contract TokenStorage is IToken {
    IERC20 public avsToken;
    address public strategyManager;

    struct Init {
        string name;
        string symbol;
        address initialOwner;
    }

    constructor(IERC20 _avsToken, address _strategyManager) {
        avsToken = _avsToken;
        strategyManager = _strategyManager;
    }
}
