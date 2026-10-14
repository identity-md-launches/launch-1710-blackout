// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IGameRegistry {
    function module(uint256 role) external view returns (address);
    function registeredModule(uint256 role) external view returns (address);
    function token() external view returns (address);
    function params() external view returns (address);
    function market() external view returns (address);
    function launchTime() external view returns (uint256);
    function freeRoot() external view returns (bytes32);
    function starterRoot() external view returns (bytes32);
    function snapshotBlock() external view returns (uint256);
    function endowment() external view returns (uint256);
}
