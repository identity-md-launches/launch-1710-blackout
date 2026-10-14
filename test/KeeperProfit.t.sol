// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";

/// @notice Execution-gas profitability at the fixture's 20 million wei gas price and funded heartbeat.
/// @dev These local measurements exclude L1 data charges, withdrawal costs, and competition between keepers.
contract KeeperProfitTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.txGasPrice(20_000_000);
        vm.deal(address(d.packs), 50 ether);
        vm.prank(address(market));
        d.fees.depositSellTax{value: 50 ether}();
        assertEq(d.fees.heartbeatBalance(), 1 ether);
    }

    function _profit(string memory action, uint256 startGas, uint256 beforeCredit) private {
        uint256 used = startGas - gasleft();
        uint256 paid = d.fees.credit(address(this)) - beforeCredit;
        uint256 cost = (used + 21_000) * tx.gasprice;
        emit log_named_uint(string.concat(action, " execution gas"), used);
        emit log_named_uint(string.concat(action, " bounty wei"), paid);
        emit log_named_uint(string.concat(action, " execution plus 21000 gas cost wei"), cost);
        assertGt(paid, cost, string.concat(action, " bounty must cover measured execution gas"));
    }

    function testPlanEntropyKeeperProfit() public {
        calmNext();
        step();
        entropy();
        uint256 beforeCredit = d.fees.credit(address(this));
        uint256 start = gasleft();
        d.grid.resolve(2);
        _profit("plan entropy", start, beforeCredit);
    }

    function testPaidPackEntropyKeeperProfit() public {
        uint256 id = payPack(alice);
        entropy();
        uint256 beforeCredit = d.fees.credit(address(this));
        uint256 start = gasleft();
        d.packs.captureEntropy(id);
        _profit("paid pack entropy", start, beforeCredit);
    }

    function testStarterEntropyKeeperProfit() public {
        vm.warp(launch + 48 hours);
        vm.prank(alice);
        d.starter.claim(17, new bytes32[](0));
        entropy();
        uint256 beforeCredit = d.fees.credit(address(this));
        uint256 start = gasleft();
        d.starter.captureEntropy(17);
        _profit("starter entropy", start, beforeCredit);
    }

    /// @dev Populate an otherwise closed week through the genuine modules' authenticated accounting hooks.
    function _season(uint256 participants, bool withPrize) private {
        vm.mockCall(address(d.rewards), abi.encodeCall(d.rewards.seasonReady, (0)), abi.encode(true));
        for (uint256 i; i < participants; ++i) {
            address player = address(uint160(0x77000 + i));
            vm.prank(address(d.rewards));
            d.season.recordActivity(player, 0, (i + 1) * 10 ether, 10000);
            vm.prank(address(d.farm));
            d.season.recordSpend(player, 1 ether, true);
            vm.prank(address(d.rewards));
            d.season.complete(player, 0);
        }
        if (withPrize) {
            fund(1 ether);
            vm.prank(address(d.rewards));
            d.pool.reserve(1 ether);
            vm.prank(address(d.rewards));
            d.season.addPrize(0, 1 ether);
        }
        vm.warp(d.season.deadline(0));
    }

    function testSeasonPrepareIsConstantUnpaidWork() public {
        _season(1, false);
        uint256 beforeCredit = d.fees.credit(address(this));
        d.season.prepare(0, 1);
        assertEq(d.fees.credit(address(this)), beforeCredit);
    }

    function testSeasonFinalizeThreeWinnersAndPrizeKeeperProfit() public {
        _season(3, true);
        d.season.prepare(0, 3);
        entropy();
        uint256 beforeCredit = d.fees.credit(address(this));
        uint256 start = gasleft();
        d.season.finalize(0);
        _profit("season finalize three winners and prize", start, beforeCredit);
    }
}
