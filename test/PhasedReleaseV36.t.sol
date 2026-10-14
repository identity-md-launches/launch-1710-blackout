// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {GridOperator} from "../src/GridOperator.sol";
import "../src/lib/Errors.sol";

/// @notice v3.6 phased release: the launch core runs with every growth feature disabled.
contract PhasedReleaseV36Test is BaseTest {
    uint256 constant ENHANCEMENT = 3;
    uint256 constant LOCKS = 4;
    uint256 constant BILLBOARDS = 5;
    uint256 constant POT = 6;
    uint256 constant RESERVED = 7;

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.prank(alice);
        token.approve(address(d.billboards), type(uint256).max);
    }

    function testEverythingDeploysDisabledAndCoreStillWorks() public {
        assertEq(d.civic.FEATURES(), 8);
        for (uint256 i; i < 8; ++i) {
            assertFalse(d.civic.enabled(i));
            assertEq(d.civic.noticeAt(i), 0);
        }
        // Launch core: packs, placement, mining, repair, scrap, rooms, calm events, epochs all run.
        payPack(alice);
        fund(1_000_000 ether);
        uint256 id = place(alice, 0, 0, 0);
        calmNext();
        step();
        calmNext();
        step();
        assertGt(d.rewards.pending(alice), 0);
        vm.prank(alice);
        d.farm.sync();
        assertFalse(d.fees.potEnabled());
        assertEq(d.items.data(id).holder, alice);
    }

    function testEnhancementDisabledThenEnabledOnce() public {
        uint256 item = mintItem(alice, 0, 0);
        uint256 cost = d.economy.enhanceQuote(item);
        vm.expectRevert(FeatureDisabled.selector);
        vm.prank(alice);
        d.enhancement.commit(item, cost, true);
        assertEq(d.enhancement.pending(item), 0);
        enableFeature(ENHANCEMENT);
        vm.prank(alice);
        uint256 id = d.enhancement.commit(item, cost, true);
        assertEq(d.enhancement.pending(item), id);
    }

    function testLocksStakeAndLobbyDisabledThenEnabled() public {
        place(alice, 0, 0, 0);
        vm.expectRevert(FeatureDisabled.selector);
        vm.prank(alice);
        d.economy.lock(15_000 ether, 7);
        vm.expectRevert(FeatureDisabled.selector);
        d.economy.lobbyQuote(alice);
        vm.expectRevert(FeatureDisabled.selector);
        vm.prank(alice);
        d.farm.lobby(10_000 ether, true);
        assertEq(d.economy.totalLocked(), 0);
        assertEq(d.economy.districtStake(d.farm.district(alice)), 0);
        enableFeature(LOCKS);
        vm.prank(alice);
        d.economy.lock(15_000 ether, 7);
        assertEq(d.economy.totalLocked(), 15_000 ether);
        uint256 amount = d.economy.lobbyQuote(alice);
        uint256 district = d.grid.district(alice);
        vm.prank(alice);
        d.farm.lobby(amount, true);
        assertEq(d.grid.lobbyAmount(district), amount);
    }

    function testBillboardsDisabledThenEnabled() public {
        vm.expectRevert(FeatureDisabled.selector);
        vm.prank(alice);
        d.billboards.bidBillboard(0, 1000 ether, "BLACKOUT CITY", "IMDBlackout");
        assertEq(d.billboards.escrow(), 0);
        enableFeature(BILLBOARDS);
        vm.prank(alice);
        d.billboards.bidBillboard(0, 1000 ether, "BLACKOUT CITY", "IMDBlackout");
        assertEq(d.billboards.escrow(), 1000 ether);
    }

    function testPotDisabledFollowsV34RoutingThenEnabled() public {
        uint256 reward = d.fees.rewardETH();
        uint256 teamBefore = d.fees.credit(team);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.potETH(), 0);
        uint256 teamShare = d.fees.credit(team) - teamBefore;
        uint256 heartbeat = d.fees.heartbeatBalance();
        // v3.4 routing: everything that is not team or heartbeat is reward buys.
        assertEq(d.fees.rewardETH() - reward, 1 ether - teamShare - heartbeat);
        vm.expectRevert(InvalidValue.selector);
        d.fees.executePotBuys(0.1 ether, 1);
        enableFeature(POT);
        assertTrue(d.fees.potEnabled());
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.potETH(), 0.5 ether);
    }

    function testReservedEventsDisabledThenEnabled() public {
        uint256 e = d.rewards.epoch() + 1;
        vm.expectRevert(FeatureDisabled.selector);
        vm.prank(swarm);
        d.grid.submitPlan(e, GridOperator.Kind.Heatwave, 10000, keccak256("h"), "Heatwave");
        vm.expectRevert(FeatureDisabled.selector);
        vm.prank(swarm);
        d.grid.submitPlan(e, GridOperator.Kind.Festival, 10000, keccak256("f"), "Festival");
        // Ordinary events are the launch core.
        vm.prank(swarm);
        d.grid.submitPlan(e, GridOperator.Kind.Green, 10000, keccak256("g"), "Green wave");
        enableFeature(RESERVED);
        vm.prank(swarm);
        d.grid.submitPlan(e + 1, GridOperator.Kind.Festival, 8000, keccak256("f"), "Festival");
        // Severity, window and letter bounds still apply after enabling.
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.grid.submitPlan(e + 2, GridOperator.Kind.Heatwave, 4000, keccak256("h"), "Heatwave");
    }

    function testEnableIsNoticedOnceNeverOffAndSwarmOnly() public {
        vm.expectRevert(Unauthorized.selector);
        d.civic.announce(ENHANCEMENT, "not the swarm");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.announce(8, "out of range");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.announce(ENHANCEMENT, "");
        vm.expectRevert(TooEarly.selector);
        d.civic.enable(ENHANCEMENT);
        vm.prank(swarm);
        d.civic.announce(ENHANCEMENT, "Enhancement opens in 48 hours");
        assertEq(d.civic.noticeAt(ENHANCEMENT), block.timestamp + 48 hours);
        vm.warp(block.timestamp + 48 hours - 1);
        vm.expectRevert(TooEarly.selector);
        d.civic.enable(ENHANCEMENT);
        vm.warp(block.timestamp + 1);
        d.civic.enable(ENHANCEMENT);
        assertTrue(d.civic.enabled(ENHANCEMENT));
        // Once: no second notice, no second enable, and no function exists to disable.
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.announce(ENHANCEMENT, "again");
        vm.expectRevert(TooEarly.selector);
        d.civic.enable(ENHANCEMENT);
        assertFalse(d.civic.enabled(LOCKS));
    }

    function testFuzzUnannouncedFeatureCannotBeEnabled(uint256 feature) public {
        vm.expectRevert(TooEarly.selector);
        d.civic.enable(feature);
    }
}
