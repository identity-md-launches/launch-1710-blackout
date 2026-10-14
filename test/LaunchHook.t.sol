// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey as CorePoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams as CoreSwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {V4Market} from "../src/V4Market.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {PoolKey, SwapParams} from "../src/interfaces/IV4.sol";
import {Unauthorized, AlreadyDone, NotConfigured, InvalidValue, InvalidAddress} from "../src/lib/Errors.sol";

/// @dev Independent ABI definition, as used by the admission check.
interface LaunchHookPermissions {
    function getHookPermissions() external pure returns (Hooks.Permissions memory);
}

/// @notice Exercises the actual V4Market, without overrides, with the actual launch token and v4 PoolManager.
/// @dev This contract is a local factory/liquidity provider/router fixture. It only settles its own assets.
contract LaunchHookTest is Test {
    bytes32 private constant CREATION_HASH = 0xedb2d58fb4632f2ef5a81b58ea05dcff0f5510e5448c6766539f89379109af10;
    bytes32 private constant GAME_CONFIG_HASH = 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3;
    address private constant DESK = 0x5cb0686A4475D1F8a6c6e5240579080a4A05B609;
    uint160 private constant SQRT_PRICE = 79228162514264337593543950336;
    uint160 private constant BUY_LIMIT = 4295128740;
    uint160 private constant SELL_LIMIT = 1461446703485210103287273052203988822378723970341;

    PoolManager private manager;
    LaunchToken private token;
    V4Market private hook;
    CorePoolKey private key;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_800_000_000);
        vm.deal(address(this), 10_000 ether);
        manager = new PoolManager(address(this));
        token = new LaunchToken();
        bytes memory code = abi.encodePacked(
            type(V4Market).creationCode,
            abi.encode(
                address(manager), address(token), uint24(12500), int24(60), address(this), DESK, GAME_CONFIG_HASH
            )
        );
        bytes32 hash = keccak256(code);
        address deployed;
        for (uint256 i; i < 200_000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted = vm.computeCreate2Address(salt, hash, address(this));
            if (uint160(predicted) & 0x3fff != 0x10cc) continue;
            assembly ("memory-safe") {
                deployed := create2(0, add(code, 32), mload(code), salt)
            }
            assertEq(deployed, predicted, "production constructor failed");
            break;
        }
        require(deployed != address(0), "no matching salt found");
        hook = V4Market(payable(deployed));
        key = CorePoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 12500, 60, IHooks(deployed));
    }

    receive() external payable {}

    function testPinnedCreationHashAndRuntimeSize() public view {
        assertEq(keccak256(type(V4Market).creationCode), CREATION_HASH);
        assertEq(address(hook).code.length, 21_982);
        assertEq(hook.token(), address(token));
        assertEq(hook.desk(), DESK);
        assertEq(hook.gameConfigHash(), GAME_CONFIG_HASH);
        assertEq(address(hook.manager()), address(manager));
        assertEq(hook.launcher(), address(this));
        assertEq(hook.poolFee(), 12500);
        assertEq(hook.tickSpacing(), 60);
        assertEq(hook.poolId(), keccak256(abi.encode(key)));
        assertEq(abi.encode(hook.key()), abi.encode(key));
    }

    function testPermissionsMatchV4CoreABIAndMinedAddress() public view {
        Hooks.Permissions memory p = LaunchHookPermissions(address(hook)).getHookPermissions();
        Hooks.validateHookPermissions(IHooks(address(hook)), p);
        assertFalse(p.beforeInitialize);
        assertTrue(p.afterInitialize);
        assertFalse(p.beforeAddLiquidity);
        assertFalse(p.afterAddLiquidity);
        assertFalse(p.beforeRemoveLiquidity);
        assertFalse(p.afterRemoveLiquidity);
        assertTrue(p.beforeSwap);
        assertTrue(p.afterSwap);
        assertFalse(p.beforeDonate);
        assertFalse(p.afterDonate);
        assertTrue(p.beforeSwapReturnDelta);
        assertTrue(p.afterSwapReturnDelta);
        assertFalse(p.afterAddLiquidityReturnDelta);
        assertFalse(p.afterRemoveLiquidityReturnDelta);
        assertEq(uint160(address(hook)) & 0x3fff, 0x10cc);
        assertEq(hook.HOOK_FLAGS(), 0x10cc);
    }

    function testFactoryInitializesOnceThroughRealPoolManager() public {
        manager.initialize(key, SQRT_PRICE);
        assertEq(hook.initializedAt(), block.timestamp);
        assertEq(hook.spot(), 1 ether);
        PoolKey memory k = hook.key();
        vm.expectRevert(AlreadyDone.selector);
        vm.prank(address(manager));
        hook.afterInitialize(address(this), k, SQRT_PRICE, 0);
    }

    function testAnotherSenderCannotInitializeFactoryPool() public {
        vm.prank(makeAddr("unauthorized initializer"));
        vm.expectRevert();
        manager.initialize(key, SQRT_PRICE);
        assertEq(hook.initializedAt(), 0);
        manager.initialize(key, SQRT_PRICE);
        assertEq(hook.initializedAt(), block.timestamp);
    }

    function testWrongPoolTermsCannotInitialize() public {
        CorePoolKey memory wrong = key;
        wrong.fee = 3000;
        vm.expectRevert();
        manager.initialize(wrong, SQRT_PRICE);
        wrong = key;
        wrong.tickSpacing = 120;
        vm.expectRevert();
        manager.initialize(wrong, SQRT_PRICE);
        assertEq(hook.initializedAt(), 0);
        manager.initialize(key, SQRT_PRICE);
    }

    function testAllCallbacksRejectNonManagerEvenWithCorrectPool() public {
        PoolKey memory k = hook.key();
        SwapParams memory p = SwapParams(true, -int256(1 ether), BUY_LIMIT);
        vm.expectRevert(Unauthorized.selector);
        hook.afterInitialize(address(this), k, SQRT_PRICE, 0);
        vm.expectRevert(Unauthorized.selector);
        hook.beforeSwap(address(this), k, p, "");
        vm.expectRevert(Unauthorized.selector);
        hook.afterSwap(address(this), k, p, 0, "");
        vm.expectRevert(Unauthorized.selector);
        hook.unlockCallback("");
        (bool paid,) = address(hook).call{value: 1}("");
        assertFalse(paid);
        assertEq(hook.initializedAt(), 0);
        assertEq(address(hook).balance, 0);
    }

    function testManagerCannotDriveCallbacksForAnotherPool() public {
        PoolKey memory wrong = hook.key();
        wrong.fee = 3000;
        SwapParams memory p = SwapParams(true, -int256(1 ether), BUY_LIMIT);
        vm.startPrank(address(manager));
        vm.expectRevert(Unauthorized.selector);
        hook.afterInitialize(address(this), wrong, SQRT_PRICE, 0);
        vm.expectRevert(Unauthorized.selector);
        hook.beforeSwap(address(this), wrong, p, "");
        vm.expectRevert(Unauthorized.selector);
        hook.afterSwap(address(this), wrong, p, 0, "");
        vm.stopPrank();
    }

    function testExactOutputAndZeroInputRefusedInBothDirections() public {
        manager.initialize(key, SQRT_PRICE);
        PoolKey memory k = hook.key();
        for (uint256 i; i < 2; ++i) {
            for (uint256 amount; amount < 2; ++amount) {
                SwapParams memory p = SwapParams(i == 0, int256(amount), i == 0 ? BUY_LIMIT : SELL_LIMIT);
                vm.startPrank(address(manager));
                vm.expectRevert(InvalidValue.selector);
                hook.beforeSwap(address(this), k, p, "");
                vm.expectRevert(InvalidValue.selector);
                hook.afterSwap(address(this), k, p, 0, "");
                vm.stopPrank();
            }
        }
    }

    function testPriceLimitedBuyRefusedBeforeFundsMove() public {
        _seed();
        uint256 beforeETH = address(this).balance;
        uint256 beforeTokens = token.balanceOf(address(this));
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), int256(10 ether), SQRT_PRICE - 1));
        assertEq(address(this).balance, beforeETH);
        assertEq(token.balanceOf(address(this)), beforeTokens);
        assertEq(hook.heldLaunchTax(), 0);
        PoolKey memory k = hook.key();
        vm.expectRevert(abi.encodeWithSelector(V4Market.PriceLimitedBuy.selector, SQRT_PRICE - 1));
        vm.prank(address(manager));
        hook.beforeSwap(address(this), k, SwapParams(true, -int256(10 ether), SQRT_PRICE - 1), "");
    }

    function testPartialFillRefusedWithExactError() public {
        manager.initialize(key, SQRT_PRICE);
        PoolKey memory k = hook.key();
        SwapParams memory p = SwapParams(true, -int256(10 ether), BUY_LIMIT);
        int256 partialDelta = (int256(-0.5 ether) << 128) | int256(0.5 ether);
        vm.expectRevert(abi.encodeWithSelector(V4Market.PartialFill.selector, 0.5 ether, 1 ether));
        vm.prank(address(manager));
        hook.afterSwap(address(this), k, p, partialDelta, "");
    }

    function testFuzzBuyStepsConserveEthAndTokens(uint96 input, uint16 elapsed) public {
        _seed();
        uint256 amount = bound(input, 1e6, 10 ether);
        uint256 age = bound(elapsed, 0, 3600);
        vm.warp(hook.initializedAt() + age);
        uint256 bps = age < 600 ? 9000 : age < 1200 ? 5000 : age < 1800 ? 2500 : 100;
        uint256 beforeETH = address(this).balance;
        uint256 beforeManager = address(manager).balance;
        uint256 beforeTokens = token.balanceOf(address(this));
        BalanceDelta delta = _swap(true, amount);
        uint256 tax = amount * bps / 10000;
        assertEq(delta.amount0(), -int128(int256(amount)));
        assertGt(delta.amount1(), 0);
        assertEq(beforeETH - address(this).balance, amount);
        assertEq(address(manager).balance - beforeManager, amount - tax);
        assertEq(address(hook).balance, tax);
        assertEq(hook.heldLaunchTax(), age < 1800 ? tax : 0);
        assertEq(hook.heldBase(), age >= 1800 ? tax : 0);
        assertEq(token.balanceOf(address(this)) - beforeTokens, uint256(uint128(delta.amount1())));
        assertEq(token.balanceOf(address(this)) + token.balanceOf(address(manager)), token.totalSupply());
    }

    function testSellFeesAccrueOnActualOutputAndFactoryCanCollect() public {
        _seed();
        vm.warp(hook.initializedAt() + 31 minutes);
        _swap(true, 1 ether);
        uint256 baseBefore = hook.heldBase();
        uint256 ethBefore = address(this).balance;
        uint256 managerBefore = address(manager).balance;
        BalanceDelta delta = _swap(false, 100 ether);
        uint256 gross = managerBefore - address(manager).balance;
        uint256 base = hook.heldBase() - baseBefore;
        uint256 surcharge = hook.heldSellTax();
        assertEq(base, gross / 100);
        assertGt(surcharge, 0);
        assertLe(base + surcharge, gross * 1500 / 10000);
        assertEq(address(this).balance - ethBefore + base + surcharge, gross);
        assertEq(delta.amount0(), int128(int256(gross - base - surcharge)));
        assertEq(delta.amount1(), -int128(100 ether));
        uint256 feesBefore = address(hook).balance;
        BalanceDelta collect = abi.decode(manager.unlock(abi.encode(uint8(0), int256(0), uint160(0))), (BalanceDelta));
        assertGe(collect.amount0(), 0);
        assertGe(collect.amount1(), 0);
        assertGt(uint256(uint128(collect.amount0())) + uint256(uint128(collect.amount1())), 0);
        assertEq(address(hook).balance, feesBefore, "hook takes nothing from factory fee collection");
    }

    function testFeesHeldAndFlushRefusedUntilDeskAndRouterBind() public {
        _seed();
        _swap(true, 10 ether);
        assertEq(hook.heldLaunchTax(), 9 ether);
        assertEq(address(hook.fees()), address(0));
        assertEq(address(hook.params()), address(0));
        vm.expectRevert(NotConfigured.selector);
        hook.flushFees();
        assertEq(hook.heldLaunchTax(), 9 ether);
        assertEq(address(hook).balance, 9 ether);
        vm.expectRevert(InvalidAddress.selector);
        hook.bindFeeRouter(makeAddr("router with no code"), 1, 0);
        assertEq(address(hook.fees()), address(0));
    }

    function testAcceptedManagerFloatConstraintOnTokenOnlyPool() public {
        manager.initialize(key, SQRT_PRICE);
        // Below the current tick: this position holds only token1 (BLACKOUT).
        manager.unlock(abi.encode(uint8(3), int256(1000 ether), uint160(0)));
        assertEq(address(manager).balance, 0);
        assertGt(token.balanceOf(address(manager)), 0);
        uint256 beforeETH = address(this).balance;
        vm.expectRevert();
        manager.unlock(abi.encode(uint8(1), int256(1 ether), BUY_LIMIT));
        assertEq(address(this).balance, beforeETH);
        assertEq(hook.heldLaunchTax(), 0);
        assertEq(address(hook).balance, 0);
    }

    function testHookHasNoOwnerOrUpgradeEntryPoint() public {
        (bool hasOwner,) = address(hook).staticcall(abi.encodeWithSignature("owner()"));
        assertFalse(hasOwner);
        (bool upgraded,) = address(hook).call(abi.encodeWithSignature("upgradeTo(address)", address(this)));
        assertFalse(upgraded);
        bytes memory code = address(hook).code;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) i += op - 0x5f;
            else assertTrue(op != 0xf2 && op != 0xf4 && op != 0xff);
        }
    }

    function _seed() private {
        manager.initialize(key, SQRT_PRICE);
        manager.unlock(abi.encode(uint8(0), int256(1000 ether), uint160(0)));
    }

    function _swap(bool buy, uint256 amount) private returns (BalanceDelta) {
        return abi.decode(
            manager.unlock(abi.encode(buy ? uint8(1) : uint8(2), int256(amount), buy ? BUY_LIMIT : SELL_LIMIT)),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (uint8 action, int256 amount, uint160 limit) = abi.decode(data, (uint8, int256, uint160));
        BalanceDelta delta;
        if (action == 0 || action == 3) {
            (delta,) = manager.modifyLiquidity(
                key,
                ModifyLiquidityParams(
                    action == 3 ? int24(-120) : int24(-887220),
                    action == 3 ? int24(-60) : int24(887220),
                    amount,
                    bytes32(0)
                ),
                ""
            );
        } else {
            delta = manager.swap(key, CoreSwapParams(action == 1, -amount, limit), "");
        }
        int128 eth = delta.amount0();
        int128 tokens = delta.amount1();
        if (eth < 0) manager.settle{value: uint256(-int256(eth))}();
        else if (eth > 0) manager.take(key.currency0, address(this), uint256(uint128(eth)));
        if (tokens < 0) {
            manager.sync(key.currency1);
            require(token.transfer(address(manager), uint256(-int256(tokens))));
            manager.settle();
        } else if (tokens > 0) {
            manager.take(key.currency1, address(this), uint256(uint128(tokens)));
        }
        return abi.encode(delta);
    }
}
