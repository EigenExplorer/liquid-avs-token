// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract MockChainlinkFeed {
    int256 private _answer;
    uint8 private _decimals;
    uint256 private _updatedAt;

    constructor(int256 initialAnswer, uint8 decimals) {
        _answer = initialAnswer;
        _decimals = decimals;
        _updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            1, // roundId
            _answer, // answer
            block.timestamp - 100, // startedAt
            _updatedAt, // updatedAt
            1 // answeredInRound
        );
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // Test helpers
    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }
}