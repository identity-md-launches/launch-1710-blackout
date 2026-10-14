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

interface IFeatureFlags {
    function enabled(uint256) external view returns (bool);
}

interface IPurchasePause {
    function paused() external view returns (bool);
}

/// @notice Eight weekly token billboard auctions. Immutable, soulbound advertising rights.
contract Billboards is GameModule, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Billboard {
        address bidder;
        uint256 bid;
        string text;
        string handle;
        bool settled;
    }
    mapping(uint256 => mapping(uint256 => Billboard)) private boards;
    mapping(address => uint256) public refund;
    uint256 public escrow;
    event BillboardBid(
        uint256 indexed week, uint256 indexed district, address bidder, uint256 amount, string text, string handle
    );
    event BillboardSettled(uint256 indexed week, uint256 indexed district, uint256 amount);
    constructor(address r) GameModule(r) {}

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

    function _safeText(string calldata text_, string calldata handle_) private pure {
        bytes memory t = bytes(text_);
        bytes memory h = bytes(handle_);
        if (t.length == 0 || t.length > 32 || h.length == 0 || h.length > 15) revert InvalidValue();
        for (uint256 i; i < t.length; ++i) {
            bytes1 c = t[i];
            if (!((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x20
                        || c == 0x21 || c == 0x2d || c == 0x5f)) {
                revert InvalidValue();
            }
        }
        for (uint256 i; i < h.length; ++i) {
            bytes1 c = h[i];
            if (!((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x5f)) {
                revert InvalidValue();
            }
        }
    }

    /// @notice Bid this week for next week's display. Losing bids are pull-refunded.
    function bidBillboard(uint256 d, uint256 amount, string calldata text_, string calldata handle_)
        external
        nonReentrant
    {
        if (!IFeatureFlags(registry.module(12)).enabled(5)) revert FeatureDisabled();
        if (d >= 8) revert InvalidValue();
        _safeText(text_, handle_);
        uint256 w = week() + 1;
        Billboard storage b = boards[w][d];
        uint256 minimum = Math.max(Economy(registry.module(10)).averageDaily() / 4, b.bid + b.bid / 20 + 1);
        if (amount < minimum) revert InvalidValue();
        if (b.bid != 0) refund[b.bidder] += b.bid;
        b.bidder = msg.sender;
        b.bid = amount;
        b.text = text_;
        b.handle = handle_;
        _take(msg.sender, amount);
        emit BillboardBid(w, d, msg.sender, amount, text_, handle_);
    }

    function settleBillboard(uint256 w, uint256 d) external nonReentrant {
        if (d >= 8 || w > week()) revert TooEarly();
        Billboard storage b = boards[w][d];
        if (b.settled || b.bid == 0) revert InvalidValue();
        b.settled = true;
        _pool(b.bid);
        emit BillboardSettled(w, d, b.bid);
    }

    function billboard(uint256 w, uint256 d) external view returns (Billboard memory) {
        if (d >= 8) revert InvalidValue();
        return boards[w][d];
    }

    function withdrawRefund() external nonReentrant {
        uint256 amount = refund[msg.sender];
        if (amount == 0) revert InsufficientBalance();
        refund[msg.sender] = 0;
        escrow -= amount;
        IERC20(registry.token()).safeTransfer(msg.sender, amount);
    }
}
