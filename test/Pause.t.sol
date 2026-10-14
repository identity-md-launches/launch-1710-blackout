// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import "../src/lib/Errors.sol";

contract PauseTest is BaseTest {
    function testOnlySwarmBoundedDurationAndCannotExtendPause() public {
        vm.expectRevert(Unauthorized.selector);
        d.packs.pause(1 hours);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.packs.pause(72 hours + 1);
        vm.prank(swarm);
        d.packs.pause(72 hours);
        assertTrue(d.packs.paused());
        vm.expectRevert(TooEarly.selector);
        vm.prank(swarm);
        d.packs.pause(1 hours);
        vm.warp(launch + 72 hours);
        assertFalse(d.packs.paused());
        vm.expectRevert(TooEarly.selector);
        vm.prank(swarm);
        d.packs.pause(1 hours);
    }

    function testSalePausedWhileEntropyClaimsWithdrawalsAndEpochsContinue() public {
        token.transfer(alice, 50_000_000 ether);
        fund(100_000_000 ether);
        uint256 id = payPack(alice);
        place(alice, 0, 0, 0);
        step();
        step();
        vm.prank(swarm);
        d.packs.pause(72 hours);
        uint256 q = d.packs.quote(1);
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.packs.openPack(1);
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.farm.buyTokenPack(true);
        vm.prank(bob);
        d.packs.captureEntropy(id);
        d.packs.resolve(id, 1);
        uint256 pending = d.rewards.pending(alice);
        assertGt(pending, 0);
        vm.prank(alice);
        d.rewards.claim(pending);
        step();
        (uint256 batch, uint256 minimum) = d.fees.sellBatchQuote();
        d.fees.executeSells(batch, minimum); // Fee conversion also remains callable during a purchase pause.
        uint256 credited = d.fees.credit(team);
        assertGt(credited, 0);
        vm.prank(team);
        d.fees.withdraw();
        vm.warp(d.packs.pausedUntil());
        assertFalse(d.packs.paused());
        entropy();
        d.rewards.advanceEpoch();
        finish();
        payPack(bob);
    }

    function testUnpauseCannotResetNextPauseCooldown() public {
        vm.prank(swarm);
        d.packs.pause(1 hours);
        vm.expectRevert(Unauthorized.selector);
        d.packs.unpause();
        vm.prank(swarm);
        d.packs.unpause();
        assertFalse(d.packs.paused());
        vm.expectRevert(TooEarly.selector);
        vm.prank(swarm);
        d.packs.pause(72 hours);
    }
}
