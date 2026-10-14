// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {EndowmentEscrow} from "../src/EndowmentEscrow.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {MarketFactory} from "../src/MarketFactory.sol";
import {V4Market} from "../src/V4Market.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";

contract DeployGateV314Test is Test {
    bytes32 private constant GAME_CONFIG_HASH = 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3;
    /// @dev v3.16 eighth constructor word: the project wallet that signs the one `bind` call (not a protocol address).
    address private constant BINDER = 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007;

    function testAllLaunchConstructorsWorkWithNoProtocolCode() public {
        assertEq(Robinhood.PROJECT_FACTORY.code.length, 0);
        assertEq(Robinhood.PROJECT_REGISTRY.code.length, 0);
        assertEq(Robinhood.POOL_MANAGER.code.length, 0);
        assertEq(Robinhood.LAUNCH_FACTORY.code.length, 0);
        assertEq(Robinhood.INTAKE.code.length, 0);
        assertEq(Robinhood.DELIVERY.code.length, 0);
        assertEq(Robinhood.IMD.code.length, 0);
        assertEq(Robinhood.ATTESTER.code.length, 0);
        SwarmDesk desk = SwarmDesk(
            deployCode(
                "SwarmDesk.sol:SwarmDesk",
                abi.encode(
                    bytes32("oracle.request@oracle-1"),
                    uint256(5391989333430298100116863486635657822062725418115979424500284366258177),
                    bytes32(0x2fc5a57f2c5f7bc083ea8ac5016234f1a0b1c68a514e5d921956cc57948534ef),
                    bytes32(0xc13efed8438aab53ea052a4507def2dc4ce9856765520dfa28c66daa59cfc11d),
                    bytes32(0x00e69e4445c7ca7256338293f9f9cea439fd2beb1959d1d43ebec7b14493e2f6),
                    bytes32(0xc0ae7511b06744cf7ccadc6b60ff9ff96cb7234cf32988850df33324861cc8df),
                    GAME_CONFIG_HASH,
                    BINDER
                )
            )
        );
        assertEq(desk.binder(), BINDER);
        assertEq(BINDER.code.length, 0, "the binder is a wallet; the constructor never requires code");
        assertEq(desk.oracleConfig().signer, Robinhood.ATTESTER);
        assertEq(desk.oracleConfig().intake, Robinhood.INTAKE);
        assertEq(desk.oracleConfig().delivery, Robinhood.DELIVERY);
        assertEq(desk.oracleConfig().asset, Robinhood.IMD);
        assertEq(desk.bindingConfig().factory, Robinhood.PROJECT_FACTORY);
        assertEq(desk.bindingConfig().gameConfigHash, GAME_CONFIG_HASH);
        EndowmentEscrow escrow = new EndowmentEscrow(address(desk));
        assertEq(escrow.factory(), Robinhood.PROJECT_FACTORY);
        assertEq(escrow.records(), Robinhood.PROJECT_REGISTRY);
        Params params = new Params(address(desk), 200, 1 ether);
        // Test-only token/root inputs, never launch values or substitutes for the committed roots.
        address token = makeAddr("test-only token");
        MarketFactory factory = new MarketFactory();
        MarketFactory.Config memory c = MarketFactory.Config(
            Robinhood.POOL_MANAGER, token, 60, Robinhood.LAUNCH_FACTORY, address(desk), GAME_CONFIG_HASH
        );
        (bytes32 salt,) = factory.findSalt(c, 0, 100000);
        V4Market hook = factory.deploy(c, salt);
        assertEq(address(hook.applicationFactory()), Robinhood.PROJECT_FACTORY);
        GameRegistry registry = new GameRegistry(
            token,
            address(params),
            address(hook),
            keccak256("test-only starter"),
            keccak256("test-only free"),
            1,
            200_000_000 ether
        );
        assertEq(address(registry.factory()), Robinhood.PROJECT_FACTORY);
        string[14] memory names = [
            "RewardPool",
            "FarmRewards",
            "FarmCore",
            "FarmItems",
            "PackSale",
            "StarterClaim",
            "FeeRouter",
            "GridOperator",
            "Season",
            "FarmEngine",
            "Economy",
            "Enhancement",
            "Civic",
            "Billboards"
        ];
        for (uint256 i; i < names.length; ++i) {
            address module = deployCode(string.concat(names[i], ".sol:", names[i]), abi.encode(address(registry)));
            assertGt(module.code.length, 0);
            assertLe(module.code.length, 24576);
        }
    }
}
