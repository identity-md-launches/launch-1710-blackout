// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {wadExp, wadLn} from "solmate/src/utils/SignedWadMath.sol";
import {RewardPool} from "./RewardPool.sol";
import {ILaunchHook} from "./interfaces/ILaunchHook.sol";
import {FarmItems} from "./FarmItems.sol";
import {Params} from "./Params.sol";
import {FeeRouter} from "./FeeRouter.sol";
import {ICore} from "./interfaces/IGame.sol";
import {ChainClock} from "./lib/ChainClock.sol";
import {Economy} from "./Economy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ItemMath} from "./lib/ItemMath.sol";
import "./lib/Errors.sol";

contract PackSale is GameModule, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Commit {
        address player;
        uint64 target;
        uint256 count;
        uint256 opened;
        bool mythic;
        bool guaranteed;
        bytes32 seed;
        bool fixedSeed;
        bool expired;
    }

    uint256 public sold;
    uint8 public constant profile = 1;
    bool public constant profileChosen = true;

    /// @notice Values are yield-days (1e18), decay basis points/hour, sales/hour target.
    function profileParams(uint256 choice)
        public
        pure
        returns (uint256 start, uint256 floor, uint256 ceiling, uint256 decay, uint256 target)
    {
        if (choice == 0) return (3 ether, 1.5 ether, 6 ether, 300, 20);
        if (choice == 1) return (5 ether, 2.5 ether, 10 ether, 200, 20);
        if (choice == 2) return (7 ether, 3.5 ether, 14 ether, 100, 15);
        revert InvalidValue();
    }

    function priceBounds() public view returns (uint256 low, uint256 high) {
        (, uint256 floor, uint256 ceiling,,) = profileParams(profile);
        uint256 daily = Economy(registry.module(10)).averageDaily();
        return (daily * floor / 1 ether, daily * ceiling / 1 ether);
    }
    /// @notice Sales open this long after the authenticated hook initialization timestamp.
    uint256 public constant OPEN_DELAY = 60 minutes;
    uint256 public pausedUntil;
    uint256 public nextPauseAt;
    event SalePaused(uint256 until);

    function paused() public view returns (bool) {
        return block.timestamp < pausedUntil;
    }

    function pause(uint256 duration) external {
        if (msg.sender != params().swarmWallet()) revert Unauthorized();
        if (duration == 0 || duration > 72 hours) revert InvalidValue();
        if (block.timestamp < nextPauseAt) revert TooEarly();
        pausedUntil = block.timestamp + duration;
        nextPauseAt = pausedUntil + 72 hours; // No extension or chaining into an indefinite pause.
        emit SalePaused(pausedUntil);
    }

    function unpause() external {
        if (msg.sender != params().swarmWallet()) revert Unauthorized();
        pausedUntil = 0;
        emit SalePaused(0);
    }
    uint256 public nextId = 1;
    mapping(uint256 => Commit) public commits;
    event PackCommitted(uint256 indexed id, address indexed player, uint256 count, uint256 target, bool guaranteed);
    event PackOpened(uint256 indexed id, uint256 count, bool expired);

    constructor(address registry_) GameModule(registry_) {}

    function items() public view returns (FarmItems) {
        return FarmItems(registry.module(3));
    }

    function params() public view returns (Params) {
        return Params(registry.params());
    }

    function fees() public view returns (FeeRouter) {
        return FeeRouter(payable(registry.module(6)));
    }

    function farm() public view returns (ICore) {
        return ICore(registry.module(2));
    }

    function season() public view returns (address) {
        return registry.module(8);
    }

    function launchTime() public view returns (uint256) {
        return registry.launchTime();
    }

    function opensAt() public view returns (uint256) {
        return ILaunchHook(registry.market()).initializedAt() == 0
            ? type(uint256).max
            : ILaunchHook(registry.market()).initializedAt() + OPEN_DELAY;
    }

    function isOpen() public view returns (bool) {
        return block.timestamp >= opensAt() && !paused();
    }

    function ready() external view returns (bool) {
        return isOpen() && profileChosen && RewardPool(registry.module(0)).endowed()
            && ILaunchHook(registry.market()).fees() == address(fees());
    }

    function price() public view returns (uint256) {
        return priceAt(sold);
    }

    function priceAt(uint256 sales) public view returns (uint256 p) {
        uint256 elapsed = block.timestamp > opensAt() ? block.timestamp - opensAt() : 0;
        (uint256 start, uint256 floor, uint256 ceiling, uint256 decay, uint256 target) = profileParams(profile);
        int256 ahead = int256(sales * 1 ether) - int256(elapsed * target * 1 ether / 1 hours);
        int256 exponent;
        if (ahead >= 0) {
            exponent = wadLn(int256(1 ether + params().get(Params.Key.PriceStepBps) * 1e14)) * ahead / 1 ether;
        } else {
            exponent = wadLn(int256(1 ether - decay * 1e14)) * (-ahead) / int256(target) / 1 ether;
        }
        if (exponent > 10 ether) exponent = 10 ether;
        if (exponent < -10 ether) exponent = -10 ether;
        uint256 daysPrice = start * uint256(wadExp(exponent)) / 1 ether;
        if (daysPrice < floor) daysPrice = floor;
        if (daysPrice > ceiling) daysPrice = ceiling;
        p = Economy(registry.module(10)).averageDaily() * daysPrice / 1 ether;
        (uint256 low, uint256 high) = priceBounds();
        if (p < low) p = low;
        if (p > high) p = high;
    }

    /// @notice Each pack pays its position on the curve. There is no wallet, daily, or global quantity cap.
    function quote(uint256 count_) public view returns (uint256 total) {
        if (count_ == 0) revert InvalidValue();
        (, uint256 ceiling) = priceBounds();
        for (uint256 i; i < count_; ++i) {
            uint256 p = priceAt(sold + i);
            if (p == ceiling) return total + (count_ - i) * ceiling;
            total += p;
        }
    }

    function openPack(uint256 n) external payable nonReentrant returns (uint256 id) {
        if (msg.value != 0) revert InvalidValue();
        return _buy(msg.sender, msg.sender, n, type(uint256).max, false);
    }

    function buyPackFor(address recipient) external nonReentrant returns (uint256) {
        return _buy(msg.sender, recipient, 1, type(uint256).max, false);
    }

    function buyPacksFor(address recipient, uint256 n, uint256 maxCost) external nonReentrant returns (uint256) {
        return _buy(msg.sender, recipient, n, maxCost, false);
    }

    function buyWithETH(address recipient, uint256 n, uint256 minTokens, uint256 maxCost)
        external
        payable
        nonReentrant
        returns (uint256 id)
    {
        if (!isOpen()) revert TooEarly();
        _requireReady();
        uint256 received = fees().zapBuy{value: msg.value}(minTokens, address(this));
        uint256 cost = quote(n);
        if (received < cost) revert InsufficientBalance();
        id = _buy(address(this), recipient, n, maxCost, true);
        if (received > cost) IERC20(registry.token()).safeTransfer(msg.sender, received - cost);
    }

    function _buy(address payer, address recipient, uint256 n, uint256 maximum, bool funded)
        private
        returns (uint256 id)
    {
        if (!isOpen()) revert TooEarly();
        if (recipient == address(0)) revert InvalidAddress();
        _requireReady();
        uint256 cost = quote(n);
        if (cost > maximum) revert InvalidValue();
        sold += n;
        farm().register(recipient);
        farm().paidPackBought(recipient, n, cost);
        id = _commit(recipient, n, false);
        IERC20 t = IERC20(registry.token());
        uint256 before_ = t.balanceOf(address(fees()));
        if (funded) t.safeTransfer(address(fees()), cost);
        else t.safeTransferFrom(payer, address(fees()), cost);
        if (t.balanceOf(address(fees())) - before_ != cost) revert InvalidValue();
        fees().routeTokens(cost);
    }

    function tokenPack(address p) external nonReentrant returns (uint256 id) {
        if (msg.sender != address(farm())) revert Unauthorized();
        if (paused() || block.timestamp < opensAt()) revert TooEarly();
        _requireReady();
        sold++;
        id = _commit(p, 1, false);
    }

    function _requireReady() private view {
        if (!profileChosen) revert NotConfigured();
        if (!RewardPool(registry.module(0)).endowed() || ILaunchHook(registry.market()).fees() != address(fees())) {
            revert NotConfigured();
        }
    }

    function rewardPack(address p) external nonReentrant returns (uint256 id) {
        if (msg.sender != season()) revert Unauthorized();
        id = _commit(p, 1, true);
    }

    function _commit(address p, uint256 n, bool guaranteed) private returns (uint256 id) {
        id = nextId++;
        uint64 target = uint64(ChainClock.number() + 2);
        commits[id] = Commit(p, target, n, 0, false, guaranteed, bytes32(0), false, false);
        emit PackCommitted(id, p, n, target, guaranteed);
    }

    /// @notice Preserve entropy even when inventory is full. Exactly one credit per receipt.
    function captureEntropy(uint256 id) external nonReentrant {
        _capture(id, msg.sender);
    }

    function _capture(uint256 id, address keeper) private returns (bool) {
        uint256 startGas = gasleft();
        Commit storage c = commits[id];
        if (c.player == address(0)) revert InvalidValue();
        if (c.fixedSeed) return true;
        if (ChainClock.number() <= c.target) revert TooEarly();
        bytes32 h = ChainClock.hash(c.target);
        if (h == bytes32(0)) {
            if (ChainClock.number() <= uint256(c.target) + 256) revert NotConfigured();
            _rearm(id, c);
            return false;
        }
        c.seed = keccak256(abi.encode(h, address(this), id));
        c.fixedSeed = true;
        fees().payWork(keeper, Params.Key.EntropyBounty, 1, startGas - gasleft());
        return true;
    }

    event PackRearmed(uint256 indexed id, uint256 target);

    function rearm(uint256 id) external {
        Commit storage c = commits[id];
        if (c.player == address(0)) revert InvalidValue();
        if (c.fixedSeed || ChainClock.number() <= uint256(c.target) + 256) revert TooEarly();
        _rearm(id, c);
    }

    function _rearm(uint256 id, Commit storage c) private {
        c.target = uint64(ChainClock.number() + 2);
        emit PackRearmed(id, c.target);
    }

    /// @notice Opening is bounded; unopen packs stay claimable while the player makes inventory space.
    function resolve(uint256 id, uint256 n) external nonReentrant {
        Commit storage c = commits[id];
        if (c.player == address(0) || n == 0 || n > 8 || n > c.count - c.opened) revert InvalidValue();
        if (ChainClock.number() <= c.target) revert TooEarly();
        if (!_capture(id, msg.sender)) return;
        if (items().inventory(c.player) + n * 3 > items().capacity(c.player)) revert InsufficientBalance();
        c.mythic = farm().level(c.player) >= 10;
        uint256 first = c.opened * 3;
        c.opened += n;
        for (uint256 i; i < n * 3; ++i) {
            uint8 k;
            uint8 r;
            (k, r) = ItemMath.draw(keccak256(abi.encode(c.seed, first + i)), c.mythic, false);
            if (c.guaranteed && i % 3 == 0 && r < 1) r = 1;
            items().mint(c.player, k, r, c.guaranteed);
        }
        emit PackOpened(id, n, c.expired);
    }
}
