// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract EndowmentGameTest is BaseTest {
    function testRealMiningCannotSpendFutureEndowment() public {
        d = deployment.deploy(
            Deploy.Config(
                address(token),
                abi.encode(oracleFixture()),
                address(market),
                tokenLaunch(),
                keccak256("endowed fixture root"),
                freePackRoot(),
                123,
                2500,
                200,
                1 ether
            )
        );
        market.configureLaunch(tokenLaunch(), address(d.fees));
        uint256 principal = 250_000_000 ether;
        token.transfer(address(d.pool), principal);
        d.pool.fundEndowment();
        assertEq(d.pool.available(), 0);
        d.rewards.advanceEpoch();
        swarm = d.params.swarmWallet();
        uint256 packInflow = d.packs.price() * 88 / 100;
        payPack(alice);
        place(alice, 0, 0, 0);
        uint256 paid;
        for (uint256 i; i < 28; ++i) {
            calmNext();
            step();
            uint256 pending = d.rewards.pending(alice);
            if (pending > 0) {
                uint256 beforeBalance = token.balanceOf(alice);
                vm.prank(alice);
                d.rewards.claim(pending);
                paid += token.balanceOf(alice) - beforeBalance;
            }
            uint256 vested = principal - d.pool.lockedEndowment();
            assertLe(paid + d.pool.reserved(), vested + packInflow);
            assertEq(token.balanceOf(address(d.pool)) + paid, principal + packInflow);
            assertGe(token.balanceOf(address(d.pool)), d.pool.reserved() + d.pool.lockedEndowment());
        }
        assertGt(paid, 0);
        assertGt(d.pool.lockedEndowment(), 0);
    }
}
