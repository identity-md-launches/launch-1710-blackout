// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Params} from "../src/Params.sol";
import {GridOperator} from "../src/GridOperator.sol";
import {ItemMath} from "../src/lib/ItemMath.sol";
import "../src/lib/Errors.sol";

contract BountiesTest is BaseTest {
    address private keeper;

    function setUp() public override {
        super.setUp();
        keeper = makeAddr("public keeper");
        vm.deal(address(d.packs), 100 ether);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 50 ether}();
    }

    function _close() private {
        entropy();
        vm.warp(d.rewards.epochEnd());
        d.rewards.advanceEpoch();
    }

    function testLazySettlementUnpaidAndCannotReplay() public {
        fund(100_000_000 ether);
        payPack(alice);
        place(alice, 0, 0, 0);
        _close();
        _close();
        vm.prank(keeper);
        d.rewards.settle(alice, 8);
        assertGt(d.rewards.pending(alice), 0);
        assertEq(d.fees.credit(keeper), 0);
        uint256 pending = d.rewards.pending(alice);
        uint256 reserved = d.pool.reserved();
        vm.prank(keeper);
        d.rewards.settle(alice, 8);
        assertEq(d.rewards.pending(alice), pending);
        assertEq(d.pool.reserved(), reserved);
        assertEq(d.fees.credit(keeper), 0);
    }

    function testEmptyRosterAndInvalidBatchReceiveNothing() public {
        _close();
        vm.expectRevert(InvalidValue.selector);
        d.rewards.settle(alice, 0);
        vm.expectRevert(InvalidValue.selector);
        d.rewards.settle(alice, 9);
        vm.prank(keeper);
        d.rewards.settle(alice, 8);
        assertEq(d.fees.credit(keeper), 0);
    }

    function testPlanResolutionPaidOnceIncludingAdvanceForwarding() public {
        vm.expectRevert(TooEarly.selector);
        vm.prank(keeper);
        d.grid.resolve(1);
        assertEq(d.fees.credit(keeper), 0);
        entropy();
        vm.prank(keeper);
        d.grid.resolve(1);
        assertGt(d.fees.credit(keeper), 0);
        assertLe(d.fees.credit(keeper), d.params.get(Params.Key.EntropyBounty));
        uint256 entropyPaid = d.fees.credit(keeper);
        vm.prank(keeper);
        d.grid.resolve(1);
        assertEq(d.fees.credit(keeper), entropyPaid);
        vm.expectRevert(Unauthorized.selector);
        d.grid.resolveFor(1, keeper);
        vm.warp(d.rewards.epochEnd());
        vm.prank(keeper);
        d.rewards.advanceEpoch();
        assertEq(d.fees.credit(keeper), entropyPaid + d.params.get(Params.Key.Bounty));
        finish();
        entropy();
        vm.warp(d.rewards.epochEnd());
        uint256 old = d.fees.credit(keeper);
        vm.prank(keeper);
        d.rewards.advanceEpoch();
        assertGt(d.fees.credit(keeper) - old, d.params.get(Params.Key.Bounty));
        assertLe(d.fees.credit(keeper) - old, d.params.get(Params.Key.EntropyBounty) + d.params.get(Params.Key.Bounty));
        assertEq(d.fees.credit(address(d.rewards)), 0);
    }

    function testPackEntropyCapturedOnceWithFullInventoryAndThroughPause() public {
        uint256 id = payPack(alice);
        for (uint256 i; i < 15; ++i) {
            mintItem(alice, uint8(i % 12), 0);
        }
        vm.prank(swarm);
        d.packs.pause(72 hours);
        entropy();
        vm.prank(keeper);
        d.packs.captureEntropy(id);
        assertGt(d.fees.credit(keeper), 0);
        assertLe(d.fees.credit(keeper), d.params.get(Params.Key.EntropyBounty));
        uint256 paid = d.fees.credit(keeper);
        vm.prank(keeper);
        d.packs.captureEntropy(id);
        assertEq(d.fees.credit(keeper), paid);
        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(keeper);
        d.packs.resolve(id, 1);
        assertEq(d.fees.credit(keeper), paid);
        vm.expectRevert(InvalidValue.selector);
        d.packs.captureEntropy(10000);
    }

    function testBuyBountyProportionalCapNoDustCreditAndFailureRollback() public {
        uint256 q = market.quote(0.5 ether);
        market.setFailure(true);
        vm.expectRevert();
        vm.prank(keeper);
        d.fees.executeBuys(0.5 ether, q);
        assertEq(d.fees.credit(keeper), 0);
        market.setFailure(false);
        vm.prank(keeper);
        d.fees.executeBuys(0.25 ether, q / 2);
        uint256 first = d.fees.credit(keeper);
        assertGt(first, 0);
        assertLe(first, d.params.get(Params.Key.BuyBounty) / 2);
        vm.warp(block.timestamp + 5 minutes);
        vm.prank(keeper);
        d.fees.executeBuys(0.25 ether, q / 2);
        uint256 paid = d.fees.credit(keeper);
        assertGt(paid, first);
        assertLe(paid - first, d.params.get(Params.Key.BuyBounty) / 2);
        assertLe(paid, d.params.get(Params.Key.BuyBounty));
        uint256 dustQuote = market.quote(1);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(keeper);
        d.fees.executeBuys(1, dustQuote);
        assertEq(d.fees.credit(keeper), paid);
        vm.expectRevert(InvalidValue.selector);
        vm.prank(keeper);
        d.fees.executeBuys(0, 1);
        assertEq(d.fees.credit(keeper), paid);
    }

    function testOnlyFinalizePaidOnceAndEmptyWeekUnpaid() public {
        vm.mockCall(address(d.rewards), abi.encodeCall(d.rewards.seasonReady, (0)), abi.encode(true));
        vm.startPrank(address(d.rewards));
        d.season.recordActivity(alice, 0, 10 ether, 10000);
        d.season.recordActivity(bob, 0, 20 ether, 10000);
        d.season.complete(alice, 0);
        d.season.complete(bob, 0);
        vm.stopPrank();
        vm.warp(d.season.deadline(0));
        vm.prank(keeper);
        d.season.prepare(0, 1);
        assertEq(d.fees.credit(keeper), 0);
        vm.expectRevert(AlreadyDone.selector);
        d.season.prepare(0, 64);
        vm.expectRevert(TooEarly.selector);
        d.season.finalize(0);
        entropy();
        vm.prank(keeper);
        d.season.finalize(0);
        uint256 paid = d.fees.credit(keeper);
        assertGt(paid, 0);
        assertLe(paid, d.params.get(Params.Key.SeasonBounty));
        vm.expectRevert(AlreadyDone.selector);
        d.season.finalize(0);
        vm.mockCall(address(d.rewards), abi.encodeCall(d.rewards.seasonReady, (1)), abi.encode(true));
        vm.warp(d.season.deadline(1));
        d.season.prepare(1, 64);
        entropy();
        vm.prank(keeper);
        d.season.finalize(1);
        assertEq(d.fees.credit(keeper), paid);
    }

    function testEveryWorkKindBoundedByHeartbeatAndAuthorizedProducer() public {
        Params.Key[4] memory kinds =
            [Params.Key.EntropyBounty, Params.Key.SeasonBounty, Params.Key.EntropyBounty, Params.Key.EntropyBounty];
        address[4] memory senders = [address(d.grid), address(d.season), address(d.packs), address(d.starter)];
        for (uint256 i; i < kinds.length; ++i) {
            vm.expectRevert(Unauthorized.selector);
            d.fees.payWork(keeper, kinds[i], 1, 100_000);
            vm.expectRevert(InvalidValue.selector);
            vm.prank(senders[i]);
            d.fees.payWork(keeper, kinds[i], 0, 100_000);
            vm.expectRevert(InvalidValue.selector);
            vm.prank(senders[i]);
            d.fees.payWork(keeper, kinds[i], 65, 100_000);
            // Exhaust heartbeat first, then give precisely one wei of budget via the routing split.
            while (d.fees.heartbeatBalance() != 0) {
                vm.prank(address(d.rewards));
                d.fees.payBounty(keeper);
            }
            vm.prank(address(market));
            d.fees.depositSellTax{value: 50}();
            uint256 old = d.fees.credit(keeper);
            vm.prank(senders[i]);
            d.fees.payWork(keeper, kinds[i], 1, 100_000);
            assertEq(d.fees.credit(keeper) - old, 1);
            assertEq(d.fees.heartbeatBalance(), 0);
            vm.prank(senders[i]);
            d.fees.payWork(keeper, kinds[i], 1, 100_000);
            assertEq(d.fees.credit(keeper) - old, 1);
        }
    }

    function testRemovedWorkBountiesRejectedEvenFromOldProducer() public {
        Params.Key[4] memory kinds =
            [Params.Key.MeasureBounty, Params.Key.CreditBounty, Params.Key.AuditBounty, Params.Key.SeasonScoreBounty];
        for (uint256 i; i < kinds.length; ++i) {
            vm.expectRevert(Unauthorized.selector);
            vm.prank(i == 3 ? address(d.season) : address(d.rewards));
            d.fees.payWork(keeper, kinds[i], 1, 100000);
        }
    }

    function testStarterEntropySurvivesFullInventoryExpiryAndPauseWithoutReplayPayment() public {
        entropy();
        vm.warp(launch + 48 hours);
        d.rewards.advanceEpoch();
        finish();
        for (uint256 i; i < 15; ++i) {
            mintItem(alice, uint8(i % 12), 0);
        }
        vm.prank(swarm);
        d.packs.pause(72 hours);
        vm.prank(alice);
        d.starter.claim(17, new bytes32[](0));
        vm.expectRevert(TooEarly.selector);
        vm.prank(keeper);
        d.starter.captureEntropy(17);
        assertEq(d.fees.credit(keeper), 0);
        entropy();
        vm.prank(keeper);
        d.starter.captureEntropy(17);
        bytes32 captured = d.starter.entropyHash(17);
        assertTrue(d.starter.entropyCaptured(17));
        assertTrue(captured != bytes32(0));
        uint256 paid = d.fees.credit(keeper);
        assertGt(paid, 0);
        assertLe(paid, d.params.get(Params.Key.EntropyBounty));
        vm.prank(keeper);
        d.starter.captureEntropy(17);
        assertEq(d.fees.credit(keeper), paid);
        vm.expectRevert(InsufficientBalance.selector);
        d.starter.resolve(17);

        vm.roll(vm.getBlockNumber() + 300);
        assertEq(d.starter.entropyHash(17), captured);
        vm.prank(alice);
        d.farm.expand(true);
        vm.prank(keeper);
        d.starter.resolve(17);
        assertEq(d.items.inventory(alice), 18);
        for (uint256 i; i < 3; ++i) {
            (uint8 kind, uint8 rarity) =
                ItemMath.draw(keccak256(abi.encode(captured, address(d.starter), uint256(17), i)), false, true);
            assertEq(d.items.data(16 + i).kind, kind);
            assertEq(d.items.data(16 + i).rarity, rarity);
        }
        vm.prank(keeper);
        d.starter.captureEntropy(17);
        assertEq(d.fees.credit(keeper), paid);
        vm.expectRevert(AlreadyDone.selector);
        d.starter.resolve(17);
    }

    function testWorkCreditRespectsZeroGasPricePriceCeilingAndUnitCap() public {
        vm.txGasPrice(0);
        vm.prank(address(d.grid));
        d.fees.payWork(keeper, Params.Key.EntropyBounty, 1, 10_000);
        assertEq(d.fees.credit(keeper), 0);

        uint256 ceiling = d.params.get(Params.Key.KeeperGasPrice);
        vm.txGasPrice(ceiling);
        vm.prank(address(d.grid));
        d.fees.payWork(keeper, Params.Key.EntropyBounty, 1, 10_000);
        uint256 atCeiling = d.fees.credit(keeper);
        assertGt(atCeiling, 0);
        assertLt(atCeiling, d.params.get(Params.Key.EntropyBounty));
        vm.txGasPrice(ceiling * 100);
        vm.prank(address(d.grid));
        d.fees.payWork(keeper, Params.Key.EntropyBounty, 1, 10_000);
        assertEq(d.fees.credit(keeper), atCeiling * 2);

        uint256 before_ = d.fees.credit(keeper);
        vm.prank(address(d.grid));
        d.fees.payWork(keeper, Params.Key.EntropyBounty, 1, 100_000_000);
        assertEq(d.fees.credit(keeper) - before_, d.params.get(Params.Key.EntropyBounty));
    }
}
