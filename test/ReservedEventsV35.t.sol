// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {DeferredEntryTest} from "./Base.t.sol";
import {GridOperator} from "../src/GridOperator.sol";

contract ReservedEventsV35Test is DeferredEntryTest {
    function testReservedHeatwaveExtraCoolingWearAndBothProtections() public {
        uint256 exposed = place(alice, 6, 0, 0);
        uint256 airflow = place(bob, 6, 0, 0);
        place(bob, 10, 0, 1);
        address carol = makeAddr("reserved-event-cold-farm");
        uint256 cold = place(carol, 7, 0, 0);
        place(carol, 3, 0, 1);
        calmNext();
        step();
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(GridOperator.Kind.Heatwave, uint16(10000), uint8(8), bytes32(uint256(1)), true)
        );
        step();
        assertEq(d.items.data(exposed).durability, 9400);
        assertEq(d.items.data(airflow).durability, 9900);
        assertEq(d.items.data(cold).durability, 9900);
    }

    function testFuzzReservedFestivalCannotExceedFifteenPercent(uint16 severity) public {
        place(alice, 0, 0, 0);
        calmNext();
        step();
        vm.mockCall(
            address(d.grid),
            abi.encodeCall(d.grid.eventAt, (uint256(2))),
            abi.encode(GridOperator.Kind.Festival, severity, uint8(d.farm.district(alice)), bytes32(uint256(1)), true)
        );
        step();
        (, uint256 productive,,) = d.rewards.shares(2, alice);
        assertGe(productive, 10500);
        assertLe(productive, 11500);
    }
}
