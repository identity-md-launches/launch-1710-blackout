// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {EconomyMath} from "./EconomyMath.sol";

library ItemMetadata {
    using Strings for uint256;

    function render(uint256 id, uint256 kind, uint256 rarity, uint256 level, uint256 health, bool starter)
        internal
        pure
        returns (string memory)
    {
        string[12] memory kinds = [
            "GPU", "ASIC", "FPGA", "PSU", "Battery", "Solar", "Fan", "Liquid", "Router", "Motherboard", "Rack", "Surge"
        ];
        string[5] memory rarities = ["Common", "Rare", "Epic", "Legendary", "Mythic"];
        string[5] memory colors = ["#7884AA", "#39E6FF", "#B45CFF", "#FFE600", "#FF3DF2"];
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" shape-rendering="crispEdges"><rect width="128" height="128" fill="#0B102B"/>',
            level >= 12
                ? '<defs><filter id="g"><feGaussianBlur stdDeviation="3"/></filter></defs><rect x="20" y="20" width="88" height="88" fill="#FF3DF2" filter="url(#g)"/>'
                : "",
            '<rect x="24" y="24" width="80" height="80" fill="#302050" stroke="',
            colors[rarity],
            '" stroke-width="4"/>'
        );
        // A distinct 8x8 deterministic pixel circuit for each of the twelve kinds.
        for (uint256 y; y < 8; ++y) {
            for (uint256 x; x < 8; ++x) {
                uint256 pattern = uint256(keccak256(abi.encode(kind, y, x < 4 ? x : 7 - x)));
                if (pattern % 3 == 0) {
                    svg = string.concat(
                        svg,
                        '<rect x="',
                        (32 + x * 8).toString(),
                        '" y="',
                        (32 + y * 8).toString(),
                        '" width="6" height="6" fill="',
                        colors[rarity],
                        '"/>'
                    );
                }
            }
        }
        svg = string.concat(
            svg, '<path d="M16 40h8m-8 16h8m-8 16h8m80-32h8m-8 16h8m-8 16h8" stroke="#39E6FF" stroke-width="4"/></svg>'
        );
        string memory json = string.concat(
            '{"name":"+',
            level.toString(),
            " ",
            kinds[kind],
            " #",
            id.toString(),
            '","description":"BLACKOUT soulbound farm item","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[{"trait_type":"Kind","value":"',
            kinds[kind],
            '"},{"trait_type":"Rarity","value":"',
            rarities[rarity],
            '"},{"trait_type":"Enhancement","value":',
            level.toString(),
            "},"
        );
        json = string.concat(
            json,
            '{"trait_type":"Durability bps","value":',
            health.toString(),
            '}, {"trait_type":"Output tier bps","value":',
            EconomyMath.tier(health).toString(),
            '}, {"trait_type":"Starter","value":',
            starter ? "true" : "false",
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }
}
