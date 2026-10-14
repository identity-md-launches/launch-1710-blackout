// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {IGameRegistry} from "../interfaces/IGameRegistry.sol";
import "./Errors.sol";

/// @notice Every module is permanently tied to one immutable, append-only deployment graph.
abstract contract GameModule {
    // Constructor-only storage: no setter, delegatecall, upgrade or other write exists.
    // Exact initcode registration proves this initial value. This avoids the pinned
    // 0.8.26 assembler's immutable-patching size failure in larger modules.
    IGameRegistry public registry;

    constructor(address registry_) {
        if (registry_ == address(0)) revert InvalidAddress();
        registry = IGameRegistry(registry_);
    }
}
