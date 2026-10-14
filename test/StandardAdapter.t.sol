// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {StandardAdapter, IStandardTwap} from "../src/StandardAdapter.sol";
import {MockV4Manager} from "./mocks/MockV4Manager.sol";
import {MockGameRegistry} from "./mocks/MockGameRegistry.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import "../src/lib/Errors.sol";

contract MockStandardTwap is IStandardTwap {
    uint256 public rate = 1 ether;
    uint256 public at;
    uint256 public window = 30 minutes;
    bytes32 public expectedPool;

    constructor() {
        at = block.timestamp;
    }

    function configure(bytes32 pool, uint256 at_, uint256 window_) external {
        expectedPool = pool;
        at = at_;
        window = window_;
    }

    function consult(bytes32 pool) external view returns (uint256, uint256, uint256) {
        require(pool == expectedPool, "wrong pool");
        return (rate, at, window);
    }
}

contract StandardAdapterTest is BaseTest {
    StandardAdapter private adapter;
    MockStandardTwap private oracle;
    MockV4Manager private manager;
    FeeRouter private fees;

    function setUp() public override {
        super.setUp();
        oracle = new MockStandardTwap();
        manager = new MockV4Manager();
        fees = newFees(makeAddr("pending test adapter"));
        adapter = new StandardAdapter(
            address(manager), address(token), address(oracle), address(fees), makeAddr("existing standard hook"), 60
        );
        MockGameRegistry(address(fees.registry())).setMarket(address(adapter));
        oracle.configure(adapter.poolId(), block.timestamp, 30 minutes);
        token.transfer(address(manager), 100 ether);
    }

    function testExistingHookKeyPreservedAndNoExtraFee() public {
        assertEq(adapter.key().hooks, adapter.standardHook());
        fees.depositBaseFee{value: 1 ether}();
        uint256 before_ = token.balanceOf(address(d.pool));
        fees.executeBuys(0.5 ether, 0.5 ether);
        assertEq(token.balanceOf(address(d.pool)) - before_, 0.5 ether);
        assertEq(fees.rewardETH(), 0.5 ether); // v3.9: the whole base deposit is reward ETH
        assertEq(fees.credit(team), 0);
        assertEq(fees.heartbeatBalance(), 0);
    }

    function testRequiresThirtyMinutesFreshOracleAndAuthorizedCallback() public {
        oracle.configure(adapter.poolId(), block.timestamp, 29 minutes);
        vm.expectRevert(NotConfigured.selector);
        adapter.quote(1 ether);
        oracle.configure(adapter.poolId(), block.timestamp - 301, 30 minutes);
        vm.expectRevert(NotConfigured.selector);
        adapter.quote(1 ether);
        vm.expectRevert(Unauthorized.selector);
        adapter.unlockCallback("");
        vm.expectRevert(Unauthorized.selector);
        adapter.buy{value: 1}(1, alice);
    }

    function testSettlementSlippageFailurePreservesCredits() public {
        fees.depositBaseFee{value: 1 ether}();
        vm.expectRevert(InsufficientBalance.selector);
        fees.executeBuys(0.5 ether, 0.51 ether);
        assertEq(fees.rewardETH(), 1 ether);
    }
}
