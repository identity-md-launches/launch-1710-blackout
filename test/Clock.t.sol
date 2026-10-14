// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {ChainClock} from "../src/lib/ChainClock.sol";

contract ClockHarness {
    function number() external view returns (uint256) {
        return ChainClock.number();
    }

    function hash(uint256 n) external view returns (bytes32) {
        return ChainClock.hash(n);
    }
}

contract MockArbSys {
    uint256 public arbBlockNumber;
    mapping(uint256 => bytes32) public arbBlockHash;

    function set(uint256 n, uint256 target, bytes32 h) external {
        arbBlockNumber = n;
        arbBlockHash[target] = h;
    }
}

contract ClockTest is Test {
    function testRobinhoodUsesArbSysNotL1EstimateAndHandlesExpiry() public {
        vm.chainId(4663);
        vm.roll(500);
        // Foundry 1.8 reserves 0x64 as a precompile; mock the ArbSys calls instead of etching code.
        vm.mockCall(address(100), abi.encodeWithSignature("arbBlockNumber()"), abi.encode(uint256(9000)));
        vm.mockCall(
            address(100),
            abi.encodeWithSignature("arbBlockHash(uint256)", uint256(8999)),
            abi.encode(keccak256("L2 block"))
        );
        ClockHarness clock = new ClockHarness();
        assertEq(clock.number(), 9000);
        assertEq(clock.hash(8999), keccak256("L2 block"));
        assertEq(clock.hash(9000), bytes32(0));
        assertEq(clock.hash(8743), bytes32(0));
    }

    function testLocalEvmFutureBlockAnd256BlockBoundary() public {
        vm.chainId(31337);
        vm.roll(1000);
        vm.setBlockhash(744, keccak256("last available"));
        ClockHarness clock = new ClockHarness();
        assertEq(clock.number(), 1000);
        assertEq(clock.hash(744), keccak256("last available"));
        assertEq(clock.hash(743), bytes32(0));
        assertEq(clock.hash(1000), bytes32(0));
    }
}
