// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "./TokenStorage.sol";

contract Token is
    Initializable,
    OwnableUpgradeable,
    TokenStorage,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    constructor(
        IERC20 _avsToken,
        address _strategyManager
    ) TokenStorage(_avsToken, _strategyManager) {
        _disableInitializers();
    }

    function initialize(Init calldata init) external initializer {
        __ERC20_init(init.name, init.symbol);
        __ReentrancyGuard_init();
        _transferOwnership(init.initialOwner);
    }


    function deposit(uint256 amount) external returns (uint256) {
        require(amount > 0, "Deposit amount must be greater than 0");
        uint256 shares = calculateShares(amount);

        avsToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount, shares);
        return shares;
    }

    function withdraw(uint256 shares) external returns (uint256) {
        require(shares > 0, "Withdraw shares must be greater than 0");
        require(balanceOf(msg.sender) >= shares, "Insufficient balance");

        uint256 amount = calculateAmount(shares);
        _burn(msg.sender, shares);
        avsToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, shares);
        return amount;
    }

    function withdrawToNode(address node, uint256 amount) external {
        require(
            msg.sender == strategyManager,
            "Only strategy manager can withdraw to nodes"
        );
        require(
            amount <= avsToken.balanceOf(address(this)),
            "Insufficient balance"
        );

        avsToken.safeTransfer(node, amount);
    }

    function calculateShares(uint256 amount) public view returns (uint256) {
        if (totalSupply() == 0) {
            return amount;
        }
        return (amount * totalSupply()) / avsToken.balanceOf(address(this));
    }

    function calculateAmount(uint256 shares) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (shares * avsToken.balanceOf(address(this))) / totalSupply();
    }
}
