 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "@eigenlayer/contracts/interfaces/IEigenPodManager.sol";
import {ISlasher} from "@eigenlayer/contracts/interfaces/ISlasher.sol";

contract MockStrategyManager {
    mapping(IStrategy => bool) public whitelistedStrategies;
    mapping(address => mapping(IStrategy => uint256)) public stakerStrategyShares;
    mapping(address => IStrategy[]) public stakerStrategies;
    mapping(IStrategy => bool) internal _thirdPartyTransfersForbidden;

    address private _strategyWhitelister;

    constructor() {
        _strategyWhitelister = msg.sender;
    }

    function depositIntoStrategyWithSignature(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) external returns (uint256) {
        require(whitelistedStrategies[strategy], "Strategy not whitelisted");
        token.transferFrom(msg.sender, address(this), amount);
        if (stakerStrategyShares[msg.sender][strategy] == 0) {
            stakerStrategies[msg.sender].push(strategy);
        }
        stakerStrategyShares[msg.sender][strategy] += amount;
        return amount;
    }

    function depositIntoStrategy(IStrategy strategy, IERC20 token, uint256 amount)
        external
        returns (uint256)
    {
        require(whitelistedStrategies[strategy], "Strategy not whitelisted");
        token.transferFrom(msg.sender, address(this), amount);
        if (stakerStrategyShares[msg.sender][strategy] == 0) {
            stakerStrategies[msg.sender].push(strategy);
        }
        stakerStrategyShares[msg.sender][strategy] += amount;
        return amount;
    }

    function withdrawFromStrategy(IStrategy strategy, uint256 shares)
        external
        returns (IERC20[] memory tokens, uint256[] memory amounts)
    {
        require(whitelistedStrategies[strategy], "Strategy not whitelisted");
        require(stakerStrategyShares[msg.sender][strategy] >= shares, "Insufficient shares");
        
        stakerStrategyShares[msg.sender][strategy] -= shares;
        
        tokens = new IERC20[](1);
        amounts = new uint256[](1);
        tokens[0] = strategy.underlyingToken();
        amounts[0] = shares;
        
        tokens[0].transfer(msg.sender, shares);
        
        return (tokens, amounts);
    }

    function addStrategiesToDepositWhitelist(
        IStrategy[] calldata strategiesToWhitelist,
        bool[] calldata thirdPartyTransfersForbiddenValues
    ) external {
        require(msg.sender == _strategyWhitelister, "Not strategy whitelister");
        require(
            strategiesToWhitelist.length == thirdPartyTransfersForbiddenValues.length,
            "Length mismatch"
        );

        for (uint256 i = 0; i < strategiesToWhitelist.length; i++) {
            whitelistedStrategies[strategiesToWhitelist[i]] = true;
            _thirdPartyTransfersForbidden[strategiesToWhitelist[i]] = thirdPartyTransfersForbiddenValues[i];
        }
    }

    function stakerStrategyListLength(address staker) external view returns (uint256) {
        return stakerStrategies[staker].length;
    }

    function addShares(address staker, IERC20 token, IStrategy strategy, uint256 shares) external {
        if (stakerStrategyShares[staker][strategy] == 0) {
            stakerStrategies[staker].push(strategy);
        }
        stakerStrategyShares[staker][strategy] += shares;
    }

    function getDeposits(address staker) external view returns (IStrategy[] memory strategies, uint256[] memory shares) {
        uint256 length = stakerStrategies[staker].length;
        strategies = new IStrategy[](length);
        shares = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            strategies[i] = stakerStrategies[staker][i];
            shares[i] = stakerStrategyShares[staker][strategies[i]];
        }
    }

    function delegation() external view returns (IDelegationManager) {
        return IDelegationManager(address(0));
    }

    function eigenPodManager() external view returns (IEigenPodManager) {
        return IEigenPodManager(address(0));
    }

    function slasher() external view returns (ISlasher) {
        return ISlasher(address(0));
    }

    function strategyWhitelister() external view returns (address) {
        return _strategyWhitelister;
    }

    function thirdPartyTransfersForbidden(IStrategy strategy) external view returns (bool) {
        return _thirdPartyTransfersForbidden[strategy];
    }
}