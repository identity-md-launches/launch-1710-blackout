// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {FarmItems} from "../src/FarmItems.sol";
import {GridOperator} from "../src/GridOperator.sol";
import "../src/lib/Errors.sol";

/// @notice Pre-token audit 339b6b19 (v3.17): the four reproductions are kept as permanent tests and now assert the
/// fixed behaviour. 1 medium (Enhancement re-roll), 3 low (GridOperator fallback seed, Economy.unlock liveness,
/// destroyed item keeps committed weight).
contract AuditV317Test is BaseTest {
    // ---------------------------------------------------------------- 1. medium: Enhancement re-roll

    /// @dev Outcome rank: burned 0, otherwise the item's resulting level + 1. Higher is better for the player.
    function _score(uint256 item) private view returns (uint256) {
        FarmItems.Item memory x = d.items.data(item);
        return x.holder == address(0) ? 0 : uint256(x.overclock) + 1;
    }

    function _attempt(uint8 target) private returns (uint256 item, uint256 id, uint64 blockTarget) {
        item = mintItem(alice, 1, 0);
        vm.prank(address(d.farm));
        d.items.maintain(item, 10000, target - 1);
        vm.prank(alice);
        id = d.enhancement.commit(item, type(uint256).max, true);
        (,, blockTarget,,,,) = d.enhancement.attempts(id);
    }

    function _discard(uint256 item) private {
        if (d.items.data(item).holder != address(0)) {
            vm.prank(address(d.farm));
            d.items.destroy(item);
        }
    }

    /// @notice Audit reproduction: a player who reads the outcome off-chain can no longer let a failure or burn
    /// lapse and re-arm. A lapsed attempt is settled at once with the worst outcome of its level, and that outcome
    /// is never better than any resolution the seed could have produced.
    function testEnhancementRearmGrind() public {
        vm.prank(alice);
        d.farm.register(alice);
        veteran(alice);
        for (uint8 target = 1; target <= 8; ++target) {
            (uint256 item, uint256 id, uint64 blockTarget) = _attempt(target);
            vm.roll(uint256(blockTarget) + 257); // the 256-block hash window has lapsed
            uint256 pendingBefore = d.enhancement.pending(item);
            assertEq(pendingBefore, id);
            d.enhancement.capture(id); // the grinder's "let it expire" path
            (bool burned, uint8 level) = d.enhancement.worstOutcome(target);
            assertEq(burned, target >= 6, "burn chance exists from level 6");
            assertEq(level, target >= 4 ? target - 2 : target - 1, "levels 1-3 keep their level, 4+ lose one");
            uint256 lapsed = _score(item);
            assertEq(lapsed, burned ? 0 : uint256(level) + 1, "lapsed attempt applied the worst outcome");
            assertEq(d.enhancement.pending(item), 0, "the item is free again");
            (,, uint64 after_,, bytes32 seed, bool captured, bool resolved) = d.enhancement.attempts(id);
            assertEq(after_, blockTarget, "no re-arm");
            assertEq(seed, bytes32(0));
            assertTrue(captured && resolved);
            vm.expectRevert(InvalidValue.selector);
            d.enhancement.resolve(id);
            vm.expectRevert(InvalidValue.selector);
            d.enhancement.capture(id);
            _discard(item);
            _resolveManySeeds(target, lapsed);
        }
    }

    /// @dev Every seed resolves at least as well as lapsing: success > keep > drop > burn.
    function _resolveManySeeds(uint8 target, uint256 lapsed) private {
        for (uint256 k = 1; k <= 6; ++k) {
            (uint256 item, uint256 id, uint64 t) = _attempt(target);
            vm.roll(uint256(t) + 1);
            vm.setBlockhash(t, keccak256(abi.encode(target, k, "seed")));
            d.enhancement.resolve(id);
            assertGe(_score(item), lapsed, "resolving is never worse than lapsing");
            _discard(item);
        }
    }

    function testEnhancementLapseEmitsResolvedAsFailureAndKeepsSoulboundChecks() public {
        vm.prank(alice);
        d.farm.register(alice);
        veteran(alice);
        (uint256 item, uint256 id, uint64 blockTarget) = _attempt(6); // 10% burn chance: lapse burns
        vm.roll(uint256(blockTarget) + 257);
        vm.expectEmit(true, false, false, true, address(d.enhancement));
        emit EnhancementLapsed(id, true, 4);
        vm.expectEmit(true, false, false, true, address(d.enhancement));
        emit EnhancementResolved(id, false, true, 4);
        d.enhancement.resolve(id);
        assertEq(d.items.data(item).holder, address(0), "a level with any burn chance burns on lapse");
        (uint256 item2, uint256 id2, uint64 t2) = _attempt(3);
        vm.roll(uint256(t2) + 257);
        d.enhancement.resolve(id2);
        assertEq(d.items.data(item2).overclock, 2, "levels 1-3 keep their level on lapse");
        assertEq(d.items.data(item2).holder, alice);
    }

    function testEnhancementInsideWindowStillCapturesAndResolvesNormally() public {
        (uint256 item, uint256 id, uint64 blockTarget) = _attempt(1);
        vm.expectRevert(TooEarly.selector);
        d.enhancement.capture(id);
        vm.roll(uint256(blockTarget) + 1);
        vm.setBlockhash(blockTarget, keccak256("in window"));
        d.enhancement.capture(id);
        (,,,, bytes32 seed, bool captured, bool resolved) = d.enhancement.attempts(id);
        assertTrue(captured && !resolved);
        assertEq(seed, keccak256(abi.encode(keccak256("in window"), address(d.enhancement), id)));
        vm.roll(uint256(blockTarget) + 400); // a captured seed never lapses
        d.enhancement.resolve(id);
        assertEq(d.items.data(item).overclock, uint256(seed) % 100 < 95 ? 1 : 0);
    }

    event EnhancementLapsed(uint256 indexed id, bool burned, uint256 level);
    event EnhancementResolved(uint256 indexed id, bool success, bool burned, uint256 level);

    // ---------------------------------------------------------------- 2. low: GridOperator fallback seed

    /// @notice Audit reproduction: a plan whose window lapsed was dropped for a seed computable before the epoch.
    /// Now the event is re-armed and the attested plan is applied with the fresh block hash.
    function testSubmittedPlanDiscardedAfterHashWindow() public {
        uint256 e = d.rewards.epoch() + 1;
        vm.prank(swarm);
        d.grid.submitPlan(e, GridOperator.Kind.Surge, 6000, keccak256("plan"), "attested plan");
        step();
        assertEq(d.rewards.epoch(), e);
        uint64 first = d.grid.eventTarget(e);
        vm.roll(uint256(first) + 300); // nobody resolved inside the window
        bytes32 precomputable = keccak256(abi.encode(address(d.grid), e, "fixed fallback"));
        assertFalse(d.grid.resolve(e), "lapsed window re-arms instead of resolving");
        (,,,, bool resolved) = d.grid.eventAt(e);
        assertFalse(resolved);
        uint64 fresh = d.grid.eventTarget(e);
        assertEq(fresh, vm.getBlockNumber() + 2, "re-armed to a future block");
        vm.expectRevert(TooEarly.selector);
        d.grid.resolve(e);
        vm.roll(uint256(fresh) + 1);
        vm.setBlockhash(fresh, keccak256("fresh"));
        assertTrue(d.grid.resolve(e));
        (GridOperator.Kind k, uint16 severity,, bytes32 seed, bool r) = d.grid.eventAt(e);
        assertTrue(r);
        assertEq(uint256(k), uint256(GridOperator.Kind.Surge), "the attested plan is still applied");
        assertEq(severity, 6000);
        assertEq(seed, keccak256(abi.encode(keccak256("plan"), keccak256("fresh"), address(d.grid), e)));
        assertTrue(seed != precomputable);
    }

    function testUnplannedLapsedWindowAlsoRearmsAndNeverUsesAPrecomputableSeed() public {
        uint256 e = d.rewards.epoch();
        uint64 first = d.grid.eventTarget(e);
        vm.roll(uint256(first) + 300);
        assertFalse(d.grid.resolve(e));
        uint64 fresh = d.grid.eventTarget(e);
        vm.roll(uint256(fresh) + 1);
        vm.setBlockhash(fresh, keccak256("fresh fallback"));
        assertTrue(d.grid.resolve(e));
        (,,, bytes32 seed, bool r) = d.grid.eventAt(e);
        assertTrue(r);
        assertEq(seed, keccak256(abi.encode(bytes32(0), keccak256("fresh fallback"), address(d.grid), e)));
        assertTrue(seed != keccak256(abi.encode(address(d.grid), e, "fixed fallback")));
    }

    function testAdvanceEpochDefersUntilTheRearmedEventResolves() public {
        uint256 e = d.rewards.epoch();
        vm.warp(d.rewards.epochEnd());
        vm.roll(uint256(d.grid.eventTarget(e)) + 300);
        d.rewards.advanceEpoch();
        assertEq(d.rewards.epoch(), e, "the epoch is not closed with an unresolved event");
        (,,,, bool resolved) = d.grid.eventAt(e);
        assertFalse(resolved);
        uint64 fresh = d.grid.eventTarget(e);
        vm.roll(uint256(fresh) + 1);
        vm.setBlockhash(fresh, keccak256("deferred close"));
        d.rewards.advanceEpoch();
        assertEq(d.rewards.epoch(), e + 1);
        (,,,, resolved) = d.rewards.eventAt(e);
        assertTrue(resolved, "the closed epoch carries the resolved event");
    }

    // ---------------------------------------------------------------- 3. low: Economy.unlock while stale

    /// @notice Audit reproduction: unlock reverted TooEarly when no epoch was live. The principal is now returned
    /// and the weight resync is skipped.
    function testUnlockBlockedWhileEpochStale() public {
        (uint256 minimum,) = d.economy.lockQuote(alice, 7);
        vm.prank(alice);
        d.economy.lock(minimum, 7);
        uint256 balance = token.balanceOf(alice);
        vm.warp(vm.getBlockTimestamp() + 7 days);
        assertFalse(d.rewards.live(), "the epoch went stale");
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.farm.sync();
        vm.prank(alice);
        d.economy.unlock();
        assertEq(token.balanceOf(alice), balance + minimum, "principal returned");
        (uint256 amount,,,) = d.economy.locks(alice);
        assertEq(amount, 0);
        assertEq(d.economy.districtTotal(d.economy.district(alice)), 0);
        assertEq(d.economy.totalLocked(), 0);
        assertEq(d.economy.head(d.economy.district(alice)), address(0));
    }

    function testUnlockWhileBehindReturnsPrincipalAndSkipsResync() public {
        fund(800_000_000 ether);
        place(alice, 0, 1, 0);
        (uint256 minimum,) = d.economy.lockQuote(alice, 7); // floor-priced before any settlement
        vm.prank(alice);
        d.economy.lock(minimum, 7);
        uint256 boosted = d.rewards.configuredWeight(alice);
        assertEq(boosted, d.farm.committedHash(alice));
        // 29 epochs pass without anyone settling alice: she is more than MAX_SETTLE behind.
        for (uint256 i; i < 29; ++i) {
            entropy();
            vm.warp(d.rewards.epochEnd());
            d.rewards.advanceEpoch();
        }
        assertTrue(d.rewards.live());
        assertGt(d.rewards.settledEpoch(), d.rewards.lastSettled(alice) + 8);
        vm.expectRevert(CatchUpRequired.selector);
        vm.prank(alice);
        d.farm.sync();
        uint256 balance = token.balanceOf(alice);
        vm.prank(alice);
        d.economy.unlock();
        assertEq(token.balanceOf(alice), balance + minimum);
        assertEq(d.rewards.configuredWeight(alice), boosted, "resync skipped while behind");
        assertEq(d.economy.boostAt(alice, vm.getBlockTimestamp()), 0);
        // The next owner action, once caught up, drops the boost.
        while (d.rewards.lastSettled(alice) < d.rewards.settledEpoch()) d.rewards.settle(alice, 8);
        vm.prank(alice);
        d.farm.sync();
        assertEq(d.rewards.configuredWeight(alice), d.farm.committedHash(alice));
        assertLt(d.rewards.configuredWeight(alice), boosted);
    }

    function testUnlockLiveAndCaughtUpStillResyncsWeight() public {
        fund(800_000_000 ether);
        place(alice, 0, 1, 0);
        uint256 plain = d.rewards.configuredWeight(alice);
        (uint256 minimum,) = d.economy.lockQuote(alice, 7); // floor-priced before any settlement
        vm.prank(alice);
        d.economy.lock(minimum, 7);
        assertEq(d.rewards.configuredWeight(alice), plain * 10500 / 10000, "7-day lock boosts 500 bps");
        for (uint256 i; i < 29; ++i) {
            step();
        }
        vm.expectRevert(TooEarly.selector);
        vm.prank(bob);
        d.economy.unlock();
        vm.prank(alice);
        d.economy.unlock();
        assertEq(d.rewards.configuredWeight(alice), d.farm.committedHash(alice));
        assertEq(d.economy.boostAt(alice, vm.getBlockTimestamp()), 0);
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.economy.unlock();
    }

    // ---------------------------------------------------------------- 4. low: destroyed item keeps weight

    /// @dev Seed an epoch-`e` Surge on alice's district that destroys the `index`-th of her `occupied` items
    /// (rarity < 3), through the real engine path, as the event tests do.
    function _surgeDestroys(uint256 e, uint256 occupied, uint256 index) private returns (bytes32 seed) {
        for (uint256 i;; ++i) {
            seed = bytes32(i + 1);
            uint256 r = uint256(keccak256(abi.encode(seed, alice)));
            if (r % 10000 < 1000 && (r >> 128) % 100 < 2 && (r >> 64) % occupied == index) break;
        }
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (e)),
            abi.encode(GridOperator.Kind.Surge, uint16(10000), uint8(d.farm.district(alice)), seed, true)
        );
    }

    /// @notice Audit reproduction: an item destroyed while equipped was removed from the loadout at settlement but
    /// its hash stayed in the farm's commitment, the global and the district denominators.
    function testDestroyedItemWeightStale() public {
        fund(800_000_000 ether);
        place(alice, 0, 0, 0);
        uint256 b = place(alice, 1, 0, 1);
        calmNext();
        step();
        uint256 current = d.rewards.epoch();
        uint256 before_ = d.rewards.configuredWeight(alice);
        uint256 district = d.farm.district(alice);
        assertEq(d.rewards.nextTotalHash(), before_);
        assertEq(d.rewards.nextDistrictHash(district), before_);
        _surgeDestroys(current, 2, 1);
        step(); // settlement of `current` destroys item b, removes it and re-commits the farm from its loadout
        assertEq(d.items.data(b).holder, address(0), "the surge destroyed the equipped item");
        assertEq(d.farm.itemAt(alice, 0, 1), 0);
        uint256 after_ = d.rewards.configuredWeight(alice);
        assertLt(after_, before_, "the destroyed item's hash left the commitment");
        assertGt(after_, 0);
        assertEq(after_, d.farm.committedHash(alice));
        assertFalse(d.rewards.resyncDue(alice));
        assertEq(d.rewards.nextTotalHash(), after_, "global hash no longer counts it");
        assertEq(d.rewards.nextDistrictHash(district), after_, "district hash no longer counts it");
        assertEq(d.rewards.farmWeight(alice, current + 1), before_, "the open epoch keeps its snapshot");
        assertEq(d.rewards.farmWeight(alice, current + 2), after_, "the drop takes effect next epoch");
        step();
        assertEq(d.rewards.epochData(current + 2).raw, after_);
        assertEq(d.rewards.epochData(current + 1).settledHash, d.rewards.epochData(current + 1).raw);
    }

    function testDestroyedItemResyncWaitsUntilTheFarmIsCaughtUp() public {
        fund(800_000_000 ether);
        place(alice, 0, 0, 0);
        uint256 b = place(alice, 1, 0, 1);
        calmNext();
        step();
        uint256 destroyedIn = d.rewards.epoch();
        uint256 before_ = d.rewards.configuredWeight(alice);
        _surgeDestroys(destroyedIn, 2, 1);
        for (uint256 i; i < 2; ++i) {
            entropy();
            vm.warp(d.rewards.epochEnd());
            d.rewards.advanceEpoch();
        }
        assertEq(d.rewards.settledEpoch(), destroyedIn + 1);
        d.rewards.settle(alice, 1); // settles `destroyedIn`: flagged, but one closed epoch is still unsettled
        assertEq(d.items.data(b).holder, address(0));
        assertTrue(d.rewards.resyncDue(alice));
        assertEq(d.rewards.configuredWeight(alice), before_, "no commit while behind");
        d.rewards.settle(alice, 1);
        assertFalse(d.rewards.resyncDue(alice));
        uint256 after_ = d.rewards.configuredWeight(alice);
        assertEq(after_, d.farm.committedHash(alice));
        assertLt(after_, before_);
        for (uint256 e = destroyedIn; e <= destroyedIn + 1; ++e) {
            assertEq(d.rewards.epochData(e).settledHash, d.rewards.epochData(e).raw, "every settled epoch balances");
        }
        step();
        assertEq(d.rewards.epochData(destroyedIn + 3).raw, after_);
    }

    function testOwnerActionClearsThePendingResync() public {
        fund(800_000_000 ether);
        place(alice, 0, 0, 0);
        place(alice, 1, 0, 1);
        calmNext();
        step();
        _surgeDestroys(d.rewards.epoch(), 2, 0);
        step();
        assertEq(d.farm.itemAt(alice, 0, 0), 0);
        assertFalse(d.rewards.resyncDue(alice));
        vm.prank(address(d.farm));
        d.rewards.flagResync(alice);
        assertTrue(d.rewards.resyncDue(alice));
        vm.prank(alice);
        d.farm.sync();
        assertFalse(d.rewards.resyncDue(alice), "setWeight recomputed from the loadout");
        vm.expectRevert(Unauthorized.selector);
        d.rewards.flagResync(alice);
    }
}
