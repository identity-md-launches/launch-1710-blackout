// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "./Errors.sol";

library EconomyMath {
    function tier(uint256 health) internal pure returns (uint256) {
        if (health >= 8000) return 10000;
        if (health >= 6000) return 8500;
        if (health >= 4000) return 6500;
        if (health >= 2000) return 4000;
        return 0;
    }

    function enhancement(uint256 level)
        internal
        pure
        returns (uint256 chance, uint256 burn, uint256 bonus, uint256 daysWad)
    {
        if (level == 0 || level > 16) revert InvalidValue();
        uint8[16] memory chances = [95, 90, 80, 70, 60, 50, 40, 30, 25, 22, 20, 18, 15, 12, 10, 8];
        uint8[16] memory burns = [0, 0, 0, 0, 0, 10, 25, 50, 55, 60, 65, 70, 75, 80, 85, 90];
        uint8[16] memory bonuses = [3, 6, 10, 14, 19, 25, 32, 40, 44, 48, 52, 56, 60, 64, 67, 70];
        uint256[16] memory costs = [
            uint256(0.25 ether),
            0.5 ether,
            1 ether,
            1.5 ether,
            2.5 ether,
            4 ether,
            6 ether,
            9 ether,
            12 ether,
            15 ether,
            19 ether,
            24 ether,
            30 ether,
            37 ether,
            45 ether,
            55 ether
        ];
        return (chances[level - 1], burns[level - 1], uint256(bonuses[level - 1]) * 100, costs[level - 1]);
    }

    function bonus(uint256 level) internal pure returns (uint256 b) {
        if (level == 0) return 0;
        (,, b,) = enhancement(level);
    }
}
