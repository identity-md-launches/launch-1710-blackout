// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GameModule} from "./lib/GameModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/Errors.sol";
import {Params} from "./Params.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RewardPool is GameModule, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public reserved;

    uint256 public dripStart;
    uint256 public dripPeriod;
    bool public endowed;
    uint256 public otherInflow; // Non-endowment funds received before funding, never counted twice.
    event Endowed(address indexed caller, uint256 amount, uint256 start, uint256 period);
    event Donated(address indexed sender, uint256 amount);
    event Reserved(uint256 amount);
    event Recycled(uint256 amount);
    event Paid(address indexed to, uint256 amount);

    constructor(address registry_) GameModule(registry_) {}

    function token() public view returns (IERC20) {
        return IERC20(registry.token());
    }

    function rewards() public view returns (address) {
        return registry.module(1);
    }

    function params() public view returns (Params) {
        return Params(registry.params());
    }

    function endowment() public view returns (uint256) {
        return registry.endowment();
    }
    modifier onlyRewards() {
        if (msg.sender != rewards()) revert Unauthorized();
        _;
    }

    /// @notice Locked principal is never reservable, including before the funding transaction.
    function lockedEndowment() public view returns (uint256) {
        if (!endowed) return endowment();
        if (endowment() == 0 || block.timestamp >= dripStart + dripPeriod) return 0;
        return endowment() - Math.mulDiv(endowment(), block.timestamp - dripStart, dripPeriod);
    }

    function available() public view returns (uint256) {
        if (!endowed && endowment() != 0) return 0;
        uint256 balance = token().balanceOf(address(this));
        uint256 excluded = reserved + lockedEndowment();
        return balance > excluded ? balance - excluded : 0;
    }

    /// @notice Start the drip only after the predicted pool has received its full principal.
    /// No caller allowance or swarm funding fallback exists; ordinary inflows are excluded.
    function fundEndowment() external nonReentrant {
        uint256 principal = endowment();
        if (endowed || principal == 0) revert AlreadyDone();
        uint256 balance = token().balanceOf(address(this));
        if (balance < otherInflow || balance - otherInflow < principal) revert InsufficientBalance();
        _startDrip();
    }

    /// @dev The immutable core/router measure the actual balance delta before reporting ordinary inflows.
    function recordInflow(uint256 amount) external {
        if (msg.sender != registry.module(2) && msg.sender != registry.module(6)) revert Unauthorized();
        if (!endowed) otherInflow += amount;
    }

    function _startDrip() private {
        uint256 period = params().get(Params.Key.DripPeriod);
        if (period < 14 days || period > 56 days) revert InvalidValue();
        endowed = true;
        dripStart = block.timestamp;
        dripPeriod = period; // Later Params changes cannot accelerate an existing schedule.
        emit Endowed(msg.sender, endowment(), dripStart, period);
    }

    function donate(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidValue();
        uint256 before_ = token().balanceOf(address(this));
        token().safeTransferFrom(msg.sender, address(this), amount);
        if (token().balanceOf(address(this)) - before_ != amount) revert InvalidValue();
        if (!endowed) otherInflow += amount;
        emit Donated(msg.sender, amount);
    }

    function reserve(uint256 amount) external onlyRewards {
        if (amount > available()) revert InsufficientBalance();
        reserved += amount;
        emit Reserved(amount);
    }

    function recycle(uint256 amount) external onlyRewards {
        reserved -= amount;
        emit Recycled(amount);
    }

    function pay(address to, uint256 amount) external onlyRewards nonReentrant {
        if (to == address(0) || to == address(this)) revert InvalidAddress();
        reserved -= amount;
        token().safeTransfer(to, amount);
        emit Paid(to, amount);
    }
}
