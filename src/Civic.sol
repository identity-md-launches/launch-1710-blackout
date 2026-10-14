// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Params} from "./Params.sol";
import {Economy} from "./Economy.sol";
import {FarmItems} from "./FarmItems.sol";
import {RewardPool} from "./RewardPool.sol";
import {IRewards, ICore} from "./interfaces/IGame.sol";
import "./lib/Errors.sol";

interface ICivicRewards {
    function districtActiveHash(uint256) external view returns (uint256);
}

interface IPurchaseReadiness {
    function ready() external view returns (bool);
}

/// @notice Immutable civic escrow, optional modules and the v3.6 phased-release flags.
/// Features deploy disabled; the swarm announces each one once with a letter, anyone can
/// enable it after 48 hours, and nothing can ever disable it again. Feature ids:
/// 0 district war, 1 grid collapse, 2 weekly lots (dormant modules, unchanged),
/// 3 enhancement, 4 locks + district stake + lobby, 5 billboards, 6 season token pot,
/// 7 reserved events (Heatwave/Festival plans).
contract Civic is GameModule, ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 public constant FEATURES = 8;
    uint256 public escrow;
    uint256[8] public noticeAt;
    bool[8] public enabled;
    mapping(uint256 => bool) public seasonBoostUsed;
    uint256[8] public boostUntil;
    uint16[8] public seasonBoost;
    uint256[8] public warBoostUntil;
    event ModuleNotice(uint256 indexed module, uint256 at, string letter);
    event ModuleEnabled(uint256 indexed module);
    event DistrictBoost(uint256 indexed season, uint256 district, uint256 bps, uint256 until, string letter);
    constructor(address r) GameModule(r) {}
    modifier onlySwarm() {
        if (msg.sender != Params(registry.params()).swarmWallet()) revert Unauthorized();
        _;
    }

    function district(address p) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(p))) % 8;
    }

    function week() public view returns (uint256) {
        return (block.timestamp - registry.launchTime()) / 7 days;
    }

    function _take(address p, uint256 amount) private {
        if (amount == 0) revert InvalidValue();
        IERC20 t = IERC20(registry.token());
        uint256 before_ = t.balanceOf(address(this));
        t.safeTransferFrom(p, address(this), amount);
        if (t.balanceOf(address(this)) - before_ != amount) revert InvalidValue();
        escrow += amount;
    }

    function _pool(uint256 amount) private {
        if (amount == 0) return;
        escrow -= amount;
        IERC20 t = IERC20(registry.token());
        address pool = registry.module(0);
        t.forceApprove(pool, amount);
        RewardPool(pool).donate(amount);
        t.forceApprove(pool, 0);
    }

    function announce(uint256 feature, string calldata letter) external onlySwarm {
        if (feature >= FEATURES || noticeAt[feature] != 0 || bytes(letter).length == 0 || bytes(letter).length > 1024) {
            revert InvalidValue();
        }
        noticeAt[feature] = block.timestamp + 48 hours;
        emit ModuleNotice(feature, noticeAt[feature], letter);
    }

    function enable(uint256 feature) external {
        if (feature >= FEATURES || noticeAt[feature] == 0 || enabled[feature] || block.timestamp < noticeAt[feature]) {
            revert TooEarly();
        }
        enabled[feature] = true;
        emit ModuleEnabled(feature);
    }

    function grantDistrictBoost(uint256 d, uint16 bps, string calldata letter) external onlySwarm {
        uint256 w = week();
        if (d >= 8 || bps > 1500 || seasonBoostUsed[w] || bytes(letter).length == 0 || bytes(letter).length > 1024) {
            revert InvalidValue();
        }
        seasonBoostUsed[w] = true;
        seasonBoost[d] = bps;
        boostUntil[d] = block.timestamp + 7 days;
        emit DistrictBoost(w, d, bps, boostUntil[d], letter);
    }

    function outputBonus(uint256 d) external view returns (uint256) {
        return (block.timestamp < boostUntil[d] ? seasonBoost[d] : 0) + (block.timestamp < warBoostUntil[d] ? 1000 : 0);
    }

    struct War {
        uint8 a;
        uint8 b;
        uint8 winner;
        uint64 end;
        bool settled;
        uint256 chestA;
        uint256 chestB;
        uint256 payout;
        uint256 winningChest;
        uint256 hashA;
        uint256 hashB;
    }
    uint256 public warId;
    mapping(uint256 => uint256) public warRate;
    mapping(uint256 => War) public wars;
    mapping(uint256 => mapping(address => uint256)) public contribution;
    mapping(uint256 => mapping(address => bool)) public warClaimed;
    mapping(uint256 => mapping(uint256 => address[10])) private warTop;
    event WarStarted(uint256 indexed id, uint256 a, uint256 b, uint256 end);
    event WarFunded(uint256 indexed id, address indexed player, uint256 amount);
    event WarFinished(uint256 indexed id, uint256 winner, uint256 payout, uint256 pool);

    function startWar(uint8 a, uint8 b) external onlySwarm {
        if (!enabled[0] || a >= 8 || b >= 8 || a == b || (warId != 0 && !wars[warId].settled)) revert InvalidValue();
        ++warId;
        warRate[warId] = Economy(registry.module(10)).averageDaily();
        wars[warId] = War(
            a,
            b,
            0,
            uint64(block.timestamp + 48 hours),
            false,
            0,
            0,
            0,
            0,
            ICivicRewards(registry.module(1)).districtActiveHash(a),
            ICivicRewards(registry.module(1)).districtActiveHash(b)
        );
        emit WarStarted(warId, a, b, block.timestamp + 48 hours);
    }

    function fundWar(uint256 amount) external nonReentrant {
        War storage w = wars[warId];
        uint256 d = district(msg.sender);
        if (!enabled[0] || warId == 0 || block.timestamp >= w.end || w.settled || (d != w.a && d != w.b)) {
            revert InvalidValue();
        }
        contribution[warId][msg.sender] += amount;
        if (d == w.a) w.chestA += amount;
        else w.chestB += amount;
        address[10] storage top = warTop[warId][d];
        uint256 slot;
        uint256 low = type(uint256).max;
        bool found;
        for (uint256 i; i < 10; ++i) {
            if (top[i] == msg.sender) {
                found = true;
                break;
            }
            uint256 v = contribution[warId][top[i]];
            if (v < low) {
                low = v;
                slot = i;
            }
        }
        if (!found && contribution[warId][msg.sender] > low) top[slot] = msg.sender;
        _take(msg.sender, amount);
        emit WarFunded(warId, msg.sender, amount);
    }

    function warScore(uint256 id, uint256 d) public view returns (uint256) {
        War storage w = wars[id];
        if (d != w.a && d != w.b) revert InvalidValue();
        uint256 raw = d == w.a ? w.chestA : w.chestB;
        uint256 capped = raw;
        for (uint256 i; i < 10; ++i) {
            uint256 amount = contribution[id][warTop[id][d][i]];
            if (amount > raw / 10) capped -= amount - raw / 10;
        }
        return capped * 10000 / warRate[id] + (d == w.a ? w.hashA : w.hashB);
    }

    function finishWar() external nonReentrant {
        War storage w = wars[warId];
        if (warId == 0 || w.settled || block.timestamp < w.end) revert TooEarly();
        w.settled = true;
        w.winner = warScore(warId, w.a) >= warScore(warId, w.b) ? w.a : w.b;
        uint256 win = w.winner == w.a ? w.chestA : w.chestB;
        uint256 lose = w.winner == w.a ? w.chestB : w.chestA;
        w.winningChest = win;
        w.payout = win == 0 ? 0 : win + lose / 2;
        uint256 toPool = w.chestA + w.chestB - w.payout;
        _pool(toPool);
        warBoostUntil[w.winner] = block.timestamp + 7 days;
        emit WarFinished(warId, w.winner, w.payout, toPool);
    }

    function claimWar(uint256 id) external nonReentrant returns (uint256 amount) {
        War storage w = wars[id];
        if (
            !w.settled || warClaimed[id][msg.sender] || district(msg.sender) != w.winner
                || contribution[id][msg.sender] == 0
        ) revert InvalidValue();
        warClaimed[id][msg.sender] = true;
        amount = Math.mulDiv(w.payout, contribution[id][msg.sender], w.winningChest);
        escrow -= amount;
        IERC20(registry.token()).safeTransfer(msg.sender, amount);
    }
    uint256 public collapseEnd;
    uint256 public collapseGoal;
    uint256 public collapseRaised;
    uint256 public greenUntil;
    bool public collapseFinalized = true;
    bool public outagePending;
    event CollapseStarted(uint256 goal, uint256 end);
    event CollapseFunded(address indexed player, uint256 amount);
    event CollapseFinished(bool met);

    function startCollapse(uint256 goal) external onlySwarm {
        if (
            !enabled[1] || !collapseFinalized || outagePending || block.timestamp < greenUntil
                || goal < Economy(registry.module(10)).averageDaily()
        ) revert InvalidValue();
        collapseEnd = block.timestamp + 24 hours;
        collapseGoal = goal;
        collapseRaised = 0;
        collapseFinalized = false;
        emit CollapseStarted(goal, collapseEnd);
    }

    function fundCollapse(uint256 amount) external nonReentrant {
        if (collapseFinalized || block.timestamp >= collapseEnd) revert TooEarly();
        collapseRaised += amount;
        _take(msg.sender, amount);
        _pool(amount);
        emit CollapseFunded(msg.sender, amount);
    }

    function finishCollapse() external {
        if (collapseFinalized || block.timestamp < collapseEnd) revert TooEarly();
        collapseFinalized = true;
        bool met = collapseRaised >= collapseGoal;
        if (met) greenUntil = block.timestamp + 1 days;
        else outagePending = true;
        emit CollapseFinished(met);
    }

    function consumeCityEvent() external returns (uint8 forced) {
        if (msg.sender != registry.module(7)) revert Unauthorized();
        if (outagePending) {
            outagePending = false;
            return 2;
        }
        if (block.timestamp < greenUntil) return 1;
    }

    struct Lot {
        uint8 kind;
        uint8 rarity;
        uint8 supply;
        uint8 sold;
        uint64 start;
    }
    mapping(uint256 => Lot) public lots;
    event LotListed(uint256 indexed week, uint256 kind, uint256 rarity, uint256 supply);
    event LotBought(uint256 indexed week, address indexed player, uint256 item, uint256 amount);

    function listLot(uint8 kind, uint8 rarity, uint8 supply) external onlySwarm {
        uint256 w = week();
        if (!enabled[2] || kind >= 12 || rarity < 1 || rarity > 3 || supply == 0 || supply > 3 || lots[w].start != 0) {
            revert InvalidValue();
        }
        lots[w] = Lot(kind, rarity, supply, 0, uint64(block.timestamp));
        emit LotListed(w, kind, rarity, supply);
    }

    function lotQuote(uint256 w) external view returns (uint256) {
        return Economy(registry.module(10)).auctionQuote(lots[w].start);
    }

    function buyLot(uint256 maxCost) external nonReentrant returns (uint256 id) {
        if (!enabled[2] || !IPurchaseReadiness(registry.module(4)).ready()) revert TooEarly();
        uint256 w = week();
        Lot storage l = lots[w];
        if (l.start == 0 || l.sold >= l.supply) revert InvalidValue();
        uint256 cost = Economy(registry.module(10)).auctionQuote(l.start);
        if (cost > maxCost) revert InvalidValue();
        ++l.sold;
        _take(msg.sender, cost);
        _pool(cost);
        ICore(registry.module(2)).civicPurchase(msg.sender, cost);
        id = FarmItems(registry.module(3)).mint(msg.sender, l.kind, l.rarity, false);
        emit LotBought(w, msg.sender, id, cost);
    }
}
