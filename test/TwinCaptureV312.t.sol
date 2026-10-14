// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {EndowmentEscrow} from "../src/EndowmentEscrow.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {Params} from "../src/Params.sol";
import {LocalApplicationFactory} from "../script/Deploy.s.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {SwarmArgs} from "../script/SwarmArgs.sol";
import {MockMarket} from "./mocks/MockMarket.sol";
import {MockToken} from "./mocks/MockToken.sol";
import "../src/lib/Errors.sol";

/// @dev v3.12 (docs/m2-trust-assumption.md): what a twin capture of `SwarmDesk.bind` can and cannot do. The attacker
/// knows the private configuration and launches a byte-identical twin (Params + GameRegistry + RewardPool from the
/// pinned code) through the same factory before the honest bind. v3.16: `bind` is restricted to the pinned binder,
/// so the twin can no longer win the race at all; the capture tests now cover the residual case of the binder key
/// itself choosing the twin (what that key can and cannot do).
contract TwinCaptureV312Test is BaseTest {
    uint256 private constant ENDOWMENT = 200_000_000 ether;
    address private attacker;
    LocalApplicationFactory private f;
    address private freshDesk;
    EndowmentEscrow private escrow;
    bytes private registryCode;
    bytes private poolCode;

    struct Game {
        Params params;
        GameRegistry registry;
        RewardPool pool;
    }

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.clearMockedCalls();
        attacker = makeAddr("attacker");
        f = LocalApplicationFactory(address(d.registry.factory()));
        registryCode = type(GameRegistry).creationCode;
        poolCode = vm.getCode("RewardPool.sol:RewardPool");
        bytes32 configHash = keccak256(
            abi.encode(d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), ENDOWMENT)
        );
        freshDesk = f.deploy(
            40,
            0,
            bytes.concat(
                vm.getCode("SwarmDesk.sol:SwarmDesk"),
                SwarmArgs.encode(
                    desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether), team
                )
            )
        );
        market.configureBinding(freshDesk, configHash);
        escrow = new EndowmentEscrow(freshDesk);
        token.transfer(address(escrow), ENDOWMENT); // the token launch's remainderTo share
    }

    /// @dev Params at (launch, 0), Registry at (launch, 1), RewardPool at (launch, 2), pool registered as role 0.
    function _launch(uint64 launch) private returns (Game memory) {
        return _launchWith(launch, address(token), address(market));
    }

    function _launchWith(uint64 launch, address gameToken, address gameMarket) private returns (Game memory g) {
        g.params = Params(
            f.deploy(
                launch,
                0,
                bytes.concat(type(Params).creationCode, abi.encode(freshDesk, uint256(200), uint256(1 ether)))
            )
        );
        bytes memory args = abi.encode(
            gameToken,
            address(g.params),
            gameMarket,
            d.registry.starterRoot(),
            d.registry.freeRoot(),
            d.registry.snapshotBlock(),
            ENDOWMENT
        );
        g.registry = GameRegistry(f.deploy(launch, 1, bytes.concat(registryCode, args)));
        g.pool = RewardPool(f.deploy(launch, 2, bytes.concat(poolCode, abi.encode(address(g.registry)))));
        g.registry.register(0, launch, 2, poolCode);
    }

    /// @dev From the pinned binder (team), the only account `bind` admits since v3.16.
    function _bind(Game memory g, uint64 launch) private returns (bool ok, bytes memory ret) {
        return _bindFrom(team, g, launch);
    }

    function _bindFrom(address who, Game memory g, uint64 launch) private returns (bool ok, bytes memory ret) {
        uint64 tokenLaunch_ = desk.tokenLaunch(); // read before the prank so the prank reaches the bind call
        vm.prank(who);
        (ok, ret) = freshDesk.call(
            abi.encodeWithSignature(
                "bind(address,bytes,bytes,uint64,uint8,uint64,uint8,uint64)",
                address(g.registry),
                registryCode,
                type(Params).creationCode,
                launch,
                uint8(1),
                launch,
                uint8(0),
                tokenLaunch_
            )
        );
    }

    function _reject(Game memory g, uint64 launch) private {
        (bool ok, bytes memory reason) = _bind(g, launch);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        assertEq(address(SwarmDesk(freshDesk).registry()), address(0));
        assertEq(token.balanceOf(address(escrow)), ENDOWMENT);
    }

    function testTwinWithForeignMarketCannotBind() public {
        MockMarket foreign = new MockMarket(address(token));
        foreign.configureBinding(address(desk), market.gameConfigHash());
        _reject(_launchWith(41, address(token), address(foreign)), 41);
        (bool ok,) = _bind(_launch(42), 42);
        assertTrue(ok, "honest binding remains available");
    }

    function testTwinWithForeignTokenCannotBind() public {
        _reject(_launchWith(41, address(new MockToken()), address(market)), 41);
        (bool ok,) = _bind(_launch(42), 42);
        assertTrue(ok);
    }

    function testEOAMarketCannotBind() public {
        _reject(_launchWith(41, address(token), attacker), 41);
    }

    function testHookWithForeignConfigurationCannotBind() public {
        market.configureBinding(freshDesk, keccak256("foreign config"));
        _reject(_launch(41), 41);
    }

    /// Success path without a twin: the honest game binds and the escrow pays its pinned RewardPool.
    function testHonestBindThenForwardReachesHonestPool() public {
        Game memory honest = _launch(41);
        (bool ok,) = _bind(honest, 41);
        assertTrue(ok);
        escrow.forward(address(honest.registry), 41, 1, registryCode, 41, 2, poolCode);
        assertEq(token.balanceOf(address(honest.pool)), ENDOWMENT);
        honest.pool.fundEndowment();
        assertEq(honest.pool.lockedEndowment(), ENDOWMENT);
    }

    /// v3.16: the twin passes every proof but its launcher is not the binder, so it cannot win the race; the
    /// honest bind by the binder lands afterwards and the twin is the one orphaned.
    function testTwinCannotWinTheBindRace() public {
        vm.startPrank(attacker);
        Game memory twin = _launch(41);
        vm.stopPrank();
        (bool ok, bytes memory ret) = _bindFrom(attacker, twin, 41);
        assertFalse(ok, "attacker cannot bind");
        assertEq(bytes4(ret), Unauthorized.selector);
        (ok, ret) = _bindFrom(bob, twin, 41);
        assertFalse(ok, "no third party can bind for the attacker either");
        assertEq(bytes4(ret), Unauthorized.selector);
        assertEq(address(SwarmDesk(freshDesk).registry()), address(0));

        Game memory honest = _launch(42);
        (ok,) = _bind(honest, 42);
        assertTrue(ok, "the binder binds the honest registry after the twin exists");
        assertEq(address(SwarmDesk(freshDesk).registry()), address(honest.registry));
        (ok, ret) = _bindFrom(attacker, twin, 41);
        assertEq(bytes4(ret), Unauthorized.selector);
        (ok, ret) = _bind(twin, 41);
        assertEq(bytes4(ret), AlreadyDone.selector);
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(twin.registry), 41, 1, registryCode, 41, 2, poolCode);
        escrow.forward(address(honest.registry), 42, 1, registryCode, 42, 2, poolCode);
        assertEq(token.balanceOf(address(honest.pool)), ENDOWMENT);
        vm.expectRevert(InsufficientBalance.selector);
        twin.pool.fundEndowment();
    }

    /// Residual trust (v3.16): if the binder key itself chose the twin, the honest bind is refused and the honest
    /// modules are orphaned, exactly the v3.12 capture outcome. The binder cannot bypass a proof, only pick
    /// among registries that pass all of them.
    function testBinderChoosingTwinOrphansHonestGame() public {
        vm.startPrank(attacker);
        Game memory twin = _launch(41);
        vm.stopPrank();
        (bool ok,) = _bind(twin, 41);
        assertTrue(ok);
        assertEq(address(SwarmDesk(freshDesk).registry()), address(twin.registry));

        Game memory honest = _launch(42);
        (bool ok2, bytes memory ret) = _bind(honest, 42);
        assertFalse(ok2);
        assertEq(bytes4(ret), AlreadyDone.selector);
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(honest.registry), 42, 1, registryCode, 42, 2, poolCode);
        vm.expectRevert(InsufficientBalance.selector);
        honest.pool.fundEndowment();
        assertEq(token.balanceOf(address(escrow)), ENDOWMENT);
    }

    /// Residual trust (v3.16): even a binder-chosen twin pays only the twin's pinned RewardPool, never a wallet or
    /// code of the attacker's choice, and nothing becomes withdrawable by the attacker.
    function testBinderChosenTwinCannotPayAttacker() public {
        uint256 attackerTokens = token.balanceOf(attacker);
        uint256 attackerEth = attacker.balance;
        vm.startPrank(attacker);
        Game memory twin = _launch(41);
        vm.stopPrank();
        (bool ok,) = _bind(twin, 41);
        assertTrue(ok);
        vm.startPrank(attacker);

        // An attacker-chosen pool (other code, or a plain wallet) is refused.
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(twin.registry), 41, 1, registryCode, 41, 2, type(MockToken).creationCode);
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(twin.registry), 41, 1, registryCode, 41, 3, poolCode);

        // The only exit: the whole balance to the twin's pinned RewardPool.
        uint256 sent = escrow.forward(address(twin.registry), 41, 1, registryCode, 41, 2, poolCode);
        assertEq(sent, ENDOWMENT);
        assertEq(token.balanceOf(address(twin.pool)), ENDOWMENT);
        vm.expectRevert(NotConfigured.selector);
        twin.pool.rewards(); // no FarmRewards registered yet: nothing can pay out
        bytes memory rewardsCode = vm.getCode("FarmRewards.sol:FarmRewards");
        address farmRewards = f.deploy(41, 3, bytes.concat(rewardsCode, abi.encode(address(twin.registry))));
        twin.registry.register(1, 41, 3, rewardsCode);
        assertEq(twin.pool.rewards(), farmRewards);

        // The pool pays only its registry's pinned FarmRewards, by the mining rules; no withdrawal for anyone else.
        vm.expectRevert(Unauthorized.selector);
        twin.pool.pay(attacker, 1 ether);
        vm.expectRevert(Unauthorized.selector);
        twin.pool.reserve(1 ether);
        vm.expectRevert(Unauthorized.selector);
        twin.pool.recycle(1 ether);
        vm.expectRevert(AlreadyDone.selector);
        escrow.forward(address(twin.registry), 41, 1, registryCode, 41, 2, poolCode);
        vm.stopPrank();

        twin.pool.fundEndowment(); // the drip runs exactly as in the honest game
        assertEq(twin.pool.lockedEndowment(), ENDOWMENT);
        assertEq(token.balanceOf(attacker), attackerTokens);
        assertEq(attacker.balance, attackerEth);
        // The twin is governed by the same Desk: its Params answer only to the attested oracle.
        assertEq(twin.params.swarmWallet(), freshDesk);
    }
}
