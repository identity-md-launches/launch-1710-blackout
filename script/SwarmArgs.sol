// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Robinhood} from "../src/lib/Robinhood.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import "../src/lib/Errors.sol";

/// @notice Offline constructor encoding: exactly eight static words, no tuple/dynamic arguments (v3.14, v3.16 binder).
library SwarmArgs {
    /// @dev policyWord = chainId[0:32] | fromBlock[32:80] | toBlock[80:128] | maxPrice[128:224] | heartbeatBps[224:240].
    function policy(SwarmDesk.OracleConfig memory o, SwarmDesk.BindingConfig memory b) internal pure returns (uint256) {
        if (
            o.questionChain == 0 || o.questionChain > type(uint32).max || o.fromBlock > type(uint48).max
                || o.toBlock > type(uint48).max || o.maxPrice == 0 || o.maxPrice > type(uint96).max
                || b.heartbeatCap != 1 ether || b.heartbeatBps > type(uint16).max || b.registryLaunch != 0
                || b.paramsLaunch != 0 || b.registryIndex != 0 || b.paramsIndex != 0
        ) revert InvalidValue();
        return o.questionChain | (uint256(o.fromBlock) << 32) | (uint256(o.toBlock) << 80) | (o.maxPrice << 128)
            | (b.heartbeatBps << 224);
    }

    /// @dev `binder` (v3.16) is the one account allowed to call `bind`: the project wallet, never a protocol address.
    function encode(SwarmDesk.OracleConfig memory o, SwarmDesk.BindingConfig memory b, address binder)
        internal
        pure
        returns (bytes memory)
    {
        if (
            o.intake != Robinhood.INTAKE || o.delivery != Robinhood.DELIVERY || o.signer != Robinhood.ATTESTER
                || o.asset != Robinhood.IMD || b.factory != Robinhood.PROJECT_FACTORY || binder == address(0)
                || binder == Robinhood.PROJECT_FACTORY || binder == Robinhood.PROJECT_REGISTRY
                || binder == Robinhood.INTAKE || binder == Robinhood.DELIVERY || binder == Robinhood.ATTESTER
                || binder == Robinhood.IMD || binder == Robinhood.LAUNCH_FACTORY || binder == Robinhood.POOL_MANAGER
        ) revert InvalidValue();
        return abi.encode(
            o.action, policy(o, b), o.questions[0], o.questions[1], o.bodies[0], o.bodies[1], b.gameConfigHash, binder
        );
    }
}
