// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 blockNumber) external view returns (bytes32);
}

/// @dev ArbSys is a protocol precompile, not a configurable third-party oracle.
library ChainClock {
    function number() internal view returns (uint256) {
        if (block.chainid == 4663 || block.chainid == 46630) return IArbSys(address(100)).arbBlockNumber();
        return block.number;
    }

    function hash(uint256 target) internal view returns (bytes32) {
        uint256 n = number();
        if (n <= target || n - target > 256) return bytes32(0);
        if (block.chainid == 4663 || block.chainid == 46630) return IArbSys(address(100)).arbBlockHash(target);
        return blockhash(target);
    }
}
