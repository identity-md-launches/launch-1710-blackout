// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Robinhood} from "../src/lib/Robinhood.sol";
import {Script} from "forge-std/Script.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {SwarmArgs} from "./SwarmArgs.sol";
import {Params} from "../src/Params.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {FarmRewards} from "../src/FarmRewards.sol";
import {FarmEngine} from "../src/FarmEngine.sol";
import {FarmCore} from "../src/FarmCore.sol";
import {FarmItems} from "../src/FarmItems.sol";
import {PackSale} from "../src/PackSale.sol";
import {StarterClaim} from "../src/StarterClaim.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {GridOperator} from "../src/GridOperator.sol";
import {Economy} from "../src/Economy.sol";
import {Enhancement} from "../src/Enhancement.sol";
import {Billboards} from "../src/Billboards.sol";
import {Civic} from "../src/Civic.sol";
import {Season} from "../src/Season.sol";
import {PoolKey} from "../src/interfaces/IV4.sol";
import "../src/lib/Errors.sol";

/// @dev Local fixture for the platform's predictContract/CREATE2 behavior, never a launch target.
contract LocalApplicationFactory {
    mapping(uint64 => mapping(uint256 => bool)) public used;
    mapping(uint64 => bool) public isRecorded;

    function predictContract(uint64 launchNumber, uint256 index, bytes calldata initCode)
        external
        view
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(this), keccak256(abi.encode(launchNumber, index)), keccak256(initCode)
                        )
                    )
                )
            )
        );
    }

    function deploy(uint64 launchNumber, uint256 index, bytes memory initCode) external returns (address result) {
        if (index >= 8 || launchNumber == 0) revert InvalidValue();
        if (used[launchNumber][index]) revert AlreadyDone();
        used[launchNumber][index] = true;
        isRecorded[launchNumber] = true;
        bytes32 salt = keccak256(abi.encode(launchNumber, index));
        assembly ("memory-safe") { result := create2(0, add(initCode, 32), mload(initCode), salt) }
        if (result == address(0)) revert InvalidValue();
    }
}

/// @notice Offline rehearsal of a Desk bootstrap and two application launches. Explicit values only; no broadcasts or environment reads.
interface IFixtureMarket {
    function configureBinding(address desk, bytes32 gameConfigHash) external;
}

contract LocalLaunchRecords {
    function isRecorded(uint64 n) external view returns (bool) {
        return LocalApplicationFactory(Robinhood.PROJECT_FACTORY).isRecorded(n);
    }
}

/// @dev Local stand-in for the LaunchFactory's `positionOf(uint64)` record (v3.15), the eight static words the
/// real factory returns on 4663 for a recorded univ4_hook launch. Tests record what a launch would have written;
/// an unrecorded number reads as zeros exactly as on chain. Never a launch target.
contract LocalLaunchFactory {
    struct Position {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        address requester;
    }

    mapping(uint64 => Position) private positions;

    function record(uint64 launchNumber, address currency0, address token, address hook, address requester) external {
        if (launchNumber == 0 || positions[launchNumber].key.hooks != address(0)) revert AlreadyDone();
        positions[launchNumber] = Position(PoolKey(currency0, token, 12500, 60, hook), -887220, 128940, requester);
    }

    function positionOf(uint64 launchNumber)
        external
        view
        returns (PoolKey memory key, int24 tickLower, int24 tickUpper, address requester)
    {
        Position storage p = positions[launchNumber];
        return (p.key, p.tickLower, p.tickUpper, p.requester);
    }
}

contract Deploy is Script {
    uint64 private nextLaunch = 1;
    uint64 private baseLaunch;

    struct Config {
        address token;
        bytes oracle;
        address market;
        uint256 launchTime;
        bytes32 starterRoot;
        bytes32 freeRoot;
        uint256 snapshotBlock;
        uint256 endowmentBps;
        uint256 heartbeatBps;
        uint256 heartbeatCap;
    }

    struct Deployment {
        Params params;
        RewardPool pool;
        FarmRewards rewards;
        FarmCore farm;
        FarmItems items;
        PackSale packs;
        StarterClaim starter;
        FeeRouter fees;
        GridOperator grid;
        Season season;
        FarmEngine engine;
        GameRegistry registry;
        Economy economy;
        Enhancement enhancement;
        Civic civic;
        Billboards billboards;
    }

    function deploy(Config memory c) public returns (Deployment memory d) {
        if (
            c.token == address(0) || c.oracle.length == 0 || c.market == address(0) || c.launchTime == 0
                || c.freeRoot == bytes32(0) || c.starterRoot == bytes32(0) || c.snapshotBlock == 0
        ) revert InvalidValue();
        if (
            c.endowmentBps != 0 && c.endowmentBps != 1000 && c.endowmentBps != 1500 && c.endowmentBps != 2000
                && c.endowmentBps != 2500
        ) revert InvalidValue();
        if (Robinhood.PROJECT_FACTORY.code.length == 0) {
            vm.etch(Robinhood.PROJECT_FACTORY, type(LocalApplicationFactory).runtimeCode);
            vm.etch(Robinhood.PROJECT_REGISTRY, type(LocalLaunchRecords).runtimeCode);
        }
        if (Robinhood.LAUNCH_FACTORY.code.length == 0) {
            vm.etch(Robinhood.LAUNCH_FACTORY, type(LocalLaunchFactory).runtimeCode);
        }
        LocalApplicationFactory factory = LocalApplicationFactory(Robinhood.PROJECT_FACTORY);
        baseLaunch = nextLaunch == 0 ? 1 : nextLaunch;
        nextLaunch = baseLaunch + 1000;
        SwarmDesk desk = _desk(factory, c);
        // v3.15: the fixture token launch (baseLaunch + 3) records the fixture market as the token's hook.
        LocalLaunchFactory(Robinhood.LAUNCH_FACTORY).record(baseLaunch + 3, address(0), c.token, c.market, msg.sender);
        d.params = Params(
            factory.deploy(
                baseLaunch,
                0,
                abi.encodePacked(type(Params).creationCode, abi.encode(address(desk), c.heartbeatBps, c.heartbeatCap))
            )
        );
        d.registry = _registry(factory, c, address(d.params));
        IFixtureMarket(c.market)
            .configureBinding(
                address(desk), keccak256(abi.encode(c.starterRoot, c.freeRoot, c.snapshotBlock, _endowment(c)))
            );
        desk.bind(
            address(d.registry),
            type(GameRegistry).creationCode,
            type(Params).creationCode,
            baseLaunch,
            1,
            baseLaunch,
            0,
            baseLaunch + 3
        );
        address[14] memory modules = _modules(factory, address(d.registry));
        d.pool = RewardPool(modules[0]);
        d.rewards = FarmRewards(modules[1]);
        d.farm = FarmCore(modules[2]);
        d.items = FarmItems(modules[3]);
        d.packs = PackSale(modules[4]);
        d.starter = StarterClaim(modules[5]);
        d.fees = FeeRouter(payable(modules[6]));
        d.grid = GridOperator(modules[7]);
        d.season = Season(modules[8]);
        d.engine = FarmEngine(modules[9]);
        d.economy = Economy(modules[10]);
        d.enhancement = Enhancement(modules[11]);
        d.civic = Civic(modules[12]);
        d.billboards = Billboards(modules[13]);
    }

    function _endowment(Config memory c) private pure returns (uint256) {
        return 1_000_000_000 ether * c.endowmentBps / 10000;
    }

    /// @dev v3.8: no launch coordinates at construction; the token is excluded (Desk precedes the token launch).
    /// v3.16: this fixture contract is the Desk's pinned binder, since `deploy` sends the bind itself.
    function _desk(LocalApplicationFactory factory, Config memory c) private returns (SwarmDesk) {
        SwarmDesk.BindingConfig memory binding = SwarmDesk.BindingConfig(
            address(factory),
            0,
            0,
            0,
            0,
            keccak256(abi.encode(c.starterRoot, c.freeRoot, c.snapshotBlock, _endowment(c))),
            c.heartbeatBps,
            c.heartbeatCap
        );
        bytes memory args = SwarmArgs.encode(abi.decode(c.oracle, (SwarmDesk.OracleConfig)), binding, address(this));
        return SwarmDesk(factory.deploy(baseLaunch + 2, 0, bytes.concat(vm.getCode("SwarmDesk.sol:SwarmDesk"), args)));
    }

    function _registry(LocalApplicationFactory factory, Config memory c, address params)
        private
        returns (GameRegistry)
    {
        bytes memory args = abi.encode(
            c.token, params, c.market, c.starterRoot, c.freeRoot, c.snapshotBlock, _endowment(c)
        );
        return GameRegistry(factory.deploy(baseLaunch, 1, abi.encodePacked(type(GameRegistry).creationCode, args)));
    }

    function _modules(LocalApplicationFactory factory, address registry) private returns (address[14] memory modules) {
        string[14] memory names = [
            "RewardPool",
            "FarmRewards",
            "FarmCore",
            "FarmItems",
            "PackSale",
            "StarterClaim",
            "FeeRouter",
            "GridOperator",
            "Season",
            "FarmEngine",
            "Economy",
            "Enhancement",
            "Civic",
            "Billboards"
        ];
        for (uint256 i; i < 14; ++i) {
            bytes memory code = vm.getCode(string.concat(names[i], ".sol:", names[i]));
            uint64 launchNumber = i < 6 ? baseLaunch : baseLaunch + 1;
            uint256 index = i < 6 ? i + 2 : i - 6;
            modules[i] = factory.deploy(launchNumber, index, abi.encodePacked(code, abi.encode(registry)));
            assert(GameRegistry(registry).register(i, launchNumber, index, code) == modules[i]);
        }
    }
}
