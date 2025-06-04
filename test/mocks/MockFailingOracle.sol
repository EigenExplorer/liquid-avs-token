// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock oracle that throws
contract MockFailingOracle {
    function arePricesStale() external pure returns (bool) {
        return true;
    }
    function updateAllPricesIfNeeded() external pure returns (bool) {
        revert();
    }
}

// Mock oracle that returns false on update
contract MockRejectedUpdateOracle {
    function arePricesStale() external pure returns (bool) {
        return true;
    }
    function updateAllPricesIfNeeded() external pure returns (bool) {
        return false;
    }
}

// Mock oracle with zero price for assets
contract MockZeroPriceOracle {
    function arePricesStale() external pure returns (bool) {
        return false;
    }
    function updateAllPricesIfNeeded() external pure returns (bool) {
        return true;
    }
    function getTokenPrice(address) external pure returns (uint256) {
        return 0;
    }
}

// Mock oracle that remains stale after update
contract MockStillStaleOracle {
    function arePricesStale() external pure returns (bool) {
        return true; // Always returns stale
    }

    function updateAllPricesIfNeeded() external pure returns (bool) {
        return true; // Claims success
    }
}

// Mock oracle that returns zero for specific tokens but says prices are not stale
contract MockZeroPriceCheckOracle {
    address public tokenToFail;

    constructor(address _tokenToFail) {
        tokenToFail = _tokenToFail;
    }

    function arePricesStale() external pure returns (bool) {
        return false; // Changed from true to false - prices are not stale
    }

    function updateAllPricesIfNeeded() external pure returns (bool) {
        return true;
    }

    function getTokenPrice(address token) external view returns (uint256) {
        if (token == tokenToFail) {
            return 0; // Zero price for specific token
        }
        return 1e18; // Valid price for other tokens
    }
}

// Simple mock oracle for zero price testing
contract ZeroTokenPriceOracle {
    // Return false for stale prices check to bypass that check
    function arePricesStale() external pure returns (bool) {
        return false;
    }

    // This function won't be called since prices aren't stale
    function updateAllPricesIfNeeded() external pure returns (bool) {
        return true;
    }

    // Always return 0 price for any token
    function getTokenPrice(address) external pure returns (uint256) {
        return 0;
    }

    // For interface compatibility
    function getRate(IERC20) external pure returns (uint256) {
        return 0;
    }

    // For compatibility with contract roles check
    bytes32 public constant RATE_UPDATER_ROLE = keccak256("RATE_UPDATER_ROLE");
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
    function hasRole(bytes32, address) external pure returns (bool) {
        return true; // All roles granted
    }
}
