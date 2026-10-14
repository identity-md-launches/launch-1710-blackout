// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FarmItems} from "./FarmItems.sol";
import {Params} from "./Params.sol";
import {GridOperator} from "./GridOperator.sol";
import {IRewards} from "./interfaces/IGame.sol";
import {EconomyMath} from "./lib/EconomyMath.sol";
import {ItemMath} from "./lib/ItemMath.sol";
import "./lib/Errors.sol";

/// @notice Immutable room/event calculator. Only Core may apply damage; no delegatecall or upgrades.
contract FarmEngine is GameModule {
    struct Snapshot {
        uint256[24] ids;
        uint8[24] clocks;
        uint16[24] health;
        bool paid;
        uint64 theftUntil;
        uint16 routerRepairBps;
    }

    struct RoomStats {
        uint256 raw;
        uint256 productive;
        uint256 power;
        uint256 bonus;
        bool cooling;
        bool cold;
        bool offgrid;
        bool clean;
        bool locked;
        bool airflow;
    }

    constructor(address registry_) GameModule(registry_) {}

    function items() public view returns (FarmItems) {
        return FarmItems(registry.module(3));
    }

    function params() public view returns (Params) {
        return Params(registry.params());
    }

    function rewards() public view returns (IRewards) {
        return IRewards(registry.module(1));
    }

    function grid() public view returns (GridOperator) {
        return GridOperator(registry.module(7));
    }

    function core() public view returns (address) {
        return registry.module(2);
    }

    function _param(Params.Key k, bool active, uint256 e) private view returns (uint256) {
        if (e == type(uint256).max) {
            (, uint256 hi) = params().bounds(k);
            return hi;
        }
        return active ? rewards().epochParam(e, uint256(k)) : params().get(k);
    }

    /// @notice Full-health allocation envelope at maximum protocol combo bonuses; independent of lazy wear.
    function allocationHash(uint256[24] memory ids, bool paid) external view returns (uint256 hash) {
        Snapshot memory f;
        f.ids = ids;
        f.paid = paid;
        for (uint256 i; i < 24; ++i) {
            if (ids[i] == 0) continue;
            f.clocks[i] = items().data(ids[i]).overclock;
            f.health[i] = 10000;
        }
        for (uint256 r; r < 4; ++r) {
            hash += _stats(f, r, false, type(uint256).max).raw;
        }
    }

    function preview(uint256[24] memory ids, uint64 theftUntil, uint256 room) external view returns (RoomStats memory) {
        Snapshot memory snap;
        snap.ids = ids;
        snap.theftUntil = theftUntil;
        for (uint256 i; i < 24; ++i) {
            if (ids[i] == 0) continue;
            FarmItems.Item memory x = items().data(ids[i]);
            snap.clocks[i] = x.overclock;
            snap.health[i] = x.durability;
        }
        return stats(snap, room, false, rewards().epoch());
    }

    function stats(Snapshot memory f, uint256 room, bool active, uint256 e) public view returns (RoomStats memory s) {
        s = _stats(f, room, active, e);
        // Repair restores only the remaining fraction of this epoch, including Router combos.
        if (e < f.theftUntil && f.routerRepairBps != 0 && !s.locked) {
            uint64 saved = f.theftUntil;
            f.theftUntil = 0;
            RoomStats memory restored = _stats(f, room, active, e);
            f.theftUntil = saved;
            uint256 fraction = f.routerRepairBps;
            s.raw = (s.raw * (10000 - fraction) + restored.raw * fraction) / 10000;
            s.productive = (s.productive * (10000 - fraction) + restored.productive * fraction) / 10000;
            s.power = (s.power * (10000 - fraction) + restored.power * fraction) / 10000;
            s.bonus = (s.bonus * (10000 - fraction) + restored.bonus * fraction) / 10000;
        }
    }

    /// @dev Per-room accumulators, kept in memory so the legacy code generator stays within its stack.
    struct Acc {
        uint256 mask;
        uint256 baseRaw;
        uint256 baseProductive;
        uint256 tags;
        uint256[5] rarity;
    }

    function _stats(Snapshot memory f, uint256 room, bool active, uint256 e) private view returns (RoomStats memory s) {
        if (room >= 4) revert InvalidValue();
        Acc memory a;
        for (uint256 i; i < 6; ++i) {
            uint256 id = f.ids[room * 6 + i];
            if (id == 0) continue;
            FarmItems.Item memory x = items().data(id);
            if (x.holder != address(0)) a.mask |= 1 << x.kind;
        }
        s.cooling = a.mask & ((1 << 6) | (1 << 7)) != 0;
        s.airflow = a.mask & (1 << 6) != 0 && a.mask & (1 << 10) != 0;
        s.cold = a.mask & (1 << 3) != 0 && a.mask & (1 << 7) != 0;
        s.offgrid = a.mask & (1 << 4) != 0 && a.mask & (1 << 5) != 0;
        s.clean = a.mask & (1 << 11) != 0 && a.mask & (1 << 3) != 0;
        s.locked = a.mask & (1 << 8) != 0 && a.mask & (1 << 10) != 0;
        for (uint256 i; i < 6; ++i) {
            _accumulate(f, room * 6 + i, e, s, a);
        }
        if (a.mask & 3 == 3) {
            s.bonus += _param(a.mask & 7 == 7 ? Params.Key.TripleCoreBps : Params.Key.ComputePairBps, active, e);
        }
        if (a.tags == 31) s.bonus += _param(Params.Key.FullSetBps, active, e);
        if (s.airflow) s.bonus += _param(Params.Key.AirflowBps, active, e);
        if (a.rarity[4] >= 3) s.bonus += _param(Params.Key.MythicSetBps, active, e);
        else if (a.rarity[3] >= 3) s.bonus += _param(Params.Key.LegendarySetBps, active, e);
        else if (a.rarity[2] >= 3) s.bonus += _param(Params.Key.EpicSetBps, active, e);
        else if (a.rarity[1] >= 3) s.bonus += _param(Params.Key.RareSetBps, active, e);
        uint256 cap = _param(Params.Key.SetCapBps, active, e);
        s.bonus = Math.min(s.bonus, cap);
        s.raw = Math.min(s.raw + a.baseRaw * s.bonus / 10000, a.baseRaw * (10000 + cap) / 10000);
        s.productive =
            Math.min(s.productive + a.baseProductive * s.bonus / 10000, a.baseProductive * (10000 + cap) / 10000);
        uint256 saving = (s.cold ? _param(Params.Key.ElectricityPairBps, active, e) : 0)
            + (s.offgrid ? _param(Params.Key.OffgridBps, active, e) : 0);
        s.power = s.productive * (10000 - saving) / 10000;
    }

    function _accumulate(Snapshot memory f, uint256 idx, uint256 e, RoomStats memory s, Acc memory a) private view {
        uint256 id = f.ids[idx];
        if (id == 0) return;
        FarmItems.Item memory x = items().data(id);
        if (x.holder == address(0)) return;
        if (x.kind == 8 && e < f.theftUntil && !s.locked) return;
        a.tags |= 1 << ItemMath.tag(x.kind);
        a.rarity[x.rarity]++;
        uint256 raw = ItemMath.baseHash(x.rarity) * (x.kind < 3 ? 10000 : 6000) / 10000;
        uint256 tier = EconomyMath.tier(f.health[idx]);
        a.baseRaw += raw;
        a.baseProductive += raw * tier / 10000;
        raw = raw * (10000 + EconomyMath.bonus(f.clocks[idx])) / 10000;
        s.raw += raw;
        s.productive += raw * tier / 10000;
    }

    /// @dev The resolved event as it applies to one farm; computed once per settlement.
    struct Event {
        GridOperator.Kind kind;
        uint16 severity;
        bool local;
        bool outage;
        bool surge;
        bool theft;
        uint256 random;
        uint256 target;
        uint256 cursor;
        uint256 boost;
    }

    function _event(address p, uint256 e, Snapshot memory f) private view returns (Event memory ev) {
        (GridOperator.Kind kind, uint16 severity, uint8 d, bytes32 seed, bool resolved) = rewards().eventAt(e);
        if (!resolved) revert TooEarly();
        ev.kind = kind;
        ev.severity = severity;
        ev.random = uint256(keccak256(abi.encode(seed, p)));
        uint256 home = uint256(keccak256(abi.encodePacked(p))) % 8;
        ev.local = d == 8 || home == d;
        ev.outage = ev.local && kind == GridOperator.Kind.Outage
            && (d == 8 || ev.random % 10000 < 3000 * uint256(severity) / 10000);
        ev.surge = ev.local && kind == GridOperator.Kind.Surge && ev.random % 10000 < 1000 * uint256(severity) / 10000;
        ev.theft = ev.local && kind == GridOperator.Kind.Theft && ev.random % 10000 < 2000 * uint256(severity) / 10000;
        uint256 occupied;
        for (uint256 i; i < 24; ++i) {
            if (f.ids[i] != 0) occupied++;
        }
        ev.target = occupied == 0 ? type(uint256).max : (ev.random >> 64) % occupied;
        ev.boost = grid().outputBonus(e, home);
    }

    function process(address p, uint256 e, Snapshot memory f)
        external
        returns (uint256 raw, uint256 productive, uint256 power, uint64 theftUntil)
    {
        if (msg.sender != core()) revert Unauthorized();
        Event memory ev = _event(p, e, f);
        RoomStats[4] memory baseline;
        for (uint256 r; r < 4; ++r) {
            baseline[r] = stats(f, r, true, e);
        }
        for (uint256 r; r < 4; ++r) {
            raw += baseline[r].raw;
            if (ev.theft && !baseline[r].locked) {
                f.theftUntil = uint64(e + 2);
                f.routerRepairBps = 0;
            }
            _damage(f, r, ev, baseline[r]);
            RoomStats memory s = _output(f, r, e, ev);
            productive += s.productive;
            power += s.power;
            _wear(f, r);
        }
        theftUntil = f.theftUntil;
    }

    /// @dev Event damage to the items of room `r`, using the room's pre-event combos.
    function _damage(Snapshot memory f, uint256 r, Event memory ev, RoomStats memory before_) private {
        for (uint256 i; i < 6; ++i) {
            uint256 idx = r * 6 + i;
            uint256 id = f.ids[idx];
            if (id == 0) continue;
            FarmItems.Item memory x = items().data(id);
            if (x.holder == address(0)) continue;
            uint256 damage;
            if (ev.surge && ev.cursor == ev.target && !before_.clean) {
                if ((ev.random >> 128) % 100 < 2 && x.rarity < 3) {
                    items().destroy(id);
                    f.ids[idx] = 0;
                    ev.cursor++;
                    continue;
                }
                damage = 5000;
            }
            if (ev.local && ev.kind == GridOperator.Kind.Fire && !before_.cold) {
                damage += 3000 * uint256(ev.severity) / 10000 / (before_.airflow ? 2 : 1);
            }
            if (
                ev.local && ev.kind == GridOperator.Kind.Heatwave && x.kind >= 6 && x.kind <= 7 && !before_.airflow
                    && !before_.cold
            ) damage += 500;
            f.health[idx] = uint16(f.health[idx] > damage ? f.health[idx] - damage : 0);
            items().maintain(id, uint16(x.durability > damage ? x.durability - damage : 0), x.overclock);
            ev.cursor++;
        }
    }

    /// @dev Post-damage output of room `r` with event and district effects applied.
    function _output(Snapshot memory f, uint256 r, uint256 e, Event memory ev)
        private
        view
        returns (RoomStats memory s)
    {
        s = stats(f, r, true, e);
        if (ev.outage) {
            s.productive = s.offgrid ? s.productive / 2 : 0;
            s.power = s.offgrid ? s.power / 2 : 0;
        }
        if (ev.local && ev.kind == GridOperator.Kind.Fire && !s.cooling) {
            s.productive = 0;
            s.power = 0;
        }
        if (ev.local && (ev.kind == GridOperator.Kind.Green || ev.kind == GridOperator.Kind.Festival)) {
            uint256 eventBonus = ev.kind == GridOperator.Kind.Festival
                ? Math.min(1500, Math.max(500, uint256(ev.severity)))
                : uint256(ev.severity) / 10;
            s.productive = s.productive * (10000 + eventBonus) / 10000;
            s.power = s.power * (10000 + eventBonus) / 10000;
        }
        s.productive = s.productive * (10000 + ev.boost) / 10000;
        s.power = s.power * (10000 + ev.boost) / 10000;
    }

    /// @dev Ordinary epoch wear: 1% of durability per active epoch.
    function _wear(Snapshot memory f, uint256 r) private {
        for (uint256 i; i < 6; ++i) {
            uint256 id = f.ids[r * 6 + i];
            if (id == 0) continue;
            FarmItems.Item memory x = items().data(id);
            items().maintain(id, x.durability > 100 ? x.durability - 100 : 0, x.overclock);
        }
    }
}
