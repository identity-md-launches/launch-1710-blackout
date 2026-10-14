// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {EndowmentEscrow} from "../src/EndowmentEscrow.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {SwarmArgs} from "../script/SwarmArgs.sol";
import {LocalApplicationFactory, LocalLaunchFactory} from "../script/Deploy.s.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {TestV4Market, MockV4Manager} from "./mocks/MockV4Manager.sol";
import {PoolKey} from "../src/interfaces/IV4.sol";
import "../src/lib/Errors.sol";

/// @dev v3.16, import audit 10bfac6d (medium): the v3.15 proofs accept a registry on an attacker's own token. The
/// attacker launches their own univ4_hook token whose V4Market names this Desk and the public gameConfigHash, then
/// Params + GameRegistry on that token once the roots are public at L3. Their LaunchFactory record is
/// self-consistent (ETH-paired, their token as currency1, their hook), so every v3.15 proof passes: the Desk would
/// be captured forever and EndowmentEscrow could never forward the genuine remainder. The fix pins one binder.
/// Two Desks are built: `fresh` (binder: team) and the genuine graph on the launched token; the attacker's twin is
/// a complete, pinned-code game on `foreignToken` with a genuine-code hook recorded by the fixture LaunchFactory.
contract ForeignTokenTwinTest is BaseTest {
    uint256 private constant ENDOWMENT = 200_000_000 ether;
    LocalApplicationFactory private f;
    LocalLaunchFactory private lf;
    address private attacker;
    address private fresh;
    EndowmentEscrow private escrow;
    bytes32 private configHash;
    bytes private registryCode;
    bytes private paramsCode;
    bytes private poolCode;
    MockToken private foreignToken;
    TestV4Market private foreignHook;
    GameRegistry private foreignRegistry;
    GameRegistry private genuineRegistry;
    uint64 private constant N_FOREIGN_TOKEN = 71;
    uint64 private constant N_FOREIGN_GAME = 72;
    uint64 private constant N_GENUINE_TOKEN = 73;
    uint64 private constant N_GENUINE_GAME = 74;

    event Bound(address indexed registry);

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.clearMockedCalls();
        attacker = makeAddr("attacker");
        f = LocalApplicationFactory(address(d.registry.factory()));
        lf = LocalLaunchFactory(Robinhood.LAUNCH_FACTORY);
        registryCode = type(GameRegistry).creationCode;
        paramsCode = type(Params).creationCode;
        poolCode = vm.getCode("RewardPool.sol:RewardPool");
        configHash = keccak256(
            abi.encode(d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), ENDOWMENT)
        );
        // L1: a Desk with the eight v3.16 words, binder = the project wallet.
        fresh = f.deploy(
            70,
            0,
            bytes.concat(
                vm.getCode("SwarmDesk.sol:SwarmDesk"),
                SwarmArgs.encode(
                    desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether), team
                )
            )
        );
        escrow = new EndowmentEscrow(fresh);
        token.transfer(address(escrow), ENDOWMENT); // the genuine token launch's remainderTo share
        // L2 (genuine): the launched token's hook, recorded by the LaunchFactory.
        MockV4Manager manager = new MockV4Manager();
        TestV4Market genuineHook =
            new TestV4Market(address(manager), address(token), address(bindingFactory), fresh, configHash);
        manager.initializeHook(genuineHook);
        lf.record(N_GENUINE_TOKEN, address(0), address(token), address(genuineHook), team);
        // The attacker's own univ4_hook launch: their token, a genuine-code hook naming this Desk and the public
        // commitment, and the LaunchFactory's own record of it (ETH-paired, their token, their hook).
        vm.startPrank(attacker);
        foreignToken = new MockToken();
        foreignHook =
            new TestV4Market(address(manager), address(foreignToken), address(bindingFactory), fresh, configHash);
        manager.initializeHook(foreignHook);
        lf.record(N_FOREIGN_TOKEN, address(0), address(foreignToken), address(foreignHook), attacker);
        // L3 (attacker, after the roots are public): pinned Params + GameRegistry + RewardPool on their token.
        foreignRegistry = _game(N_FOREIGN_GAME, address(foreignToken), address(foreignHook));
        vm.stopPrank();
        genuineRegistry = _game(N_GENUINE_GAME, address(token), address(genuineHook));
    }

    /// @dev Params at (launch, 0), registry at (launch, 1), RewardPool at (launch, 2) registered as role 0.
    function _game(uint64 launch, address gameToken, address gameMarket) private returns (GameRegistry r) {
        Params p =
            Params(f.deploy(launch, 0, bytes.concat(paramsCode, abi.encode(fresh, uint256(200), uint256(1 ether)))));
        bytes memory args = abi.encode(
            gameToken,
            address(p),
            gameMarket,
            d.registry.starterRoot(),
            d.registry.freeRoot(),
            d.registry.snapshotBlock(),
            ENDOWMENT
        );
        r = GameRegistry(f.deploy(launch, 1, bytes.concat(registryCode, args)));
        address pool = f.deploy(launch, 2, bytes.concat(poolCode, abi.encode(address(r))));
        assertEq(r.register(0, launch, 2, poolCode), pool);
    }

    function _bindFrom(address who, GameRegistry r, uint64 launch, uint64 tokenLaunch)
        private
        returns (bool ok, bytes memory ret)
    {
        vm.prank(who);
        (ok, ret) = fresh.call(
            abi.encodeWithSignature(
                "bind(address,bytes,bytes,uint64,uint8,uint64,uint8,uint64)",
                address(r),
                registryCode,
                paramsCode,
                launch,
                uint8(1),
                launch,
                uint8(0),
                tokenLaunch
            )
        );
    }

    function _assertUnbound() private view {
        assertEq(address(SwarmDesk(fresh).registry()), address(0), "still unbound");
        assertEq(SwarmDesk(fresh).tokenLaunch(), 0);
        assertEq(token.balanceOf(address(escrow)), ENDOWMENT, "escrow untouched");
    }

    /// @dev The premise: the attacker's record is self-consistent and the twin passes every v3.15 proof. Nothing
    /// in the proofs names BLACKOUT's token, so only the binder pin separates it from the genuine registry.
    function testForeignTwinIsSelfConsistentAndPassesEveryProofExceptTheBinder() public view {
        (PoolKey memory k,,, address requester) = lf.positionOf(N_FOREIGN_TOKEN);
        assertEq(k.currency0, address(0), "ETH-paired like a real univ4_hook launch");
        assertEq(k.currency1, address(foreignToken));
        assertEq(k.hooks, address(foreignHook));
        assertEq(requester, attacker);
        assertEq(foreignHook.desk(), fresh);
        assertEq(address(foreignHook.token()), address(foreignToken));
        assertEq(foreignHook.gameConfigHash(), configHash);
        assertEq(address(foreignRegistry.factory()), address(f));
        assertEq(foreignRegistry.market(), address(foreignHook));
        assertEq(foreignRegistry.token(), address(foreignToken));
        assertEq(Params(foreignRegistry.params()).swarmWallet(), fresh);
        assertEq(
            keccak256(
                abi.encode(
                    foreignRegistry.starterRoot(),
                    foreignRegistry.freeRoot(),
                    foreignRegistry.snapshotBlock(),
                    foreignRegistry.endowment()
                )
            ),
            configHash
        );
        assertTrue(SwarmDesk(fresh).binder() != attacker);
    }

    /// @dev The import-audit scenario: the attacker binds their twin. Refused as Unauthorized before any proof.
    function testForeignTwinCannotBindFromTheAttacker() public {
        (bool ok, bytes memory reason) = _bindFrom(attacker, foreignRegistry, N_FOREIGN_GAME, N_FOREIGN_TOKEN);
        assertFalse(ok, "attacker bind must revert");
        assertEq(bytes4(reason), Unauthorized.selector);
        _assertUnbound();
        // The genuine escrow forward stays impossible for the twin whether or not it is bound.
        vm.prank(attacker);
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(foreignRegistry), N_FOREIGN_GAME, 1, registryCode, N_FOREIGN_GAME, 2, poolCode);
        _assertUnbound();
    }

    /// @dev Any non-binder (a relayer, the keeper hot wallet, a bystander) is refused the same way, for the twin and
    /// for the genuine registry alike: the restriction is on the caller, not on the candidate.
    function testNoNonBinderCanBindEitherRegistry() public {
        address[4] memory callers = [bob, alice, address(this), makeAddr("keeper hot wallet")];
        for (uint256 i; i < callers.length; ++i) {
            (bool ok, bytes memory reason) = _bindFrom(callers[i], foreignRegistry, N_FOREIGN_GAME, N_FOREIGN_TOKEN);
            assertFalse(ok);
            assertEq(bytes4(reason), Unauthorized.selector);
            (ok, reason) = _bindFrom(callers[i], genuineRegistry, N_GENUINE_GAME, N_GENUINE_TOKEN);
            assertFalse(ok);
            assertEq(bytes4(reason), Unauthorized.selector);
        }
        _assertUnbound();
    }

    /// @dev Success: the binder binds the genuine registry once, then AlreadyDone for everyone including itself.
    function testBinderBindsTheGenuineRegistryThenAlreadyDone() public {
        vm.expectEmit(true, false, false, true, fresh);
        emit Bound(address(genuineRegistry));
        (bool ok,) = _bindFrom(team, genuineRegistry, N_GENUINE_GAME, N_GENUINE_TOKEN);
        assertTrue(ok, "binder binds");
        assertEq(address(SwarmDesk(fresh).registry()), address(genuineRegistry));
        assertEq(SwarmDesk(fresh).tokenLaunch(), N_GENUINE_TOKEN);
        bytes memory reason;
        (ok, reason) = _bindFrom(team, genuineRegistry, N_GENUINE_GAME, N_GENUINE_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), AlreadyDone.selector);
        (ok, reason) = _bindFrom(team, foreignRegistry, N_FOREIGN_GAME, N_FOREIGN_TOKEN);
        assertFalse(ok, "the binder cannot rebind to the twin either");
        assertEq(bytes4(reason), AlreadyDone.selector);
        (ok, reason) = _bindFrom(attacker, foreignRegistry, N_FOREIGN_GAME, N_FOREIGN_TOKEN);
        assertEq(bytes4(reason), Unauthorized.selector);
        // The genuine remainder forwards to the genuine pinned pool; the twin is refused.
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(foreignRegistry), N_FOREIGN_GAME, 1, registryCode, N_FOREIGN_GAME, 2, poolCode);
        uint256 sent =
            escrow.forward(address(genuineRegistry), N_GENUINE_GAME, 1, registryCode, N_GENUINE_GAME, 2, poolCode);
        assertEq(sent, ENDOWMENT);
        assertEq(token.balanceOf(genuineRegistry.module(0)), ENDOWMENT);
        RewardPool(genuineRegistry.module(0)).fundEndowment();
        assertEq(RewardPool(genuineRegistry.module(0)).lockedEndowment(), ENDOWMENT);
    }

    /// @dev The binder cannot bypass a proof: with the binder's key, a wrong launch number, wrong coordinates or a
    /// registry whose hook names another token still revert InvalidProof. The key chooses among proven registries.
    function testBinderCannotBypassAnyProof() public {
        (bool ok, bytes memory reason) = _bindFrom(team, genuineRegistry, N_GENUINE_GAME, N_FOREIGN_TOKEN);
        assertFalse(ok, "genuine registry under the attacker's record");
        assertEq(bytes4(reason), InvalidProof.selector);
        (ok, reason) = _bindFrom(team, genuineRegistry, N_FOREIGN_GAME, N_GENUINE_TOKEN);
        assertFalse(ok, "genuine registry at the twin's coordinates");
        assertEq(bytes4(reason), InvalidProof.selector);
        (ok, reason) = _bindFrom(team, genuineRegistry, N_GENUINE_GAME, 999_999);
        assertFalse(ok, "unrecorded launch number");
        assertEq(bytes4(reason), InvalidProof.selector);
        (ok, reason) = _bindFrom(team, genuineRegistry, N_GENUINE_GAME, 0);
        assertEq(bytes4(reason), InvalidValue.selector);
        // A registry on the genuine token whose market is the attacker's hook fails the token/hook consistency check.
        GameRegistry mixed = _game(75, address(token), address(foreignHook));
        (ok, reason) = _bindFrom(team, mixed, 75, N_FOREIGN_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        _assertUnbound();
    }

    /// @dev Construction: a zero binder is refused by the constructor and by the offline encoder; bind is refused
    /// through the eight-word launch shape as well (the launch words carry the project wallet, not a protocol address).
    function testZeroBinderRevertsAtConstruction() public {
        SwarmDesk.OracleConfig memory o = desk.oracleConfig();
        SwarmDesk.BindingConfig memory b = SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether);
        bytes memory args = SwarmArgs.encode(o, b, team);
        assertEq(args.length, 8 * 32, "eight static words");
        assembly ("memory-safe") {
            mstore(add(args, 256), 0)
        }
        bytes memory code = vm.getCode("SwarmDesk.sol:SwarmDesk");
        vm.expectRevert(InvalidValue.selector);
        f.deploy(76, 0, bytes.concat(code, args));
        vm.expectRevert(InvalidValue.selector);
        this.encodeWith(o, b, address(0));
        vm.expectRevert(InvalidValue.selector);
        this.encodeWith(o, b, Robinhood.PROJECT_FACTORY);
        // Direct construction with a zero binder reverts the same way.
        vm.expectRevert(InvalidValue.selector);
        new SwarmDesk(
            o.action,
            SwarmArgs.policy(o, b),
            o.questions[0],
            o.questions[1],
            o.bodies[0],
            o.bodies[1],
            configHash,
            address(0)
        );
        SwarmDesk ok = new SwarmDesk(
            o.action, SwarmArgs.policy(o, b), o.questions[0], o.questions[1], o.bodies[0], o.bodies[1], configHash, team
        );
        assertEq(ok.binder(), team);
    }

    function encodeWith(SwarmDesk.OracleConfig memory o, SwarmDesk.BindingConfig memory b, address binder)
        external
        pure
        returns (bytes memory)
    {
        return SwarmArgs.encode(o, b, binder);
    }
}
