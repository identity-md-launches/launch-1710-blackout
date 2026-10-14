// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {IGameRegistry} from "../../src/interfaces/IGameRegistry.sol";
import "../../src/lib/Errors.sol";

/// @dev Isolated test graph. Production uses authenticated, write-once GameRegistry.
contract MockGameRegistry is IGameRegistry {
    address public token;
    address public params;
    address public market;
    uint256 public launchTime;
    bytes32 public starterRoot;
    bytes32 public freeRoot = keccak256("mock free root");
    uint256 public snapshotBlock;
    uint256 public endowment;
    mapping(uint256 => address) private modules;

    constructor(
        address token_,
        address params_,
        address market_,
        uint256 launch_,
        bytes32 root_,
        uint256 snapshot_,
        uint256 endowment_
    ) {
        token = token_;
        params = params_;
        market = market_;
        launchTime = launch_;
        starterRoot = root_;
        snapshotBlock = snapshot_;
        endowment = endowment_;
    }

    function setMarket(address value) external {
        market = value;
    }

    function setModule(uint256 role, address value) external {
        modules[role] = value;
    }

    function registeredModule(uint256 role) external view returns (address) {
        return modules[role];
    }

    function module(uint256 role) external view returns (address value) {
        value = modules[role];
        if (value == address(0)) revert NotConfigured();
    }
}
