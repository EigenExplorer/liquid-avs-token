// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library StalenessThreshold {
    function getHiddenThreshold(uint256 salt) internal view returns (uint256 thresholdSeconds) {
        uint256 bucket = ((block.timestamp / 3600) + block.number / 100);
        bytes32 hash = keccak256(abi.encodePacked(bucket, block.prevrandao, salt, address(this)));
        uint256 val = uint256(hash);
        uint256 squashed = ((val ^ (val >> 13)) % 1001); // [0, 1000]
        thresholdSeconds = 3600 + ((squashed * squashed) % 10800); // [3600, 14400)
    }
}
