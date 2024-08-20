// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../interfaces/IToken.sol";
import "../interfaces/ITokenRegistry.sol";

contract Token is
    IToken,
    Initializable,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    struct Asset {
        uint256 balance;
    }

    mapping(address => Asset) public assets;
    ITokenRegistry public tokenRegistry;
    address public strategyManager;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    bool public depositsPaused;

    constructor(ITokenRegistry _tokenRegistry, address _strategyManager) {
        _disableInitializers();
        tokenRegistry = _tokenRegistry;
        strategyManager = _strategyManager;
    }

    function initialize(Init calldata init) external initializer {
        __ERC20_init(init.name, init.symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();

        _grantRole(ADMIN_ROLE, init.initialOwner);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);
    }

    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) external nonReentrant returns (uint256) {
        if (depositsPaused) revert Paused();
        if (amount == 0) revert ZeroAmount();
        if (!tokenRegistry.tokenIsSupported(asset))
            revert UnsupportedAsset(asset);

        uint256 shares = calculateShares(asset, amount);
        if (shares == 0) revert ZeroShares();

        asset.safeTransferFrom(msg.sender, address(this), amount);
        assets[address(asset)].balance += amount;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, asset, amount, shares);
        return shares;
    }

    function withdraw(
        IERC20 asset,
        uint256 shares
    ) external nonReentrant returns (uint256) {
        if (shares == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < shares)
            revert InsufficientBalance(balanceOf(msg.sender), shares);

        uint256 amount = calculateAmount(asset, shares);
        _burn(msg.sender, shares);
        asset.safeTransfer(msg.sender, amount);
        assets[address(asset)].balance -= amount;

        emit Withdraw(msg.sender, asset, amount, shares);
        return amount;
    }

    function withdrawToNode(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external {
        if (msg.sender != strategyManager)
            revert NotStrategyManager(msg.sender);
        if (assetsToRetrieve.length != amounts.length)
            revert("Length mismatch");

        for (uint256 i = 0; i < assetsToRetrieve.length; i++) {
            IERC20 asset = assetsToRetrieve[i];
            uint256 amount = amounts[i];
            if (amount > assets[address(asset)].balance)
                revert InsufficientBalance(
                    assets[address(asset)].balance,
                    amount
                );

            assets[address(asset)].balance -= amount;
            asset.safeTransfer(strategyManager, amount);
            emit AssetRetrieved(asset, amount, strategyManager);
        }
    }

    function calculateShares(
        IERC20 asset,
        uint256 amount
    ) public view returns (uint256) {
        uint256 assetAmountInUnitOfAccount = tokenRegistry
            .convertToUnitOfAccount(asset, amount);
        return
            _convertToShares(assetAmountInUnitOfAccount, Math.Rounding.Floor);
    }

    function calculateAmount(
        IERC20 asset,
        uint256 shares
    ) public view returns (uint256) {
        uint256 amountInUnitOfAccount = _convertToAssets(
            shares,
            Math.Rounding.Floor
        );
        return
            tokenRegistry.convertFromUnitOfAccount(
                asset,
                amountInUnitOfAccount
            );
    }

    function _convertToShares(
        uint256 amount,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? amount
                : amount.mulDiv(supply, totalAssets(), rounding);
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares
                : shares.mulDiv(totalAssets(), supply, rounding);
    }

    function totalAssets() public view returns (uint256) {
        return tokenRegistry.totalAssets();
    }
}
