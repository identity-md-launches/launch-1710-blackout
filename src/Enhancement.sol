// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {FarmItems} from "./FarmItems.sol";
import {Economy} from "./Economy.sol";
import {Params} from "./Params.sol";
import {EconomyMath} from "./lib/EconomyMath.sol";
import {ChainClock} from "./lib/ChainClock.sol";
import "./lib/Errors.sol";

interface IFeatureFlags {
    function enabled(uint256) external view returns (bool);
}

interface IEnhanceCore {
    function level(address) external view returns (uint256);
    function prepareEnhancement(address, uint256, uint256, bool) external;
}

contract Enhancement is GameModule, ReentrancyGuard {
    struct Attempt {
        address player;
        uint256 item;
        uint64 target;
        uint8 level;
        bytes32 seed;
        bool captured;
        bool resolved;
    }
    uint8 public cap = 8;
    uint8 public announcedCap;
    uint256 public activationAt;
    uint256 public lastRaised;
    uint256 public nextId = 1;
    mapping(uint256 => Attempt) public attempts;
    mapping(uint256 => uint256) public pending;
    event EnhancementCommitted(
        uint256 indexed id, address indexed player, uint256 indexed item, uint256 level, uint256 target, uint256 cost
    );
    event EnhancementCaptured(uint256 indexed id, bytes32 seed);
    /// @notice v3.17 (audit 339b6b19 medium): an attempt whose 256-block hash window lapsed is settled as the worst
    /// failure its level allows instead of being re-armed, so reading the outcome off-chain and letting a bad one
    /// lapse is never better than resolving it.
    event EnhancementLapsed(uint256 indexed id, bool burned, uint256 level);
    event EnhancementResolved(uint256 indexed id, bool success, bool burned, uint256 level);
    event CapAnnounced(uint256 cap, uint256 at, string letter);
    event CapRaised(uint256 cap);
    constructor(address r) GameModule(r) {}

    function table(uint256 level) external pure returns (uint256, uint256, uint256, uint256) {
        return EconomyMath.enhancement(level);
    }

    function announceCap(uint8 next, string calldata letter) external {
        if (msg.sender != Params(registry.params()).swarmWallet()) revert Unauthorized();
        if (
            (cap == 8 ? next != 12 : cap == 12 ? next != 16 : true) || announcedCap != 0 || bytes(letter).length == 0
                || bytes(letter).length > 1024
        ) revert InvalidValue();
        uint256 earliest = (lastRaised == 0 ? registry.launchTime() : lastRaised) + 30 days;
        activationAt = block.timestamp + 48 hours;
        if (activationAt < earliest) activationAt = earliest;
        announcedCap = next;
        emit CapAnnounced(next, activationAt, letter);
    }

    function activateCap() external {
        if (announcedCap == 0 || block.timestamp < activationAt) revert TooEarly();
        cap = announcedCap;
        announcedCap = 0;
        lastRaised = block.timestamp;
        emit CapRaised(cap);
    }

    /// @notice Disabled until Civic feature 3 is enabled (v3.6 phased release).
    function commit(uint256 item, uint256 maxCost, bool wallet) external nonReentrant returns (uint256 id) {
        if (!IFeatureFlags(registry.module(12)).enabled(3)) revert FeatureDisabled();
        FarmItems.Item memory x = FarmItems(registry.module(3)).data(item);
        IEnhanceCore core = IEnhanceCore(registry.module(2));
        uint8 target = x.overclock + 1;
        if (x.holder != msg.sender || pending[item] != 0 || target > cap) revert InvalidValue();
        if ((target >= 6 && core.level(msg.sender) < 7) || (target >= 9 && core.level(msg.sender) < 10)) {
            revert InvalidValue();
        }
        uint256 cost = Economy(registry.module(10)).enhanceQuote(item);
        if (cost > maxCost) revert InvalidValue();
        core.prepareEnhancement(msg.sender, item, cost, wallet);
        id = nextId++;
        pending[item] = id;
        attempts[id] = Attempt(msg.sender, item, uint64(ChainClock.number() + 2), target, bytes32(0), false, false);
        emit EnhancementCommitted(id, msg.sender, item, target, ChainClock.number() + 2, cost);
    }

    /// @notice Capture the target block hash once it is available. Past the 256-block window the attempt lapses:
    /// it is settled at once as a failure with the worst outcome of its level (never re-armed, see `_lapse`).
    function capture(uint256 id) external nonReentrant {
        _capture(id);
    }

    /// @dev True when a seed is now fixed and the attempt still awaits `resolve`.
    function _capture(uint256 id) private returns (bool) {
        Attempt storage a = attempts[id];
        if (a.player == address(0) || a.resolved) revert InvalidValue();
        if (a.captured) return true;
        if (ChainClock.number() <= a.target) revert TooEarly();
        bytes32 h = ChainClock.hash(a.target);
        if (h == bytes32(0)) {
            if (ChainClock.number() <= uint256(a.target) + 256) revert NotConfigured();
            _lapse(id, a);
            return false;
        }
        a.seed = keccak256(abi.encode(h, address(this), id));
        a.captured = true;
        emit EnhancementCaptured(id, a.seed);
        return true;
    }

    /// @notice Worst outcome `level` allows, which is what a lapsed attempt receives: never a success, levels 1-3
    /// keep the item's level, levels 4 and above lose one, and any level with a burn chance burns the item.
    function worstOutcome(uint256 level) public pure returns (bool burned, uint8 resulting) {
        (, uint256 burn,,) = EconomyMath.enhancement(level);
        burned = burn != 0;
        resulting = _failureLevel(uint8(level));
    }

    function _failureLevel(uint8 target) private pure returns (uint8) {
        return target >= 4 ? target - 2 : target - 1;
    }

    /// @dev Audit 339b6b19 medium: the old re-arm let a player read the outcome off-chain, resolve successes and let
    /// failures and burns expire. A lapsed attempt is now settled immediately at its level's worst outcome, so
    /// lapsing is never better for the player than resolving.
    function _lapse(uint256 id, Attempt storage a) private {
        (bool burned, uint8 level) = worstOutcome(a.level);
        a.captured = true;
        a.resolved = true;
        delete pending[a.item];
        _apply(a, burned, level);
        emit EnhancementLapsed(id, burned, level);
        emit EnhancementResolved(id, false, burned, level);
    }

    function _apply(Attempt storage a, bool burned, uint8 level) private {
        FarmItems inventory = FarmItems(registry.module(3));
        FarmItems.Item memory x = inventory.data(a.item);
        if (x.holder != a.player || x.equipped) revert InvalidValue();
        if (burned) inventory.destroy(a.item);
        else inventory.maintain(a.item, x.durability, level);
    }

    function resolve(uint256 id) external nonReentrant {
        if (!_capture(id)) return;
        Attempt storage a = attempts[id];
        a.resolved = true;
        delete pending[a.item];
        (uint256 chance, uint256 burn,,) = EconomyMath.enhancement(a.level);
        bool success = uint256(a.seed) % 100 < chance;
        bool burned = !success && uint256(keccak256(abi.encode(a.seed, "burn"))) % 100 < burn;
        uint8 level = success ? a.level : _failureLevel(a.level);
        _apply(a, burned, level);
        emit EnhancementResolved(id, success, burned, level);
    }
}
