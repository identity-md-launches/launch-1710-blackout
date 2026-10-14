// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IV4PoolManager, PoolKey, SwapParams} from "./interfaces/IV4.sol";
import "./lib/Errors.sol";

interface IStandardTwap {
    /// @notice Raw game-token units per ETH, from the specified pool; an actual >=30-minute observation window.
    function consult(bytes32 poolId) external view returns (uint256 tokensPerETH, uint256 updatedAt, uint256 window);
}

/// @notice Buy adapter for an EXISTING standard IMD hook. It never replaces that hook or adds a surcharge.
/// @dev The immutable oracle is an external deployment input; launch must verify its exact pool and observation implementation.
contract StandardAdapter is ReentrancyGuard {
    IV4PoolManager public immutable manager;
    IERC20 public immutable token;
    IStandardTwap public immutable oracle;
    address public immutable fees;
    address public immutable standardHook;
    int24 public immutable tickSpacing;
    bytes32 public immutable poolId;
    bool private buying;

    constructor(address manager_, address token_, address oracle_, address fees_, address hook_, int24 spacing_) {
        if (
            manager_ == address(0) || token_ == address(0) || oracle_ == address(0) || fees_ == address(0)
                || hook_ == address(0) || spacing_ <= 0 || spacing_ > 32767
        ) revert InvalidValue();
        manager = IV4PoolManager(manager_);
        token = IERC20(token_);
        oracle = IStandardTwap(oracle_);
        fees = fees_;
        standardHook = hook_;
        tickSpacing = spacing_;
        poolId = keccak256(abi.encode(PoolKey(address(0), token_, 12500, spacing_, hook_)));
    }

    function key() public view returns (PoolKey memory) {
        return PoolKey(address(0), address(token), 12500, tickSpacing, standardHook);
    }

    function quote(uint256 ethAmount) public view returns (uint256) {
        (uint256 rate, uint256 at, uint256 window) = oracle.consult(poolId);
        if (rate == 0 || rate > 1e40 || window < 30 minutes || at > block.timestamp || block.timestamp - at > 5 minutes)
        {
            revert NotConfigured();
        }
        return Math.mulDiv(ethAmount, rate, 1 ether);
    }

    function buy(uint256 minOut, address recipient) external payable nonReentrant returns (uint256 received) {
        if (msg.sender != fees || recipient == address(0) || msg.value == 0 || minOut == 0) revert Unauthorized();
        quote(msg.value);
        buying = true;
        uint256 before_ = token.balanceOf(recipient);
        manager.unlock(abi.encode(msg.value, minOut, recipient));
        buying = false;
        received = token.balanceOf(recipient) - before_;
        if (received < minOut) revert InsufficientBalance();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(manager) || !buying) revert Unauthorized();
        (uint256 input, uint256 minimum, address recipient) = abi.decode(data, (uint256, uint256, address));
        int256 delta = manager.swap(key(), SwapParams(true, -int256(input), 4295128740), "");
        int128 ethDelta = int128(delta >> 128);
        int128 out = int128(delta);
        if (ethDelta >= 0 || uint256(-int256(ethDelta)) != input || out <= 0 || uint256(uint128(out)) < minimum) {
            revert InsufficientBalance();
        }
        manager.settle{value: input}();
        manager.take(address(token), recipient, uint256(uint128(out)));
        return abi.encode(uint256(uint128(out)));
    }
}
