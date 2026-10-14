// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {ModuleCode} from "../src/lib/ModuleCode.sol";
import {SwarmCode} from "../src/lib/SwarmCode.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {FarmRewards} from "../src/FarmRewards.sol";
import {FarmCore} from "../src/FarmCore.sol";
import {FarmItems} from "../src/FarmItems.sol";
import {PackSale} from "../src/PackSale.sol";
import {StarterClaim} from "../src/StarterClaim.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {GridOperator} from "../src/GridOperator.sol";
import {Season} from "../src/Season.sol";
import {FarmEngine} from "../src/FarmEngine.sol";
import {Economy} from "../src/Economy.sol";
import {Enhancement} from "../src/Enhancement.sol";
import {Civic} from "../src/Civic.sol";
import {Billboards} from "../src/Billboards.sol";

/// @dev v3.10 review: whichever toolchain compiles this suite (repository via-IR, or the IMD verifier's
/// FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none), the creation code it produces must be one of the pins,
/// and all of it must come from the same toolchain. The hook embeds type(GameRegistry).creationCode of its own
/// build, so a registry from the other toolchain would bind to the Desk but never to the hook.
contract ToolchainPinsV310Test is Test {
    function _codes() private pure returns (bytes[14] memory c) {
        c[0] = type(RewardPool).creationCode;
        c[1] = type(FarmRewards).creationCode;
        c[2] = type(FarmCore).creationCode;
        c[3] = type(FarmItems).creationCode;
        c[4] = type(PackSale).creationCode;
        c[5] = type(StarterClaim).creationCode;
        c[6] = type(FeeRouter).creationCode;
        c[7] = type(GridOperator).creationCode;
        c[8] = type(Season).creationCode;
        c[9] = type(FarmEngine).creationCode;
        c[10] = type(Economy).creationCode;
        c[11] = type(Enhancement).creationCode;
        c[12] = type(Civic).creationCode;
        c[13] = type(Billboards).creationCode;
    }

    function testEveryModuleOfThisBuildMatchesOneToolchainPin() public pure {
        bytes32 registry = keccak256(type(GameRegistry).creationCode);
        bool launch = registry == SwarmCode.REGISTRY_LAUNCH;
        assertTrue(launch || registry == SwarmCode.REGISTRY_REPO, "registry pin");
        bytes32 params = keccak256(type(Params).creationCode);
        assertEq(params, launch ? SwarmCode.PARAMS_LAUNCH : SwarmCode.PARAMS_REPO, "params pin, same toolchain");
        bytes[14] memory c = _codes();
        for (uint256 role; role < 14; ++role) {
            bytes32 h = keccak256(c[role]);
            assertEq(h, launch ? ModuleCode.launchHash(role) : ModuleCode.repoHash(role), "module pin, same toolchain");
            assertTrue(ModuleCode.matches(role, h));
            assertFalse(ModuleCode.matches((role + 1) % 14, h), "pin is role-specific");
        }
    }

    /// @dev v3.13: foundry.toml is now the launch profile itself (via_ir false, bytecode_hash none), so the
    /// repository build and the launch build are one toolchain and both pins of every role are the same hash.
    function testPinsAreOneToolchainAndRejectUnknownCode() public pure {
        assertEq(SwarmCode.REGISTRY_LAUNCH, SwarmCode.REGISTRY_REPO, "one toolchain since v3.13");
        assertEq(SwarmCode.PARAMS_LAUNCH, SwarmCode.PARAMS_REPO, "one toolchain since v3.13");
        assertEq(
            keccak256(type(GameRegistry).creationCode), SwarmCode.REGISTRY_LAUNCH, "this build is the launch build"
        );
        assertEq(keccak256(type(Params).creationCode), SwarmCode.PARAMS_LAUNCH, "this build is the launch build");
        assertFalse(SwarmCode.isRegistry(keccak256(hex"ff")));
        assertFalse(SwarmCode.isParams(SwarmCode.REGISTRY_LAUNCH));
        bytes[14] memory c = _codes();
        for (uint256 role; role < 14; ++role) {
            assertEq(ModuleCode.launchHash(role), ModuleCode.repoHash(role), "one toolchain since v3.13");
            assertEq(keccak256(c[role]), ModuleCode.launchHash(role), "this build is the launch build");
            assertFalse(ModuleCode.matches(role, bytes32(0)));
        }
        assertFalse(ModuleCode.matches(14, ModuleCode.launchHash(0)));
    }
}
