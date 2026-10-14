// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {EconomyMath} from "../src/lib/EconomyMath.sol";
import {Enhancement} from "../src/Enhancement.sol";
import {FarmEngine} from "../src/FarmEngine.sol";
import {FarmItems} from "../src/FarmItems.sol";
import {GridOperator} from "../src/GridOperator.sol";
import {Params} from "../src/Params.sol";
import "../src/lib/Errors.sol";

contract EconomyV35Test is BaseTest {
    function testTokenOnlyGiftSplitsNoEthPeg() public {
        uint256 quote = d.packs.price();
        uint256 supply = token.totalSupply();
        market.setRate(2_000_000 ether);
        assertEq(d.packs.price(), quote);
        uint256 before_ = token.balanceOf(address(d.pool));
        vm.prank(alice);
        uint256 receipt = d.packs.buyPackFor(bob);
        assertEq(token.balanceOf(address(d.pool)) - before_, quote * 88 / 100);
        assertEq(d.fees.teamTokens(), quote / 10);
        assertEq(d.fees.heartbeatTokens(), quote * 2 / 100);
        assertEq(d.farm.paidPacks(bob), 1);
        assertEq(d.farm.paidPacks(alice), 0);
        resolvePack(receipt);
        assertEq(d.items.inventory(bob), 3);
        assertEq(token.totalSupply(), supply);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.packs.openPack{value: 1}(1);
    }

    function testZapAtomicMinOutPauseAndRefund() public {
        uint256 cost = d.packs.price();
        uint256 before_ = token.balanceOf(alice);
        vm.prank(alice);
        d.packs.buyWithETH{value: 0.02 ether}(alice, 1, 20_000 ether, cost);
        assertEq(token.balanceOf(alice) - before_, 20_000 ether - cost);
        market.setFill(9000);
        uint256 sold = d.packs.sold();
        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(alice);
        d.packs.buyWithETH{value: 0.1 ether}(alice, 1, 100_000 ether, type(uint256).max);
        assertEq(d.packs.sold(), sold);
        vm.prank(swarm);
        d.packs.pause(72 hours);
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.packs.buyWithETH{value: 0.1 ether}(alice, 1, 1, type(uint256).max);
    }

    function testQuoteScalesLastSettlementAndHasFloor() public {
        assertEq(d.economy.farmDaily(alice), 3000 ether);
        uint256 id = place(alice, 0, 0, 0);
        fund(1_000_000 ether);
        assertEq(d.economy.itemDaily(id), 0.04 ether);
        calmNext();
        step();
        assertGt(d.economy.itemDaily(id), 0.04 ether);
        assertEq(d.economy.farmDaily(alice), d.rewards.lastFarmDaily(alice));
        (uint256 lo, uint256 hi) = d.packs.priceBounds();
        assertGe(d.packs.price(), lo);
        assertLe(d.packs.price(), hi);
    }

    function testDurabilityBoundariesAndIdleNoWear() public {
        assertEq(EconomyMath.tier(8000), 10000);
        assertEq(EconomyMath.tier(7999), 8500);
        assertEq(EconomyMath.tier(6000), 8500);
        assertEq(EconomyMath.tier(5999), 6500);
        assertEq(EconomyMath.tier(4000), 6500);
        assertEq(EconomyMath.tier(3999), 4000);
        assertEq(EconomyMath.tier(2000), 4000);
        assertEq(EconomyMath.tier(1999), 0);
        uint256 id = place(alice, 0, 0, 0);
        for (uint256 i; i < 14; ++i) {
            calmNext();
            step();
        }
        uint256 health = d.items.data(id).durability;
        for (uint256 i; i < 4; ++i) {
            calmNext();
            step();
        }
        assertEq(d.items.data(id).durability, health);
        assertLt(health, 10000);
    }

    function testRepairYieldQuoteAndAutoRepairCreditsOnly() public {
        uint256 id = place(alice, 0, 0, 0);
        fund(1_000_000 ether);
        vm.prank(address(d.farm));
        d.items.maintain(id, 7000, 0);
        assertEq(d.economy.repairQuote(id), d.economy.itemDaily(id) * 18 / 24);
        uint256 poolBefore = token.balanceOf(address(d.pool));
        uint256 cost = d.economy.repairQuote(id);
        vm.prank(alice);
        d.farm.repair(id, true);
        assertEq(token.balanceOf(address(d.pool)) - poolBefore, cost);
        assertEq(d.items.data(id).durability, 10000);
        vm.prank(alice);
        d.farm.setAutoRepair(true, 0);
        assertEq(d.farm.autoRepairThreshold(alice), 8000);
        // Mine an epoch, then force wear before the next snapshot.
        calmNext();
        step();
        vm.prank(address(d.farm));
        d.items.maintain(id, 7900, 0);
        vm.prank(alice);
        d.farm.sync();
        calmNext();
        step();
        assertEq(d.items.data(id).durability, 7800); // Insufficient credits: no wallet pull or free repair.
        for (uint256 i; i < 4 && d.items.data(id).durability < 10000; ++i) {
            calmNext();
            step();
        }
        assertEq(d.items.data(id).durability, 10000);
        assertGt(d.rewards.pending(alice), 0);
    }

    function testRoomsChargeYieldDaysAndRetainAgeGates() public {
        vm.prank(alice);
        d.farm.register(alice);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.buyRoom(1, true);
        veteran(alice);
        for (uint256 room = 1; room < 4; ++room) {
            assertFalse(d.farm.roomUnlocked(alice, room));
            uint256 cost = d.economy.roomQuote(alice, room);
            uint256 before_ = token.balanceOf(address(d.pool));
            vm.prank(alice);
            d.farm.buyRoom(room, true);
            assertEq(token.balanceOf(address(d.pool)) - before_, cost);
            assertTrue(d.farm.roomUnlocked(alice, room));
            vm.expectRevert(InvalidValue.selector);
            vm.prank(alice);
            d.farm.buyRoom(room, true);
        }
    }

    function testLockEscrowNoEarlyExitAndWalletCap() public {
        place(alice, 0, 0, 0);
        uint256 amount = 15_000 ether;
        vm.prank(alice);
        d.economy.lock(amount, 7);
        assertEq(d.economy.totalLocked(), amount);
        assertEq(d.economy.stakeOf(alice), amount / 10);
        assertEq(d.economy.districtStake(d.farm.district(alice)), amount / 10);
        assertEq(d.economy.boostAt(alice, block.timestamp), 500);
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.economy.unlock();
        vm.warp(block.timestamp + 7 days);
        assertEq(d.economy.boostAt(alice, block.timestamp), 0);
        // Bring the autonomous epoch current before owner actions.
        entropy();
        d.rewards.advanceEpoch();
        d.rewards.settle(alice, 8);
        uint256 before_ = token.balanceOf(alice);
        vm.prank(alice);
        d.economy.unlock();
        assertEq(token.balanceOf(alice) - before_, amount);
        assertEq(d.economy.totalLocked(), 0);
    }

    function testLockBonusRedistributesWithinReservedEmission() public {
        payPack(alice);
        payPack(bob);
        fund(1_000_000 ether);
        place(alice, 0, 0, 0);
        place(bob, 0, 0, 0);
        vm.prank(alice);
        d.economy.lock(15_000 ether, 7);
        calmNext();
        step();
        calmNext();
        step();
        (uint256 ar, uint256 ap,,) = d.rewards.shares(2, alice);
        (uint256 br, uint256 bp,,) = d.rewards.shares(2, bob);
        assertEq(ar, br * 105 / 100);
        assertEq(ap, bp * 105 / 100);
        assertGe(d.pool.reserved(), d.rewards.pending(alice) + d.rewards.pending(bob));
    }

    /// @dev v3.17 (audit 339b6b19 medium): a lapsed window settles the attempt as its worst outcome, never re-arms.
    function testEnhanceCommitCannotPlaceScrapOrRetryAndLapsesAsWorstOutcome() public {
        uint256 item = mintItem(alice, 0, 0);
        uint256 cost = d.economy.enhanceQuote(item);
        vm.prank(alice);
        uint256 id = d.enhancement.commit(item, cost, true);
        assertEq(d.enhancement.pending(item), id);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(item, 0, 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.scrap(item, 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.enhancement.commit(item, cost, true);
        vm.roll(vm.getBlockNumber() + 300);
        d.enhancement.resolve(id);
        assertEq(d.enhancement.pending(item), 0, "lapsed: settled as a failure, item free again");
        assertEq(d.items.data(item).overclock, 0, "level 1 keeps its level on failure");
        assertEq(d.items.data(item).holder, alice);
        (,,,, bytes32 seed, bool captured, bool resolved) = d.enhancement.attempts(id);
        assertEq(seed, bytes32(0));
        assertTrue(captured && resolved);
        vm.expectRevert(InvalidValue.selector);
        d.enhancement.resolve(id);
        // A fresh attempt inside the window still captures and resolves on the real hash.
        vm.prank(alice);
        id = d.enhancement.commit(item, cost, true);
        entropy();
        d.enhancement.capture(id);
        (,,,, seed, captured,) = d.enhancement.attempts(id);
        assertTrue(captured);
        vm.roll(vm.getBlockNumber() + 300);
        d.enhancement.resolve(id);
        assertEq(d.enhancement.pending(item), 0);
        assertEq(d.items.data(item).overclock, uint256(seed) % 100 < 95 ? 1 : 0);
    }

    function testEnhanceBurnFailureAndLevelGate() public {
        uint256 item = mintItem(alice, 1, 0);
        vm.prank(alice);
        d.farm.register(alice);
        vm.prank(address(d.farm));
        d.items.maintain(item, 10000, 5);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.enhancement.commit(item, type(uint256).max, true);
        veteran(alice);
        vm.prank(alice);
        uint256 id = d.enhancement.commit(item, type(uint256).max, true);
        (,, uint64 target,,,,) = d.enhancement.attempts(id);
        bytes32 h;
        for (uint256 n = 1;; ++n) {
            h = bytes32(n);
            bytes32 seed = keccak256(abi.encode(h, address(d.enhancement), id));
            if (uint256(seed) % 100 >= 50 && uint256(keccak256(abi.encode(seed, "burn"))) % 100 < 10) break;
        }
        vm.roll(uint256(target) + 1);
        vm.setBlockhash(target, h);
        d.enhancement.resolve(id);
        assertEq(d.items.data(item).holder, address(0));
    }

    function testEnhanceCapsNoticeUpwardOnlyAndThirtyDays() public {
        vm.expectRevert(Unauthorized.selector);
        d.enhancement.announceCap(12, "Raise cap");
        vm.prank(swarm);
        d.enhancement.announceCap(12, "Raise cap");
        vm.expectRevert(TooEarly.selector);
        d.enhancement.activateCap();
        vm.warp(d.enhancement.activationAt());
        d.enhancement.activateCap();
        assertEq(d.enhancement.cap(), 12);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.enhancement.announceCap(8, "Lower rejected");
        vm.prank(swarm);
        d.enhancement.announceCap(16, "Final tier");
        assertEq(d.enhancement.activationAt(), block.timestamp + 30 days);
        vm.warp(d.enhancement.activationAt());
        d.enhancement.activateCap();
        assertEq(d.enhancement.cap(), 16);
    }

    function testFreeAllowlistOnceWindowStarterScrapAndMetadata() public {
        assertEq(d.starter.freeRoot(), freePackRoot());
        (bool ok,) = address(d.starter).call(abi.encodeWithSignature("setFreeRoot(bytes32)", keccak256("replacement")));
        assertFalse(ok);
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(InvalidProof.selector);
        vm.prank(bob);
        d.starter.claimFree(0, proof);
        vm.prank(alice);
        uint256 receipt = d.starter.claimFree(0, proof);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.starter.claimFree(0, proof);
        entropy();
        d.starter.resolve(receipt);
        assertEq(d.items.inventory(alice), 3);
        assertTrue(d.items.data(1).starter);
        assertGt(bytes(d.items.uri(1)).length, 500);
        uint256[] memory ids = d.items.itemsByOwner(alice, 0, 100);
        assertEq(ids.length, 3);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.scrap(1, 0);
        payPack(alice);
        vm.prank(alice);
        d.farm.scrap(1, 0);
        assertEq(d.items.ownedCount(alice), 2);
        vm.warp(d.starter.freeClaimEnds());
        vm.expectRevert(TooEarly.selector);
        vm.prank(bob);
        d.starter.claimFree(1, proof);
    }

    function testFeeSalesDepthSlippageCadenceAndNormalFeePot() public {
        payPack(alice);
        vm.deal(address(market), 100 ether);
        (uint256 amount, uint256 minimum) = d.fees.sellBatchQuote();
        assertEq(amount, 1000 ether);
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeSells(amount, minimum - 1);
        uint256 received = d.fees.executeSells(amount, minimum);
        assertGt(received, 0);
        assertGt(d.fees.credit(team), 0);
        assertGt(d.fees.heartbeatBalance(), 0);
        vm.expectRevert(TooEarly.selector);
        d.fees.executeSells(100 ether, 1);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.potETH(), 0.5 ether);
        uint256 q = market.quote(0.5 ether);
        d.fees.executePotBuys(0.5 ether, q);
        assertEq(d.season.pot(0), q);
        assertEq(d.season.potLiability(), q);
    }

    function testFreeRootWindowAndIndexLimit() public {
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.starter.claimFree(500, proof);
        assertEq(d.starter.freeClaimed(), 0);
    }

    function testFreeRootRemainsFrozenAfterSevenDays() public {
        vm.warp(tokenLaunch() + 7 days + 1);
        (bool ok,) = address(d.starter).call(abi.encodeWithSignature("setFreeRoot(bytes32)", keccak256("replacement")));
        assertFalse(ok);
        assertEq(d.starter.freeRoot(), freePackRoot());
    }

    function testSystemSellDustCannotOccupyCadenceAndCappedHeartbeatReturnsTokens() public {
        payPack(alice);
        (uint256 batch, uint256 minOut) = d.fees.sellBatchQuote();
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeSells(1, 1);
        assertEq(d.fees.lastSell(), 0);
        uint256 queued = d.fees.heartbeatTokens();
        vm.prank(address(market));
        d.fees.depositSellTax{value: 100 ether}();
        assertEq(d.fees.heartbeatBalance(), 1 ether);
        uint256 beforePool = token.balanceOf(address(d.pool));
        (batch, minOut) = d.fees.sellBatchQuote();
        d.fees.executeSells(batch, minOut);
        assertEq(token.balanceOf(address(d.pool)) - beforePool, queued);
        assertEq(d.fees.heartbeatTokens(), 0);
        assertEq(d.fees.heartbeatBalance(), 1 ether);
    }

    function testAllEnhancementTableEndpointsAndGlobalBonusCap() public {
        (uint256 chance, uint256 burn, uint256 bonus, uint256 cost) = d.enhancement.table(16);
        assertEq(chance, 8);
        assertEq(burn, 90);
        assertEq(bonus, 7000);
        assertEq(cost, 55 ether);
        vm.expectRevert(InvalidValue.selector);
        d.enhancement.table(17);
        uint256 id = mintItem(alice, 0, 0);
        vm.prank(alice);
        d.farm.register(alice);
        vm.prank(address(d.farm));
        d.items.maintain(id, 10000, 8);
        veteran(alice);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.enhancement.commit(id, type(uint256).max, true);
        FarmEngine.Snapshot memory snapshot;
        uint256 base;
        for (uint256 i; i < 6; ++i) {
            snapshot.ids[i] = mintItem(alice, uint8(i), 4);
            snapshot.clocks[i] = 16;
            snapshot.health[i] = 10000;
            base += i < 3 ? 800000 : 480000;
        }
        FarmEngine.RoomStats memory stats = d.engine.stats(snapshot, 0, false, d.rewards.epoch());
        assertEq(stats.raw, base * 2); // +70% enhancement plus +50% combos hits shared +100% cap.
        assertEq(stats.productive, stats.raw);
    }

    function testFuzzPriceCurveDaysBounds(uint32 sold, uint32 elapsed) public {
        vm.warp(launch + bound(elapsed, 0, 365 days));
        uint256 price = d.packs.priceAt(sold);
        (uint256 lo, uint256 hi) = d.packs.priceBounds();
        assertGe(price, lo);
        assertLe(price, hi);
    }
}
