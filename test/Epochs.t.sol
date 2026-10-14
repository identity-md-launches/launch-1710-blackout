// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {DeferredEntryTest} from "./Base.t.sol";
import {GridOperator} from "../src/GridOperator.sol";
import {FarmRewards} from "../src/FarmRewards.sol";
import "../src/lib/Errors.sol";

contract EpochsTest is DeferredEntryTest {
    function testCannotAdvanceEarlyAndBountyOnce() public {
        payPack(alice);
        uint256 h = d.fees.heartbeatBalance();
        vm.expectRevert(TooEarly.selector);
        d.rewards.advanceEpoch();
        entropy();
        vm.warp(d.rewards.epochEnd());
        vm.prank(bob);
        d.rewards.advanceEpoch();
        assertEq(d.fees.credit(bob), h);
        assertEq(d.fees.heartbeatBalance(), 0);
        vm.expectRevert(TooEarly.selector);
        d.rewards.advanceEpoch();
        finish();
        vm.expectRevert(TooEarly.selector);
        d.rewards.advanceEpoch();
    }

    function testNoCatchupEmissionDuringGap() public {
        fund(10_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        uint256 before_ = d.pool.available();
        entropy();
        vm.warp(d.rewards.epochEnd() + 30 days);
        d.rewards.advanceEpoch();
        finish();
        assertEq(d.rewards.epoch(), 3);
        assertEq(d.rewards.epochEnd(), block.timestamp + 6 hours);
        assertGt(d.rewards.pending(alice), 0);
        assertLe(before_ - d.pool.available(), before_ * 350 * 117 / 4_000_000);
    }

    function testClaimsEveryEpochAndRedistributionIsNextEpoch() public {
        fund(10_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        uint256 pending = d.rewards.pending(alice);
        assertGt(pending, 0);
        uint256 bal = token.balanceOf(alice);
        vm.prank(alice);
        d.rewards.claim(pending);
        uint256 tax = pending * 2000 / 10000;
        assertEq(token.balanceOf(alice) - bal, pending - tax);
        assertEq(d.rewards.queuedTax(), tax);
        calmNext();
        step();
        assertEq(d.rewards.currentRedis(), tax);
        assertEq(d.rewards.queuedTax(), 0);
        calmNext();
        step();
        assertEq(d.rewards.currentRedis(), 0);
        assertGt(d.rewards.pending(alice), tax);
        assertLe(d.pool.reserved(), token.balanceOf(address(d.pool)));
    }

    function testTaxCurveExactAndFloor() public view {
        assertEq(d.rewards.taxBps(0), 2000);
        assertEq(d.rewards.taxBps(3.5 days), 1250);
        assertEq(d.rewards.taxBps(7 days), 500);
        assertEq(d.rewards.taxBps(70 days), 500);
    }

    function testNoRetroactiveEquipmentAndBoundedBatches() public {
        fund(1_000_000 ether);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        assertEq(d.rewards.pending(alice), 0);
        entropy();
        vm.warp(d.rewards.epochEnd());
        d.rewards.advanceEpoch();
        vm.expectRevert(InvalidValue.selector);
        d.rewards.settle(alice, 9);
        vm.prank(alice);
        d.farm.unplace(0, 0);
        finish();
        assertGt(d.rewards.pending(alice), 0);
    }

    function testNoWhaleCapHashShares() public {
        fund(10_000_000 ether);
        payPack(alice);
        payPack(bob);
        place(alice, 0, 0, 0);
        place(alice, 1, 0, 1);
        place(bob, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        uint256 a = d.rewards.pending(alice);
        uint256 b = d.rewards.pending(bob);
        assertApproxEqAbs(a * 10, b * 22, 30);
    }

    function testReferralOneLevelSetOnceNoSelf() public {
        vm.prank(alice);
        d.farm.register(alice);
        vm.prank(bob);
        d.farm.setReferrer(alice);
        vm.expectRevert(AlreadyDone.selector);
        vm.prank(bob);
        d.farm.setReferrer(alice);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.setReferrer(alice);
        fund(10_000_000 ether);
        payPack(bob);
        place(bob, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        uint256 ref = d.rewards.pending(alice);
        assertGt(ref, 0);
        assertApproxEqAbs(d.rewards.pending(bob) * 5, ref * 85, 100);
    }

    function testWithdrawFailureRollsBackAndReentrancyCannotClaimTwice() public {
        fund(10_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        uint256 amount = d.rewards.pending(alice);
        token.setFail(true);
        vm.expectRevert();
        vm.prank(alice);
        d.rewards.claim(amount);
        assertEq(d.rewards.pending(alice), amount);
        token.setFail(false);
        token.setCallback(address(d.rewards), abi.encodeCall(d.rewards.claim, (amount)));
        vm.prank(alice);
        d.rewards.claim(amount);
        assertFalse(token.callbackSucceeded());
        assertEq(d.rewards.pending(alice), 0);
    }

    function testGasAdvanceIndependentOfRoster() public {
        entropy();
        vm.warp(d.rewards.epochEnd());
        uint256 before_ = gasleft();
        d.rewards.advanceEpoch();
        uint256 empty = before_ - gasleft();
        finish();
        for (uint256 i; i < 1000; ++i) {
            address p = address(uint160(0x100000 + i));
            place(p, 0, 0, 0);
        }
        entropy();
        vm.warp(d.rewards.epochEnd());
        before_ = gasleft();
        d.rewards.advanceEpoch();
        uint256 many = before_ - gasleft();
        emit log_named_uint("advance empty roster", empty);
        emit log_named_uint("advance 1000 farms", many);
        assertLt(many, 1_500_000);
        assertLt(many, empty + 250000);
    }
}
