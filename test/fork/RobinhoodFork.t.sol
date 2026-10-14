// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {ChainClock} from "../../src/lib/ChainClock.sol";
import {IArbSys} from "../../src/lib/ChainClock.sol";

contract RobinhoodForkTest is Test {
    /// @notice Opt-in live-RPC/precompile smoke test; default offline tests skip it.
    /// Native ArbOS precompiles are read from the RPC, then replayed in Foundry's local EVM.
    function testForkArbSysAndHistoricalHash() public {
        if (block.chainid != 4663) {
            vm.skip(true);
            return;
        }
        assertGt(block.timestamp, 0);
        bytes memory numberCall = abi.encodeCall(IArbSys.arbBlockNumber, ());
        bytes memory rawNumber = rpcCall(numberCall);
        uint256 l2 = abi.decode(rawNumber, (uint256));
        assertGt(l2, 1);
        bytes memory hashCall = abi.encodeCall(IArbSys.arbBlockHash, (l2 - 1));
        bytes memory rawHash = rpcCall(hashCall);
        bytes32 previous = abi.decode(rawHash, (bytes32));
        assertTrue(previous != bytes32(0));
        vm.mockCall(address(100), numberCall, rawNumber);
        vm.mockCall(address(100), hashCall, rawHash);
        assertEq(ChainClock.number(), l2);
        assertEq(ChainClock.hash(l2 - 1), previous);
        assertEq(ChainClock.hash(l2), bytes32(0));
    }

    function rpcCall(bytes memory data) internal returns (bytes memory) {
        return vm.rpc(
            "eth_call",
            string.concat(
                '[{"to":"0x0000000000000000000000000000000000000064","data":"', vm.toString(data), '"},"latest"]'
            )
        );
    }
}
