// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Params} from "../src/Params.sol";
import {FarmItems} from "../src/FarmItems.sol";
import "../src/lib/Errors.sol";

contract DeploymentTest is BaseTest {
    function testImmutableGraphAndEip170Sizes() public view {
        assertEq(d.items.farmCore(), address(d.farm));
        assertEq(d.items.engine(), address(d.engine));
        assertEq(d.pool.rewards(), address(d.rewards));
        assertEq(address(d.farm.engine()), address(d.engine));
        assertEq(d.engine.core(), address(d.farm));
        assertEq(d.fees.rewards(), address(d.rewards));
        assertEq(d.fees.team(), team);
        address[12] memory all = [
            address(d.params),
            address(d.pool),
            address(d.rewards),
            address(d.farm),
            address(d.items),
            address(d.packs),
            address(d.starter),
            address(d.fees),
            address(d.grid),
            address(d.season),
            address(d.engine),
            address(d.registry)
        ];
        for (uint256 i; i < all.length; ++i) {
            assertGt(all[i].code.length, 0);
            assertLe(all[i].code.length, 24576);
        }
    }

    function testConstructorRejectsMissingInputsAndDoesNotCallExternalContracts() public {
        vm.expectRevert(InvalidAddress.selector);
        new Params(address(0), 200, 1 ether);
        Params p = new Params(alice, 200, 1 ether);
        assertEq(p.swarmWallet(), alice);
        vm.expectRevert(InvalidValue.selector);
        new Params(alice, 199, 1 ether);
        vm.expectRevert(InvalidValue.selector);
        new Params(alice, 5001, 1 ether);
        Params funded = new Params(alice, 1000, 1 ether);
        assertEq(funded.get(Params.Key.HeartbeatBps), 1000);
        assertEq(funded.get(Params.Key.HeartbeatCap), 1 ether);
        vm.expectRevert(InvalidValue.selector);
        new Params(alice, 200, 1 ether - 1);
        vm.expectRevert(InvalidValue.selector);
        new Params(alice, 200, 10 ether + 1);
        FarmItems items = new FarmItems(makeAddr("empty registry"));
        assertEq(items.capacity(alice), 15);
        vm.expectRevert(InvalidValue.selector);
        deployment.deploy(
            Deploy.Config(
                address(0),
                abi.encode(oracleFixture()),
                address(market),
                launch,
                keccak256("root"),
                freePackRoot(),
                123,
                0,
                200,
                1 ether
            )
        );
    }

    function testForeignCallerDoesNotGetAnyAuthority() public {
        vm.prank(bob);
        Deploy.Deployment memory fresh = deployment.deploy(
            Deploy.Config(
                address(token),
                abi.encode(oracleFixture()),
                address(market),
                launch,
                keccak256("root"),
                freePackRoot(),
                123,
                0,
                200,
                1 ether
            )
        );
        assertNotEq(fresh.params.swarmWallet(), bob);
        assertGt(fresh.params.swarmWallet().code.length, 0);
        assertEq(fresh.fees.team(), team);
        assertEq(fresh.pool.rewards(), address(fresh.rewards));
    }
}
