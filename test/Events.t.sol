// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {DeferredEntryTest} from "./Base.t.sol";
import {GridOperator} from "../src/GridOperator.sol";
import "../src/lib/Errors.sol";

contract EventsTest is DeferredEntryTest {
    function testPlansOnlyNextTwoOnceAndBoundedSeverity() public {
        vm.expectRevert(Unauthorized.selector);
        d.grid.submitPlan(2, GridOperator.Kind.Outage, 10000, bytes32(uint256(9)), "bad authority");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.grid.submitPlan(1, GridOperator.Kind.Outage, 10000, bytes32(uint256(9)), "current");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.grid.submitPlan(4, GridOperator.Kind.Outage, 10000, bytes32(uint256(9)), "far");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.grid.submitPlan(2, GridOperator.Kind.Outage, 10001, bytes32(uint256(9)), "severity");
        vm.prank(swarm);
        d.grid.submitPlan(2, GridOperator.Kind.Outage, 10000, bytes32(uint256(9)), "valid");
        vm.expectRevert(AlreadyDone.selector);
        vm.prank(swarm);
        d.grid.submitPlan(2, GridOperator.Kind.Calm, 10000, bytes32(uint256(8)), "overwrite");
    }

    /// @dev v3.17 (audit 339b6b19 low 2): a lapsed window re-arms instead of using a precomputable fallback seed.
    function testFallbackAndExpiredSeedIndependentOfSwarmNumber() public {
        vm.roll(vm.getBlockNumber() + 300);
        assertFalse(d.grid.resolve(1));
        (GridOperator.Kind k,,, bytes32 seed, bool resolved) = d.grid.eventAt(1);
        assertFalse(resolved);
        uint64 fresh = d.grid.eventTarget(1);
        vm.roll(uint256(fresh) + 1);
        vm.setBlockhash(fresh, keccak256("fresh 1"));
        assertTrue(d.grid.resolve(1));
        (k,,, seed, resolved) = d.grid.eventAt(1);
        assertTrue(resolved);
        assertTrue(seed != keccak256(abi.encode(address(d.grid), uint256(1), "fixed fallback")));
        assertEq(seed, keccak256(abi.encode(bytes32(0), keccak256("fresh 1"), address(d.grid), uint256(1))));
        vm.prank(swarm);
        d.grid.submitPlan(2, GridOperator.Kind.Surge, 10000, keccak256("attacker grinding"), "expired plan");
        vm.warp(d.rewards.epochEnd());
        d.rewards.advanceEpoch();
        finish();
        vm.roll(vm.getBlockNumber() + 300);
        assertFalse(d.grid.resolve(2));
        fresh = d.grid.eventTarget(2);
        vm.roll(uint256(fresh) + 1);
        vm.setBlockhash(fresh, keccak256("fresh 2"));
        assertTrue(d.grid.resolve(2));
        (k,,, seed,) = d.grid.eventAt(2);
        assertEq(uint256(k), uint256(GridOperator.Kind.Surge), "the submitted plan survives a lapsed window");
        assertEq(
            seed,
            keccak256(abi.encode(keccak256("attacker grinding"), keccak256("fresh 2"), address(d.grid), uint256(2)))
        );
    }

    function testRollingCapsAndInitialPositiveQuotaWithHostilePlans() public {
        uint256[8] memory last;
        for (uint256 i; i < 60; ++i) {
            uint256 e = d.rewards.epoch();
            entropy();
            d.grid.resolve(e);
            (GridOperator.Kind current,, uint8 district,,) = d.grid.eventAt(e);
            if (current == GridOperator.Kind.Outage) {
                uint256 start = d.rewards.epochStart();
                if (last[district] != 0) assertGe(start, last[district] + 2 days);
                last[district] = start;
            }
            if (e >= 20) {
                uint256 positives;
                uint256 negatives;
                for (uint256 j = e - 19; j <= e; ++j) {
                    (GridOperator.Kind k,,,,) = d.grid.eventAt(j);
                    if (k == GridOperator.Kind.Green || k == GridOperator.Kind.Cheap) positives++;
                    if (k == GridOperator.Kind.Outage) negatives++;
                }
                assertGe(positives, 4);
                assertLe(negatives, 4);
            }
            vm.prank(swarm);
            d.grid
                .submitPlan(
                    e + 1,
                    i < 20 ? GridOperator.Kind.Calm : GridOperator.Kind.Outage,
                    10000,
                    bytes32(i + 1),
                    "Quota adversary"
                );
            step();
        }
    }

    function testLobbyOwnDistrictSplitDecayAndMinimumWeight() public {
        vm.prank(alice);
        d.farm.register(alice);
        uint256 district = d.grid.district(alice);
        uint256 before_ = d.grid.lobbyWeight(district);
        uint256 amount = d.economy.lobbyQuote(alice);
        vm.prank(alice);
        d.farm.lobby(amount, true);
        assertLt(d.grid.lobbyWeight(district), before_);
        assertEq(d.fees.teamTokens(), amount / 10);
        assertEq(d.fees.heartbeatTokens(), amount * 2 / 100);
        vm.warp(launch + 3 days - 1);
        assertEq(d.grid.lobbyAmount(district), amount);
        vm.warp(launch + 3 days);
        assertEq(d.grid.lobbyAmount(district), 0);
        assertGe(d.grid.lobbyWeight(district), 5000);
    }

    function _force(GridOperator.Kind k, uint256 threshold, bool destroy) internal returns (bytes32 seed) {
        for (uint256 i;; ++i) {
            seed = bytes32(i + 1);
            uint256 r = uint256(keccak256(abi.encode(seed, alice)));
            if (r % 10000 < threshold && (!destroy || (r >> 128) % 100 < 2)) break;
        }
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(k, uint16(10000), uint8(d.farm.district(alice)), seed, true)
        );
    }

    function testOutageAndOffgridRoomMitigation() public {
        payPack(alice);
        place(alice, 4, 0, 0);
        place(alice, 5, 0, 1);
        calmNext();
        step();
        _force(GridOperator.Kind.Outage, 3000, false);
        step();
        (uint256 raw, uint256 productive,,) = d.rewards.shares(2, alice);
        assertEq(raw, 12000);
        assertEq(productive, 6000);
    }

    function testSurgeDamagesExactlyOneItemAndCleanPowerImmune() public {
        payPack(alice);
        uint256 gpu = place(alice, 0, 0, 0);
        calmNext();
        step();
        bytes32 seed = _force(GridOperator.Kind.Surge, 1000, false);
        // Avoid the destruction branch for the durability test.
        while ((uint256(keccak256(abi.encode(seed, alice))) >> 128) % 100 < 2) seed = bytes32(uint256(seed) + 1);
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(GridOperator.Kind.Surge, uint16(10000), uint8(d.farm.district(alice)), seed, true)
        );
        step();
        assertEq(d.items.data(gpu).durability, 4900);
    }

    function testSurgeCanDestroyCommonButNeverLegendary() public {
        payPack(alice);
        uint256 gpu = place(alice, 0, 0, 0);
        calmNext();
        step();
        _force(GridOperator.Kind.Surge, 1000, true);
        step();
        assertEq(d.items.data(gpu).holder, address(0));
        assertEq(d.farm.itemAt(alice, 0, 0), 0);
    }

    function testFireNoCoolingZeroYieldColdPowerImmune() public {
        payPack(alice);
        uint256 gpu = place(alice, 0, 0, 0);
        calmNext();
        step();
        _force(GridOperator.Kind.Fire, 10000, false);
        step();
        (uint256 raw, uint256 productive,,) = d.rewards.shares(2, alice);
        assertEq(raw, 10000);
        assertEq(productive, 0);
        assertEq(d.items.data(gpu).durability, 6900);
    }

    function testColdPowerFireImmuneAndCleanPowerSurgeImmune() public {
        payPack(alice);
        uint256 psu = place(alice, 3, 0, 0);
        uint256 cooling = place(alice, 7, 0, 1);
        uint256 surge = place(alice, 11, 0, 2);
        calmNext();
        step();
        _force(GridOperator.Kind.Fire, 10000, false);
        step();
        (, uint256 productive,,) = d.rewards.shares(2, alice);
        assertEq(productive, 18000);
        assertEq(d.items.data(psu).durability, 9900);
        assertEq(d.items.data(cooling).durability, 9900);
        assertEq(d.items.data(surge).durability, 9900);
    }

    function testTheftRouterDisabledAndRepairRestores() public {
        payPack(alice);
        uint256 router = place(alice, 8, 0, 0);
        calmNext();
        step();
        _force(GridOperator.Kind.Theft, 2000, false);
        step();
        (, uint256 productive,,) = d.rewards.shares(2, alice);
        assertEq(productive, 0);
        vm.prank(alice);
        d.farm.repairCable(true);
        assertGt(d.farm.roomStats(alice, 0).raw, 0);
        assertEq(d.items.data(router).durability, 9900);
    }

    function testSurgeNeverDestroysLegendaryOrMythic() public {
        uint256 price = d.packs.quote(112);
        vm.prank(alice);
        d.packs.openPack(112);
        veteran(alice);
        uint256 legend = place(alice, 0, 3, 0);
        uint256 mythic = place(alice, 1, 4, 1);
        calmNext();
        step();
        _force(GridOperator.Kind.Surge, 1000, true);
        step();
        assertEq(d.items.data(legend).holder, alice);
        assertEq(d.items.data(mythic).holder, alice);
        assertEq(uint256(d.items.data(legend).durability) + d.items.data(mythic).durability, 14800);
    }

    function testCheapTariffAppliesCitywide() public {
        fund(1_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        uint256 mining = d.pool.available() * 350 / 40000;
        _force(GridOperator.Kind.Cheap, 10000, false);
        step();
        assertEq(d.rewards.pending(alice), mining - mining * 1500 / 10000 / 2);
    }

    function testGreenWaveRaisesDistrictMiningTenPercent() public {
        fund(1_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        uint256 mining = d.pool.available() * 350 / 40000;
        _force(GridOperator.Kind.Green, 10000, false);
        step();
        uint256 gross = mining * 11000 / 10000;
        assertEq(d.rewards.pending(alice), gross - gross * 1500 / 10000);
    }
}
