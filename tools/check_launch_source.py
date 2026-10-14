#!/usr/bin/env python3
"""Offline source-preservation check for the bounded BLACKOUT hook import."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
CREATION_HASH = "0xedb2d58fb4632f2ef5a81b58ea05dcff0f5510e5448c6766539f89379109af10"
STRUCT_ADDITION = """
struct HookPermissions {
    bool beforeInitialize;
    bool afterInitialize;
    bool beforeAddLiquidity;
    bool afterAddLiquidity;
    bool beforeRemoveLiquidity;
    bool afterRemoveLiquidity;
    bool beforeSwap;
    bool afterSwap;
    bool beforeDonate;
    bool afterDonate;
    bool beforeSwapReturnDelta;
    bool afterSwapReturnDelta;
    bool afterAddLiquidityReturnDelta;
    bool afterRemoveLiquidityReturnDelta;
}
"""
FUNCTION_ADDITION = """    function getHookPermissions() public pure returns (HookPermissions memory p) {
        p.afterInitialize = true;
        p.beforeSwap = true;
        p.afterSwap = true;
        p.beforeSwapReturnDelta = true;
        p.afterSwapReturnDelta = true;
    }

"""


def check_sources():
    pins = json.loads((ROOT / "docs/launch-upstream-sha256.json").read_text())
    assert pins["commit"] == "86e71d47b12094dc6a37c6a05cd4f84f2f970b78"
    for name, expected in pins["sha256"].items():
        content = (ROOT / name).read_bytes()
        if name == "src/V4Market.sol":
            struct_anchor = b'import "./lib/Errors.sol";\n'
            function_anchor = (
                b"    receive() external payable {\n"
                b"        if (msg.sender != address(manager)) revert Unauthorized();\n"
                b"    }\n\n"
            )
            for anchor, addition in (
                (struct_anchor, STRUCT_ADDITION.encode()),
                (function_anchor, FUNCTION_ADDITION.encode()),
            ):
                assert content.count(anchor + addition) == 1, f"Missing/extraneous permitted addition: {name}"
                content = content.replace(anchor + addition, anchor, 1)
        assert hashlib.sha256(content).hexdigest() == expected, f"Upstream bytes changed: {name}"
    for directory in ("src", "lib", "vendor"):
        for path in (ROOT / directory).rglob("*"):
            if not path.is_file():
                continue
            name = path.relative_to(ROOT).as_posix()
            assert name in pins["sha256"] or name == "src/LaunchToken.sol", f"Unexpected source: {name}"
    assert (ROOT / "src/LaunchToken.sol").is_file(), "Missing production launch token"
    print(f"PASS: {len(pins['sha256'])} upstream files preserved, with only the two permitted hook additions.")


def check_artifacts():
    artifact = json.loads((ROOT / "out/V4Market.sol/V4Market.json").read_text())
    creation = artifact["bytecode"]
    runtime = artifact["deployedBytecode"]
    assert not creation.get("linkReferences"), "Unlinked creation code"
    actual = subprocess.check_output(["cast", "keccak", creation["object"]], text=True).strip()
    assert actual == CREATION_HASH, f"Unexpected creation hash: {actual}"
    size = len(bytes.fromhex(runtime["object"].removeprefix("0x")))
    assert size == 21_982, f"Unexpected runtime size: {size}"
    print(f"PASS: V4Market creation hash {actual}; runtime {size:,} bytes.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", action="store_true", help="also check artifacts produced by forge build")
    args = parser.parse_args()
    check_sources()
    if args.artifacts:
        check_artifacts()
