// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Economy} from "../src/Economy.sol";
import {FarmItems} from "../src/FarmItems.sol";
import {Params} from "../src/Params.sol";
import {MockGameRegistry} from "./mocks/MockGameRegistry.sol";

contract IndependentYieldFloorReview is Test {
    function testFirstEpochItemQuotesKeepNonzeroFloorAtCorrectScale() public {
        Params params = new Params(address(this), 200, 1 ether);
        MockGameRegistry registry =
            new MockGameRegistry(address(this), address(params), address(this), 1, keccak256("review"), 1, 0);
        Economy economy = new Economy(address(registry));
        address rewards = makeAddr("unsettledRewards");
        address inventory = makeAddr("inventory");
        registry.setModule(1, rewards);
        registry.setModule(3, inventory);
        vm.mockCall(rewards, abi.encodeWithSignature("lastYieldPerHash()"), abi.encode(uint256(0)));
        FarmItems.Item memory item = FarmItems.Item(address(this), 9000, 0, 0, 0, false, false);
        vm.mockCall(inventory, abi.encodeWithSignature("data(uint256)", 1), abi.encode(item));
        assertEq(economy.itemDaily(1), 0.04 ether);
        assertEq(economy.repairQuote(1), 0.01 ether); // Six hours for ten percent restoration.
        assertEq(economy.enhanceQuote(1), 0.01 ether); // +1 costs one quarter item-yield day.
        vm.mockCall(rewards, abi.encodeWithSignature("lastYieldPerHash()"), abi.encode(uint256(1e30 * 3)));
        assertEq(economy.itemDaily(1), 0.12 ether);
        assertEq(economy.repairQuote(1), 0.03 ether);
        assertEq(economy.enhanceQuote(1), 0.03 ether);
    }
}
