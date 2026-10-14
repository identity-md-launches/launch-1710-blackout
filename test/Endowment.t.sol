// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {MockGameRegistry} from "./mocks/MockGameRegistry.sol";
import {Params} from "../src/Params.sol";
import "../src/lib/Errors.sol";

contract EndowmentTest is BaseTest {
    RewardPool private endowedPool;
    uint256 private constant ENDOWMENT = 250_000_000 ether;

    function setUp() public override {
        super.setUp();
        MockGameRegistry r = mockRegistry(address(market), ENDOWMENT);
        r.setModule(1, address(this));
        endowedPool = new RewardPool(address(r));
    }

    function _fund() private {
        token.transfer(address(endowedPool), ENDOWMENT);
        endowedPool.fundEndowment();
    }

    function testExactFundingFullLinearDripAndConservation() public {
        _fund();
        assertEq(endowedPool.dripPeriod(), 42 days);
        assertEq(endowedPool.available(), 0);
        vm.expectRevert(InsufficientBalance.selector);
        endowedPool.reserve(1);
        vm.warp(launch + 21 days);
        assertEq(endowedPool.available(), ENDOWMENT / 2);
        endowedPool.reserve(ENDOWMENT / 2);
        endowedPool.pay(alice, ENDOWMENT / 4);
        endowedPool.recycle(ENDOWMENT / 4);
        assertEq(endowedPool.available(), ENDOWMENT / 4);
        assertEq(
            token.balanceOf(address(endowedPool)),
            endowedPool.available() + endowedPool.reserved() + endowedPool.lockedEndowment()
        );
        vm.warp(launch + 42 days);
        assertEq(endowedPool.lockedEndowment(), 0);
        assertEq(endowedPool.available(), ENDOWMENT * 3 / 4);
        endowedPool.reserve(endowedPool.available());
        endowedPool.pay(alice, endowedPool.reserved());
        assertEq(token.balanceOf(address(endowedPool)), 0);
    }

    function testDirectTransferCannotBypassOrBackdateDrip() public {
        token.transfer(address(endowedPool), ENDOWMENT);
        vm.warp(launch + 100 days);
        assertEq(endowedPool.available(), 0);
        vm.expectRevert(InsufficientBalance.selector);
        endowedPool.reserve(1);
        vm.prank(bob);
        endowedPool.fundEndowment();
        assertEq(endowedPool.dripStart(), launch + 100 days);
        assertEq(endowedPool.available(), 0);
        vm.expectRevert(AlreadyDone.selector);
        endowedPool.fundEndowment();
        vm.expectRevert(AlreadyDone.selector);
        endowedPool.fundEndowment();
    }

    function testUnderfundingCannotActivateAndDonationsStayConserved() public {
        token.transfer(address(endowedPool), ENDOWMENT - 1);
        vm.expectRevert();
        endowedPool.fundEndowment();
        token.transfer(address(endowedPool), 101);
        endowedPool.fundEndowment();
        assertEq(endowedPool.available(), 100);
        endowedPool.reserve(100);
        endowedPool.pay(alice, 100);
        assertEq(token.balanceOf(address(endowedPool)), ENDOWMENT);
    }

    function testParamsSnapshotCannotAccelerateOrRelockExistingEndowment() public {
        _fund();
        vm.warp(launch + 1 days);
        vm.prank(swarm);
        d.params.set(Params.Key.DripPeriod, 42 days * 9 / 10, "Shorten future endowments only");
        assertEq(endowedPool.dripPeriod(), 42 days);
        assertEq(endowedPool.available(), ENDOWMENT / 42);
        vm.expectRevert(Unauthorized.selector);
        d.params.set(Params.Key.DripPeriod, 14 days, "No authority");
    }

    function testNoTeamDonorOrSwarmWithdrawalOrReserveAuthority() public {
        _fund();
        vm.warp(launch + 42 days);
        address[3] memory callers = [team, swarm, alice];
        for (uint256 i; i < callers.length; ++i) {
            vm.startPrank(callers[i]);
            vm.expectRevert(Unauthorized.selector);
            endowedPool.reserve(1);
            vm.expectRevert(Unauthorized.selector);
            endowedPool.pay(callers[i], 1);
            vm.expectRevert(Unauthorized.selector);
            endowedPool.recycle(1);
            (bool ok,) = address(endowedPool).call(abi.encodeWithSignature("withdraw()"));
            assertFalse(ok);
            (ok,) = address(endowedPool).call(abi.encodeWithSignature("withdraw(address,uint256)", callers[i], 1));
            assertFalse(ok);
            vm.stopPrank();
        }
        assertEq(token.balanceOf(address(endowedPool)), ENDOWMENT);
    }

    function testFuzzCumulativePaymentsCannotExceedVestedPrincipal(uint32 elapsed, uint128 draw) public {
        _fund();
        uint256 dt = bound(elapsed, 0, 56 days);
        vm.warp(launch + dt);
        uint256 vested = ENDOWMENT * (dt > 42 days ? 42 days : dt) / 42 days;
        assertEq(endowedPool.available(), vested);
        uint256 amount = bound(draw, 0, vested);
        endowedPool.reserve(amount);
        endowedPool.pay(alice, amount);
        assertEq(endowedPool.available() + endowedPool.reserved() + endowedPool.lockedEndowment() + amount, ENDOWMENT);
        uint256 tooMuch = endowedPool.available() + 1;
        vm.expectRevert(InsufficientBalance.selector);
        endowedPool.reserve(tooMuch);
    }
}
