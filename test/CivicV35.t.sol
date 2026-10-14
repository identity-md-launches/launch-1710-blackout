// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Billboards} from "../src/Billboards.sol";
import {Civic} from "../src/Civic.sol";
import {GridOperator} from "../src/GridOperator.sol";
import "../src/lib/Errors.sol";

contract CivicV35Test is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.prank(alice);
        token.approve(address(d.civic), type(uint256).max);
        vm.prank(alice);
        token.approve(address(d.billboards), type(uint256).max);
        vm.prank(bob);
        token.approve(address(d.civic), type(uint256).max);
        vm.prank(bob);
        token.approve(address(d.billboards), type(uint256).max);
    }

    function _enable(uint256 feature) internal {
        vm.prank(swarm);
        d.civic.announce(feature, "Operator notice");
        vm.expectRevert(TooEarly.selector);
        d.civic.enable(feature);
        vm.warp(d.civic.noticeAt(feature));
        d.civic.enable(feature);
    }

    function testBillboardsBidRefundTextRulesAndPoolOnly() public {
        uint256 before_ = token.balanceOf(address(d.pool));
        vm.prank(alice);
        d.billboards.bidBillboard(0, 1000 ether, "BLACKOUT CITY", "IMDBlackout");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(bob);
        d.billboards.bidBillboard(0, 1001 ether, "SMALL RAISE", "handle");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(bob);
        d.billboards.bidBillboard(0, 2000 ether, "https://evil.xyz", "handle");
        vm.prank(bob);
        d.billboards.bidBillboard(0, 2000 ether, "DISTRICT ZERO", "handle");
        assertEq(d.billboards.refund(alice), 1000 ether);
        uint256 a = token.balanceOf(alice);
        vm.prank(alice);
        d.billboards.withdrawRefund();
        assertEq(token.balanceOf(alice) - a, 1000 ether);
        vm.expectRevert(TooEarly.selector);
        d.billboards.settleBillboard(1, 0);
        vm.warp(tokenLaunch() + 7 days);
        d.billboards.settleBillboard(1, 0);
        assertEq(token.balanceOf(address(d.pool)) - before_, 2000 ether);
        assertEq(d.billboards.escrow(), 0);
        Billboards.Billboard memory board = d.billboards.billboard(1, 0);
        assertEq(board.text, "DISTRICT ZERO");
        vm.prank(swarm);
        (bool ok,) = address(d.billboards).call(abi.encodeWithSignature("blankBillboard(uint256,uint256)", 1, 0));
        assertFalse(ok);
        assertEq(d.billboards.billboard(1, 0).text, "DISTRICT ZERO");
        vm.expectRevert(InvalidValue.selector);
        d.billboards.settleBillboard(1, 0);
    }

    function testDormantDisabledAndNoticeOnce() public {
        for (uint256 i; i < 3; ++i) {
            assertFalse(d.civic.enabled(i));
        }
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.startWar(0, 1);
        vm.expectRevert(Unauthorized.selector);
        d.civic.announce(0, "notice");
        _enable(0);
        assertTrue(d.civic.enabled(0));
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.announce(0, "again");
        vm.expectRevert(TooEarly.selector);
        d.civic.enable(0);
    }

    function testWarFreezeScoresConservationAndPayoutOnlyOnce() public {
        _enable(0);
        uint8 a = uint8(d.farm.district(alice));
        uint8 b = uint8(d.farm.district(bob));
        assertTrue(a != b);
        vm.mockCall(
            address(d.rewards),
            abi.encodeWithSignature("districtActiveHash(uint256)", uint256(a)),
            abi.encode(uint256(100000))
        );
        vm.mockCall(
            address(d.rewards),
            abi.encodeWithSignature("districtActiveHash(uint256)", uint256(b)),
            abi.encode(uint256(0))
        );
        vm.prank(swarm);
        d.civic.startWar(a, b);
        vm.prank(alice);
        d.civic.fundWar(1000 ether);
        vm.prank(bob);
        d.civic.fundWar(2000 ether);
        uint256 score = d.civic.warScore(1, a);
        vm.mockCall(
            address(d.rewards),
            abi.encodeWithSignature("districtActiveHash(uint256)", uint256(a)),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(d.rewards),
            abi.encodeWithSignature("districtActiveHash(uint256)", uint256(b)),
            abi.encode(uint256(999999999))
        );
        vm.mockCall(address(d.economy), abi.encodeWithSignature("averageDaily()"), abi.encode(uint256(1 ether)));
        assertEq(d.civic.warScore(1, a), score);
        vm.expectRevert(TooEarly.selector);
        d.civic.finishWar();
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.civic.fundWar(1 ether);
        uint256 pool = token.balanceOf(address(d.pool));
        d.civic.finishWar();
        assertEq(token.balanceOf(address(d.pool)) - pool, 1000 ether);
        uint256 before_ = token.balanceOf(alice);
        vm.prank(alice);
        uint256 won = d.civic.claimWar(1);
        assertEq(won, 2000 ether);
        assertEq(token.balanceOf(alice) - before_, won);
        assertEq(d.civic.escrow(), 0);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.civic.claimWar(1);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(bob);
        d.civic.claimWar(1);
        assertEq(d.civic.outputBonus(a), 1000);
    }

    function testCollapseSuccessAndSingleOutageFailure() public {
        _enable(1);
        vm.prank(swarm);
        d.civic.startCollapse(3000 ether);
        uint256 before_ = token.balanceOf(address(d.pool));
        vm.prank(alice);
        d.civic.fundCollapse(3000 ether);
        assertEq(token.balanceOf(address(d.pool)) - before_, 3000 ether);
        vm.expectRevert(TooEarly.selector);
        d.civic.finishCollapse();
        vm.warp(vm.getBlockTimestamp() + 24 hours);
        d.civic.finishCollapse();
        vm.prank(address(d.grid));
        assertEq(d.civic.consumeCityEvent(), 1);
        vm.warp(vm.getBlockTimestamp() + 24 hours);
        vm.prank(swarm);
        d.civic.startCollapse(3000 ether);
        vm.warp(vm.getBlockTimestamp() + 24 hours);
        d.civic.finishCollapse();
        vm.expectRevert(Unauthorized.selector);
        d.civic.consumeCityEvent();
        vm.prank(address(d.grid));
        uint256 forced = d.civic.consumeCityEvent();
        assertEq(forced, 2);
        vm.prank(address(d.grid));
        forced = d.civic.consumeCityEvent();
        assertEq(forced, 0);
    }

    function testBlackMarketDescendingLimitedAndPause() public {
        _enable(2);
        entropy();
        d.rewards.advanceEpoch();
        vm.prank(swarm);
        d.civic.listLot(1, 1, 2);
        vm.mockCall(address(d.pool), abi.encodeWithSignature("endowed()"), abi.encode(false));
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.civic.buyLot(type(uint256).max);
        vm.mockCall(address(d.pool), abi.encodeWithSignature("endowed()"), abi.encode(true));
        uint256 w = d.civic.week();
        uint256 first = d.civic.lotQuote(w);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertLt(d.civic.lotQuote(w), first);
        vm.prank(swarm);
        d.packs.pause(1 hours);
        vm.expectRevert(TooEarly.selector);
        vm.prank(alice);
        d.civic.buyLot(type(uint256).max);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        uint256 q = d.civic.lotQuote(w);
        uint256 before_ = token.balanceOf(address(d.pool));
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.civic.buyLot(q - 1);
        vm.prank(alice);
        uint256 id = d.civic.buyLot(q);
        assertEq(d.items.data(id).rarity, 1);
        assertEq(token.balanceOf(address(d.pool)) - before_, q);
        assertEq(d.farm.paidPacks(alice), 1);
        vm.prank(bob);
        d.civic.buyLot(q);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(alice);
        d.civic.buyLot(q);
    }

    function testOnceSeasonBoostBoundsAndSnapshot() public {
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.grantDistrictBoost(0, 1501, "Too much");
        vm.prank(swarm);
        d.civic.grantDistrictBoost(0, 1500, "Week boost");
        assertEq(d.civic.outputBonus(0), 1500);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.civic.grantDistrictBoost(1, 100, "Duplicate season");
        calmNext();
        step();
        assertEq(d.grid.outputBonus(2, 0), 1500);
        vm.warp(vm.getBlockTimestamp() + 7 days);
        assertEq(d.civic.outputBonus(0), 0);
        assertEq(d.grid.outputBonus(2, 0), 1500);
    }
}
