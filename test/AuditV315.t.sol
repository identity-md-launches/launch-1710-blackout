// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {SwarmArgs} from "../script/SwarmArgs.sol";
import {LocalApplicationFactory, LocalLaunchFactory} from "../script/Deploy.s.sol";
import {MockMarket} from "./mocks/MockMarket.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {TestV4Market, MockV4Manager} from "./mocks/MockV4Manager.sol";
import {PoolKey} from "../src/interfaces/IV4.sol";
import "../src/lib/Errors.sol";

/// @dev v3.15, audit 031c93c4 finding 1 (medium): `SwarmDesk.bind` must prove that the registry's market is the
/// hook the LaunchFactory deployed for the registry's token, not a contract that merely echoes `desk()`,
/// `token()` and `gameConfigHash()`. The proof is the factory's own `positionOf(tokenLaunch)` record, the one
/// `claimFees(tokenLaunch)` keys on; the local fixture at `Robinhood.LAUNCH_FACTORY` reproduces its eight-word
/// layout and reads zeros for unrecorded numbers exactly as the live factory does.
/// v3.16 (import audit 10bfac6d): every proof runs for the pinned binder only (`team` here); the attacker's own
/// self-consistent launch is covered in `test/ForeignTokenTwin.t.sol`.
contract AuditV315Test is BaseTest {
    LocalApplicationFactory private f;
    LocalLaunchFactory private lf;
    address private fresh;
    bytes32 private configHash;
    bytes private registryCode;
    bytes private paramsCode;

    event Bound(address indexed registry);

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        f = LocalApplicationFactory(address(d.registry.factory()));
        lf = LocalLaunchFactory(Robinhood.LAUNCH_FACTORY);
        registryCode = type(GameRegistry).creationCode;
        paramsCode = type(Params).creationCode;
        configHash = keccak256(
            abi.encode(
                d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), d.registry.endowment()
            )
        );
        fresh = f.deploy(
            60,
            0,
            bytes.concat(
                vm.getCode("SwarmDesk.sol:SwarmDesk"),
                SwarmArgs.encode(
                    desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether), team
                )
            )
        );
        assertEq(SwarmDesk(fresh).binder(), team);
    }

    /// @dev Params at (launch, 0) and a registry at (launch, 1) naming `gameToken` and `gameMarket`.
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
            d.registry.endowment()
        );
        r = GameRegistry(f.deploy(launch, 1, bytes.concat(registryCode, args)));
    }

    /// @dev From the pinned binder: the proofs are only reached by that caller since v3.16.
    function _bind(GameRegistry r, uint64 launch, uint64 tokenLaunch) private returns (bool ok, bytes memory ret) {
        return _bindFrom(team, r, launch, tokenLaunch);
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

    function _reject(GameRegistry r, uint64 launch, uint64 tokenLaunch, bytes4 err) private {
        (bool ok, bytes memory reason) = _bind(r, launch, tokenLaunch);
        assertFalse(ok, "bind must revert");
        assertEq(bytes4(reason), err);
        assertEq(address(SwarmDesk(fresh).registry()), address(0), "still unbound");
        assertEq(SwarmDesk(fresh).tokenLaunch(), 0);
    }

    /// @dev A market that echoes the Desk, the token and the commitment but is not the recorded hook is refused.
    function testFakeMarketEchoingDeskTokenAndHashCannotBind() public {
        MockMarket fake = new MockMarket(address(token));
        fake.configureBinding(fresh, configHash);
        assertEq(fake.desk(), fresh);
        assertEq(address(fake.token()), address(token));
        assertEq(fake.gameConfigHash(), configHash);
        GameRegistry r = _game(61, address(token), address(fake));
        // The genuine token launch record names the fixture market, not the echo.
        _reject(r, 61, desk.tokenLaunch(), InvalidProof.selector);
        // An unrecorded launch number reads as zeros.
        _reject(r, 61, 999_999, InvalidProof.selector);
        // Zero is refused outright, before any proof.
        _reject(r, 61, 0, InvalidValue.selector);
    }

    /// @dev The realistic attacker hook reports the attacker's own token (a hook is built for one token). A registry
    /// on the genuine token naming that hook fails the token/hook consistency check; a registry on the attacker's
    /// token with the attacker's own record is self-consistent and passes every proof, which is exactly the import
    /// audit's finding: since v3.16 it is refused because the attacker is not the binder (see ForeignTokenTwin).
    function testAttackerLaunchRecordNamesAnotherTokenAndIsRefused() public {
        MockToken other = new MockToken();
        MockMarket fake = new MockMarket(address(other));
        fake.configureBinding(fresh, configHash);
        assertEq(address(fake.token()), address(other), "the attacker hook reports the attacker's token");
        lf.record(62, address(0), address(other), address(fake), makeAddr("attacker"));
        GameRegistry r = _game(62, address(token), address(fake));
        _reject(r, 62, 62, InvalidProof.selector);
        GameRegistry foreign = _game(63, address(other), address(fake));
        (bool ok, bytes memory reason) = _bindFrom(makeAddr("attacker"), foreign, 63, 62);
        assertFalse(ok, "the attacker cannot bind their self-consistent twin");
        assertEq(bytes4(reason), Unauthorized.selector);
        assertEq(address(SwarmDesk(fresh).registry()), address(0));
    }

    /// @dev A record naming the token with a different hook, or a pool that is not ETH-paired, is refused.
    function testRecordWithOtherHookOrOtherPairCurrencyIsRefused() public {
        MockMarket fake = new MockMarket(address(token));
        fake.configureBinding(fresh, configHash);
        GameRegistry r = _game(64, address(token), address(fake));
        lf.record(64, address(0), address(token), address(market), team);
        _reject(r, 64, 64, InvalidProof.selector);
        lf.record(65, alice, address(token), address(fake), team);
        _reject(r, 64, 65, InvalidProof.selector);
    }

    /// @dev The genuine hook (V4Market code) whose record names the registry's token binds, once, for the binder.
    function testRealHookRecordedByTheLaunchFactoryBinds() public {
        MockV4Manager manager = new MockV4Manager();
        TestV4Market hook =
            new TestV4Market(address(manager), address(token), address(bindingFactory), fresh, configHash);
        manager.initializeHook(hook);
        lf.record(66, address(0), address(token), address(hook), team);
        (PoolKey memory k,,, address requester) = lf.positionOf(66);
        assertEq(k.hooks, address(hook));
        assertEq(k.currency1, address(token));
        assertEq(requester, team);
        GameRegistry r = _game(66, address(token), address(hook));
        // Wrong token launch first: the right hook under a number that records nothing.
        _reject(r, 66, 67, InvalidProof.selector);
        // v3.16: the complete, correct proof from a non-binder is refused.
        (bool ok, bytes memory reason) = _bindFrom(bob, r, 66, 66);
        assertFalse(ok);
        assertEq(bytes4(reason), Unauthorized.selector);
        vm.expectEmit(true, false, false, true, fresh);
        emit Bound(address(r));
        (ok,) = _bind(r, 66, 66);
        assertTrue(ok, "the recorded hook binds for the binder");
        assertEq(address(SwarmDesk(fresh).registry()), address(r));
        assertEq(SwarmDesk(fresh).tokenLaunch(), 66);
        assertEq(SwarmDesk(fresh).bindingConfig().registryLaunch, 66);
        (ok, reason) = _bind(r, 66, 66);
        assertFalse(ok, "AlreadyDone");
        assertEq(bytes4(reason), AlreadyDone.selector);
    }

    /// @dev The base fixture bound through the same proof: its token launch is recorded and names its market.
    function testFixtureDeskBoundAgainstItsTokenLaunchRecord() public {
        uint64 n = desk.tokenLaunch();
        assertGt(n, 0);
        (PoolKey memory k,,,) = lf.positionOf(n);
        assertEq(k.currency0, address(0));
        assertEq(k.currency1, address(token));
        assertEq(k.hooks, address(market));
        assertEq(k.fee, 12500);
        assertEq(k.tickSpacing, 60);
        assertEq(address(desk.registry()), address(d.registry));
        assertEq(desk.binder(), address(deployment), "the deploy fixture is the fixture Desk's binder");
    }
}
