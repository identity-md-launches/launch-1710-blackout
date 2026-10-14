// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Params} from "../src/Params.sol";
import "../src/lib/Errors.sol";

contract FeesParamsTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.deal(address(d.packs), 1000 ether);
        vm.deal(address(d.grid), 1000 ether);
        vm.deal(address(market), 1000 ether);
    }

    function testExactEthSplitsHeartbeatCapAndPullPayments() public {
        vm.prank(address(market));
        d.fees.depositSellTax{value: 100 ether}();
        assertEq(d.fees.credit(team), 10 ether);
        assertEq(d.fees.heartbeatBalance(), 1 ether);
        assertEq(d.fees.rewardETH(), 39 ether);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.credit(team), 10.1 ether);
        assertEq(d.fees.rewardETH(), 39.4 ether);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 1 ether}();
        assertEq(d.fees.credit(team), 10.2 ether);
        d.fees.depositBaseFee{value: 2 ether}();
        assertEq(d.fees.credit(team), 10.2 ether, "v3.9: the hook's 1% base stream is all reward ETH");
        assertEq(d.fees.rewardETH(), 41.8 ether);
        uint256 before_ = team.balance;
        vm.prank(team);
        d.fees.withdraw();
        assertEq(team.balance - before_, 10.2 ether);
        assertEq(d.fees.credit(team), 0);
        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(team);
        d.fees.withdraw();
    }

    function testHeartbeatCapFixedAtOneEth() public {
        vm.warp(launch + 1 days);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.HeartbeatCap, 1.1 ether, "Cannot enlarge cap");
        vm.prank(address(market));
        d.fees.depositSellTax{value: 100 ether}();
        assertEq(d.fees.heartbeatBalance(), 1 ether);
        assertEq(d.fees.rewardETH(), 39 ether);
    }

    function testFuzzSplitsConserveEveryWei(uint96 amount) public {
        uint256 v = bound(amount, 1, 100 ether);
        vm.prank(address(market));
        d.fees.depositSellTax{value: v}();
        assertEq(d.fees.credit(team) + d.fees.rewardETH() + d.fees.heartbeatBalance() + d.fees.potETH(), v);
        assertLe(d.fees.heartbeatBalance(), 1 ether);
        assertEq(d.fees.credit(team), v * 1000 / 10000);
    }

    function testBuyBackPoolOnlySlippageFailureRollbackAndDustGriefBlocked() public {
        d.fees.depositBaseFee{value: 2 ether}();
        uint256 q = market.quote(0.5 ether);
        uint256 bal = token.balanceOf(address(d.pool));
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeBuys(0, q);
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeBuys(0.5 ether, 0);
        market.setFailure(true);
        vm.expectRevert();
        d.fees.executeBuys(0.5 ether, q * 985 / 1000);
        assertEq(d.fees.rewardETH(), 2 ether);
        assertEq(d.fees.lastBuy(), 0);
        market.setFailure(false);
        d.fees.executeBuys(0.5 ether, q * 985 / 1000);
        assertEq(token.balanceOf(address(d.pool)) - bal, q);
        assertEq(d.fees.rewardETH(), 1.5 ether);
        uint256 dustQuote = market.quote(1);
        vm.expectRevert(InvalidValue.selector);
        d.fees.executeBuys(1, dustQuote);
        vm.expectRevert(TooEarly.selector);
        d.fees.executeBuys(0.5 ether, q);
        vm.warp(block.timestamp + 5 minutes);
        d.fees.executeBuys(0.5 ether, q);
    }

    function testParamsStepCooldownBoundsAuthorityAndLetter() public {
        vm.expectRevert(Unauthorized.selector);
        d.params.set(Params.Key.EmissionBps, 360, "x");
        vm.expectRevert(TooEarly.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.EmissionBps, 360, "x");
        vm.warp(launch + 1 days);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.EmissionBps, 386, "x");
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.EmissionBps, 360, "");
        vm.prank(swarm);
        d.params.set(Params.Key.EmissionBps, 385, "Lower runway risk");
        assertEq(d.params.get(Params.Key.EmissionBps), 385);
        vm.expectRevert(TooEarly.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.EmissionBps, 350, "x");
    }

    function testAllDefaultParamsWithinHardBounds() public view {
        for (uint256 i; i < 45; ++i) {
            Params.Key k = Params.Key(i);
            (uint256 low, uint256 high) = d.params.bounds(k);
            assertGe(d.params.get(k), low);
            assertLe(d.params.get(k), high);
        }
    }

    function testFuzzNoStepAboveTenPercent(uint96 value) public {
        vm.warp(launch + 1 days);
        uint256 v = bound(value, 386, 10000);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(swarm);
        d.params.set(Params.Key.EmissionBps, v, "Rejected increase");
    }

    function testPoolNoPublicReserveRecycleOrPayment() public {
        vm.expectRevert(Unauthorized.selector);
        d.pool.reserve(1);
        vm.expectRevert(Unauthorized.selector);
        d.pool.recycle(1);
        vm.expectRevert(Unauthorized.selector);
        d.pool.pay(alice, 1);
        vm.expectRevert(Unauthorized.selector);
        d.fees.payBounty(alice);
    }
}
