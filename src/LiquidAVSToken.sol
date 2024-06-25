// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20Upgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IEigenLayerStrategyManager {
    function depositIntoStrategy(address strategy, IERC20 token, uint256 amount) external returns (uint256 shares)
}

contract EigenLayerRestaking is Initializable, ERC20Upgradeable {
    IEigenLayerStrategyManager public eigenLayerStrategyManager;
    address public eigenLayerStrategy;
    uint256 public totalUnderlyingDeposited;

    event Deposited(
        address indexed user,
        uint256 amount,
        uint256 sharesReceived
    );
    event Withdrawn(
        address indexed user,
        uint256 shares,
        uint256 amountReceived
    );

    error InvalidDeposit();
    error InsufficientBalance();

    function initialize(
        string memory name,
        string memory symbol,
        IEigenLayerStrategyManager _eigenLayerStrategyManager,
        address _eigenLayerStrategy
    ) external initializer {
        __ERC20_init(name, symbol);
        eigenLayerStrategyManager = _eigenLayerStrategyManager;
        eigenLayerStrategy = _eigenLayerStrategy;
    }

    function deposit() external payable {
        if (msg.value == 0) revert InvalidDeposit();
        uint256 shares = _calculateSharesToMint(msg.value);
        
        // Implement deposit logic
    }

    function withdraw(uint256 shares) external {
        if (shares == 0 || balanceOf(msg.sender) < shares)
            revert InsufficientBalance();
        uint256 amount = _calculateUnderlyingToWithdraw(shares);
        
        // Implement withdrawal logic
    }

    function _calculateSharesToMint(
        uint256 amount
    ) internal view returns (uint256) {
        // Implement share calculation logic
    }

    function _calculateUnderlyingToWithdraw(
        uint256 shares
    ) internal view returns (uint256) {
        // Implement withdrawal amount calculation logic
    }

    receive() external payable {}
}
