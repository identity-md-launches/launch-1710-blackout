// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IMarket {
    function quote(uint256 ethAmount) external view returns (uint256);
    function buy(uint256 minOut, address recipient) external payable returns (uint256);
}

interface IFarm {
    function register(address player) external;
    function hasFarm(address player) external view returns (bool);
    function paidPackBought(address player, uint256 count, uint256 ethValue) external;
    function level(address player) external view returns (uint256);
}

interface ISystemMarket is IMarket {
    function quoteSell(uint256 tokenAmount) external view returns (uint256);
    function maxSellBatch() external view returns (uint256);
    function sell(uint256 amount, uint256 minOut, address recipient) external returns (uint256);
}
