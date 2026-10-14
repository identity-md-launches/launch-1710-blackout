// SPDX-License-Identifier: MIT
pragma solidity =0.8.26 ^0.8.20;

// vendor/openzeppelin/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success,) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(address target, bool success, bytes memory returndata)
        internal
        view
        returns (bytes memory)
    {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// src/lib/Errors.sol

error Unauthorized();
error InvalidAddress();
error InvalidValue();
error TooEarly();
error AlreadyDone();
error NotConfigured();
error CatchUpRequired();
error InsufficientBalance();
error InvalidProof();
error TransferFailed();
error FeatureDisabled();

// vendor/openzeppelin/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// vendor/openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// src/interfaces/IGameRegistry.sol

interface IGameRegistry {
    function module(uint256 role) external view returns (address);
    function registeredModule(uint256 role) external view returns (address);
    function token() external view returns (address);
    function params() external view returns (address);
    function market() external view returns (address);
    function launchTime() external view returns (uint256);
    function freeRoot() external view returns (bytes32);
    function starterRoot() external view returns (bytes32);
    function snapshotBlock() external view returns (uint256);
    function endowment() external view returns (uint256);
}

// src/interfaces/ILaunchHook.sol

interface ILaunchHook {
    function initializedAt() external view returns (uint256);
    function fees() external view returns (address);
}

// src/interfaces/IV4.sol

// ABI subset of Uniswap v4-core at 46c6834698c48bc4a463a86d8420f4eb1d7f3b75.
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

interface IV4PoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData) external returns (int256 delta);
    function take(address currency, address to, uint256 amount) external;
    function sync(address currency) external;
    function settle() external payable returns (uint256);
    function extsload(bytes32 slot) external view returns (bytes32);
}

// vendor/openzeppelin/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Muldiv operation overflow.
     */
    error MathOverflowedMulDiv();

    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            return a / b;
        }

        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0.
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            if (denominator <= prod1) {
                revert MathOverflowedMulDiv();
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

// src/lib/ModuleCode.sol

/// @notice Generated by tools/pin_module_code.py. Exact creation-code pins of the fourteen modules, no links.
/// @dev Both artifact directories use the unchanged repository foundry.toml:
/// solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none. The two pins must be equal.
library ModuleCode {
    function launchHash(uint256 role) internal pure returns (bytes32) {
        if (role == 0) return 0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de; // RewardPool
        if (role == 1) return 0xfa1a4087722916aeefae66aaf3400299a5e4cb8f4fc8e516a17cec7754e07506; // FarmRewards
        if (role == 2) return 0xc390b07ef7a9ab65bef3a1ec3b39c1a16e117543c9565fedc9342526aa57aa47; // FarmCore
        if (role == 3) return 0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76; // FarmItems
        if (role == 4) return 0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a; // PackSale
        if (role == 5) return 0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90; // StarterClaim
        if (role == 6) return 0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af; // FeeRouter
        if (role == 7) return 0x931bdfaeeacadb7c8014ce1411671d0045013c2b373d95bbf0bb83dfce0b7c74; // GridOperator
        if (role == 8) return 0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83; // Season
        if (role == 9) return 0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c; // FarmEngine
        if (role == 10) return 0x105f9f29d79579fa33ff8e11d4d86847dd7d9f59bd681500553a3844db50ccc9; // Economy
        if (role == 11) return 0x31242676dd3a728a2ad32a5cb300166020e87831b0f547756fa0bab88cedea38; // Enhancement
        if (role == 12) return 0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2; // Civic
        if (role == 13) return 0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60; // Billboards
        return bytes32(0);
    }

    function repoHash(uint256 role) internal pure returns (bytes32) {
        if (role == 0) return 0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de; // RewardPool
        if (role == 1) return 0xfa1a4087722916aeefae66aaf3400299a5e4cb8f4fc8e516a17cec7754e07506; // FarmRewards
        if (role == 2) return 0xc390b07ef7a9ab65bef3a1ec3b39c1a16e117543c9565fedc9342526aa57aa47; // FarmCore
        if (role == 3) return 0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76; // FarmItems
        if (role == 4) return 0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a; // PackSale
        if (role == 5) return 0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90; // StarterClaim
        if (role == 6) return 0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af; // FeeRouter
        if (role == 7) return 0x931bdfaeeacadb7c8014ce1411671d0045013c2b373d95bbf0bb83dfce0b7c74; // GridOperator
        if (role == 8) return 0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83; // Season
        if (role == 9) return 0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c; // FarmEngine
        if (role == 10) return 0x105f9f29d79579fa33ff8e11d4d86847dd7d9f59bd681500553a3844db50ccc9; // Economy
        if (role == 11) return 0x31242676dd3a728a2ad32a5cb300166020e87831b0f547756fa0bab88cedea38; // Enhancement
        if (role == 12) return 0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2; // Civic
        if (role == 13) return 0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60; // Billboards
        return bytes32(0);
    }

    /// @notice True when `h` is one of the two pinned creation-code hashes of `role`.
    function matches(uint256 role, bytes32 h) internal pure returns (bool) {
        if (h == bytes32(0) || role >= 14) return false;
        return h == launchHash(role) || h == repoHash(role);
    }
}

// vendor/openzeppelin/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// src/lib/Robinhood.sol

/// @notice BLACKOUT v3.14 protocol endpoints, pinned to Robinhood Chain (4663).
/// @dev Never pass these literal addresses as launch constructor words.
library Robinhood {
    address internal constant PROJECT_FACTORY = 0x9C9D2FCB75c2C132C0AC0C42DF3819A42347265e;
    address internal constant PROJECT_REGISTRY = 0xF52bbE066B7Ad2d28C2195D066Ea08DCbcA88406;
    address internal constant INTAKE = 0xa43e6F75ee006411F79Ac1C84120606C2330DE82;
    address internal constant DELIVERY = 0xCE0E6a670AA75E161d02aca3C7F00B94cA428CCb;
    address internal constant ATTESTER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    address internal constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address internal constant LAUNCH_FACTORY = 0xA25B02A1e93903b790E6aaf7dA1b8B8d50294645;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
}

// src/Params.sol

/// @notice Numeric governance only: immutable swarm, no owner, upgrade or asset authority.
contract Params {
    enum Key {
        EmissionBps,
        TariffBps,
        PriceStepBps,
        PriceFloor,
        PriceCeiling,
        PriceStart,
        DemandTarget,
        PriceDecayBps,
        RepairBps,
        LobbyKBps,
        LobbyMinWeight,
        FullSetBps,
        ComputePairBps,
        TripleCoreBps,
        AirflowBps,
        ElectricityPairBps,
        OffgridBps,
        RareSetBps,
        EpicSetBps,
        LegendarySetBps,
        MythicSetBps,
        SetCapBps,
        BuyBatch,
        SlippageBps,
        SellHourBps,
        SellDayBps,
        SellDeviationBps,
        Bounty,
        ExpansionPrice,
        MergePrice,
        OverclockPrice,
        PositiveWeight,
        DripPeriod,
        MeasureBounty,
        CreditBounty,
        AuditBounty,
        BuyBounty,
        EntropyBounty,
        SeasonScoreBounty,
        SeasonBounty,
        HeartbeatBps,
        KeeperGasPrice,
        HeartbeatCap,
        AuditHashThreshold,
        RepairHours
    }
    address public immutable swarmWallet;
    mapping(Key => uint256) public get;
    mapping(Key => uint256) public lastChanged;
    event ParamChanged(Key indexed key, uint256 oldValue, uint256 newValue, string letter);

    constructor(address swarm_, uint256 heartbeatBps_, uint256 heartbeatCap_) {
        if (swarm_ == address(0)) revert InvalidAddress();
        if (heartbeatBps_ < 200 || heartbeatBps_ > 5000) revert InvalidValue();
        if (heartbeatCap_ != 1 ether) revert InvalidValue();
        swarmWallet = swarm_;
        uint256[45] memory defaults = [
            uint256(350),
            1500,
            100,
            0.006 ether,
            0.03 ether,
            0.01 ether,
            20,
            200,
            250,
            5000,
            4000,
            1500,
            1000,
            2000,
            500,
            1500,
            2000,
            500,
            1000,
            2000,
            3000,
            10000,
            0.5 ether,
            150,
            500,
            400,
            5000,
            0.001 ether,
            100 ether,
            50 ether,
            100 ether,
            2500,
            42 days,
            0.00006 ether,
            0.00004 ether,
            0.00001 ether,
            0.00015 ether,
            0.00001 ether,
            0.00001 ether,
            0.00004 ether,
            heartbeatBps_,
            50_000_000,
            heartbeatCap_,
            100_000,
            6 ether
        ];
        for (uint256 i; i < defaults.length; ++i) {
            get[Key(i)] = defaults[i];
            lastChanged[Key(i)] = block.timestamp;
        }
    }

    function bounds(Key k) public pure returns (uint256, uint256) {
        if (k == Key.EmissionBps) return (200, 600);
        if (k == Key.TariffBps) return (1000, 3000);
        if (k == Key.PriceStepBps) return (50, 200);
        if (k == Key.PriceFloor) return (0.004 ether, 0.01 ether);
        if (k == Key.PriceCeiling) return (0.02 ether, 0.05 ether);
        if (k == Key.PriceStart) return (0.008 ether, 0.015 ether);
        if (k == Key.DemandTarget) return (10, 40);
        if (k == Key.PriceDecayBps) return (100, 400);
        if (k == Key.RepairBps) return (150, 400);
        if (k == Key.LobbyKBps) return (2500, 10000);
        if (k == Key.LobbyMinWeight) return (4000, 7000);
        if (k == Key.FullSetBps) return (500, 1500);
        if (k == Key.ComputePairBps) return (500, 1000);
        if (k == Key.TripleCoreBps) return (1000, 2000);
        if (k == Key.AirflowBps) return (250, 500);
        if (k == Key.ElectricityPairBps) return (500, 1500);
        if (k == Key.OffgridBps) return (1000, 2000);
        if (k == Key.RareSetBps) return (250, 500);
        if (k == Key.EpicSetBps) return (500, 1000);
        if (k == Key.LegendarySetBps) return (1000, 2000);
        if (k == Key.MythicSetBps) return (1500, 3000);
        if (k == Key.SetCapBps) return (8000, 10000);
        if (k == Key.RepairHours) return (4 ether, 8 ether);
        if (k == Key.BuyBatch) return (0.1 ether, 1 ether);
        if (k == Key.SlippageBps) return (10, 150);
        if (k == Key.SellHourBps) return (200, 600);
        if (k == Key.SellDayBps) return (100, 500);
        if (k == Key.SellDeviationBps) return (2000, 5000);
        if (k == Key.Bounty) return (0.0005 ether, 0.003 ether);
        if (k == Key.ExpansionPrice) return (50 ether, 500 ether);
        if (k == Key.MergePrice) return (25 ether, 250 ether);
        if (k == Key.OverclockPrice) return (50 ether, 500 ether);
        if (k == Key.PositiveWeight) return (2000, 5000);
        if (k == Key.DripPeriod) return (14 days, 56 days);
        if (k == Key.MeasureBounty) return (0.00001 ether, 0.0002 ether);
        if (k == Key.CreditBounty) return (0.000003 ether, 0.00005 ether);
        if (k == Key.AuditBounty) return (0.000001 ether, 0.00003 ether);
        if (k == Key.BuyBounty) return (0.000005 ether, 0.0003 ether);
        if (k == Key.EntropyBounty) return (0.000002 ether, 0.00005 ether);
        if (k == Key.SeasonScoreBounty) return (0.000001 ether, 0.00002 ether);
        if (k == Key.SeasonBounty) return (0.00001 ether, 0.0002 ether);
        if (k == Key.HeartbeatBps) return (200, 5000);
        if (k == Key.HeartbeatCap) return (1 ether, 1 ether);
        if (k == Key.AuditHashThreshold) return (10_000, 10_000_000);
        return (1_000_000, 100_000_000);
    }

    function set(Key k, uint256 next, string calldata letter) external {
        if (msg.sender != swarmWallet) revert Unauthorized();
        (uint256 lo, uint256 hi) = bounds(k);
        uint256 old = get[k];
        uint256 delta = next > old ? next - old : old - next;
        if (
            next < lo || next > hi || delta == 0 || delta > old / 10 || bytes(letter).length == 0
                || bytes(letter).length > 1024
        ) {
            revert InvalidValue();
        }
        if (block.timestamp < lastChanged[k] + 1 days) revert TooEarly();
        get[k] = next;
        lastChanged[k] = block.timestamp;
        emit ParamChanged(k, old, next, letter);
    }
}

// vendor/openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silents catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We cannot use {Address-functionCall} here since this should return false
        // and not revert is the subcall reverts.

        (bool success, bytes memory returndata) = address(token).call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool))) && address(token).code.length > 0;
    }
}

// src/GameRegistry.sol

interface IApplicationFactory {
    function predictContract(uint64 launchNumber, uint256 index, bytes calldata initCode)
        external
        view
        returns (address);
}

/// @notice No owner and no replacements. Enrollment proves canonical factory deployment of exact initcode.
/// @dev v3.9: each role accepts the creation code of either pinned toolchain (the IMD verifier's build and
/// the repository's build of the same source); see ModuleCode.
contract GameRegistry is IGameRegistry {
    address public immutable token;
    address public immutable params;
    address public immutable market;

    bytes32 public immutable starterRoot;
    bytes32 public immutable freeRoot;
    uint256 public immutable snapshotBlock;
    uint256 public immutable endowment;
    IApplicationFactory public constant factory = IApplicationFactory(Robinhood.PROJECT_FACTORY);
    mapping(uint256 => address) private modules;
    uint256 public registered;
    event Registered(uint256 indexed role, address indexed module, uint64 launchNumber, uint256 index);

    constructor(
        address token_,
        address params_,
        address market_,
        bytes32 root_,
        bytes32 freeRoot_,
        uint256 snapshot_,
        uint256 endowment_
    ) {
        if (
            token_ == address(0) || params_ == address(0) || market_ == address(0) || freeRoot_ == bytes32(0)
                || root_ == bytes32(0) || snapshot_ == 0 || endowment_ > 250_000_000 ether
        ) revert InvalidValue();
        token = token_;
        params = params_;
        market = market_;
        starterRoot = root_;
        freeRoot = freeRoot_;
        snapshotBlock = snapshot_;
        endowment = endowment_;
    }

    function launchTime() external view returns (uint256) {
        uint256 t = ILaunchHook(market).initializedAt();
        if (t == 0) revert NotConfigured();
        return t;
    }

    function module(uint256 role) external view returns (address result) {
        result = modules[role];
        if (result == address(0)) revert NotConfigured();
    }

    function registeredModule(uint256 role) external view returns (address) {
        return modules[role];
    }

    /// @notice The launch toolchain's pin (IMD verifier settings) for a role.
    function creationCodeHash(uint256 role) external pure returns (bytes32) {
        if (role >= 14) revert InvalidValue();
        return ModuleCode.launchHash(role);
    }

    /// @notice Both pins for a role: the launch toolchain's and the repository toolchain's.
    function creationCodeHashes(uint256 role) external pure returns (bytes32 launch, bytes32 repo) {
        if (role >= 14) revert InvalidValue();
        return (ModuleCode.launchHash(role), ModuleCode.repoHash(role));
    }

    function acceptsCreationCode(uint256 role, bytes32 codeHash) external pure returns (bool) {
        return role < 14 && ModuleCode.matches(role, codeHash);
    }

    /// @dev Runtime hash alone cannot prove safe initial storage. CREATE2 over exact initcode can.
    function register(uint256 role, uint64 launchNumber, uint256 index, bytes calldata creationCode)
        external
        returns (address deployed)
    {
        if (role >= 14 || index >= 8 || launchNumber == 0 || !ModuleCode.matches(role, keccak256(creationCode))) {
            revert InvalidValue();
        }
        if (modules[role] != address(0)) revert AlreadyDone();
        deployed = factory.predictContract(launchNumber, index, bytes.concat(creationCode, abi.encode(address(this))));
        if (deployed.code.length == 0) revert NotConfigured();
        modules[role] = deployed;
        registered++;
        emit Registered(role, deployed, launchNumber, index);
    }
}

// src/V4Market.sol

interface IHookDesk {
    function registry() external view returns (address);
}

interface IHookParams {
    function get(uint8 key) external view returns (uint256);
}

interface IHookRouter {
    function registry() external view returns (address);
    function token() external view returns (address);
    function market() external view returns (address);
    function params() external view returns (address);
    function depositBaseFee() external payable;
    function depositSellTax() external payable;
    function depositLaunchTax() external payable;
}

/// @notice Immutable ETH/token v4 hook + buy adapter, selected as the IMD launch pool's hook.
/// @dev v3.9 fee model. The pool carries the platform LP fee 12500 (1.25%): LaunchFactory.claimFees pays 1%
/// of swap volume to the paying wallet (the team's swap income) and 0.25% to the IMD network. The hook adds
/// no network share of its own. After the stepped launch tax window it adds exactly PROJECT_BPS (1%) to
/// rewards on every swap, plus the progressive sell surcharge on sells. The LaunchFactory initializes the
/// pool, so afterInitialize authenticates its sender as `launcher` ($factory). No launch number is known at
/// construction: the registry is proven at bind time. The hook has no owner.
/// v3.18 (import audit a3749636, medium): a buy's launch tax and 1% share are an ETH charge on the specified
/// input, which v4 only lets a hook set in beforeSwap, before the pool reports how much it consumed. A buy whose
/// sqrtPriceLimitX96 stops the swap early would therefore pay tax on ETH the pool never took. Buys are accepted
/// only at the extreme price bound (BUY_PRICE_LIMIT), where an exact-input swap consumes its whole input, and
/// afterSwap additionally reverts unless the pool consumed exactly the taxed input, so no buyer ever pays
/// tax on unconsumed ETH. Routers already send the extreme bound and protect the buyer with a minimum output.
contract V4Market is ReentrancyGuard {
    using SafeERC20 for IERC20;
    bool private selling;
    /// @notice Hook share added to every swap after the launch window, entirely for reward buys.
    uint256 public constant PROJECT_BPS = 100;
    /// @notice Hard cap of the hook's total sell charge (base plus progressive surcharge).
    uint256 public constant TOTAL_CAP_BPS = 1500;
    /// @notice The only sqrtPriceLimitX96 a buy may carry: TickMath.MIN_SQRT_PRICE + 1 (v4-core), the extreme
    /// bound an exact-input ETH -> token swap runs to, so the pool consumes the whole taxed input.
    uint160 public constant BUY_PRICE_LIMIT = 4295128740;
    /// @notice A buy carried a price limit other than BUY_PRICE_LIMIT; it could have stopped early and paid tax on
    /// ETH the pool did not consume. Send the extreme bound and a minimum output instead.
    error PriceLimitedBuy(uint160 sqrtPriceLimitX96);
    /// @notice The pool consumed less than the taxed input of a buy (liquidity exhausted); the swap is refused.
    error PartialFill(uint256 consumed, uint256 expected);
    uint160 public constant HOOK_FLAGS = 0x10cc; // afterInitialize, before/afterSwap and both swap deltas
    IV4PoolManager public immutable manager;
    address public immutable token;
    address public immutable launcher;
    bytes32 public immutable gameConfigHash;
    IApplicationFactory public constant applicationFactory = IApplicationFactory(Robinhood.PROJECT_FACTORY);
    IHookParams public params;
    IHookRouter public fees;
    uint256 public heldBase;
    uint256 public heldSellTax;
    uint256 public heldLaunchTax;
    /// @notice Launch protection, fixed in bytecode and anchored to the pool's one-time initialization.
    uint256 public constant LAUNCH_TAX_BPS = 9000;
    uint256 public constant LAUNCH_TAX_DECAY = 30 minutes;
    uint256 public constant LAUNCH_TAX_STEP = 10 minutes;
    event Bound(address indexed router, address indexed params);
    event FeesFlushed(uint256 base, uint256 sellTax);
    event LaunchTaxFlushed(uint256 amount);
    event LaunchTax(address indexed sender, uint256 ethInput, uint256 taxBps, uint256 launchTax);
    uint24 public immutable poolFee;
    int24 public immutable tickSpacing;
    bytes32 public immutable poolId;

    struct Volume {
        uint64 period;
        uint192 sells;
        uint192 buys;
    }
    Volume[12] private shortVolumes;
    Volume[24] private longVolumes;

    struct Observation {
        uint64 minute;
        uint256 cumulative;
    }
    Observation[32] private observations;
    uint256 public initializedAt;
    uint256 public updatedAt;
    uint256 public cumulative;
    uint256 public lastPrice;
    uint256 public storedFeeWad = 100 ether;
    uint256 public feeTimestamp;
    bool private buying;
    event PriceObserved(uint256 timestamp, uint256 tokensPerETH);
    event SellFee(
        address indexed sender,
        uint256 ethOutput,
        uint256 feeBps,
        uint256 hourImbalance,
        uint256 dayImbalance,
        uint256 deviation
    );

    uint24 public constant POOL_FEE = 12500;
    address public immutable desk;

    /// @param launcher_ the LaunchFactory ($factory): it initializes the pool inside the launch transaction.
    /// @param desk_ the already-deployed SwarmDesk bootstrap; the canonical game is the one it binds to.
    /// @param gameConfigHash_ keccak256(abi.encode(starterRoot, freeRoot, snapshotBlock, endowment)).
    constructor(
        address manager_,
        address token_,
        uint24 fee_,
        int24 spacing_,
        address launcher_,
        address desk_,
        bytes32 gameConfigHash_
    ) {
        if (
            gameConfigHash_ == bytes32(0) || launcher_ == address(0) || manager_ == address(0) || token_ == address(0)
                || desk_ == address(0) || spacing_ <= 0 || spacing_ > 32767 || fee_ != POOL_FEE
        ) revert InvalidValue();
        gameConfigHash = gameConfigHash_;
        launcher = launcher_;
        manager = IV4PoolManager(manager_);
        token = token_;
        desk = desk_;
        poolFee = fee_;
        tickSpacing = spacing_;
        poolId = keccak256(abi.encode(PoolKey(address(0), token_, fee_, spacing_, address(this))));
        _validateHookAddress();
    }

    /// @notice Permissionless, one-time binding with bind-time proofs (v3.8). The caller supplies the
    /// registry's recorded factory coordinates. The registry must be the factory's CREATE2 result for its
    /// own exact initcode, its frozen configuration must match the commitment, its Params must be the
    /// Params of the registry the Desk bound to (the Desk proved that Params against pinned code and the
    /// factory), Params must point at the Desk, and in the strict path the Desk must have bound to it.
    function bindFeeRouter(address router, uint64 registryLaunch, uint256 registryIndex) external nonReentrant {
        if (address(fees) != address(0)) revert AlreadyDone();
        if (router.code.length == 0) revert InvalidAddress();
        if (registryLaunch == 0 || registryIndex >= 8) revert InvalidValue();
        IHookRouter candidate = IHookRouter(router);
        GameRegistry r = GameRegistry(candidate.registry());
        if (
            address(r.factory()) != address(applicationFactory) || r.token() != token || !_routerMarketValid(r.market())
        ) revert InvalidValue();
        if (keccak256(abi.encode(r.starterRoot(), r.freeRoot(), r.snapshotBlock(), r.endowment())) != gameConfigHash) {
            revert InvalidProof();
        }
        address p = r.params();
        _checkDesk(p);
        if (applicationFactory.predictContract(registryLaunch, registryIndex, _registryInitCode(r, p)) != address(r)) {
            revert InvalidProof();
        }
        if (!_canonical(r)) revert InvalidProof();
        // Enrollment proves exact FeeRouter initcode (including registry) and its factory CREATE2 address.
        if (
            r.module(6) != router || candidate.token() != token || candidate.market() != r.market()
                || candidate.params() != p
        ) {
            revert InvalidValue();
        }
        fees = candidate;
        params = IHookParams(p);
        emit Bound(router, p);
    }

    /// @dev The candidate's Params must be the Params of the registry the Desk bound to, pointing at the Desk.
    function _checkDesk(address p) private view {
        address bound = IHookDesk(desk).registry();
        if (bound == address(0) || GameRegistry(bound).params() != p || Params(p).swarmWallet() != desk) {
            revert InvalidProof();
        }
    }

    /// @dev Concatenation has a fixed, pinned creation-code prefix and one ABI tuple; no packed dynamic tuple.
    function _registryInitCode(GameRegistry r, address p) private view returns (bytes memory) {
        bytes memory args =
            abi.encode(r.token(), p, r.market(), r.starterRoot(), r.freeRoot(), r.snapshotBlock(), r.endowment());
        return bytes.concat(type(GameRegistry).creationCode, args);
    }

    /// @dev The Desk binds once; its registry is the canonical game.
    function _canonical(GameRegistry r) internal view virtual returns (bool) {
        return IHookDesk(desk).registry() == address(r);
    }

    /// @notice Permissionless forwarding, kept separate so a receiver cannot interrupt pool swaps.
    function flushFees() external nonReentrant {
        if (address(fees) == address(0)) revert NotConfigured();
        uint256 base = heldBase;
        uint256 excess = heldSellTax;
        uint256 launchTax = heldLaunchTax;
        if (base + excess + launchTax == 0) revert InsufficientBalance();
        heldBase = 0;
        heldSellTax = 0;
        heldLaunchTax = 0;
        if (base != 0) fees.depositBaseFee{value: base}();
        if (excess != 0) fees.depositSellTax{value: excess}();
        if (launchTax != 0) fees.depositLaunchTax{value: launchTax}();
        emit FeesFlushed(base, excess);
        if (launchTax != 0) emit LaunchTaxFlushed(launchTax);
    }

    function _routerMarketValid(address market_) internal view virtual returns (bool) {
        return market_ == address(this);
    }

    function _coefficient(uint8 key_, uint256 default_) private view returns (uint256) {
        return address(params) == address(0) ? default_ : params.get(key_);
    }

    function _validateHookAddress() internal view virtual {
        if (uint160(address(this)) & 0x3fff != HOOK_FLAGS) revert InvalidAddress();
    }

    /// @dev The progressive sell surcharge is part of the launch hook; the standard reference path disables it.
    function _surcharged() internal pure virtual returns (bool) {
        return true;
    }

    receive() external payable {
        if (msg.sender != address(manager)) revert Unauthorized();
    }

    function key() public view returns (PoolKey memory) {
        return PoolKey(address(0), token, poolFee, tickSpacing, address(this));
    }

    function _check(PoolKey calldata k) private view {
        if (msg.sender != address(manager) || keccak256(abi.encode(k)) != poolId) revert Unauthorized();
    }

    function spot() public view returns (uint256) {
        uint256 sqrt = uint160(uint256(manager.extsload(keccak256(abi.encode(poolId, uint256(6))))));
        if (sqrt == 0) revert NotConfigured();
        uint256 price = Math.mulDiv(Math.mulDiv(sqrt, sqrt, 1 << 96), 1 ether, 1 << 96);
        if (price == 0 || price > 1e40) revert InvalidValue();
        return price;
    }

    function afterInitialize(address sender, PoolKey calldata k, uint160, int24) external returns (bytes4) {
        _check(k);
        if (sender != launcher) revert Unauthorized();
        if (initializedAt != 0) revert AlreadyDone();
        initializedAt = block.timestamp;
        _observe(spot());
        return this.afterInitialize.selector;
    }

    function _observe(uint256 price) private {
        uint256 now_ = block.timestamp;
        if (initializedAt == 0) revert NotConfigured();
        if (updatedAt == 0) {
            updatedAt = now_;
            lastPrice = price;
            emit PriceObserved(now_, price);
            return;
        }
        uint256 first = updatedAt / 60 + 1;
        uint256 last = now_ / 60;
        if (last >= 32 && first < last - 31) first = last - 31;
        for (uint256 minute = first; minute <= last; ++minute) {
            uint256 c = cumulative + (1e60 / lastPrice) * (minute * 60 - updatedAt);
            observations[minute % 32] = Observation(uint64(minute), c);
        }
        cumulative += (1e60 / lastPrice) * (now_ - updatedAt);
        updatedAt = now_;
        lastPrice = price;
        emit PriceObserved(now_, price);
    }

    function _cumulativeAt(uint256 minute) private view returns (uint256) {
        uint256 ts = minute * 60;
        if (ts < initializedAt) revert NotConfigured();
        if (ts >= updatedAt) return cumulative + (1e60 / lastPrice) * (ts - updatedAt);
        Observation memory o = observations[minute % 32];
        if (o.minute != minute) revert NotConfigured();
        return o.cumulative;
    }

    function twap() public view returns (uint256) {
        if (initializedAt == 0 || block.timestamp < initializedAt + 31 minutes) revert NotConfigured();
        uint256 minute = block.timestamp / 60;
        uint256 averageETH = (_cumulativeAt(minute) - _cumulativeAt(minute - 30)) / 30 minutes;
        return 1e60 / averageETH;
    }

    /// @notice Tokens a system buy of `ethAmount` receives at TWAP after the hook's 1% share and the pool LP fee.
    function quote(uint256 ethAmount) external view returns (uint256) {
        uint256 netInput = ethAmount - ethAmount * PROJECT_BPS / 10000;
        netInput = netInput * (1_000_000 - poolFee) / 1_000_000;
        return Math.mulDiv(netInput, twap(), 1 ether);
    }

    function _record(bool sell, uint256 amount) private {
        if (amount > type(uint192).max) revert InvalidValue();
        uint256 p = block.timestamp / 5 minutes;
        Volume storage a = shortVolumes[p % 12];
        if (a.period != p) {
            delete shortVolumes[p % 12];
            a.period = uint64(p);
        }
        p = block.timestamp / 1 hours;
        Volume storage b = longVolumes[p % 24];
        if (b.period != p) {
            delete longVolumes[p % 24];
            b.period = uint64(p);
        }
        if (sell) {
            a.sells += uint192(amount);
            b.sells += uint192(amount);
        } else {
            a.buys += uint192(amount);
            b.buys += uint192(amount);
        }
    }

    function imbalances() public view returns (uint256 hour, uint256 day) {
        uint256 s;
        uint256 b;
        uint256 current = block.timestamp / 5 minutes;
        for (uint256 i; i < 12; ++i) {
            if (uint256(shortVolumes[i].period) + 12 > current) {
                s += shortVolumes[i].sells;
                b += shortVolumes[i].buys;
            }
        }
        if (s > b) hour = Math.mulDiv(s - b, 10000, s + b + 0.5 ether);
        s = 0;
        b = 0;
        current = block.timestamp / 1 hours;
        for (uint256 i; i < 24; ++i) {
            if (uint256(longVolumes[i].period) + 24 > current) {
                s += longVolumes[i].sells;
                b += longVolumes[i].buys;
            }
        }
        if (s > b) day = Math.mulDiv(s - b, 10000, s + b + 2 ether);
    }

    /// @notice The hook's own share after the launch window: exactly 1%, all to reward buys.
    function projectBps() public pure returns (uint256) {
        return PROJECT_BPS;
    }

    /// @notice Seconds since the pool was initialized (token launch). Zero before initialization.
    function sinceLaunch() public view returns (uint256) {
        return initializedAt == 0 ? 0 : block.timestamp - initializedAt;
    }

    /// @notice Immutable total buy-tax steps; the entire stepped tax funds reward buys.
    function currentBuyTaxBps() public view returns (uint256) {
        uint256 t = sinceLaunch();
        if (t < 10 minutes) return 9000;
        if (t < 20 minutes) return 5000;
        if (t < 30 minutes) return 2500;
        return PROJECT_BPS;
    }

    function launchTaxTimeLeft() public view returns (uint256) {
        uint256 t = sinceLaunch();
        return t >= LAUNCH_TAX_DECAY ? 0 : LAUNCH_TAX_DECAY - t;
    }

    function nextStepIn() public view returns (uint256) {
        uint256 t = sinceLaunch();
        return t >= LAUNCH_TAX_DECAY ? 0 : LAUNCH_TAX_STEP - t % LAUNCH_TAX_STEP;
    }

    /// @notice Compatibility views: buys are unlimited from the first block.
    function maxBuy() public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxBuyTimeLeft() public pure returns (uint256) {
        return 0;
    }

    function launchStatus() external view returns (uint256, uint256, uint256, uint256) {
        return (currentBuyTaxBps(), launchTaxTimeLeft(), type(uint256).max, 0);
    }

    function _sellFee(uint256 price) private returns (uint256 fee, uint256 hour, uint256 day, uint256 dev) {
        if (!_surcharged()) return (PROJECT_BPS, 0, 0, 0);
        (hour, day) = imbalances();
        uint256 average;
        // Trading is possible during warmup; the deviation component starts only when TWAP is ready.
        if (block.timestamp >= initializedAt + 31 minutes) average = twap();
        if (average != 0 && price > average) dev = Math.min(1000, 10000 - Math.mulDiv(average, 10000, price));
        uint256 target = PROJECT_BPS + _coefficient(24, 500) * hour / 10000 + _coefficient(25, 400) * day / 10000
            + _coefficient(26, 5000) * dev / 10000;
        target = Math.min(TOTAL_CAP_BPS, target) * 1 ether;
        uint256 fall = feeTimestamp == 0 ? 0 : (block.timestamp - feeTimestamp) * 100 ether / 10 minutes;
        uint256 decayed = storedFeeWad > fall ? storedFeeWad - fall : PROJECT_BPS * 1 ether;
        storedFeeWad = Math.max(target, decayed);
        feeTimestamp = block.timestamp;
        fee = Math.min(TOTAL_CAP_BPS, (storedFeeWad + 1 ether - 1) / 1 ether);
    }

    function beforeSwap(address sender, PoolKey calldata k, SwapParams calldata p, bytes calldata)
        external
        returns (bytes4, int256, uint24)
    {
        _check(k);
        if (p.amountSpecified >= 0) revert InvalidValue();
        _observe(spot());
        if (!p.zeroForOne) return (this.beforeSwap.selector, 0, 0);
        // v3.18: the charge below is on the specified input, so the swap must be one that consumes all of it.
        if (p.sqrtPriceLimitX96 != BUY_PRICE_LIMIT) revert PriceLimitedBuy(p.sqrtPriceLimitX96);
        uint256 ethIn = uint256(-p.amountSpecified);
        uint256 taxBps = currentBuyTaxBps();
        uint256 fee = ethIn * taxBps / 10000;
        if (fee > uint256(uint128(type(int128).max))) revert InvalidValue();
        if (sinceLaunch() < LAUNCH_TAX_DECAY) {
            // Taken from the manager's float before the swapper settles; accepted (docs/accepted-v318.md).
            manager.take(address(0), address(this), fee);
            heldLaunchTax += fee;
            emit LaunchTax(sender, ethIn, taxBps, fee);
        } else {
            // Exactly PROJECT_BPS of the input, all of it the base stream (reward buys).
            _take(fee, 0);
        }
        return (this.beforeSwap.selector, int256(fee << 128), 0);
    }

    function afterSwap(address sender, PoolKey calldata k, SwapParams calldata p, int256 delta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        _check(k);
        if (p.amountSpecified >= 0) revert InvalidValue();
        uint256 price = spot();
        _observe(price);
        int128 ethDelta = int128(delta >> 128);
        if (p.zeroForOne) {
            if (ethDelta >= 0) revert InvalidValue();
            uint256 consumed = uint256(-int256(ethDelta));
            // v3.18: beforeSwap taxed the whole specified input; the pool must have consumed all of the rest.
            uint256 ethIn = uint256(-p.amountSpecified);
            uint256 expected = ethIn - ethIn * currentBuyTaxBps() / 10000;
            if (consumed != expected) revert PartialFill(consumed, expected);
            _record(false, consumed);
            return (this.afterSwap.selector, 0);
        }
        if (ethDelta <= 0) revert InvalidValue();
        uint256 output = uint256(uint128(ethDelta));
        _record(true, output);
        return (this.afterSwap.selector, int128(int256(_chargeSell(sender, output, price))));
    }

    /// @dev Base 1% to rewards plus the progressive surcharge above it; both taken from the sell output.
    function _chargeSell(address sender, uint256 output, uint256 price) private returns (uint256) {
        (uint256 bps, uint256 hour, uint256 day, uint256 dev) = _sellFee(price);
        uint256 base = output * PROJECT_BPS / 10000;
        uint256 excess = output * (bps - PROJECT_BPS) / 10000;
        _take(base, excess);
        emit SellFee(sender, output, bps, hour, day, dev);
        return base + excess;
    }

    function _take(uint256 base, uint256 excess) private {
        uint256 total = base + excess;
        if (total != 0) manager.take(address(0), address(this), total);
        heldBase += base;
        heldSellTax += excess;
    }

    function buy(uint256 minOut, address recipient) external payable nonReentrant returns (uint256 received) {
        if (msg.sender != address(fees) || recipient == address(0) || msg.value == 0 || minOut == 0) {
            revert Unauthorized();
        }
        if (initializedAt == 0 || sinceLaunch() < LAUNCH_TAX_DECAY) revert TooEarly();
        twap();
        buying = true;
        received = abi.decode(manager.unlock(abi.encode(msg.value, minOut, recipient)), (uint256));
        buying = false;
    }

    function quoteSell(uint256 amount) public view returns (uint256) {
        uint256 gross = Math.mulDiv(amount, 1 ether, twap());
        gross = gross * (1_000_000 - poolFee) / 1_000_000;
        return gross - gross * PROJECT_BPS / 10000;
    }

    /// @notice At most 0.1% of current virtual token reserves, additionally capped by 0.1 ETH TWAP value.
    function maxSellBatch() public view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(poolId, uint256(6)));
        uint256 liquidity = uint128(uint256(manager.extsload(bytes32(uint256(slot) + 3))));
        uint256 sqrt = uint160(uint256(manager.extsload(slot)));
        uint256 depth = Math.mulDiv(liquidity, sqrt, 1 << 96);
        return Math.min(depth / 1000, twap() / 10);
    }

    function sell(uint256 amount, uint256 minOut, address recipient) external nonReentrant returns (uint256 received) {
        if (msg.sender != address(fees) || recipient != address(fees) || amount == 0 || minOut == 0) {
            revert Unauthorized();
        }
        if (amount > maxSellBatch()) revert InvalidValue();
        if (minOut < quoteSell(amount) * 9850 / 10000) revert InvalidValue();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        selling = true;
        received = abi.decode(manager.unlock(abi.encode(amount, minOut, recipient)), (uint256));
        selling = false;
    }

    function _sellCallback(bytes calldata data) private returns (bytes memory) {
        (uint256 amount, uint256 minimum, address recipient) = abi.decode(data, (uint256, uint256, address));
        _observe(spot());
        int256 delta = manager.swap(
            key(), SwapParams(false, -int256(amount), 1461446703485210103287273052203988822378723970341), ""
        );
        _observe(spot());
        int128 ethOut = int128(delta >> 128);
        int128 tokenIn = int128(delta);
        if (ethOut <= 0 || tokenIn >= 0 || uint256(-int256(tokenIn)) != amount) revert InsufficientBalance();
        uint256 gross = uint256(uint128(ethOut));
        uint256 base = gross * PROJECT_BPS / 10000;
        uint256 net = gross - base;
        if (net < minimum) revert InsufficientBalance();
        manager.sync(token);
        IERC20(token).safeTransfer(address(manager), amount);
        manager.settle();
        manager.take(address(0), address(this), gross);
        heldBase += base;
        _record(true, gross);
        (bool ok,) = recipient.call{value: net}("");
        if (!ok) revert TransferFailed();
        return abi.encode(net);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(manager) || (!buying && !selling)) revert Unauthorized();
        if (selling) return _sellCallback(data);
        (uint256 ethIn, uint256 minOut, address recipient) = abi.decode(data, (uint256, uint256, address));
        uint256 base = ethIn * PROJECT_BPS / 10000;
        uint256 input = ethIn - base;
        _observe(spot());
        // v4 suppresses a hook's callbacks on its own swaps. Account for this system buy explicitly.
        int256 delta = manager.swap(key(), SwapParams(true, -int256(input), 4295128740), "");
        _observe(spot());
        int128 ethDelta = int128(delta >> 128);
        int128 tokenDelta = int128(delta);
        if (
            ethDelta >= 0 || uint256(-int256(ethDelta)) != input || tokenDelta <= 0
                || uint256(uint128(tokenDelta)) < minOut
        ) {
            revert InsufficientBalance();
        }
        _record(false, input);
        manager.settle{value: input}();
        manager.take(token, recipient, uint256(uint128(tokenDelta)));
        heldBase += base;
        return abi.encode(uint256(uint128(tokenDelta)));
    }
}
