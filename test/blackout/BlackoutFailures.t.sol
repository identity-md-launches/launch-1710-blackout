// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BlackoutFixture} from "./BlackoutFixture.sol";
import {V4Market} from "src/V4Market.sol";
import {GameRegistry} from "src/GameRegistry.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {Params} from "src/Params.sol";
import {PoolKey, SwapParams} from "src/interfaces/IV4.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {
    Unauthorized,
    InvalidValue,
    InvalidAddress,
    InvalidProof,
    AlreadyDone,
    NotConfigured,
    TooEarly,
    InsufficientBalance
} from "src/lib/Errors.sol";

contract BlackoutConstructorProbe {
    function deploy(bytes calldata arguments) external returns (address deployed) {
        bytes memory code = bytes.concat(type(V4Market).creationCode, arguments);
        assembly ("memory-safe") {
            deployed := create(0, add(code, 32), mload(code))
            if iszero(deployed) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}

contract BlackoutFailureTest is BlackoutFixture {
    function setUp() public {
        _deployFixture();
        _seed();
    }

    function test_ConstructorRejectsEachMissingIdentityAndWrongPoolPolicy() public {
        BlackoutConstructorProbe probe = new BlackoutConstructorProbe();
        for (uint256 word; word < 7; ++word) {
            bytes memory args = abi.encode(
                address(manager), address(token), uint24(12500), int24(60), address(this), address(desk), _configHash()
            );
            assembly ("memory-safe") { mstore(add(add(args, 32), mul(word, 32)), 0) }
            vm.expectRevert(InvalidValue.selector);
            probe.deploy(args);
        }
        vm.expectRevert(InvalidValue.selector);
        probe.deploy(
            abi.encode(
                address(manager), address(token), uint24(3000), int24(60), address(this), address(desk), _configHash()
            )
        );
        vm.expectRevert(InvalidValue.selector);
        probe.deploy(
            abi.encode(
                address(manager), address(token), uint24(12500), int24(-60), address(this), address(desk), _configHash()
            )
        );
        vm.expectRevert(InvalidValue.selector);
        probe.deploy(
            abi.encode(
                address(manager),
                address(token),
                uint24(12500),
                int24(32768),
                address(this),
                address(desk),
                _configHash()
            )
        );
    }

    function test_ValidConstructorArgumentsStillRequirePermissionAddress() public {
        BlackoutConstructorProbe probe = new BlackoutConstructorProbe();
        address predicted = vm.computeCreateAddress(address(probe), 1);
        assertTrue(uint160(predicted) & 0x3fff != 0x10cc, "fixture must exercise wrong flags");
        vm.expectRevert(InvalidAddress.selector);
        probe.deploy(
            abi.encode(
                address(manager), address(token), uint24(12500), int24(60), address(this), address(desk), _configHash()
            )
        );
    }

    function test_EveryPoolKeyWordIsAuthenticated() public {
        for (uint256 field; field < 5; ++field) {
            PoolKey memory wrong = hook.key();
            if (field == 0) wrong.currency0 = address(token);
            else if (field == 1) wrong.currency1 = actors[0];
            else if (field == 2) wrong.fee = 3000;
            else if (field == 3) wrong.tickSpacing = 120;
            else wrong.hooks = actors[0];
            SwapParams memory p = SwapParams(true, -int256(1 ether), BUY_LIMIT);
            vm.startPrank(address(manager));
            vm.expectRevert(Unauthorized.selector);
            hook.afterInitialize(address(this), wrong, PRICE, 0);
            vm.expectRevert(Unauthorized.selector);
            hook.beforeSwap(address(this), wrong, p, "");
            vm.expectRevert(Unauthorized.selector);
            hook.afterSwap(address(this), wrong, p, 0, "");
            vm.stopPrank();
        }
        assertEq(_held(), 0);
        assertEq(hook.initializedAt(), START);
    }

    function test_UnlockCallbackRequiresActiveSystemOperationEvenFromManager() public {
        vm.expectRevert(Unauthorized.selector);
        vm.prank(address(manager));
        hook.unlockCallback(abi.encode(1 ether, 1, actors[0]));
        vm.expectRevert(Unauthorized.selector);
        hook.buy{value: 1 ether}(1, actors[0]);
        vm.expectRevert(Unauthorized.selector);
        hook.sell(1 ether, 1, actors[0]);
        assertEq(address(hook).balance, 0);
    }

    function test_WrongPriceLimitBubblesExactHookErrorAndRollsBack() public {
        uint160 rejected = BUY_LIMIT + 1;
        bytes memory expected = abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hook),
            IHooks.beforeSwap.selector,
            abi.encodeWithSelector(V4Market.PriceLimitedBuy.selector, rejected),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
        uint256 beforeETH = address(this).balance;
        uint256 beforeTokens = token.balanceOf(address(this));
        uint256 beforePrice = hook.spot();
        vm.expectRevert(expected);
        driver.trade{value: 1 ether}(true, 1 ether, rejected, 0);
        assertEq(address(this).balance, beforeETH);
        assertEq(token.balanceOf(address(this)), beforeTokens);
        assertEq(hook.spot(), beforePrice);
        assertEq(_held(), 0);
    }

    function test_SwapSlippageFailureRollsBackPoolFeesAndOracle() public {
        vm.warp(START + 31 minutes);
        uint256 beforePrice = hook.spot();
        uint256 beforeETH = address(this).balance;
        uint256 beforeTokens = token.balanceOf(address(this));
        uint256 beforeManager = address(manager).balance;
        uint256 beforeUpdated = hook.updatedAt();
        vm.expectRevert(bytes("minimum output"));
        driver.trade{value: 1 ether}(true, 1 ether, BUY_LIMIT, type(uint128).max);
        assertEq(hook.spot(), beforePrice);
        assertEq(address(this).balance, beforeETH);
        assertEq(token.balanceOf(address(this)), beforeTokens);
        assertEq(address(manager).balance, beforeManager);
        assertEq(hook.updatedAt(), beforeUpdated);
        assertEq(_held(), 0);
        assertGt(uint256(uint128(_buy(1 ether).amount1())), 0, "valid retry succeeds");
    }

    function test_BuyTaxTransitionsAtExactSecondBoundaries() public {
        uint256[9] memory ages = [uint256(0), 599, 600, 1199, 1200, 1799, 1800, 1801, 3600];
        uint256[9] memory bps = [uint256(9000), 9000, 5000, 5000, 2500, 2500, 100, 100, 100];
        for (uint256 i; i < ages.length; ++i) {
            vm.warp(START + ages[i]);
            uint256 beforeHeld = _held();
            uint256 beforeLaunch = hook.heldLaunchTax();
            _buy(10000);
            assertEq(_held() - beforeHeld, bps[i], "tax on 10000 wei");
            assertEq(hook.currentBuyTaxBps(), bps[i]);
            assertEq(hook.sinceLaunch(), ages[i]);
            assertEq(hook.launchTaxTimeLeft(), ages[i] >= 1800 ? 0 : 1800 - ages[i]);
            assertEq(hook.nextStepIn(), ages[i] >= 1800 ? 0 : 600 - ages[i] % 600);
            if (ages[i] >= 1800) assertEq(hook.heldLaunchTax(), beforeLaunch, "launch stream closed");
        }
        assertEq(address(hook).balance, _held());
    }

    function test_OneWeiAndTaxRoundingEdgesNeverOvercharge() public {
        uint256[8] memory inputs = [uint256(1), 2, 9, 10, 99, 100, 9999, 10000];
        uint256[4] memory rates = [uint256(9000), 5000, 2500, 100];
        for (uint256 stage; stage < 4; ++stage) {
            vm.warp(START + stage * 10 minutes);
            for (uint256 i; i < inputs.length; ++i) {
                uint256 beforeHeld = _held();
                uint256 beforeETH = address(this).balance;
                _buy(inputs[i]);
                assertEq(beforeETH - address(this).balance, inputs[i]);
                uint256 charged = _held() - beforeHeld;
                assertLe(charged * 10000, inputs[i] * rates[stage]);
                assertLt(inputs[i] * rates[stage] - charged * 10000, 10000, "less than one wei rounding");
                assertLt(charged, inputs[i], "hook cannot consume all specified input");
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_PartialSellRefundsUnusedTokensAndTaxesOnlyOutput(uint96 input, uint16 change) public {
        vm.warp(START + 31 minutes);
        uint256 amount = bound(input, 100 ether, 50_000 ether);
        uint160 limit = uint160(uint256(PRICE) * (10000 + bound(change, 1, 1000)) / 10000);
        uint256 beforeToken = token.balanceOf(address(this));
        uint256 beforeETH = address(this).balance;
        uint256 beforeManager = address(manager).balance;
        BalanceDelta delta = driver.trade(false, amount, limit, 0);
        uint256 spent = uint256(-int256(delta.amount1()));
        uint256 gross = beforeManager - address(manager).balance;
        uint256 received = address(this).balance - beforeETH;
        assertLe(spent, amount);
        assertGt(spent, 0);
        assertEq(beforeToken - token.balanceOf(address(this)), spent);
        assertEq(hook.heldBase(), gross / 100);
        assertEq(received + _held(), gross);
        assertLe(_held(), gross * 1500 / 10000);
        assertEq(address(hook).balance, _held());
    }

    function test_TwapWarmupAndLongIdleRecovery() public {
        vm.warp(START + 31 minutes - 1);
        vm.expectRevert(NotConfigured.selector);
        hook.twap();
        vm.warp(START + 31 minutes);
        assertEq(hook.twap(), 1 ether);
        vm.warp(START + 365 days);
        assertEq(hook.twap(), 1 ether, "constant price extrapolates across idle periods");
        _buy(10 ether);
        assertEq(hook.twap(), 1 ether, "same-block swap cannot rewrite historical TWAP");
        uint256 newPrice = hook.spot();
        vm.warp(vm.getBlockTimestamp() + 32 minutes);
        assertApproxEqAbs(hook.twap(), newPrice, 2);
        _sell(1 ether);
        assertEq(hook.updatedAt(), block.timestamp);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BuySellRoundTripCannotCreateValue(uint96 input, uint32 elapsed) public {
        uint256 amount = bound(input, 1e6, 10 ether);
        vm.warp(START + bound(elapsed, 0, 2 days));
        uint256 beforeETH = address(this).balance;
        uint256 beforeTokens = token.balanceOf(address(this));
        uint256 acquired = uint256(uint128(_buy(amount).amount1()));
        assertGt(acquired, 0);
        _sell(acquired);
        assertEq(token.balanceOf(address(this)), beforeTokens, "round trip returns to same token position");
        assertLt(address(this).balance, beforeETH, "swap cycle cannot produce free ETH");
        assertEq(address(hook).balance, _held());
        assertLe(_held(), beforeETH - address(this).balance, "all hook fees funded by trader loss");
    }

    function test_VolumeWindowsExpireAtTheirBucketBoundaries() public {
        _sell(10 ether);
        (uint256 hour, uint256 day) = hook.imbalances();
        assertGt(hour, 0);
        assertGt(day, 0);
        vm.warp(START + 1 hours - 1);
        (hour,) = hook.imbalances();
        assertGt(hour, 0);
        vm.warp(START + 1 hours);
        (hour, day) = hook.imbalances();
        assertEq(hour, 0);
        assertGt(day, 0);
        vm.warp(START + 24 hours);
        (hour, day) = hook.imbalances();
        assertEq(hour, 0);
        assertEq(day, 0);
        // A swap after both rings wrap can still observe and record volume.
        _sell(1 ether);
        (hour, day) = hook.imbalances();
        assertGt(hour, 0);
        assertGt(day, 0);
    }
}

contract BlackoutBindingTest is BlackoutFixture {
    function setUp() public {
        _deployFixture();
        _seed();
        _prepareBinding();
    }

    function test_BindingRejectsZeroLaunchAndOutOfRangeIndex() public {
        vm.expectRevert(InvalidValue.selector);
        hook.bindFeeRouter(address(router), 0, 0);
        vm.expectRevert(InvalidValue.selector);
        hook.bindFeeRouter(address(router), REGISTRY_LAUNCH, 8);
        vm.expectRevert(InvalidAddress.selector);
        hook.bindFeeRouter(actors[0], REGISTRY_LAUNCH, 0);
        assertEq(address(hook.fees()), address(0));
        _bind();
    }

    function test_DeskMustBeBoundAndRegistryMustBeCanonical() public {
        desk.setRegistry(address(0));
        vm.expectRevert(InvalidProof.selector);
        hook.bindFeeRouter(address(router), REGISTRY_LAUNCH, 0);
        GameRegistry twin = new GameRegistry(
            address(token), address(parameters), address(hook), STARTER_ROOT, FREE_ROOT, SNAPSHOT, ENDOWMENT
        );
        desk.setRegistry(address(twin));
        vm.expectRevert(InvalidProof.selector);
        hook.bindFeeRouter(address(router), REGISTRY_LAUNCH, 0);
        desk.setRegistry(address(registry));
        _bind();
        assertEq(address(hook.fees()), address(router));
    }

    function test_RegistryCoordinatesAndRouterEnrollmentCannotBeForged() public {
        vm.expectRevert(InvalidProof.selector);
        hook.bindFeeRouter(address(router), REGISTRY_LAUNCH, 1);
        FeeRouter twin = new FeeRouter(address(registry));
        vm.expectRevert(InvalidValue.selector);
        hook.bindFeeRouter(address(twin), REGISTRY_LAUNCH, 0);
        assertEq(address(hook.fees()), address(0));
        _bind();
    }

    function test_ChangedFrozenConfigurationCannotBind() public {
        GameRegistry other = new GameRegistry(
            address(token),
            address(parameters),
            address(hook),
            keccak256("different starter tree"),
            FREE_ROOT,
            SNAPSHOT,
            ENDOWMENT
        );
        FeeRouter otherRouter = new FeeRouter(address(other));
        vm.expectRevert(InvalidProof.selector);
        hook.bindFeeRouter(address(otherRouter), REGISTRY_LAUNCH, 0);
        assertEq(address(hook.fees()), address(0));
    }

    function test_WrongRegistryTokenOrMarketCannotBind() public {
        GameRegistry wrongToken = new GameRegistry(
            actors[0], address(parameters), address(hook), STARTER_ROOT, FREE_ROOT, SNAPSHOT, ENDOWMENT
        );
        FeeRouter tokenRouter = new FeeRouter(address(wrongToken));
        vm.expectRevert(InvalidValue.selector);
        hook.bindFeeRouter(address(tokenRouter), REGISTRY_LAUNCH, 0);
        GameRegistry wrongMarket = new GameRegistry(
            address(token), address(parameters), actors[0], STARTER_ROOT, FREE_ROOT, SNAPSHOT, ENDOWMENT
        );
        FeeRouter marketRouter = new FeeRouter(address(wrongMarket));
        vm.expectRevert(InvalidValue.selector);
        hook.bindFeeRouter(address(marketRouter), REGISTRY_LAUNCH, 0);
        assertEq(address(hook.fees()), address(0));
    }

    function test_UnrelatedParamsCannotBindEvenWithTheRightDeskRegistryView() public {
        Params foreign = new Params(actors[0], 200, 1 ether);
        GameRegistry other = new GameRegistry(
            address(token), address(foreign), address(hook), STARTER_ROOT, FREE_ROOT, SNAPSHOT, ENDOWMENT
        );
        desk.setRegistry(address(other));
        FeeRouter otherRouter = new FeeRouter(address(other));
        vm.expectRevert(InvalidProof.selector);
        hook.bindFeeRouter(address(otherRouter), REGISTRY_LAUNCH, 0);
        assertEq(address(hook.params()), address(0));
    }

    function test_AllStreamsFlushOnceToRealRouterAndAnyoneCanTrigger() public {
        _accrueAllStreams();
        uint256 base = hook.heldBase();
        uint256 launchTax = hook.heldLaunchTax();
        uint256 surcharge = hook.heldSellTax();
        vm.prank(actors[0]);
        _bind();
        vm.prank(actors[1]);
        hook.flushFees();
        assertEq(_held(), 0);
        assertEq(address(hook).balance, 0);
        assertEq(address(router).balance, base + launchTax + surcharge);
        assertEq(router.credit(router.team()), surcharge / 10);
        assertEq(router.heartbeatBalance(), surcharge * 200 / 10000);
        assertEq(router.rewardETH() + router.credit(router.team()) + router.heartbeatBalance(), address(router).balance);
        assertGe(router.rewardETH(), base + launchTax);
        vm.expectRevert(InsufficientBalance.selector);
        hook.flushFees();
        vm.expectRevert(AlreadyDone.selector);
        _bind();
    }

    /// @dev Downstream fault injection, not a claim that the immutable FeeRouter normally rejects.
    /// A failure in the third stream must roll back earlier deposits and all hook counters.
    function test_EachFailedFeeDepositRollsBackAllStreamsAndCanRetry() public {
        _bind();
        _accrueAllStreams();
        uint256 base = hook.heldBase();
        uint256 surcharge = hook.heldSellTax();
        uint256 launchTax = hook.heldLaunchTax();
        bytes4[3] memory selectors =
            [router.depositBaseFee.selector, router.depositSellTax.selector, router.depositLaunchTax.selector];
        for (uint256 i; i < selectors.length; ++i) {
            bytes memory failure = abi.encodeWithSignature("Error(string)", "injected receiver failure");
            vm.mockCallRevert(address(router), abi.encodeWithSelector(selectors[i]), failure);
            vm.expectRevert(failure);
            hook.flushFees();
            assertEq(hook.heldBase(), base);
            assertEq(hook.heldSellTax(), surcharge);
            assertEq(hook.heldLaunchTax(), launchTax);
            assertEq(address(hook).balance, base + surcharge + launchTax);
            assertEq(address(router).balance, 0);
            assertEq(router.rewardETH(), 0);
            assertEq(router.credit(router.team()), 0);
            assertEq(router.heartbeatBalance(), 0);
            vm.clearMockedCalls();
        }
        hook.flushFees();
        assertEq(_held(), 0);
        assertEq(address(router).balance, base + surcharge + launchTax);
    }

    function test_SystemBuyWarmupBadParametersSlippageAndSuccessfulRetry() public {
        _bind();
        vm.deal(address(router), 2 ether);
        vm.startPrank(address(router));
        vm.expectRevert(TooEarly.selector);
        hook.buy{value: 1 ether}(1, actors[0]);
        vm.expectRevert(Unauthorized.selector);
        hook.buy{value: 1 ether}(0, actors[0]);
        vm.expectRevert(Unauthorized.selector);
        hook.buy{value: 1 ether}(1, address(0));
        vm.expectRevert(Unauthorized.selector);
        hook.buy(1, actors[0]);
        vm.stopPrank();
        vm.warp(START + 30 minutes);
        vm.expectRevert(NotConfigured.selector);
        vm.prank(address(router));
        hook.buy{value: 1 ether}(1, actors[0]);
        vm.warp(START + 31 minutes);
        uint256 beforePrice = hook.spot();
        vm.expectRevert(InsufficientBalance.selector);
        vm.prank(address(router));
        hook.buy{value: 1 ether}(type(uint128).max, actors[0]);
        assertEq(hook.spot(), beforePrice);
        assertEq(_held(), 0);
        assertEq(address(router).balance, 2 ether);
        uint256 beforeTokens = token.balanceOf(actors[0]);
        vm.prank(address(router));
        uint256 received = hook.buy{value: 1 ether}(1, actors[0]);
        assertEq(token.balanceOf(actors[0]) - beforeTokens, received);
        assertEq(address(router).balance, 1 ether);
        assertEq(hook.heldBase(), 0.01 ether, "self-swap taxed exactly once");
        assertEq(address(hook).balance, 0.01 ether);
        vm.expectRevert(Unauthorized.selector);
        vm.prank(address(manager));
        hook.unlockCallback(abi.encode(1 ether, 1, actors[0]));
    }

    function test_RealFeeRouterRewardBuyPreservesItsLiabilities() public {
        _bind();
        _buy(1 ether);
        hook.flushFees();
        vm.warp(START + 31 minutes);
        uint256 beforeReward = router.rewardETH();
        uint256 beforeTokens = token.balanceOf(address(rewards));
        uint256 minimum = hook.quote(0.1 ether) * 9850 / 10000;
        vm.prank(actors[0]);
        uint256 received = router.executeBuys(0.1 ether, minimum);
        assertGe(received, minimum);
        assertEq(token.balanceOf(address(rewards)) - beforeTokens, received);
        assertEq(rewards.otherInflow(), received);
        assertEq(router.rewardETH(), beforeReward - 0.1 ether);
        assertEq(address(router).balance, router.rewardETH());
        assertEq(hook.heldBase(), 0.001 ether);
        assertEq(address(hook).balance, 0.001 ether);
    }

    function test_SystemSellBoundsAndFailedSlippageRestoreTokensAndAllowance() public {
        _bind();
        vm.warp(START + 31 minutes);
        uint256 amount = hook.maxSellBatch();
        uint256 tooLow = hook.quoteSell(amount) * 9850 / 10000 - 1;
        token.transfer(address(router), amount);
        vm.prank(address(router));
        token.approve(address(hook), amount);
        vm.startPrank(address(router));
        vm.expectRevert(Unauthorized.selector);
        hook.sell(amount, 1, actors[0]);
        vm.expectRevert(Unauthorized.selector);
        hook.sell(0, 1, address(router));
        vm.expectRevert(InvalidValue.selector);
        hook.sell(amount + 1, 1, address(router));
        vm.expectRevert(InvalidValue.selector);
        hook.sell(amount, tooLow, address(router));
        vm.expectRevert(InsufficientBalance.selector);
        hook.sell(amount, type(uint128).max, address(router));
        vm.stopPrank();
        assertEq(token.balanceOf(address(router)), amount);
        assertEq(token.allowance(address(router), address(hook)), amount);
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(_held(), 0);
        uint256 beforeManager = address(manager).balance;
        uint256 minimum = hook.quoteSell(amount) * 9850 / 10000;
        vm.prank(address(router));
        uint256 received = hook.sell(amount, minimum, address(router));
        uint256 gross = beforeManager - address(manager).balance;
        assertEq(received + hook.heldBase(), gross);
        assertEq(hook.heldBase(), gross / 100);
        assertEq(hook.heldSellTax(), 0, "system sale only pays the base share");
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.balanceOf(address(hook)), 0);
        assertEq(token.allowance(address(router), address(hook)), 0);
    }

    function _accrueAllStreams() private {
        _buy(1 ether);
        vm.warp(START + 31 minutes);
        _buy(1 ether);
        _sell(10 ether);
        assertGt(hook.heldBase(), 0);
        assertGt(hook.heldSellTax(), 0);
        assertGt(hook.heldLaunchTax(), 0);
    }
}
