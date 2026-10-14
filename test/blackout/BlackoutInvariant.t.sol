// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BlackoutFixture, BlackoutPoolDriver} from "./BlackoutFixture.sol";
import {V4Market} from "src/V4Market.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {NotConfigured, InsufficientBalance, AlreadyDone} from "src/lib/Errors.sol";

/// @dev Models unsolicited ETH without changing the hook's storage or balance by cheatcode.
contract BlackoutForcedETH {
    constructor(address payable recipient) payable {
        selfdestruct(recipient);
    }
}

contract BlackoutHandler is Test {
    V4Market public immutable hook;
    LaunchToken public immutable token;
    BlackoutPoolDriver public immutable driver;
    FeeRouter public immutable router;
    address[3] public actors;
    uint256 public ghostBase;
    uint256 public ghostLaunch;
    uint256 public ghostSurcharge;
    uint256 public ghostFlushedBase;
    uint256 public ghostFlushedLaunch;
    uint256 public ghostFlushedSurcharge;
    uint256 public ghostDonations;
    uint256 public ghostRewardSpent;
    uint256 public successfulBuys;
    uint256 public successfulSells;
    uint256 public successfulFlushes;
    uint256 public successfulRewardBuys;

    constructor(V4Market h, LaunchToken t, BlackoutPoolDriver d, FeeRouter r, address[3] memory a) {
        hook = h;
        token = t;
        driver = d;
        router = r;
        actors = a;
    }

    function buy(uint256 who, uint256 amount) public {
        address actor = actors[who % 3];
        amount = bound(amount, 1, 5 ether);
        uint256 ethBefore = actor.balance;
        uint256 managerBefore = address(hook.manager()).balance;
        uint256 tokenBefore = token.balanceOf(actor);
        vm.prank(actor);
        BalanceDelta delta = driver.trade{value: amount}(true, amount, 4295128740, 0);
        assertEq(ethBefore - actor.balance, amount, "exact input debited once");
        assertEq(delta.amount0(), -int128(int256(amount)));
        assertEq(token.balanceOf(actor) - tokenBefore, uint256(uint128(delta.amount1())));
        uint256 fee = amount - (address(hook.manager()).balance - managerBefore);
        if (block.timestamp < hook.initializedAt() + 30 minutes) ghostLaunch += fee;
        else ghostBase += fee;
        successfulBuys++;
    }

    function sell(uint256 who, uint256 amount) public {
        address actor = actors[who % 3];
        // All actors start with 1000 tokens; at most 96 calls sell at most 5 each.
        amount = bound(amount, 1e8, 5 ether);
        uint256 ethBefore = actor.balance;
        uint256 managerBefore = address(hook.manager()).balance;
        uint256 tokenBefore = token.balanceOf(actor);
        vm.prank(actor);
        BalanceDelta delta = driver.trade(false, amount, 1461446703485210103287273052203988822378723970341, 0);
        uint256 gross = managerBefore - address(hook.manager()).balance;
        uint256 paid = actor.balance - ethBefore;
        uint256 base = gross / 100;
        uint256 fee = gross - paid;
        assertGe(fee, base, "sell base missing");
        assertLe(fee, gross * 1500 / 10000, "sell fee cap");
        assertEq(delta.amount0(), int128(int256(paid)));
        assertEq(delta.amount1(), -int128(int256(amount)));
        assertEq(tokenBefore - token.balanceOf(actor), amount);
        ghostBase += base;
        ghostSurcharge += fee - base;
        successfulSells++;
    }

    function advance(uint256 seconds_) external {
        uint256 beforeTax = hook.currentBuyTaxBps();
        vm.warp(vm.getBlockTimestamp() + bound(seconds_, 0, 26 hours));
        assertLe(hook.currentBuyTaxBps(), beforeTax, "launch tax reopened");
    }

    function bind() public {
        if (address(hook.fees()) != address(0)) {
            vm.expectRevert(AlreadyDone.selector);
            hook.bindFeeRouter(address(router), 77, 0);
        } else {
            hook.bindFeeRouter(address(router), 77, 0);
            assertEq(address(hook.fees()), address(router));
        }
    }

    function flush(uint256 who) public {
        uint256 held = ghostBase + ghostLaunch + ghostSurcharge;
        if (address(hook.fees()) == address(0)) {
            vm.expectRevert(NotConfigured.selector);
            vm.prank(actors[who % 3]);
            hook.flushFees();
        } else if (held == 0) {
            vm.expectRevert(InsufficientBalance.selector);
            vm.prank(actors[who % 3]);
            hook.flushFees();
        } else {
            uint256 beforeBalance = address(router).balance;
            vm.prank(actors[who % 3]);
            hook.flushFees();
            assertEq(address(router).balance - beforeBalance, held, "forwarded exact liabilities");
            ghostFlushedBase += ghostBase;
            ghostFlushedLaunch += ghostLaunch;
            ghostFlushedSurcharge += ghostSurcharge;
            ghostBase = 0;
            ghostLaunch = 0;
            ghostSurcharge = 0;
            successfulFlushes++;
        }
    }

    function withdrawTeam() external {
        address team = router.team();
        uint256 owed = router.credit(team);
        uint256 beforeBalance = team.balance;
        if (owed == 0) vm.expectRevert(InsufficientBalance.selector);
        vm.prank(team);
        router.withdraw();
        assertEq(team.balance - beforeBalance, owed, "no double withdrawal");
        assertEq(router.credit(team), 0);
    }

    function rewardBuy(uint256 who, uint256 amount) public {
        // These are state-machine preconditions, not caught failures of valid buys.
        if (
            address(hook.fees()) == address(0) || block.timestamp < hook.initializedAt() + 31 minutes
                || router.rewardETH() == 0 || (router.lastBuy() != 0 && block.timestamp < router.lastBuy() + 5 minutes)
        ) return;
        uint256 maximum = router.rewardETH() < 0.1 ether ? router.rewardETH() : 0.1 ether;
        uint256 minimum = maximum < 0.05 ether ? maximum : 0.05 ether;
        amount = bound(amount, minimum, maximum);
        uint256 minimumOut = hook.quote(amount) * 9850 / 10000;
        if (minimumOut == 0) return; // Sub-wei output cannot satisfy FeeRouter's nonzero minimum.
        uint256 beforeETH = address(router).balance;
        uint256 beforeManager = address(hook.manager()).balance;
        address recipient = router.rewardPool();
        uint256 beforeTokens = token.balanceOf(recipient);
        vm.prank(actors[who % 3]);
        uint256 received = router.executeBuys(amount, minimumOut);
        assertEq(beforeETH - address(router).balance, amount);
        assertEq(token.balanceOf(recipient) - beforeTokens, received);
        assertGe(received, minimumOut);
        uint256 base = amount - (address(hook.manager()).balance - beforeManager);
        assertEq(base, amount / 100, "system buy charged exactly once");
        ghostBase += base;
        ghostRewardSpent += amount;
        successfulRewardBuys++;
    }

    function donateETH(uint256 amount) external {
        amount = bound(amount, 0, 1 ether);
        new BlackoutForcedETH{value: amount}(payable(address(hook)));
        ghostDonations += amount;
    }

    function transferTokens(uint256 from, uint256 to, uint256 amount) external {
        // Small transfers preserve useful swap balances even after long sequences.
        address sender = actors[from % 3];
        address recipient = actors[to % 3];
        amount = bound(amount, 0, 1 ether);
        uint256 beforeFrom = token.balanceOf(sender);
        uint256 beforeTo = token.balanceOf(recipient);
        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount));
        if (sender == recipient) {
            assertEq(token.balanceOf(sender), beforeFrom);
        } else {
            assertEq(token.balanceOf(sender), beforeFrom - amount);
            assertEq(token.balanceOf(recipient), beforeTo + amount);
        }
    }

    function rejectedBuy(uint256 who, uint256 amount) external {
        address actor = actors[who % 3];
        amount = bound(amount, 1, 5 ether);
        uint256 beforeETH = actor.balance;
        uint256 beforeTokens = token.balanceOf(actor);
        uint256 beforeHeld = address(hook).balance;
        vm.expectRevert(); // PoolManager wraps PriceLimitedBuy; exact wrapping is tested separately.
        vm.prank(actor);
        driver.trade{value: amount}(true, amount, 4295128741, 0);
        assertEq(actor.balance, beforeETH);
        assertEq(token.balanceOf(actor), beforeTokens);
        assertEq(address(hook).balance, beforeHeld);
    }
}

/// @notice Real token, real mined production hook and real v4 settlement, including binding and flushing.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract BlackoutInvariantTest is BlackoutFixture {
    BlackoutHandler private handler;
    uint256 private initialETH;

    function setUp() public {
        _deployFixture();
        _seed();
        _prepareBinding();
        handler = new BlackoutHandler(hook, token, driver, router, actors);
        vm.deal(address(handler), 100 ether);
        initialETH = _totalETH();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.buy.selector;
        selectors[1] = handler.sell.selector;
        selectors[2] = handler.advance.selector;
        selectors[3] = handler.bind.selector;
        selectors[4] = handler.flush.selector;
        selectors[5] = handler.withdrawTeam.selector;
        selectors[6] = handler.donateETH.selector;
        selectors[7] = handler.transferTokens.selector;
        selectors[8] = handler.rejectedBuy.selector;
        selectors[9] = handler.rewardBuy.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        // Keep Forge's automatically funded callers outside the conservation ledger.
        targetSender(makeAddr("BLACKOUT invariant executor"));
    }

    function invariant_HookLiabilitiesMatchIndependentReceipts() public view {
        assertEq(hook.heldBase(), handler.ghostBase());
        assertEq(hook.heldLaunchTax(), handler.ghostLaunch());
        assertEq(hook.heldSellTax(), handler.ghostSurcharge());
        assertEq(address(hook).balance, _held() + handler.ghostDonations());
    }

    function invariant_AllETHAndTokenSupplyConserved() public view {
        assertEq(_totalETH(), initialETH);
        uint256 sum = token.balanceOf(address(this)) + token.balanceOf(address(manager))
            + token.balanceOf(address(driver)) + token.balanceOf(address(hook)) + token.balanceOf(address(router))
            + token.balanceOf(address(rewards)) + token.balanceOf(address(handler));
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_FlushedFundsBackRouterLiabilities() public view {
        uint256 due = router.rewardETH() + router.potETH() + router.heartbeatBalance() + router.credit(router.team());
        for (uint256 i; i < actors.length; ++i) {
            due += router.credit(actors[i]);
        }
        assertEq(address(router).balance, due);
        assertEq(router.potETH(), 0, "pot feature not enabled in this fixture");
        assertGe(
            router.rewardETH() + handler.ghostRewardSpent(), handler.ghostFlushedBase() + handler.ghostFlushedLaunch()
        );
        assertLe(router.heartbeatBalance(), 1 ether);
        uint256 totalFlushed =
            handler.ghostFlushedBase() + handler.ghostFlushedLaunch() + handler.ghostFlushedSurcharge();
        assertEq(address(router).balance + router.team().balance + handler.ghostRewardSpent(), totalFlushed);
    }

    function invariant_InitializationBindingAndFeeBounds() public view {
        assertEq(hook.initializedAt(), START);
        assertTrue(address(hook.fees()) == address(0) || address(hook.fees()) == address(router));
        assertEq(address(hook.params()), address(hook.fees()) == address(0) ? address(0) : address(parameters));
        assertGe(hook.storedFeeWad(), 100 ether);
        assertLe(hook.storedFeeWad(), 1500 ether);
        (uint256 hour, uint256 day) = hook.imbalances();
        assertLt(hour, 10000);
        assertLt(day, 10000);
    }

    /// @dev Deterministic coverage witness: every fund-moving handler executes successfully.
    function test_HandlerExercisesUnboundAndBoundFlows() public {
        handler.buy(0, 1 ether);
        handler.sell(1, 1 ether);
        handler.flush(2);
        handler.advance(31 minutes);
        handler.buy(2, 1 ether);
        handler.donateETH(17);
        handler.bind();
        handler.flush(0);
        handler.rewardBuy(2, 0.1 ether);
        handler.withdrawTeam();
        handler.rejectedBuy(1, 1 ether);
        handler.transferTokens(0, 1, 1 ether);
        handler.bind();
        assertEq(handler.successfulBuys(), 2);
        assertEq(handler.successfulSells(), 1);
        assertEq(handler.successfulFlushes(), 1);
        assertEq(handler.successfulRewardBuys(), 1);
        invariant_HookLiabilitiesMatchIndependentReceipts();
        invariant_AllETHAndTokenSupplyConserved();
        invariant_FlushedFundsBackRouterLiabilities();
        invariant_InitializationBindingAndFeeBounds();
    }

    /// @dev Every generated sequence ends with permissionless fee delivery and a full LP exit.
    function afterInvariant() public {
        handler.bind();
        handler.flush(0);
        BalanceDelta withdrawn = driver.modify(-887220, 887220, -int256(100_000 ether));
        assertGt(withdrawn.amount0(), 0);
        assertGt(withdrawn.amount1(), 0);
        assertEq(_held(), 0);
        invariant_HookLiabilitiesMatchIndependentReceipts();
        invariant_AllETHAndTokenSupplyConserved();
        invariant_FlushedFundsBackRouterLiabilities();
    }

    function _totalETH() private view returns (uint256 total) {
        total = address(manager).balance + address(driver).balance + address(hook).balance + address(router).balance
            + address(handler).balance + router.team().balance;
        for (uint256 i; i < actors.length; ++i) {
            total += actors[i].balance;
        }
    }
}
