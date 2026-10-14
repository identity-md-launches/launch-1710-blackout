// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DeferredEntryTest} from "./Base.t.sol";
import {FarmRewards} from "../src/FarmRewards.sol";
import {GridOperator} from "../src/GridOperator.sol";
import {Params} from "../src/Params.sol";
import "../src/lib/Errors.sol";

/// @dev Independent eager room model: plain memory items, no calls to FarmEngine/roomStats.
contract LazyAccountingTest is DeferredEntryTest {
    struct RefItem {
        uint8 kind;
        uint8 rarity;
        uint8 clock;
        uint16 health;
        bool destroyed;
    }

    struct RefFarm {
        RefItem[6] item;
        uint256 theftUntil;
        uint256 earned;
    }

    struct Stats {
        uint256 raw;
        uint256 productive;
        uint256 power;
        uint256 mask;
    }

    function _hash(uint256 rarity) private pure returns (uint256) {
        uint256[5] memory values = [uint256(10000), 28000, 80000, 250000, 800000];
        return values[rarity];
    }

    function _stats(RefFarm memory f, uint256 e) private pure returns (Stats memory s) {
        for (uint256 i; i < 6; ++i) {
            if (!f.item[i].destroyed) s.mask |= 1 << f.item[i].kind;
        }
        bool locked = s.mask & 1280 == 1280;
        uint256 baseRaw;
        uint256 baseProductive;
        uint256 tags;
        uint256[5] memory rarities;
        for (uint256 i; i < 6; ++i) {
            RefItem memory x = f.item[i];
            if (x.destroyed || (x.kind == 8 && e < f.theftUntil && !locked)) continue;
            uint256 tag = x.kind < 3 ? 0 : x.kind < 6 ? 1 : x.kind < 8 ? 2 : x.kind == 8 ? 3 : 4;
            tags |= 1 << tag;
            rarities[x.rarity]++;
            uint256 raw = _hash(x.rarity) * (x.kind < 3 ? 10000 : 6000) / 10000;
            uint256[6] memory enhancement = [uint256(0), 300, 600, 1000, 1400, 1900];
            baseRaw += raw;
            uint256 tier = x.health >= 8000
                ? 10000
                : x.health >= 6000 ? 8500 : x.health >= 4000 ? 6500 : x.health >= 2000 ? 4000 : 0;
            baseProductive += raw * tier / 10000;
            raw = raw * (10000 + enhancement[x.clock]) / 10000;
            s.raw += raw;
            s.productive += raw * tier / 10000;
        }
        uint256 bonus;
        if (s.mask & 3 == 3) bonus += s.mask & 7 == 7 ? 2000 : 1000;
        if (tags == 31) bonus += 1500;
        if (s.mask & 1088 == 1088) bonus += 500;
        if (rarities[4] >= 3) bonus += 3000;
        else if (rarities[3] >= 3) bonus += 2000;
        else if (rarities[2] >= 3) bonus += 1000;
        else if (rarities[1] >= 3) bonus += 500;
        if (bonus > 10000) bonus = 10000;
        s.raw += baseRaw * bonus / 10000;
        s.productive += baseProductive * bonus / 10000;
        if (s.raw > baseRaw * 2) s.raw = baseRaw * 2;
        if (s.productive > baseProductive * 2) s.productive = baseProductive * 2;
        uint256 savings;
        if (s.mask & 136 == 136) savings += 1500;
        if (s.mask & 48 == 48) savings += 2000;
        s.power = s.productive * (10000 - savings) / 10000;
    }

    /// @dev Per-event flags of the reference model, grouped so the model compiles without via-IR.
    struct Ev {
        uint256 word;
        bool local;
        bool surge;
        uint256 mask;
        uint256 target;
    }

    function _eager(RefFarm memory f, address p, uint256 e, FarmRewards.Epoch memory snap)
        private
        pure
        returns (RefFarm memory, Stats memory before_, Stats memory after_)
    {
        before_ = _stats(f, e);
        Ev memory v;
        v.word = uint256(keccak256(abi.encode(snap.seed, p)));
        v.local = uint256(keccak256(abi.encodePacked(p))) % 8 == snap.district;
        v.mask = before_.mask;
        v.surge =
            v.local && snap.kind == GridOperator.Kind.Surge && v.word % 10000 < 1000 * uint256(snap.severity) / 10000;
        bool theft =
            v.local && snap.kind == GridOperator.Kind.Theft && v.word % 10000 < 2000 * uint256(snap.severity) / 10000;
        uint256 occupied;
        for (uint256 i; i < 6; ++i) {
            if (!f.item[i].destroyed) occupied++;
        }
        v.target = occupied == 0 ? type(uint256).max : (v.word >> 64) % occupied;
        if (theft && v.mask & 1280 != 1280) f.theftUntil = e + 2;
        _damage(f, v, snap);
        after_ = _stats(f, e);
        _settleRef(f, v, snap, before_, after_);
        return (f, before_, after_);
    }

    function _damage(RefFarm memory f, Ev memory v, FarmRewards.Epoch memory snap) private pure {
        uint256 cursor;
        for (uint256 i; i < 6; ++i) {
            RefItem memory x = f.item[i];
            if (x.destroyed) continue;
            uint256 damage;
            if (v.surge && cursor == v.target && v.mask & 2056 != 2056) {
                if ((v.word >> 128) % 100 < 2 && x.rarity < 3) {
                    f.item[i].destroyed = true;
                    cursor++;
                    continue;
                }
                damage = 5000;
            }
            if (v.local && snap.kind == GridOperator.Kind.Fire && v.mask & 136 != 136) {
                damage += 3000 * uint256(snap.severity) / 10000 / (v.mask & 1088 == 1088 ? 2 : 1);
            }
            f.item[i].health = uint16(x.health > damage ? x.health - damage : 0);
            cursor++;
        }
    }

    function _settleRef(
        RefFarm memory f,
        Ev memory v,
        FarmRewards.Epoch memory snap,
        Stats memory before_,
        Stats memory after_
    ) private pure {
        bool local = v.local;
        uint256 mask = v.mask;
        if (local && snap.kind == GridOperator.Kind.Outage && v.word % 10000 < 3000 * uint256(snap.severity) / 10000) {
            after_.productive = mask & 48 == 48 ? after_.productive / 2 : 0;
            after_.power = mask & 48 == 48 ? after_.power / 2 : 0;
        }
        if (local && snap.kind == GridOperator.Kind.Fire && after_.mask & 192 == 0) {
            after_.productive = 0;
            after_.power = 0;
        }
        if (local && snap.kind == GridOperator.Kind.Green) {
            after_.productive = after_.productive * (10000 + uint256(snap.severity) / 10) / 10000;
            after_.power = after_.power * (10000 + uint256(snap.severity) / 10) / 10000;
        }
        uint256 gross = snap.rewardPerHash * after_.productive / 1e27;
        uint256 electricity = snap.rewardPerHash * after_.power / 1e27 * snap.tariff / 10000;
        if (snap.kind == GridOperator.Kind.Cheap && local) electricity /= 2;
        uint256 audit = snap.kind == GridOperator.Kind.Audit && before_.raw > snap.auditThreshold ? gross / 10 : 0;
        f.earned += gross - audit - (electricity > gross - audit ? gross - audit : electricity);
        for (uint256 i; i < 6; ++i) {
            if (!f.item[i].destroyed) {
                uint16 health = f.item[i].health;
                f.item[i].health = health > 100 ? health - 100 : 0;
            }
        }
    }

    function _closeOnly() private {
        entropy();
        vm.warp(d.rewards.epochEnd());
        d.rewards.advanceEpoch();
    }

    function testFuzzLazyEqualsIndependentEagerForRandomFarmsAndAllEvents(uint256 seed) public {
        fund(100_000_000 ether);
        RefFarm[2] memory ref;
        uint256[6][2] memory ids;
        address[2] memory players = [alice, bob];
        for (uint256 p; p < 2; ++p) {
            uint256 quote = d.packs.quote(112);
            vm.prank(players[p]);
            d.packs.openPack(112);
            veteran(players[p]);
            uint8[12] memory kinds;
            for (uint8 k; k < 12; ++k) {
                kinds[k] = k;
            }
            for (uint256 i; i < 6; ++i) {
                uint256 random = uint256(keccak256(abi.encode(seed, p, i)));
                uint256 j = i + random % (12 - i);
                (kinds[i], kinds[j]) = (kinds[j], kinds[i]);
                uint8 rarity = uint8((random >> 32) % 5);
                uint8 overclock = uint8((random >> 48) % 6);
                uint16 health = uint16((random >> 64) % 10001);
                ids[p][i] = mintItem(players[p], kinds[i], rarity);
                vm.prank(address(d.farm));
                d.items.maintain(ids[p][i], health, overclock);
                vm.prank(players[p]);
                d.farm.place(ids[p][i], 0, i);
                ref[p].item[i] = RefItem(kinds[i], rarity, overclock, health, false);
            }
        }
        _closeOnly(); // Equipment starts in epoch 2; no retroactive epoch 1 reward.
        for (uint256 n; n < 8; ++n) {
            uint256 id = d.rewards.epoch();
            bytes32 eventSeed = keccak256(abi.encode(seed, n, "event"));
            uint16 severity = uint16(5000 + uint256(eventSeed) % 5001);
            uint8 district = uint8(d.farm.district(players[n % 2]));
            vm.mockCall(
                address(d.grid),
                abi.encodeCall(d.grid.eventAt, (id)),
                abi.encode(GridOperator.Kind(n), severity, district, eventSeed, true)
            );
            _closeOnly();
            FarmRewards.Epoch memory snap = d.rewards.epochData(id);
            for (uint256 p; p < 2; ++p) {
                (ref[p],,) = _eager(ref[p], players[p], id, snap);
            }
            // One farm settles eagerly, the other waits nine closed epochs and uses chunks.
            d.rewards.settle(alice, 8);
        }
        d.rewards.settle(bob, 3);
        d.rewards.settle(bob, 2);
        d.rewards.settle(bob, 8);
        for (uint256 p; p < 2; ++p) {
            assertEq(d.rewards.pending(players[p]), ref[p].earned, "eager/lazy exact payout");
            for (uint256 i; i < 6; ++i) {
                if (ref[p].item[i].destroyed) assertEq(d.items.data(ids[p][i]).holder, address(0));
                else assertEq(d.items.data(ids[p][i]).durability, ref[p].item[i].health, "eager/lazy durability");
            }
            uint256 pending = d.rewards.pending(players[p]);
            uint256 reserved = d.pool.reserved();
            d.rewards.settle(players[p], 8);
            assertEq(d.rewards.pending(players[p]), pending);
            assertEq(d.pool.reserved(), reserved);
        }
        assertLe(d.rewards.pending(alice) + d.rewards.pending(bob), d.pool.reserved());
    }

    function testStaleActionsRequireChunksAndNeverBlockGlobalAdvance() public {
        fund(10_000_000 ether);
        place(alice, 0, 0, 0);
        for (uint256 i; i < 20; ++i) {
            _closeOnly();
        }
        assertEq(d.rewards.lastSettled(alice), 0);
        assertEq(d.rewards.epoch(), 21);
        vm.expectRevert(CatchUpRequired.selector);
        vm.prank(alice);
        d.farm.unplace(0, 0);
        assertEq(d.rewards.lastSettled(alice), 0, "reverted action rolls back auto-settle");
        d.rewards.settle(alice, 8);
        d.rewards.settle(alice, 8);
        vm.prank(alice);
        d.farm.unplace(0, 0);
        assertEq(d.rewards.lastSettled(alice), 20);
        assertEq(d.rewards.nextTotalHash(), 0);
    }

    function testClaimCatchesUpWhilePacksPausedAndDoesNotEraseRemainingHistory() public {
        fund(10_000_000 ether);
        place(alice, 0, 0, 0);
        for (uint256 i; i < 12; ++i) {
            _closeOnly();
        }
        vm.prank(swarm);
        d.packs.pause(72 hours);
        vm.prank(alice);
        d.rewards.claim(1);
        assertEq(d.rewards.lastSettled(alice), 8);
        d.rewards.settle(alice, 8);
        uint256 amount = d.rewards.pending(alice);
        assertGt(amount, 0);
        vm.prank(alice);
        d.rewards.claim(amount);
        assertEq(d.rewards.pending(alice), 0);
    }

    function testLateSeasonSettlementPaysMiningWithoutChangingFrozenWinners() public {
        fund(100_000_000 ether);
        place(alice, 0, 0, 0);
        place(bob, 0, 0, 0);
        for (uint256 i; i < 28; ++i) {
            _closeOnly();
            d.rewards.settle(alice, 8);
        }
        assertTrue(d.season.completed(0, alice));
        assertFalse(d.season.completed(0, bob));
        vm.warp(d.season.deadline(0));
        d.season.prepare(0, 64);
        entropy();
        d.season.finalize(0);
        (,, address before_,, bytes32 seed) = d.season.result(0);
        for (uint256 i; i < 4; ++i) {
            d.rewards.settle(bob, 8);
        }
        assertGt(d.rewards.pending(bob), 0);
        (,, address after_,, bytes32 afterSeed) = d.season.result(0);
        assertEq(before_, after_);
        assertEq(seed, afterSeed);
        assertEq(d.season.index(0, bob), 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(bob);
        d.season.claimDistrict(0);
    }

    function testSparseMatureVintageConsumedBeforeRecentSlotAfterWrap() public {
        fund(1000 ether);
        vm.prank(address(d.rewards));
        d.pool.reserve(200 ether);
        vm.prank(address(d.season));
        d.rewards.award(alice, 100 ether); // epoch1 slot1
        for (uint256 i; i < 31; ++i) {
            _closeOnly();
        }
        vm.prank(address(d.season));
        d.rewards.award(alice, 100 ether); // epoch32 slot0
        _closeOnly();
        _closeOnly(); // epoch34 starts ring traversal at slot3
        uint256 before_ = token.balanceOf(alice);
        vm.prank(alice);
        d.rewards.claim(100 ether);
        assertEq(token.balanceOf(alice) - before_, 95 ether);
        assertEq(d.rewards.pending(alice), 100 ether);
    }

    function testGlobalAccumulatorAndWeightsAreSnapshottedBeforeMutations() public {
        fund(10_000_000 ether);
        payPack(alice);
        payPack(bob);
        place(alice, 0, 0, 0);
        place(alice, 1, 0, 1);
        place(bob, 0, 0, 0);
        _closeOnly();
        assertEq(d.rewards.epochData(2).raw, 32000);
        vm.prank(alice);
        d.farm.unplace(0, 1);
        assertEq(d.rewards.epochData(2).raw, 32000);
        assertEq(d.rewards.nextTotalHash(), 20000);
        uint256 available = d.pool.available();
        uint256 beforeIndex = d.rewards.accRewardPerHash();
        _closeOnly();
        FarmRewards.Epoch memory e = d.rewards.epochData(2);
        assertEq(e.mining, available * 350 / 40000);
        assertEq(e.rewardPerHash, e.mining * 1e27 / 32000);
        assertEq(e.accRewardPerHash, beforeIndex + e.rewardPerHash);
        assertEq(d.rewards.epochData(3).raw, 20000);
        d.rewards.settle(alice, 8);
        (uint256 raw,,,) = d.rewards.shares(2, alice);
        assertEq(raw, 22000, "withdraw does not edit past active snapshot");
    }

    function testExhaustedFarmCannotCollectRedistributionByRemainingIdle() public {
        fund(10_000_000 ether);
        uint256 id = mintItem(alice, 0, 0);
        vm.prank(address(d.farm));
        d.items.maintain(id, 0, 0);
        vm.prank(alice);
        d.farm.place(id, 0, 0);
        payPack(bob);
        place(bob, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        uint256 claimed = d.rewards.pending(bob);
        vm.prank(bob);
        d.rewards.claim(claimed);
        assertGt(d.rewards.queuedTax(), 0);
        calmNext();
        step();
        assertGt(d.rewards.currentRedis(), 0);
        calmNext();
        step();
        assertGt(d.rewards.epochData(4).redis, 0);
        assertEq(d.rewards.pending(alice), 0);
        assertGt(d.rewards.farmWeight(alice, 4), 0, "allocated but exhausted");
        assertLe(d.pool.reserved(), token.balanceOf(address(d.pool)));
    }

    function testAuditChargesTenPercentEvenAtHalfSeverityAndThresholdIsFrozen() public {
        fund(10_000_000 ether);
        payPack(alice);
        place(alice, 0, 1, 0); // 28000 raw, above snapshotted 20000 threshold.
        vm.mockCall(
            address(d.params), abi.encodeCall(d.params.get, (Params.Key.AuditHashThreshold)), abi.encode(uint256(20000))
        );
        _closeOnly();
        vm.mockCall(
            address(d.params), abi.encodeCall(d.params.get, (Params.Key.AuditHashThreshold)), abi.encode(uint256(30000))
        );
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(GridOperator.Kind.Audit, uint16(5000), uint8(0), bytes32(uint256(12)), true)
        );
        _closeOnly();
        // Later Grid responses also cannot change the stored event.
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(GridOperator.Kind.Calm, uint16(10000), uint8(0), bytes32(uint256(99)), true)
        );
        d.rewards.settle(alice, 8);
        FarmRewards.Epoch memory e = d.rewards.epochData(2);
        uint256 gross = e.rewardPerHash * 28000 / 1e27;
        assertEq(d.rewards.pending(alice), gross - gross / 10 - gross * 1500 / 10000);
        (,,, bool audit) = d.rewards.shares(2, alice);
        assertTrue(audit);
        assertEq(e.auditThreshold, 20000);
    }

    function testOneWeiMiningGreenCannotLockSettlementThroughEnvelopeRounding() public {
        fund(115); // 115 * 350 / 40000 = one wei of mining.
        uint256 quote = d.packs.quote(112);
        vm.prank(alice);
        d.packs.openPack(112);
        veteran(alice);
        payPack(bob);
        place(alice, 0, 3, 0); // 250000 / 260000 of total allocation.
        place(bob, 0, 0, 0);
        deal(address(token), address(d.pool), 115); // Isolate the one-wei rounding case after token pack inflows.
        _closeOnly();
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(
                GridOperator.Kind.Green, uint16(10000), uint8(d.farm.district(alice)), bytes32(uint256(12)), true
            )
        );
        _closeOnly();
        assertEq(d.rewards.epochData(2).mining, 1);
        d.rewards.settle(alice, 8);
        d.rewards.settle(bob, 8);
        assertEq(d.rewards.pending(alice), 1);
        assertEq(d.rewards.pending(bob), 0);
        assertEq(d.pool.reserved(), 1);
        assertEq(d.rewards.lastSettled(alice), 2);
        assertEq(d.rewards.lastSettled(bob), 2);
    }
}
