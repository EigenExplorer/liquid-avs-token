// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";

contract MockWETH is ERC20, IWETH {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() public payable override {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    function balanceOf(address account) public view override(ERC20, IWETH) returns (uint256) {
        return ERC20.balanceOf(account);
    }

    // Add mint function for testing
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    receive() external payable {
        deposit();
    }
}
