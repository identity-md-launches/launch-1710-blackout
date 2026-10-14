#!/usr/bin/env bash
# BLACKOUT v3.14 fork rehearsal of launch-v39.md L1-L4 and wiring on a local anvil fork of Robinhood Chain (4663).
# NO DEPLOY, NO BROADCAST: every transaction lands in the local fork only; the platform deployer is impersonated.
# Usage: tools/rehearse_v311.sh <robinhood-4663-rpc-url> [log-file]
# Builds with the IMD launch toolchain (viaIR false, bytecode_hash none) into out-launch/.
set -euo pipefail
RPC="${1:?usage: tools/rehearse_v311.sh <4663 rpc url> [log file]}"
LOG="${2:-artifacts/v314/rehearsal.log}"
PORT="${ANVIL_PORT:-8560}"
cd "$(dirname "$0")/.."
mkdir -p "$(dirname "$LOG")"
CHAIN=$(cast chain-id --rpc-url "$RPC")
if [ "$CHAIN" != "4663" ]; then echo "RPC is chain $CHAIN, not Robinhood Chain 4663; refusing to rehearse" >&2; exit 2; fi
# Compile before taking the fork: public RPCs may prune recent state while solc runs.
FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none FOUNDRY_OUT=out-launch FOUNDRY_CACHE_PATH=cache-launch \
  forge build > "${LOG%.log}-build.log" 2>&1
anvil --fork-url "$RPC" --port "$PORT" --silent > /tmp/anvil-v311.log 2>&1 &
ANVIL=$!
trap 'kill $ANVIL 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do cast chain-id --rpc-url "http://127.0.0.1:$PORT" >/dev/null 2>&1 && break; sleep 1; done
{
  echo "# BLACKOUT v3.14 fork rehearsal $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# upstream $RPC, anvil fork block $(cast block-number --rpc-url "http://127.0.0.1:$PORT"), basefee $(cast base-fee --rpc-url "http://127.0.0.1:$PORT") wei"
  echo "# toolchain: solc 0.8.26, optimizer 200, cancun, FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none"
  FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none FOUNDRY_OUT=out-launch FOUNDRY_CACHE_PATH=cache-launch \
    forge test --match-path test/fork/RehearsalV311.t.sol --fork-url "http://127.0.0.1:$PORT" -vv 2>&1 \
    | grep -v '^warning\|^note\|^ *│\|^ *─\|^ *╰\|^ *├\|^ *-->\|^ *|\|^[0-9]* |\|^$'
} | tee "$LOG"
