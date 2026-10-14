// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Civic} from "../src/Civic.sol";
import {Params} from "../src/Params.sol";
import {MockGameRegistry} from "./mocks/MockGameRegistry.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract ReviewWarInputs {
    mapping(uint256 => uint256) public districtActiveHash;
    uint256 public averageDaily = 3000 ether;

    function setHash(uint256 district, uint256 hash) external {
        districtActiveHash[district] = hash;
    }

    function setDaily(uint256 daily) external {
        averageDaily = daily;
    }
}

contract IndependentWarReview is Test {
    function testWarWinnerCannotChangeAfterDeadline() public {
        vm.warp(1_800_000_000);
        MockToken token = new MockToken();
        Params params = new Params(address(this), 200, 1 ether);
        MockGameRegistry registry = new MockGameRegistry(
            address(token), address(params), address(this), block.timestamp, keccak256("review"), 1, 0
        );
        Civic civic = Civic(deployCode("Civic.sol:Civic", abi.encode(address(registry))));
        assertEq(address(civic.registry()), address(registry));
        ReviewWarInputs inputs = new ReviewWarInputs();
        registry.setModule(1, address(inputs));
        registry.setModule(10, address(inputs));
        civic.announce(0, "Independent review fixture");
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        civic.enable(0);
        inputs.setHash(0, 100);
        inputs.setHash(1, 1000);
        civic.startWar(0, 1);
        address contributor = address(1);
        while (uint256(keccak256(abi.encodePacked(contributor))) % 8 != 0) {
            contributor = address(uint160(contributor) + 1);
        }
        token.transfer(contributor, 3000 ether);
        vm.startPrank(contributor);
        token.approve(address(civic), 3000 ether);
        civic.fundWar(3000 ether);
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        uint256 scoreBefore = civic.warScore(1, 0);
        assertGt(civic.warScore(1, 0), civic.warScore(1, 1));
        // No contest contribution remains possible; changes after the deadline must not reverse the result.
        inputs.setHash(1, 10000);
        inputs.setDaily(30000 ether);
        assertEq(civic.warScore(1, 0), scoreBefore);
        assertGt(civic.warScore(1, 0), civic.warScore(1, 1));
        civic.finishWar();
        (bool ok, bytes memory result) = address(civic).staticcall(abi.encodeWithSignature("wars(uint256)", 1));
        assertTrue(ok);
        (,, uint8 winner) = abi.decode(result, (uint8, uint8, uint8));
        assertEq(winner, 0);
        assertEq(address(civic.registry()), address(registry));
        (bool mutated,) = address(civic).call(abi.encodeWithSignature("setRegistry(address)", address(this)));
        assertFalse(mutated);
        assertEq(address(civic.registry()), address(registry));
    }
}
