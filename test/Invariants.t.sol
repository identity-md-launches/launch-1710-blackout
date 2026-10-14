// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Params} from "../src/Params.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract GameHandler is Test {
    Deploy.Deployment private d;
    address[2] public actors;

    constructor(Deploy.Deployment memory deployment, address a, address b) {
        d = deployment;
        actors = [a, b];
    }

    function lock(uint256 who, uint256 duration) external {
        address p = actors[who % 2];
        uint256 days_ = duration % 3 == 0 ? 7 : duration % 3 == 1 ? 14 : 30;
        (uint256 amount,) = d.economy.lockQuote(p, days_);
        vm.prank(p);
        try d.economy.lock(amount, days_) {} catch {}
    }

    function unlock(uint256 who) external {
        vm.prank(actors[who % 2]);
        try d.economy.unlock() {} catch {}
    }

    function freeClaim(uint256 who) external {
        uint256 index = who % 2;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256(abi.encode(uint256(1 - index), actors[1 - index]));
        vm.prank(actors[index]);
        try d.starter.claimFree(index, proof) {} catch {}
    }

    function fundPot(uint256 who, uint256 amount) external {
        address p = actors[who % 2];
        MockToken t = MockToken(d.registry.token());
        amount = bound(amount, 1, 1000 ether);
        if (t.balanceOf(p) < amount) return;
        vm.prank(p);
        t.transfer(address(d.season), amount);
        vm.prank(address(d.fees));
        d.season.depositPot(amount);
    }

    function rollover(uint256 week) external {
        try d.season.rollover(week % 64) {} catch {}
    }

    function buy(uint256 who) external {
        address p = actors[who % 2];
        uint256 price = d.packs.price();
        vm.prank(p);
        try d.packs.openPack(1) {} catch {}
    }

    function resolve(uint256 id) external {
        uint256 n = d.packs.nextId();
        if (n <= 1) return;
        id = id % (n - 1) + 1;
        vm.roll(vm.getBlockNumber() + 3);
        try d.packs.resolve(id, 1) {} catch {}
    }

    function equip(uint256 who, uint256 id, uint256 slot) external {
        uint256 n = d.items.nextId();
        if (n <= 1) return;
        vm.prank(actors[who % 2]);
        try d.farm.place(id % (n - 1) + 1, 0, slot % 6) {} catch {}
    }

    function unplace(uint256 who, uint256 slot) external {
        vm.prank(actors[who % 2]);
        try d.farm.unplace(0, slot % 6) {} catch {}
    }

    function advance(uint256 gap) external {
        uint256 n = vm.getBlockNumber();
        vm.roll(n + 3);
        vm.setBlockhash(n + 1, keccak256(abi.encode(n)));
        vm.warp(d.rewards.epochEnd() + gap % 1 days);
        try d.rewards.advanceEpoch() {} catch {}
    }

    function settle(uint256 who, uint256 limit) external {
        try d.rewards.settle(actors[who % 2], limit % 8 + 1) {} catch {}
    }

    function claim(uint256 who, uint256 amount) external {
        address p = actors[who % 2];
        uint256 n = d.rewards.pending(p);
        if (n == 0) return;
        vm.prank(p);
        try d.rewards.claim(amount % n + 1) {} catch {}
    }

    function expand(uint256 who, bool wallet) external {
        vm.prank(actors[who % 2]);
        try d.farm.expand(wallet) {} catch {}
    }

    function tokenPack(uint256 who, bool wallet) external {
        vm.prank(actors[who % 2]);
        try d.farm.buyTokenPack(wallet) {} catch {}
    }
}

contract InvariantsTest is BaseTest {
    GameHandler private handler;
    bytes32 private freeRoot;

    function freePackRoot() internal view override returns (bytes32) {
        bytes32 a = keccak256(abi.encode(uint256(0), alice));
        bytes32 b = keccak256(abi.encode(uint256(1), bob));
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setUp() public override {
        super.setUp();
        fund(100_000_000 ether);
        payPack(alice);
        payPack(bob);
        place(alice, 0, 0, 0);
        place(bob, 0, 0, 0);
        bytes32 a = keccak256(abi.encode(uint256(0), alice));
        bytes32 b = keccak256(abi.encode(uint256(1), bob));
        freeRoot = a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
        assertEq(d.starter.freeRoot(), freeRoot);
        handler = new GameHandler(d, alice, bob);
        targetContract(address(handler));
        // Only real player EOAs originate transactions. Fuzzing protocol addresses as
        // senders auto-funds those addresses and invalidates exact ETH conservation.
        targetSender(alice);
        targetSender(bob);
    }

    function invariantTokenConservationNoBurns() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        uint256 sum = token.balanceOf(address(this)) + token.balanceOf(address(market))
            + token.balanceOf(address(d.pool)) + token.balanceOf(alice) + token.balanceOf(bob)
            + token.balanceOf(address(d.fees)) + token.balanceOf(address(d.season))
            + token.balanceOf(address(d.economy)) + token.balanceOf(address(d.civic))
            + token.balanceOf(address(d.billboards));
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariantReservesBackedAndPendingCovered() public view {
        assertLe(d.pool.reserved(), token.balanceOf(address(d.pool)));
        assertGe(
            d.pool.reserved(),
            d.rewards.pending(alice) + d.rewards.pending(bob) + d.rewards.queuedTax() + d.rewards.currentRedis()
        );
    }

    function invariantInventoryAndEthLiabilities() public view {
        assertLe(d.items.inventory(alice), d.items.capacity(alice));
        assertLe(d.items.inventory(bob), d.items.capacity(bob));
        uint256 due = d.fees.potETH() + d.fees.rewardETH() + d.fees.heartbeatBalance() + d.fees.credit(team)
            + d.fees.credit(address(handler)) + d.fees.credit(address(this));
        assertEq(address(d.fees).balance, due);
        assertLe(d.fees.heartbeatBalance(), 1 ether);
    }

    function invariantReceiptsNeverForfeitOrFixMissingEntropy() public view {
        for (uint256 id = 1; id < d.packs.nextId(); ++id) {
            (address p,, uint256 count, uint256 opened,,, bytes32 seed, bool fixedSeed, bool expired) =
                d.packs.commits(id);
            assertTrue(p != address(0));
            assertLe(opened, count);
            assertFalse(expired);
            if (opened != 0) assertTrue(fixedSeed);
            if (fixedSeed) assertTrue(seed != bytes32(0));
        }
    }

    function invariantLocksAndPotAlwaysBacked() public view {
        (uint256 a,,,) = d.economy.locks(alice);
        (uint256 b,,,) = d.economy.locks(bob);
        assertEq(d.economy.totalLocked(), a + b);
        assertEq(token.balanceOf(address(d.economy)), a + b);
        assertLe(d.economy.stakeOf(alice), d.economy.districtTotal(d.farm.district(alice)) / 10);
        assertLe(d.economy.stakeOf(bob), d.economy.districtTotal(d.farm.district(bob)) / 10);
        assertEq(token.balanceOf(address(d.season)), d.season.potLiability());
    }

    function invariantAllowlistRootAndWalletLimit() public view {
        assertEq(d.starter.freeRoot(), freeRoot);
        uint256 claimed = (d.starter.freeClaimedBy(alice) ? 1 : 0) + (d.starter.freeClaimedBy(bob) ? 1 : 0);
        assertEq(d.starter.freeClaimed(), claimed);
        assertLe(claimed, 2);
        assertEq(d.starter.freeIndexClaimed(0), d.starter.freeClaimedBy(alice));
        assertEq(d.starter.freeIndexClaimed(1), d.starter.freeClaimedBy(bob));
    }

    function invariantPriceAndParamsBounds() public view {
        (uint256 lowPrice, uint256 highPrice) = d.packs.priceBounds();
        assertGe(d.packs.price(), lowPrice);
        assertLe(d.packs.price(), highPrice);
        for (uint256 i; i < 45; ++i) {
            Params.Key k = Params.Key(i);
            (uint256 low, uint256 high) = d.params.bounds(k);
            assertGe(d.params.get(k), low);
            assertLe(d.params.get(k), high);
        }
    }
}
