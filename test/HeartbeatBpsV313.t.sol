// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Params} from "../src/Params.sol";
import "../src/lib/Errors.sol";

/// @dev v3.13: FeeRouter reads Params.HeartbeatBps (packed regulator key 41, bounds 200–5000) instead of a
/// literal 200 in `_route` and `routeTokens`. Legacy fixture: features 3–7 enabled, so the season pot takes 50%
/// of the sell surcharge and the baseline split of 1 ETH is 0.5 pot / 0.1 team / 0.02 heartbeat / 0.38 rewards.
contract HeartbeatBpsV313Test is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.deal(address(market), 1000 ether);
    }

    /// @dev Walk HeartbeatBps to `target` through the real swarm authority: ≤10% per key per day, hard bounds.
    function _ramp(uint256 target) private {
        uint256 old = d.params.get(Params.Key.HeartbeatBps);
        while (old != target) {
            uint256 next = target > old ? old + old / 10 : old - old / 10;
            if (target > old && next > target) next = target;
            if (target < old && next < target) next = target;
            vm.warp(vm.getBlockTimestamp() + 1 days);
            vm.prank(swarm);
            d.params.set(Params.Key.HeartbeatBps, next, "heartbeat share step");
            old = next;
        }
    }

    function testLaunchDefaultIsTwoPercentAndSplitUnchanged() public {
        assertEq(d.fees.HEARTBEAT_BPS(), 200);
        assertTrue(d.fees.potEnabled());
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.heartbeatBalance(), 0.02 ether);
        assertEq(d.fees.credit(team), 0.1 ether);
        assertEq(d.fees.potETH(), 0.5 ether);
        assertEq(d.fees.rewardETH(), 0.38 ether);
    }

    function testSwarmSet220CreditsTwoPointTwoPercentOfSurchargeAndTokens() public {
        vm.warp(launch + 1 days);
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatBps, 220, "Keeper deficit: raise the heartbeat share one step");
        assertEq(d.fees.HEARTBEAT_BPS(), 220);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.heartbeatBalance(), 0.022 ether, "0.022 ETH on a 1 ETH surcharge");
        assertEq(d.fees.credit(team), 0.1 ether, "team share unchanged");
        assertEq(d.fees.potETH(), 0.5 ether, "pot share unchanged");
        assertEq(d.fees.rewardETH(), 0.378 ether, "the extra 0.002 comes out of reward buys");
        uint256 poolBefore = token.balanceOf(address(d.pool));
        token.transfer(address(d.fees), 1 ether);
        vm.prank(address(d.packs));
        d.fees.routeTokens(1 ether);
        assertEq(d.fees.heartbeatTokens(), 0.022 ether, "0.022e18 in routeTokens");
        assertEq(d.fees.teamTokens(), 0.1 ether);
        assertEq(token.balanceOf(address(d.pool)) - poolBefore, 0.878 ether);
    }

    function testRaisedShareStillStopsAtTheOneEthCap() public {
        _ramp(220);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 100 ether}();
        assertEq(d.fees.heartbeatBalance(), 1 ether, "cap, not 2.2 ETH");
        assertEq(d.fees.credit(team), 10 ether);
        assertEq(d.fees.potETH(), 50 ether);
        assertEq(d.fees.rewardETH(), 39 ether, "cap overflow stays in reward buys");
        // At the cap, routed tokens carry no heartbeat share at any bps.
        token.transfer(address(d.fees), 1 ether);
        vm.prank(address(d.packs));
        d.fees.routeTokens(1 ether);
        assertEq(d.fees.heartbeatTokens(), 0);
        assertEq(d.fees.teamTokens(), 0.1 ether);
    }

    function testLoweredShareBackToFloorAndFloorIsHard() public {
        _ramp(242);
        _ramp(200);
        assertEq(d.fees.HEARTBEAT_BPS(), 200);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatBps, 199, "below the floor");
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.heartbeatBalance(), 0.02 ether);
    }

    function testMaximumShareWithPotEnabledIsClippedToWhatIsLeft() public {
        _ramp(5000);
        assertEq(d.fees.HEARTBEAT_BPS(), 5000);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        // 10% team + 50% pot leave 40%: the 50% heartbeat share is clipped there and rewards get nothing.
        assertEq(d.fees.credit(team), 0.1 ether);
        assertEq(d.fees.potETH(), 0.5 ether);
        assertEq(d.fees.heartbeatBalance(), 0.4 ether);
        assertEq(d.fees.rewardETH(), 0);
        // Tokens have no pot share: 10% team, 50% heartbeat, 40% rewards.
        uint256 poolBefore = token.balanceOf(address(d.pool));
        token.transfer(address(d.fees), 1 ether);
        vm.prank(address(d.packs));
        d.fees.routeTokens(1 ether);
        assertEq(d.fees.heartbeatTokens(), 0.5 ether);
        assertEq(d.fees.teamTokens(), 0.1 ether);
        assertEq(token.balanceOf(address(d.pool)) - poolBefore, 0.4 ether);
    }

    function testFuzzAnyShareConservesEveryWeiAndNeverMovesTeamOrPot(uint16 rawBps, uint96 rawAmount) public {
        uint256 bps = bound(rawBps, 200, 5000);
        uint256 v = bound(rawAmount, 1, 100 ether);
        _ramp(bps);
        vm.prank(address(market));
        d.fees.depositSellTax{value: v}();
        assertEq(d.fees.credit(team) + d.fees.rewardETH() + d.fees.heartbeatBalance() + d.fees.potETH(), v);
        assertEq(d.fees.credit(team), v * 1000 / 10000);
        assertEq(d.fees.potETH(), v / 2);
        assertLe(d.fees.heartbeatBalance(), 1 ether);
        assertLe(d.fees.heartbeatBalance(), v * bps / 10000);
        token.transfer(address(d.fees), v);
        vm.prank(address(d.packs));
        d.fees.routeTokens(v);
        assertEq(d.fees.teamTokens(), v / 10);
        assertEq(d.fees.heartbeatTokens(), d.fees.heartbeatBalance() < 1 ether ? v * bps / 10000 : 0);
    }

    function testOnlyTheSwarmWithinBoundsStepAndCooldownCanMoveTheShare() public {
        vm.warp(launch + 1 days);
        vm.expectRevert(Unauthorized.selector);
        vm.prank(alice);
        d.params.set(Params.Key.HeartbeatBps, 220, "not the Desk");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatBps, 221, "more than 10% in one step");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatBps, 5001, "above the ceiling");
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatBps, 220, "one step");
        vm.expectRevert(TooEarly.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatBps, 242, "second step inside 24 hours");
        assertEq(d.fees.HEARTBEAT_BPS(), 220);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.heartbeatBalance(), 0.022 ether);
    }
}
