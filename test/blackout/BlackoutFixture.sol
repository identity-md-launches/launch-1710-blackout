// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {V4Market} from "src/V4Market.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {GameRegistry} from "src/GameRegistry.sol";
import {Params} from "src/Params.sol";
import {FeeRouter} from "src/FeeRouter.sol";
import {RewardPool} from "src/RewardPool.sol";
import {Robinhood} from "src/lib/Robinhood.sol";
import {LocalApplicationFactory} from "script/Deploy.s.sol";

/// @dev Only the already deployed, external Desk's registry view is simulated.
/// No V4Market function or binding check is overridden.
contract BlackoutDeskProbe {
    address public registry;

    function setRegistry(address registry_) external {
        registry = registry_;
    }
}

/// @dev Test router. Each unlock, both callbacks and all settlement occur in one call.
/// ERC-20 inputs are pulled only from msg.sender, before unlocking the PoolManager.
contract BlackoutPoolDriver {
    using TransientStateLibrary for IPoolManager;

    IPoolManager public immutable manager;
    LaunchToken public immutable token;
    address private immutable controller;
    PoolKey private poolKey;

    constructor(IPoolManager manager_, LaunchToken token_, V4Market hook) {
        manager = manager_;
        token = token_;
        controller = msg.sender;
        poolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token_)), 12500, 60, IHooks(address(hook)));
    }

    receive() external payable {}

    function modify(int24 lower, int24 upper, int256 liquidity) external payable returns (BalanceDelta delta) {
        require(msg.sender == controller, "fixture controller");
        delta = abi.decode(manager.unlock(abi.encode(uint8(0), lower, upper, liquidity, uint160(0))), (BalanceDelta));
        _assertSettled();
    }

    function trade(bool buy, uint256 amount, uint160 limit, uint256 minimum)
        external
        payable
        returns (BalanceDelta delta)
    {
        require(amount <= uint256(type(int256).max), "signed amount");
        if (buy) {
            require(msg.value == amount, "exact ETH input");
        } else {
            require(msg.value == 0, "token input");
            require(token.transferFrom(msg.sender, address(this), amount));
        }
        delta = abi.decode(
            manager.unlock(abi.encode(buy ? uint8(1) : uint8(2), int24(0), int24(0), -int256(amount), limit)),
            (BalanceDelta)
        );
        _assertSettled();
        if (buy) {
            require(delta.amount0() < 0 && delta.amount1() >= 0, "buy signs");
            uint256 spent = uint256(-int256(delta.amount0()));
            uint256 received = uint256(uint128(delta.amount1()));
            require(received >= minimum, "minimum output");
            require(token.transfer(msg.sender, received));
            if (spent < amount) _send(msg.sender, amount - spent);
        } else {
            require(delta.amount0() >= 0 && delta.amount1() < 0, "sell signs");
            uint256 spent = uint256(-int256(delta.amount1()));
            uint256 received = uint256(uint128(delta.amount0()));
            require(received >= minimum, "minimum output");
            if (spent < amount) require(token.transfer(msg.sender, amount - spent));
            _send(msg.sender, received);
        }
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (uint8 action, int24 lower, int24 upper, int256 amount, uint160 limit) =
            abi.decode(data, (uint8, int24, int24, int256, uint160));
        BalanceDelta delta;
        if (action == 0) {
            (delta,) = manager.modifyLiquidity(poolKey, ModifyLiquidityParams(lower, upper, amount, bytes32(0)), "");
        } else {
            delta = manager.swap(poolKey, SwapParams(action == 1, amount, limit), "");
        }
        _settle(poolKey.currency0, delta.amount0());
        _settle(poolKey.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 amount) private {
        if (amount < 0) {
            uint256 owed = uint256(-int256(amount));
            if (Currency.unwrap(currency) == address(0)) {
                manager.settle{value: owed}();
            } else {
                manager.sync(currency);
                require(token.transfer(address(manager), owed));
                manager.settle();
            }
        } else if (amount > 0) {
            manager.take(currency, address(this), uint256(uint128(amount)));
        }
    }

    /// @dev Read transient accounting inside the transaction, before Forge clears it.
    function _assertSettled() private view {
        require(!manager.isUnlocked(), "manager left unlocked");
        require(manager.getNonzeroDeltaCount() == 0, "unsettled deltas");
        require(manager.currencyDelta(address(this), poolKey.currency0) == 0, "router ETH debt");
        require(manager.currencyDelta(address(this), poolKey.currency1) == 0, "router token debt");
        require(manager.currencyDelta(address(poolKey.hooks), poolKey.currency0) == 0, "hook ETH debt");
        require(manager.currencyDelta(address(poolKey.hooks), poolKey.currency1) == 0, "hook token debt");
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH payout");
    }
}

abstract contract BlackoutFixture is Test {
    uint160 internal constant PRICE = 79228162514264337593543950336;
    uint160 internal constant BUY_LIMIT = 4295128740;
    uint160 internal constant SELL_LIMIT = 1461446703485210103287273052203988822378723970341;
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant START = 1_800_000_000;
    uint64 internal constant REGISTRY_LAUNCH = 77;
    bytes32 internal constant STARTER_ROOT = keccak256("BLACKOUT test-only starter tree");
    bytes32 internal constant FREE_ROOT = keccak256("BLACKOUT test-only free tree");
    uint256 internal constant SNAPSHOT = 23_000_000;
    uint256 internal constant ENDOWMENT = 200_000_000 ether;

    PoolManager internal manager;
    LaunchToken internal token;
    V4Market internal hook;
    BlackoutPoolDriver internal driver;
    BlackoutDeskProbe internal desk;
    LocalApplicationFactory internal factory;
    GameRegistry internal registry;
    Params internal parameters;
    FeeRouter internal router;
    RewardPool internal rewards;
    address[3] internal actors;

    receive() external payable {}

    function _deployFixture() internal {
        vm.chainId(4663);
        vm.warp(START);
        vm.deal(address(this), 1_000_000 ether);
        manager = new PoolManager(address(this));
        token = new LaunchToken();
        desk = new BlackoutDeskProbe();
        hook = _deployHook(address(desk), _configHash());
        driver = new BlackoutPoolDriver(IPoolManager(address(manager)), token, hook);
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("BLACKOUT actor ", vm.toString(i)));
            vm.deal(actors[i], 1000 ether);
            token.transfer(actors[i], 1000 ether);
            vm.prank(actors[i]);
            token.approve(address(driver), type(uint256).max);
        }
        token.approve(address(driver), type(uint256).max);
    }

    function _configHash() internal pure returns (bytes32) {
        return keccak256(abi.encode(STARTER_ROOT, FREE_ROOT, SNAPSHOT, ENDOWMENT));
    }

    function _deployHook(address desk_, bytes32 config) internal returns (V4Market deployed) {
        bytes memory code = bytes.concat(
            type(V4Market).creationCode,
            abi.encode(address(manager), address(token), uint24(12500), int24(60), address(this), desk_, config)
        );
        bytes32 hash = keccak256(code);
        for (uint256 i; i < 200_000; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, hash)))));
            if (uint160(predicted) & 0x3fff != 0x10cc) continue;
            address result;
            assembly ("memory-safe") { result := create2(0, add(code, 32), mload(code), salt) }
            require(result == predicted, "production hook deployment");
            return V4Market(payable(result));
        }
        revert("hook salt exhausted");
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 12500, 60, IHooks(address(hook)));
    }

    function _seed() internal {
        manager.initialize(_key(), PRICE);
        token.transfer(address(driver), 100_001 ether);
        driver.modify{value: 100_001 ether}(-887220, 887220, int256(100_000 ether));
    }

    function _prepareBinding() internal {
        // The external platform factory is represented by the repository's CREATE2 fixture.
        vm.etch(Robinhood.PROJECT_FACTORY, type(LocalApplicationFactory).runtimeCode);
        factory = LocalApplicationFactory(Robinhood.PROJECT_FACTORY);
        parameters = new Params(address(desk), 200, 1 ether);
        registry = GameRegistry(
            factory.deploy(
                REGISTRY_LAUNCH,
                0,
                bytes.concat(
                    type(GameRegistry).creationCode,
                    abi.encode(
                        address(token), address(parameters), address(hook), STARTER_ROOT, FREE_ROOT, SNAPSHOT, ENDOWMENT
                    )
                )
            )
        );
        router = FeeRouter(
            payable(factory.deploy(78, 0, bytes.concat(type(FeeRouter).creationCode, abi.encode(address(registry)))))
        );
        registry.register(6, 78, 0, type(FeeRouter).creationCode);
        rewards = RewardPool(
            factory.deploy(78, 1, bytes.concat(type(RewardPool).creationCode, abi.encode(address(registry))))
        );
        registry.register(0, 78, 1, type(RewardPool).creationCode);
        // RewardPool.recordInflow authenticates the real FarmCore role before checking FeeRouter.
        bytes memory coreCode = vm.getCode("src/FarmCore.sol:FarmCore");
        factory.deploy(78, 2, bytes.concat(coreCode, abi.encode(address(registry))));
        registry.register(2, 78, 2, coreCode);
        desk.setRegistry(address(registry));
    }

    function _bind() internal {
        hook.bindFeeRouter(address(router), REGISTRY_LAUNCH, 0);
    }

    function _buy(uint256 amount) internal returns (BalanceDelta) {
        return driver.trade{value: amount}(true, amount, BUY_LIMIT, 0);
    }

    function _sell(uint256 amount) internal returns (BalanceDelta) {
        return driver.trade(false, amount, SELL_LIMIT, 0);
    }

    function _held() internal view returns (uint256) {
        return hook.heldBase() + hook.heldSellTax() + hook.heldLaunchTax();
    }
}
