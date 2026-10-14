// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {GridOperator} from "../src/GridOperator.sol";
import "../src/lib/Errors.sol";

contract GridV35Test is BaseTest {
    function _pick(bytes32 seed, uint256 strongest, bool positive) private pure returns (uint256) {
        uint256 point = uint256(keccak256(abi.encode(seed, "district"))) % (positive ? 50000 : 110000);
        for (uint256 district; district < 8; ++district) {
            uint256 w = district == strongest ? (positive ? 15000 : 5000) : (positive ? 5000 : 15000);
            if (point < w) return district;
            point -= w;
        }
        revert();
    }

    function testGreenAndCheapBothFavorTheStableDistrict() public {
        vm.prank(alice);
        d.economy.lock(15000 ether, 7);
        uint256 strong = d.farm.district(alice);
        assertEq(d.grid.gridStability(strong), 15000);
        assertEq(d.grid.lobbyWeight(strong), 5000);
        assertEq(d.grid.gridStability((strong + 1) % 8), 5000);
        for (uint256 epoch = 2; epoch <= 3; ++epoch) {
            GridOperator.Kind expected = epoch == 2 ? GridOperator.Kind.Green : GridOperator.Kind.Cheap;
            bytes32 number = keccak256(abi.encode(epoch, "plan"));
            vm.prank(swarm);
            d.grid.submitPlan(epoch, expected, 10000, number, "Stable district positive regression");
            entropy();
            vm.warp(d.rewards.epochEnd());
            d.rewards.advanceEpoch();
            uint256 target = vm.getBlockNumber() + 1;
            bytes32 h;
            for (uint256 i = 1;; ++i) {
                h = bytes32(i);
                bytes32 seed = keccak256(abi.encode(number, h, address(d.grid), epoch));
                // Choose a deterministic vector that distinguishes positive from old negative weighting.
                if (_pick(seed, strong, true) == strong && _pick(seed, strong, false) != strong) break;
            }
            vm.roll(target + 1);
            vm.setBlockhash(target, h);
            d.grid.resolve(epoch);
            (GridOperator.Kind actual,, uint8 selected,, bool resolved) = d.grid.eventAt(epoch);
            assertTrue(resolved);
            assertEq(uint256(actual), uint256(expected));
            assertEq(selected, strong);
        }
    }

    /// @dev v3.6: reserved kinds never come from the autonomous fallback; the swarm can plan them only
    /// once Civic feature 7 is enabled (this legacy fixture enables it; PhasedReleaseV36 covers disabled).
    function testReservedEventsHaveZeroLaunchWeightAndPlanOnlyWhenEnabled() public {
        for (uint256 e = 1; e <= 40; ++e) {
            assertLe(uint256(d.grid.fallbackKind(e)), uint256(GridOperator.Kind.Cheap));
        }
        assertTrue(d.civic.enabled(7));
        vm.prank(swarm);
        d.grid.submitPlan(2, GridOperator.Kind.Heatwave, 10000, bytes32(uint256(1)), "Reserved");
        vm.prank(swarm);
        d.grid.submitPlan(3, GridOperator.Kind.Festival, 10000, bytes32(uint256(1)), "Reserved");
        vm.expectRevert(AlreadyDone.selector);
        vm.prank(swarm);
        d.grid.submitPlan(2, GridOperator.Kind.Festival, 10000, bytes32(uint256(1)), "Reserved");
    }
}
