// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {FarmRewards} from "../src/FarmRewards.sol";
import "../src/lib/Errors.sol";

/// @notice Review finding e11b8d0f (medium): the farm price basis `lastFarmDaily` was one settled epoch's net yield,
/// so a single engineered or event-hit zero-net epoch repriced rooms, expansions, lock minimums, cable repair and the
/// lobby to the 3000-token floor. Since v3.17 the basis rises at once to any higher settled yield, otherwise decays
/// by 1/96 per settled epoch, and a pro-rata entry epoch is scaled to its full-epoch equivalent.
contract FarmDailyBasisV317Test is BaseTest {
    uint256 private constant DECAY = 96;

    function _wornLoadout(uint256 slot0, uint256 slot1, uint256 slot2) private returns (uint256 worn) {
        // One item below the 2000-durability tier boundary: weight > 0 next epoch, productive == 0, net == 0.
        worn = mintItem(alice, 0, 0);
        vm.prank(address(d.farm));
        d.items.maintain(worn, 1500, 0);
        vm.startPrank(alice);
        d.farm.unplace(0, slot0);
        d.farm.unplace(0, slot1);
        d.farm.unplace(0, slot2);
        d.farm.place(worn, 0, 0);
        vm.stopPrank();
    }

    function testZeroNetEpochOnlyDecaysTheBasisByOneStep() public {
        fund(800_000_000 ether);
        uint256 a = place(alice, 0, 1, 0);
        uint256 b = place(alice, 1, 1, 1);
        uint256 c = place(alice, 2, 1, 2);
        step(); // closes epoch 1, settles alice at her real yield
        assertGt(d.rewards.lastFarmDaily(alice), 1_000_000 ether);
        assertEq(d.economy.farmDaily(alice), d.rewards.lastFarmDaily(alice));

        _wornLoadout(0, 1, 2);
        step(); // epoch 2 closes and settles with the full loadout; the worn loadout takes effect for epoch 3
        uint256 before_ = d.rewards.lastFarmDaily(alice);
        assertGt(before_, 1_000_000 ether);
        step(); // epoch 3 settles with weight > 0 and net == 0
        uint256 expected = before_ - before_ / DECAY;
        assertEq(d.rewards.lastFarmDaily(alice), expected, "one zero-net epoch decays the basis by exactly 1/96");
        assertEq(d.economy.farmDaily(alice), expected);
        assertEq(d.economy.roomQuote(alice, 3), expected * 10, "room 3 stays yield-priced");
        assertEq(d.economy.roomQuote(alice, 1), expected * 2);
        (uint256 lockMin, uint256 bps) = d.economy.lockQuote(alice, 30);
        assertEq(lockMin, expected * 20, "30-day lock minimum stays yield-priced");
        assertEq(bps, 2000);
        assertEq(d.economy.lobbyQuote(alice), expected);

        // Restoring the productive loadout never lowers the quote before the next settlement either.
        vm.startPrank(alice);
        d.farm.unplace(0, 0);
        d.farm.place(a, 0, 0);
        d.farm.place(b, 0, 1);
        d.farm.place(c, 0, 2);
        vm.stopPrank();
        assertEq(d.economy.farmDaily(alice), expected);
    }

    function testStarvingForManyEpochsDecaysGeometricallyNotToTheFloor() public {
        fund(800_000_000 ether);
        place(alice, 0, 1, 0);
        place(alice, 1, 1, 1);
        place(alice, 2, 1, 2);
        step();
        _wornLoadout(0, 1, 2);
        step(); // takes effect next epoch
        uint256 basis = d.rewards.lastFarmDaily(alice);
        for (uint256 i; i < 8; ++i) {
            step();
            basis -= basis / DECAY;
            assertEq(d.rewards.lastFarmDaily(alice), basis, "geometric decay per settled zero-net epoch");
        }
        // Eight epochs (two days) of forfeited yield lowered the basis by about 8%, far from the 3000-token floor.
        assertGt(basis, 1_000_000 ether);
        assertGt(d.economy.roomQuote(alice, 3), 10_000_000 ether);
    }

    function testBasisRisesAtOnceToAHigherSettledYield() public {
        fund(800_000_000 ether);
        // bob is a large competitor, so alice's share of the budget scales with her own loadout.
        place(bob, 0, 1, 0);
        place(bob, 1, 1, 1);
        place(bob, 2, 1, 2);
        place(alice, 0, 0, 0); // one Common
        step();
        uint256 small = d.rewards.lastFarmDaily(alice);
        assertGt(small, 0);
        assertLt(small, d.rewards.lastFarmDaily(bob));
        place(alice, 1, 1, 1);
        place(alice, 2, 1, 2);
        step(); // the larger loadout takes effect next epoch; this settlement is still the Common's yield
        uint256 mid = d.rewards.lastFarmDaily(alice);
        assertGe(mid, small - small / DECAY);
        assertLt(mid, small * 2);
        vm.recordLogs();
        step(); // the first settlement of the larger loadout
        uint256 credited = _creditedTo(alice, vm.getRecordedLogs());
        uint256 id = d.rewards.settledEpoch();
        assertEq(d.rewards.epochData(id).redis, 0, "no redistribution in this fixture, so the credit is o.net");
        uint256 basis = d.rewards.lastFarmDaily(alice);
        assertEq(basis, credited * 4, "a higher settled net yield becomes the basis immediately, undecayed");
        assertGt(basis, mid * 3 / 2);
    }

    function testProRataEntryEpochIsScaledToItsFullEpochEquivalent() public {
        fund(800_000_000 ether);
        place(alice, 0, 1, 0);
        place(alice, 1, 1, 1);
        place(alice, 2, 1, 2);
        // bob installs the same loadout half way through the same epoch and is admitted pro rata.
        vm.warp(vm.getBlockTimestamp() + 3 hours);
        place(bob, 0, 1, 0);
        place(bob, 1, 1, 1);
        place(bob, 2, 1, 2);
        uint256 e = d.rewards.epoch();
        assertEq(d.rewards.entrySeconds(e, bob), 3 hours);
        assertEq(d.rewards.entrySeconds(e, alice), 6 hours, "admitted at the epoch start: scaling is the identity");
        step();
        uint256 full = d.rewards.lastFarmDaily(alice);
        uint256 entry = d.rewards.lastFarmDaily(bob);
        assertGt(full, 1_000_000 ether);
        // bob mined for half the epoch, so his credit is half of alice's, but his price basis is the same farm's day.
        assertApproxEqRel(entry, full, 1e12, "entry epoch scaled by EPOCH / secondsLeft");
        assertLt(d.rewards.pending(bob), d.rewards.pending(alice));
    }

    function testDecayConstantIsExposed() public view {
        assertEq(d.rewards.FARM_DAILY_DECAY(), DECAY);
    }

    function _creditedTo(address p, Vm.Log[] memory logs) private pure returns (uint256 amount) {
        bytes32 topic = keccak256("Credited(address,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length == 3 && logs[i].topics[0] == topic
                    && address(uint160(uint256(logs[i].topics[1]))) == p
            ) {
                amount += abi.decode(logs[i].data, (uint256));
            }
        }
    }
}
