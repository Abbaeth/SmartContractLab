// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockPriceFeed {
    int256 private price;
    uint8 private _decimals;

    constructor(int256 _initialPrice, uint8 decimals_) {
        price = _initialPrice;
        _decimals = decimals_;
    }

    function setPrice(int256 _newPrice) external {
        price = _newPrice;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, price, 0, 0, 0);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
