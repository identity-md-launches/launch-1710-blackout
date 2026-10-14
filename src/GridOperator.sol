// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Economy} from "./Economy.sol";
import {Civic} from "./Civic.sol";
import {Params} from "./Params.sol";
import {FeeRouter} from "./FeeRouter.sol";
import {ChainClock} from "./lib/ChainClock.sol";
import {IRewards, ICore, ISeason} from "./interfaces/IGame.sol";
import "./lib/Errors.sol";

contract GridOperator is GameModule, ReentrancyGuard {
    enum Kind {
        Calm,
        Outage,
        Surge,
        Fire,
        Theft,
        Audit,
        Green,
        Cheap,
        Heatwave,
        Festival
    }

    struct Plan {
        Kind kind;
        uint16 severity;
        bytes32 number;
        string letter;
        bool submitted;
    }

    struct EventData {
        Kind kind;
        uint16 severity;
        uint8 district;
        uint64 target;
        uint64 started;
        bytes32 seed;
        bool resolved;
        uint256[8] weights;
    }

    struct Lobby {
        uint256 amount;
        uint64 at;
    }

    mapping(uint256 => uint8) public cityEvent;
    mapping(uint256 => mapping(uint256 => uint256)) public outputBonus;
    mapping(uint256 => Plan) private plans;
    mapping(uint256 => EventData) private events;
    mapping(uint256 => Lobby) public lobbies;
    mapping(uint256 => uint256) public lastOutage;
    event PlanSubmitted(uint256 indexed epoch, Kind kind, uint256 severity, bytes32 number, string letter);
    event Herald(uint256 indexed epoch, Kind kind, uint256 district, uint256 severity, bytes32 seed, string letter);
    event Lobbied(address indexed player, uint256 indexed district, uint256 ethValue);

    constructor(address registry_) GameModule(registry_) {}

    function swarmWallet() public view returns (address) {
        return Params(registry.params()).swarmWallet();
    }

    function params() public view returns (Params) {
        return Params(registry.params());
    }

    function fees() public view returns (FeeRouter) {
        return FeeRouter(payable(registry.module(6)));
    }

    function rewards() public view returns (IRewards) {
        return IRewards(registry.module(1));
    }

    function core() public view returns (ICore) {
        return ICore(registry.module(2));
    }

    function season() public view returns (ISeason) {
        return ISeason(registry.module(8));
    }

    function district(address p) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(p))) % 8;
    }

    /// @notice On-chain severity floor for submitted plans (v3.9). The SwarmDesk additionally clamps attested
    /// severities to its own 5000-7000 band; the fallback table keeps 10000.
    uint16 public constant SEVERITY_FLOOR = 3000;

    function submitPlan(uint256 e, Kind kind, uint16 severity, bytes32 number, string calldata letter) external {
        if (msg.sender != swarmWallet()) revert Unauthorized();
        uint256 current = rewards().epoch();
        // Reserved Heatwave/Festival plans need Civic feature 7 (v3.6 phased release).
        if (uint256(kind) > uint256(Kind.Cheap) && !Civic(registry.module(12)).enabled(7)) revert FeatureDisabled();
        if (
            e <= current || e > current + 2 || severity < SEVERITY_FLOOR || severity > 10000
                || bytes(letter).length == 0 || bytes(letter).length > 1024
        ) revert InvalidValue();
        if (plans[e].submitted) revert AlreadyDone();
        plans[e] = Plan(kind, severity, number, letter, true);
        emit PlanSubmitted(e, kind, severity, number, letter);
    }

    function planAt(uint256 e) external view returns (Plan memory) {
        return plans[e];
    }

    /// @notice Lobby contributions expire after three days; new spending extends the district boost.
    function lobbyAmount(uint256 d) public view returns (uint256) {
        Lobby memory l = lobbies[d];
        return block.timestamp < uint256(l.at) + 3 days ? l.amount : 0;
    }

    function gridStability(uint256 d) public view returns (uint256) {
        if (d >= 8) revert InvalidValue();
        Economy eco = Economy(registry.module(10));
        uint256 total;
        uint256 largest;
        uint256[8] memory stake;
        for (uint256 i; i < 8; ++i) {
            stake[i] = eco.districtStake(i);
            total += stake[i];
            if (stake[i] > largest) largest = stake[i];
        }
        uint256 stable = 10000;
        if (total != 0) {
            uint256 average = total / 8;
            if (stake[d] >= average) {
                stable = largest == average ? 10000 : 10000 + 5000 * (stake[d] - average) / (largest - average);
            } else {
                stable = average == 0 ? 10000 : 5000 + 5000 * stake[d] / average;
            }
        }
        uint256 lobby = lobbyAmount(d);
        stable += 5000 * lobby / (eco.averageDaily() * 5 + lobby);
        return stable > 15000 ? 15000 : stable;
    }

    function lobbyWeight(uint256 d) public view returns (uint256) {
        return 20000 - gridStability(d);
    }

    function lobbyETH() external payable {
        revert InvalidValue();
    }

    function tokenLobby(address p, uint256 value) external {
        if (msg.sender != address(core()) || value == 0) revert Unauthorized();
        _lobby(p, value);
    }

    function _lobby(address p, uint256 value) private {
        uint256 d = district(p);
        lobbies[d] = Lobby(lobbyAmount(d) + value, uint64(block.timestamp));
        emit Lobbied(p, d, value);
    }

    function shift(uint256 e) external {
        if (msg.sender != address(rewards())) revert Unauthorized();
        EventData storage x = events[e];
        if (x.target != 0) revert AlreadyDone();
        x.target = uint64(ChainClock.number() + 1);
        x.started = uint64(block.timestamp);
        Civic civic = Civic(registry.module(12));
        cityEvent[e] = civic.consumeCityEvent();
        for (uint256 d; d < 8; ++d) {
            x.weights[d] = lobbyWeight(d);
            outputBonus[e][d] = civic.outputBonus(d);
        }
    }

    function fallbackKind(uint256 e) public pure returns (Kind) {
        uint8[20] memory table = [uint8(6), 7, 0, 1, 0, 6, 2, 0, 3, 0, 7, 4, 0, 5, 0, 6, 0, 1, 0, 7];
        return Kind(table[(e - 1) % 20]);
    }

    /// @notice v3.17 (audit 339b6b19 low 2): when the target's 256-block hash window lapses before anyone resolves,
    /// the event is re-armed to a fresh future block instead of falling back to a seed computable before the epoch.
    /// The submitted plan stays attached and is applied with the fresh hash.
    event EventRearmed(uint256 indexed epoch, uint256 target);

    /// @return True when the event is resolved; false when its window lapsed and it was re-armed instead.
    function resolve(uint256 e) public nonReentrant returns (bool) {
        return _resolve(e, msg.sender);
    }

    function resolveFor(uint256 e, address keeper) external nonReentrant returns (bool) {
        if (msg.sender != address(rewards())) revert Unauthorized();
        return _resolve(e, keeper);
    }

    function _resolve(uint256 e, address keeper) private returns (bool) {
        uint256 startGas = gasleft();
        EventData storage x = events[e];
        if (x.resolved) return true;
        if (x.target == 0 || ChainClock.number() <= x.target) revert TooEarly();
        Plan storage p = plans[e];
        bytes32 h = ChainClock.hash(x.target);
        if (h == bytes32(0)) {
            // Never a seed computable before the epoch: re-arm like PackSale/StarterClaim and keep the plan.
            x.target = uint64(ChainClock.number() + 2);
            emit EventRearmed(e, x.target);
            return false;
        }
        x.seed = keccak256(abi.encode(p.number, h, address(this), e));
        Kind k = p.submitted ? p.kind : fallbackKind(e);
        x.severity = p.submitted ? p.severity : 10000;
        uint256 positives;
        uint256 repeated;
        uint256 first = e > 19 ? e - 19 : 1;
        for (uint256 j = first; j < e; ++j) {
            Kind old = events[j].kind;
            if (old == Kind.Green || old == Kind.Cheap) positives++;
            if (old == k) repeated++;
        }
        if ((e >= 20 && positives < 4) || (e < 20 && positives + 20 - e < 4)) {
            k = uint256(x.seed) % 2 == 0 ? Kind.Green : Kind.Cheap;
        }
        if (k >= Kind.Outage && k <= Kind.Audit && repeated >= 4) k = Kind.Calm;
        if (!p.submitted && uint256(x.seed) % 10000 < params().get(Params.Key.PositiveWeight)) {
            k = uint256(x.seed) >> 16 & 1 == 0 ? Kind.Green : Kind.Cheap;
        }
        uint256[8] memory weights;
        uint256 sum;
        for (uint256 d; d < 8; ++d) {
            uint256 w = (k == Kind.Green || k == Kind.Cheap || k == Kind.Festival) ? 20000 - x.weights[d] : x.weights[d];
            if (k == Kind.Outage && lastOutage[d] != 0 && x.started < lastOutage[d] + 2 days) w = 0;
            weights[d] = w;
            sum += w;
        }
        if (sum == 0) {
            k = Kind.Calm;
        } else {
            uint256 point = uint256(keccak256(abi.encode(x.seed, "district"))) % sum;
            for (uint256 d; d < 8; ++d) {
                if (point < weights[d]) {
                    x.district = uint8(d);
                    break;
                }
                point -= weights[d];
            }
        }
        if (cityEvent[e] != 0) {
            k = cityEvent[e] == 1 ? Kind.Green : Kind.Outage;
            x.district = 8;
            x.severity = 10000;
        }
        x.kind = k;
        x.resolved = true;
        if (k == Kind.Outage) lastOutage[x.district] = x.started;
        emit Herald(
            e, k, x.district, x.severity, x.seed, p.submitted ? p.letter : "Autonomous fallback: the grid continues."
        );
        fees().payWork(keeper, Params.Key.EntropyBounty, 1, startGas - gasleft());
        return true;
    }

    /// @notice Block whose hash seeds epoch `e`; moves forward when the window lapses unresolved (v3.17).
    function eventTarget(uint256 e) external view returns (uint64) {
        return events[e].target;
    }

    function eventAt(uint256 e)
        external
        view
        returns (Kind kind, uint16 severity, uint8 d, bytes32 seed, bool resolved)
    {
        EventData storage x = events[e];
        return (x.kind, x.severity, x.district, x.seed, x.resolved);
    }
}
