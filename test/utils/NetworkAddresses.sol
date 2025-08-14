// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library NetworkAddresses {
    struct Addresses {
        address strategyManager;
        address delegationManager;
        address rewardsCoordinator;
    }

    function getAddresses(uint256 chainId) internal pure returns (Addresses memory) {
        if (chainId == 1) {
            // Mainnet
            return
                Addresses({
                    strategyManager: 0x858646372CC42E1A627fcE94aa7A7033e7CF075A,
                    delegationManager: 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A,
                    rewardsCoordinator: 0x7750d328b314EfFa365A0402CcfD489B80B0adda
                });
        } else if (chainId == 17000) {
            // Holesky
            return
                Addresses({
                    strategyManager: 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6,
                    delegationManager: 0xA44151489861Fe9e3055d95adC98FbD462B948e7,
                    rewardsCoordinator: 0xAcc1fb458a1317E886dB376Fc8141540537E68fE
                });
        } else {
            revert("Unsupported network");
        }
    }
}
