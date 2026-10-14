// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "./Errors.sol";

library ItemMath {
    // GPU, ASIC, FPGA, PSU, Battery, Solar, Fan, Liquid, Router, Motherboard, Rack, Surge.
    function baseHash(uint256 rarity) internal pure returns (uint256) {
        if (rarity > 4) revert InvalidValue();
        return rarity == 0 ? 10000 : rarity == 1 ? 28000 : rarity == 2 ? 80000 : rarity == 3 ? 250000 : 800000;
    }

    function tag(uint256 kind) internal pure returns (uint256) {
        return kind < 3 ? 0 : kind < 6 ? 1 : kind < 8 ? 2 : kind == 8 ? 3 : 4;
    }

    function draw(bytes32 seed, bool mythic, bool starter) internal pure returns (uint8 kind, uint8 rarity) {
        uint256 x = uint256(seed) % 100;
        kind = x < 16
            ? 0
            : x < 31
                ? 1
                : x < 43
                    ? 2
                    : x < 52
                        ? 3
                        : x < 59 ? 4 : x < 66 ? 5 : x < 75 ? 6 : x < 81 ? 7 : x < 87 ? 8 : x < 92 ? 9 : x < 96 ? 10 : 11;
        uint256 r = (uint256(seed) >> 64) % 10000;
        if (starter) rarity = r < 9200 ? 1 : 2;
        else rarity = r < 7000 ? 0 : r < 9200 ? 1 : r < 9870 ? 2 : r < 9970 ? 3 : mythic ? 4 : 0;
    }
}
