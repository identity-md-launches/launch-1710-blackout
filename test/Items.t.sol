// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {DeferredEntryTest} from "./Base.t.sol";
import {FarmEngine} from "../src/FarmEngine.sol";
import {FarmCore} from "../src/FarmCore.sol";
import {FarmItems} from "../src/FarmItems.sol";
import "../src/lib/Errors.sol";

contract ItemsTest is DeferredEntryTest {
    function testSoulboundOnlyOwnFarmAndNoDuplicateTypes() public {
        uint256 gpu = place(alice, 0, 0, 0);
        uint256 another = mintItem(alice, 0, 1);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(another, 0, 1);
        vm.expectRevert(Unauthorized.selector);
        vm.prank(alice);
        d.items.safeTransferFrom(alice, bob, another, 1, "");
        vm.expectRevert(Unauthorized.selector);
        vm.prank(alice);
        d.items.setApprovalForAll(bob, true);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(bob);
        d.farm.place(another, 0, 0);
        vm.prank(alice);
        d.farm.unplace(0, 0);
        assertEq(d.items.balanceOf(alice, gpu), 1);
        assertEq(d.items.inventory(alice), 2);
    }

    function testRoomGatesAndLevelProgression() public {
        uint256 id = mintItem(alice, 0, 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(id, 1, 0);
        vm.prank(alice);
        d.farm.place(id, 0, 0);
        payPack(alice);
        calmNext();
        step();
        for (uint256 i; i < 4; ++i) {
            calmNext();
            step();
        }
        assertEq(d.farm.level(alice), 3);
        for (uint256 i; i < 4; ++i) {
            calmNext();
            step();
        }
        assertEq(d.farm.level(alice), 5);
        for (uint256 i; i < 20; ++i) {
            calmNext();
            step();
            if (i % 8 == 0) {
                vm.prank(alice);
                d.farm.sync(); // v3.3: stay committed; idle farms stop earning activity XP
            }
        }
        assertEq(d.farm.level(alice), 10);
        assertEq(d.farm.rooms(alice), 1);
        for (uint256 room = 1; room < 4; ++room) {
            assertTrue(d.farm.roomEligible(alice, room));
            vm.prank(alice);
            d.farm.buyRoom(room, true);
        }
        assertEq(d.farm.rooms(alice), 4);
        assertEq(d.farm.rooms(bob), 1);
        vm.prank(bob);
        d.farm.register(bob);
        vm.warp(vm.getBlockTimestamp() + 3 days);
        assertEq(d.farm.rooms(bob), 1);
        assertTrue(d.farm.roomEligible(bob, 1));
    }

    function testPaidXpCannotBypassRoomTwoAgeGate() public {
        uint256 cost = d.packs.quote(112);
        vm.prank(alice);
        d.packs.openPack(112);
        // v3.3: paid XP is capped at 400 per day, so a whale stays at level 3 on day one.
        assertEq(d.farm.xp(alice), 400);
        assertEq(d.farm.level(alice), 3);
        assertFalse(d.farm.roomUnlocked(alice, 1));
        assertFalse(d.farm.roomUnlocked(alice, 2));
        assertEq(d.farm.rooms(alice), 1);
        uint256 id = mintItem(alice, 0, 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(id, 1, 0);
        vm.warp(vm.getBlockTimestamp() + 3 days);
        assertTrue(d.farm.roomEligible(alice, 1));
    }

    function testEquipRarityGatesAndMythicGate() public {
        uint256 e = mintItem(alice, 0, 2);
        uint256 l = mintItem(alice, 1, 3);
        uint256 m = mintItem(alice, 2, 4);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(e, 0, 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(l, 0, 1);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(m, 0, 2);
        uint256 q = d.packs.quote(16);
        vm.prank(alice);
        d.packs.openPack(16);
        assertEq(d.farm.level(alice), 3);
        vm.prank(alice);
        d.farm.place(e, 0, 0);
        // Legendary and Mythic need age-gated levels 5 and 10; see V33Test for the full gate walk.
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.place(l, 0, 1);
    }

    function testComputeHashSupportHashAndBonusesReplaceDuo() public {
        payPack(alice);
        place(alice, 0, 0, 0);
        assertEq(d.farm.roomStats(alice, 0).raw, 10000);
        place(alice, 1, 0, 1);
        FarmEngine.RoomStats memory s = d.farm.roomStats(alice, 0);
        assertEq(s.bonus, 1000);
        assertEq(s.raw, 22000);
        place(alice, 2, 0, 2);
        s = d.farm.roomStats(alice, 0);
        assertEq(s.bonus, 2000);
        assertEq(s.raw, 36000);
        place(alice, 3, 0, 3);
        s = d.farm.roomStats(alice, 0);
        assertEq(s.raw, 43200);
    }

    function testFullStackRarityCapAndRoomFlags() public {
        payPack(alice);
        place(alice, 0, 1, 0);
        place(alice, 3, 1, 1);
        place(alice, 6, 1, 2);
        place(alice, 8, 1, 3);
        place(alice, 10, 1, 4);
        place(alice, 11, 1, 5);
        FarmEngine.RoomStats memory s = d.farm.roomStats(alice, 0);
        assertEq(s.bonus, 2500);
        assertTrue(s.airflow);
        assertTrue(s.locked);
        assertTrue(s.clean);
        assertTrue(s.cooling);
        vm.prank(alice);
        d.farm.unplace(0, 2);
        place(alice, 7, 0, 2);
        s = d.farm.roomStats(alice, 0);
        assertTrue(s.cold);
        assertEq(s.power, s.productive * 8500 / 10000);
    }

    function testOffgridSavings() public {
        payPack(alice);
        place(alice, 4, 0, 0);
        place(alice, 5, 0, 1);
        FarmEngine.RoomStats memory s = d.farm.roomStats(alice, 0);
        assertTrue(s.offgrid);
        assertEq(s.power, s.productive * 8 / 10);
    }

    function testDurabilityWearRepairAndEnhancementMetadataPreserved() public {
        uint256 id = place(alice, 0, 0, 0);
        payPack(alice);
        calmNext();
        step();
        calmNext();
        step();
        assertEq(d.items.data(id).durability, 9900);
        uint256 before_ = token.balanceOf(address(d.pool));
        vm.prank(alice);
        d.farm.repair(id, true);
        assertEq(d.items.data(id).durability, 10000);
        assertGt(token.balanceOf(address(d.pool)), before_);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.repair(id, true);
        vm.prank(address(d.farm));
        d.items.maintain(id, 10000, 5);
        assertEq(d.items.data(id).overclock, 5);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.overclock(id, true);
        vm.prank(alice);
        d.farm.unplace(0, 0);
        vm.prank(alice);
        d.farm.place(id, 0, 1);
        assertEq(d.items.data(id).overclock, 5);
    }

    function testLockedItemCannotBeScrappedUntilEpochRolls() public {
        uint256 gpu = place(alice, 1, 0, 0);
        calmNext();
        step();
        vm.prank(alice);
        d.farm.unplace(0, 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.scrap(gpu, 0);
        calmNext();
        step();
        vm.prank(alice);
        d.farm.scrap(gpu, 0);
    }

    function testScrapPaysPoolYieldAndCannotRepeat() public {
        fund(10_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        uint256 id = mintItem(alice, 0, 0);
        uint256 before_ = d.rewards.pending(alice);
        vm.prank(alice);
        d.farm.scrap(id, 0);
        assertGt(d.rewards.pending(alice), before_);
        assertEq(d.items.data(id).holder, address(0));
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.farm.scrap(id, 0);
    }

    function testInventoryMintCannotExceedCapacityAndExpansionRises() public {
        for (uint256 i; i < 15; ++i) {
            mintItem(alice, uint8(i % 12), 0);
        }
        vm.expectRevert(InvalidValue.selector);
        vm.prank(address(d.packs));
        d.items.mint(alice, 0, 0, false);
        uint256 before_ = token.balanceOf(alice);
        vm.prank(alice);
        d.farm.expand(true);
        assertEq(before_ - token.balanceOf(alice), 3000 ether);
        before_ = token.balanceOf(alice);
        vm.prank(alice);
        d.farm.expand(true);
        assertEq(before_ - token.balanceOf(alice), 12000 ether);
        assertEq(d.items.capacity(alice), 25);
    }
}
