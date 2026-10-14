// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ILaunchHook {
    function initializedAt() external view returns (uint256);
    function fees() external view returns (address);
}
