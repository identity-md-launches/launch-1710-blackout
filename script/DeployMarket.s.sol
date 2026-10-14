// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script} from "forge-std/Script.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {V4Market} from "../src/V4Market.sol";

/// @notice Explicit-config local helper; never reads keys or broadcasts transactions.
contract DeployMarket is Script {
    function deploy(MarketFactory factory, MarketFactory.Config calldata config, bytes32 salt)
        external
        returns (V4Market)
    {
        return factory.deploy(config, salt);
    }
}
