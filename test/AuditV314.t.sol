// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import "../src/lib/Errors.sol";

contract AuditV314Test is BaseTest {
    function testStaleSellAmountUsesCurrentDepthAndEnforcesCurrentMinimum() public {
        payPack(alice);
        (uint256 staleAmount, uint256 staleMinimum) = d.fees.sellBatchQuote();
        market.setDepth(500_000 ether);
        (uint256 actualAmount, uint256 minimum) = d.fees.sellBatchQuote();
        assertLt(actualAmount, staleAmount);
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeSells(staleAmount, minimum - 1);
        assertEq(d.fees.lastSell(), 0);
        // A stale high minimum must still protect the caller and roll all state back.
        uint256 queued = d.fees.teamTokens() + d.fees.heartbeatTokens();
        vm.expectRevert();
        d.fees.executeSells(staleAmount, staleMinimum);
        assertEq(d.fees.teamTokens() + d.fees.heartbeatTokens(), queued);
        assertEq(d.fees.lastSell(), 0);
        uint256 received = d.fees.executeSells(staleAmount, minimum);
        assertGe(received, minimum);
        assertEq(queued - d.fees.teamTokens() - d.fees.heartbeatTokens(), actualAmount);
        assertEq(token.allowance(address(d.fees), address(market)), 0);
    }

    function testDustAmountCannotReduceExecutedBatchAndEmptyQueueReverts() public {
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeSells(1, 1);
        payPack(alice);
        (uint256 batch, uint256 minimum) = d.fees.sellBatchQuote();
        uint256 queued = d.fees.teamTokens() + d.fees.heartbeatTokens();
        d.fees.executeSells(0, minimum);
        assertEq(queued - d.fees.teamTokens() - d.fees.heartbeatTokens(), batch);
        vm.expectRevert(TooEarly.selector);
        d.fees.executeSells(batch, minimum);
    }

    function testOnlyFarmerCanRetireEvenAnEmptyFarm() public {
        place(alice, 0, 0, 0);
        vm.prank(alice);
        d.farm.unplace(0, 0);
        step();
        uint256 count = d.farm.count();
        vm.expectRevert(Unauthorized.selector);
        vm.prank(bob);
        d.farm.retire(alice);
        assertEq(d.farm.count(), count);
        vm.prank(alice);
        d.farm.retire(alice);
        assertEq(d.farm.count(), count - 1);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.retire(alice);
    }

    function testLaterSameEpochCreditKeepsEarlierTaxVintage() public {
        fund(1000 ether);
        vm.prank(address(d.rewards));
        d.pool.reserve(200 ether);
        uint256 first = vm.getBlockTimestamp();
        vm.prank(address(d.season));
        d.rewards.award(alice, 100 ether);
        vm.warp(first + 1 hours);
        vm.prank(address(d.season));
        d.rewards.award(alice, 100 ether);
        vm.warp(first + 2 hours);
        uint256 expectedTax = 200 ether * d.rewards.taxBps(2 hours) / 10000;
        uint256 before_ = token.balanceOf(alice);
        vm.prank(alice);
        assertEq(d.rewards.claim(200 ether), 200 ether - expectedTax);
        assertEq(token.balanceOf(alice) - before_, 200 ether - expectedTax);
        assertEq(d.rewards.pending(alice), 0);
    }

    function testLockInsertionWalkIsBoundedAndFailureIsAtomic() public {
        address[34] memory players;
        uint256 found;
        for (uint256 i = 1; found < players.length; ++i) {
            address p = address(uint160(i + 10000));
            if (d.economy.district(p) == 0) players[found++] = p;
        }
        uint256 amount = 20000 ether;
        for (uint256 i; i < 33; ++i) {
            token.transfer(players[i], amount);
            vm.startPrank(players[i]);
            token.approve(address(d.economy), amount);
            d.economy.lock(amount, 7);
            vm.stopPrank();
        }
        assertEq(d.economy.head(0), players[0]);
        assertEq(d.economy.previous(players[32]), players[31]);
        token.transfer(players[33], amount);
        vm.startPrank(players[33]);
        token.approve(address(d.economy), amount);
        vm.expectRevert(InvalidValue.selector);
        d.economy.lock(amount, 7); // a 33rd traversal is refused
        vm.stopPrank();
        assertEq(d.economy.totalLocked(), 33 * amount);
        assertEq(d.economy.districtTotal(0), 33 * amount);
        assertEq(token.balanceOf(players[33]), amount);
        (uint256 locked,,,) = d.economy.locks(players[33]);
        assertEq(locked, 0);
        assertEq(d.economy.next(players[32]), address(0));
        vm.warp(vm.getBlockTimestamp() + 7 days);
        entropy();
        d.rewards.advanceEpoch();
        vm.prank(players[0]);
        d.economy.unlock();
        vm.prank(players[33]);
        d.economy.lock(amount, 7); // exactly 32 traversals succeeds after one exit
        assertEq(d.economy.previous(players[33]), players[32]);
        assertEq(d.economy.districtTotal(0), 33 * amount);
    }
}
