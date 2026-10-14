// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IntegrationV4Market, TestV4Market, MockV4Manager} from "./mocks/MockV4Manager.sol";
import {RealManager, LiquidityParams} from "./V4Integration.t.sol";
import {V4Market} from "../src/V4Market.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {PoolKey, SwapParams} from "../src/interfaces/IV4.sol";
import "../src/lib/Errors.sol";

/// @notice L2 import audit a3749636 (v3.18, medium): the launch tax and the 1% share were charged on the specified
/// exact input, not on what the pool consumed. On the old hook (e17f0ef) a 10 ETH buy at the extreme bound
/// stopped by a sqrtPriceLimitX96 just under spot swapped about 0.51 ETH, paid 9.51 ETH and lost 9 ETH to the
/// launch tax (`test/scratch` reproduction: paid 9506582405126613941 wei, heldLaunchTax 9e18). The v4 rules let a
/// hook charge the specified currency only in beforeSwap, so the fix refuses any buy whose limit is not the
/// extreme bound and makes afterSwap refuse a partial fill. These tests run the real v4 PoolManager.
contract AuditV318Test is BaseTest {
    uint160 internal constant EXTREME = 4295128740; // TickMath.MIN_SQRT_PRICE + 1
    uint160 internal constant MAX_EXTREME = 1461446703485210103287273052203988822378723970341;
    uint160 internal constant SPOT = uint160(1 << 96);
    RealManager internal manager;
    V4Market internal hook;
    FeeRouter internal router;
    uint160 internal limit;

    function setUp() public override {
        super.setUp();
        vm.deal(address(this), 10000 ether);
        manager = RealManager(address(new PoolManager(address(this))));
        bytes memory code = abi.encodePacked(
            type(IntegrationV4Market).creationCode,
            abi.encode(
                address(manager),
                address(token),
                uint24(12500),
                int24(60),
                address(this),
                address(bindingFactory),
                address(desk),
                bindingConfigHash()
            )
        );
        bytes32 hash = keccak256(code);
        bytes32 salt;
        for (uint256 i;; ++i) {
            salt = bytes32(i);
            if (uint160(vm.computeCreate2Address(salt, hash, address(this))) & 0x3fff == 0x10cc) break;
        }
        hook = new IntegrationV4Market{salt: salt}(
            address(manager),
            address(token),
            12500,
            60,
            address(this),
            address(bindingFactory),
            address(desk),
            bindingConfigHash()
        );
        router = canonicalFees(address(hook));
        vm.prank(team);
        bindHook(hook, address(router));
        manager.initialize(hook.key(), SPOT);
        manager.unlock(abi.encode(uint8(0), uint256(1000 ether)));
    }

    receive() external payable {}

    /// @dev action 0 adds full-range liquidity, 1 buys (ETH in) and 2 sells (tokens in) at `limit`.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager));
        (uint8 action, uint256 amount) = abi.decode(data, (uint8, uint256));
        int256 delta;
        if (action == 0) {
            (delta,) =
                manager.modifyLiquidity(hook.key(), LiquidityParams(-887220, 887220, int256(amount), bytes32(0)), "");
        } else {
            delta = manager.swap(hook.key(), SwapParams(action == 1, -int256(amount), limit), "");
        }
        int128 a = int128(delta >> 128);
        int128 b = int128(delta);
        if (a < 0) manager.settle{value: uint256(-int256(a))}();
        else if (a > 0) manager.take(address(0), address(this), uint256(uint128(a)));
        if (b < 0) {
            manager.sync(address(token));
            token.transfer(address(manager), uint256(-int256(b)));
            manager.settle();
        } else if (b > 0) {
            manager.take(address(token), address(this), uint256(uint128(b)));
        }
        return abi.encode(delta);
    }

    function _swap(uint8 action, uint256 amount, uint160 limit_) internal returns (int128 eth, int128 tokens) {
        limit = limit_;
        int256 delta = abi.decode(manager.unlock(abi.encode(action, amount)), (int256));
        eth = int128(delta >> 128);
        tokens = int128(delta);
    }

    // ------------------------------------------------------------- audit reproduction: price-limited buy

    /// @dev The audit's input: 10 ETH specified, a limit the pool reaches after about 0.5 ETH. The hook refuses it
    /// before any ETH moves; nothing is taxed and nothing is held.
    function testAuditPriceLimitedBuyRevertsInsteadOfPayingTaxOnUnconsumedEth() public {
        uint160 reached = uint160(uint256(SPOT) * 9995 / 10000);
        uint256 before = address(this).balance;
        uint256 tokensBefore = token.balanceOf(address(this));
        limit = reached;
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), uint256(10 ether)));
        assertEq(address(this).balance, before, "no ETH left the buyer");
        assertEq(token.balanceOf(address(this)), tokensBefore);
        assertEq(hook.heldLaunchTax(), 0, "no launch tax on a refused buy");
        assertEq(hook.heldBase(), 0);
        assertEq(address(hook).balance, 0);
    }

    /// @dev The same refusal after the launch window (1% share) and for a front-run style limit at spot itself.
    function testPriceLimitedBuyRefusedAfterLaunchWindowToo() public {
        vm.warp(hook.initializedAt() + 60 minutes);
        uint256 before = address(this).balance;
        limit = uint160(uint256(SPOT) * 9999 / 10000);
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), uint256(10 ether)));
        limit = SPOT - 1;
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), uint256(1 ether)));
        limit = EXTREME + 1;
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), uint256(1 ether)));
        assertEq(address(this).balance, before);
        assertEq(hook.heldBase(), 0);
    }

    /// @dev The hook's own revert reason, seen directly as the manager would see it.
    function testBeforeSwapNamesThePriceLimitedBuyError() public {
        PoolKey memory k = hook.key();
        uint160 given = uint160(uint256(SPOT) * 9995 / 10000);
        vm.prank(address(manager));
        vm.expectRevert(abi.encodeWithSelector(V4Market.PriceLimitedBuy.selector, given));
        hook.beforeSwap(address(this), k, SwapParams(true, -int256(10 ether), given), "");
        assertEq(hook.BUY_PRICE_LIMIT(), EXTREME);
    }

    // ------------------------------------------------------------- full fills pay exactly as before

    /// @dev At the extreme bound the pool consumes the whole net input: 10 ETH pays exactly 9 ETH launch tax and
    /// the buyer is debited exactly 10 ETH, as on e17f0ef.
    function testFullFillTenEthBuyPaysExactlyNinetyPercentInTheFirstStep() public {
        uint256 before = address(this).balance;
        (int128 eth, int128 tokens) = _swap(1, 10 ether, EXTREME);
        assertEq(before - address(this).balance, 10 ether, "buyer pays exactly the specified input");
        assertEq(eth, -int128(int256(10 ether)));
        assertGt(tokens, 0);
        assertEq(hook.heldLaunchTax(), 9 ether, "90% of the input, all of it consumed or taxed");
        assertEq(hook.heldBase(), 0);
        assertEq(address(hook).balance, 9 ether);
        hook.flushFees();
        assertEq(router.rewardETH(), 9 ether);
    }

    function testFullFillBuysPayEachStepExactly() public {
        uint256[4] memory bps = [uint256(9000), 5000, 2500, 100];
        uint256 taxHeld;
        uint256 baseHeld;
        for (uint256 i; i < 4; ++i) {
            vm.warp(hook.initializedAt() + i * 10 minutes);
            uint256 before = address(this).balance;
            _swap(1, 2 ether, EXTREME);
            assertEq(before - address(this).balance, 2 ether);
            if (bps[i] > 100) {
                assertEq(hook.heldLaunchTax() - taxHeld, 2 ether * bps[i] / 10000);
                assertEq(hook.heldBase(), baseHeld);
            } else {
                assertEq(hook.heldLaunchTax(), taxHeld);
                assertEq(hook.heldBase() - baseHeld, 0.02 ether);
            }
            taxHeld = hook.heldLaunchTax();
            baseHeld = hook.heldBase();
        }
        assertEq(taxHeld, 3.3 ether);
        assertEq(baseHeld, 0.02 ether);
    }

    /// @dev Any limit other than the extreme bound is refused; the extreme bound always pays floor(in * bps / 1e4)
    /// and debits exactly the specified input. Run with the verifier's FOUNDRY_FUZZ_SEED.
    function testFuzzOnlyTheExtremeBoundBuysAndPaysTheFlooredTax(uint96 amountIn, uint160 badLimit, uint8 step) public {
        uint256 ethIn = bound(amountIn, 1, 100 ether);
        badLimit = uint160(bound(badLimit, EXTREME + 1, SPOT - 1));
        vm.warp(hook.initializedAt() + bound(step, 0, 3) * 10 minutes);
        uint256 taxBps = hook.currentBuyTaxBps();
        uint256 before = address(this).balance;
        limit = badLimit;
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), ethIn));
        assertEq(address(this).balance, before);
        (int128 eth,) = _swap(1, ethIn, EXTREME);
        assertEq(uint256(-int256(eth)), ethIn);
        assertEq(before - address(this).balance, ethIn);
        assertEq(hook.heldLaunchTax() + hook.heldBase(), ethIn * taxBps / 10000, "tax only on consumed input");
    }

    /// @dev The FeeRouter's reward buy goes through the hook's own unlock with the extreme bound: unchanged.
    function testSystemRewardBuyStillFills() public {
        vm.warp(hook.initializedAt() + 60 minutes);
        router.depositBaseFee{value: 1 ether}();
        uint256 beforePool = token.balanceOf(address(d.pool));
        uint256 quoted = hook.quote(0.5 ether);
        router.executeBuys(0.5 ether, quoted * 985 / 1000);
        assertGe(token.balanceOf(address(d.pool)) - beforePool, quoted * 985 / 1000);
    }

    // ------------------------------------------------------------- sells are charged on the actual output

    /// @dev A price-limited sell may stop early: the surcharge is taken in afterSwap from the ETH the pool actually
    /// paid, so it needs no restriction and is unchanged.
    function testPriceLimitedSellStillFillsPartiallyAndIsChargedOnActualOutput() public {
        vm.warp(hook.initializedAt() + 60 minutes);
        uint160 reached = uint160(uint256(SPOT) * 10005 / 10000);
        uint256 tokensBefore = token.balanceOf(address(this));
        (int128 eth, int128 tokens) = _swap(2, 100 ether, reached);
        uint256 sold = uint256(-int256(tokens));
        assertLt(sold, 100 ether, "the limit stopped the sell early");
        assertGt(sold, 0);
        assertEq(tokensBefore - token.balanceOf(address(this)), sold);
        uint256 received = uint256(uint128(eth));
        uint256 fees = hook.heldBase() + hook.heldSellTax();
        uint256 poolOutput = received + fees;
        assertEq(hook.heldBase(), poolOutput * 100 / 10000, "base 1% of the ETH the pool actually paid");
        assertEq(address(hook).balance, fees);
        // The extreme bound still works for sells as well.
        (eth,) = _swap(2, 1 ether, MAX_EXTREME);
        assertGt(eth, 0);
    }

    // ------------------------------------------------------------- interface unchanged

    function testPublicInterfaceUnchanged() public view {
        assertEq(hook.desk(), address(desk));
        assertEq(hook.token(), address(token));
        assertEq(hook.gameConfigHash(), bindingConfigHash());
        assertEq(hook.launcher(), address(this));
        assertEq(address(hook.manager()), address(manager));
        assertGt(hook.initializedAt(), 0);
        assertEq(address(hook.fees()), address(router));
        (uint256 taxBps, uint256 left, uint256 cap, uint256 capLeft) = hook.launchStatus();
        assertEq(taxBps, 9000);
        assertEq(left, 30 minutes);
        assertEq(cap, type(uint256).max);
        assertEq(capLeft, 0);
        assertEq(hook.spot(), 1 ether);
        assertEq(hook.HOOK_FLAGS(), 0x10cc);
    }
}

/// @notice The afterSwap guard, driven through the mock manager so a partial fill can be presented to the hook.
contract AuditV318PartialFillTest is BaseTest {
    uint160 internal constant EXTREME = 4295128740;
    MockV4Manager internal manager;
    TestV4Market internal hook;

    function setUp() public override {
        super.setUp();
        manager = new MockV4Manager();
        hook = new TestV4Market(
            address(manager), address(token), address(bindingFactory), address(desk), bindingConfigHash()
        );
        vm.deal(address(manager), 100 ether);
        manager.initializeHook(hook);
    }

    function _delta(int256 eth, int256 tokens) private pure returns (int256) {
        return (int256(int128(eth)) << 128) | int256(uint256(uint128(int128(tokens))));
    }

    /// @dev The audit's numbers presented to afterSwap: 10 ETH specified at 90%, only 0.5 ETH consumed.
    function testAfterSwapRefusesAPartialFill() public {
        SwapParams memory p = SwapParams(true, -int256(10 ether), EXTREME);
        (, int256 fee,) = manager.invokeBefore(hook, p);
        assertEq(uint256(fee >> 128), 9 ether);
        vm.expectRevert(abi.encodeWithSelector(V4Market.PartialFill.selector, 0.5 ether, 1 ether));
        manager.invokeAfter(hook, p, _delta(-0.5 ether, 0.5 ether));
        vm.expectRevert(abi.encodeWithSelector(V4Market.PartialFill.selector, 1 ether - 1, 1 ether));
        manager.invokeAfter(hook, p, _delta(-(1 ether - 1), 1 ether));
        // Exactly the taxed input consumed: accepted and recorded as buy volume.
        manager.invokeAfter(hook, p, _delta(-1 ether, 1 ether));
        (uint256 hour, uint256 day) = hook.imbalances();
        assertEq(hour, 0);
        assertEq(day, 0);
    }

    function testAfterSwapAcceptsExactFillAtEveryStep() public {
        uint256[4] memory bps = [uint256(9000), 5000, 2500, 100];
        for (uint256 i; i < 4; ++i) {
            vm.warp(hook.initializedAt() + i * 10 minutes);
            SwapParams memory p = SwapParams(true, -int256(3 ether), EXTREME);
            (, int256 fee,) = manager.invokeBefore(hook, p);
            uint256 taxed = 3 ether * bps[i] / 10000;
            assertEq(uint256(fee >> 128), taxed);
            manager.invokeAfter(hook, p, _delta(-int256(3 ether - taxed), 1 ether));
        }
        assertEq(hook.heldLaunchTax(), 3 ether * 16500 / 10000);
        assertEq(hook.heldBase(), 0.03 ether);
    }

    function testMockBeforeSwapRefusesNonExtremeLimitAndKeepsExactOutputRefusal() public {
        vm.expectRevert(abi.encodeWithSelector(V4Market.PriceLimitedBuy.selector, uint160(EXTREME - 1)));
        manager.invokeBefore(hook, SwapParams(true, -int256(1 ether), EXTREME - 1));
        vm.expectRevert(abi.encodeWithSelector(V4Market.PriceLimitedBuy.selector, uint160(1 << 96)));
        manager.invokeBefore(hook, SwapParams(true, -int256(1 ether), uint160(1 << 96)));
        vm.expectRevert(InvalidValue.selector);
        manager.invokeBefore(hook, SwapParams(true, int256(1 ether), EXTREME));
        assertEq(hook.heldLaunchTax(), 0);
        // Sells carry any limit; the hook ignores it in beforeSwap.
        manager.invokeBefore(hook, SwapParams(false, -int256(1 ether), uint160(2 << 96)));
    }
}
