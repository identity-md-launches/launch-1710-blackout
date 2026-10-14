// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";

contract IndependentAutoRepairReview is BaseTest {
    function _prepareAutomaticRepair() private returns (uint256 item) {
        fund(1_000_000 ether);
        item = place(alice, 0, 0, 0);
        vm.prank(alice);
        d.farm.setAutoRepair(true, 10000);
    }

    function testAutomaticRepairRecordsHistoricalWeekBeforeCompletion() public {
        uint256 item = _prepareAutomaticRepair();
        entropy();
        vm.warp(tokenLaunch() + 7 days);
        d.rewards.advanceEpoch();
        d.rewards.settle(alice, 8);
        assertEq(d.items.data(item).durability, 10000);
        assertGt(d.season.spend(0, alice), 0);
        assertEq(d.season.spend(0, alice), d.season.districtSpendOf(0, alice));
        assertEq(d.season.spend(1, alice), 0);
        assertEq(d.season.eligiblePayers(0, d.farm.district(alice)), 1);
        assertTrue(d.season.completed(0, alice));
    }

    function testLateAutomaticRepairCannotReopenSeasonEligibility() public {
        uint256 item = _prepareAutomaticRepair();
        entropy();
        vm.warp(d.season.deadline(0));
        d.rewards.advanceEpoch();
        d.rewards.settle(alice, 8);
        assertEq(d.items.data(item).durability, 10000);
        assertEq(d.season.spend(0, alice), 0);
        assertEq(d.season.districtSpendOf(0, alice), 0);
        assertEq(d.season.eligiblePayers(0, d.farm.district(alice)), 0);
    }
}
