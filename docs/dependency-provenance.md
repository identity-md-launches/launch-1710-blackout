# Vendored dependencies

- OpenZeppelin Contracts **v5.0.2**, https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.0.2. Contracts and MIT license are ordinary files under `vendor/openzeppelin`.
- forge-std **v1.9.6**, https://github.com/foundry-rs/forge-std/releases/tag/v1.9.6. Test/script sources and licenses are ordinary files under `vendor/forge-std`.
- `src/interfaces/IV4.sol` is a minimal ABI declaration checked against Uniswap v4-core commit **46c6834698c48bc4a463a86d8420f4eb1d7f3b75** (PoolKey, SwapParams, IPoolManager). `V4Market` uses the pool mapping at slot 6 described by that revision's StateLibrary and the hook flags from its Hooks library. No externally linked Solidity library is used.

No install, git submodule, FFI, filesystem permission, package registry or network access is needed for the default build/tests. The compiler is the Foundry-managed version pinned in `foundry.toml`.

Actual v4 integration tests also vendor the complete `src/` of v4-core at that revision, including its original licenses, and its solmate dependency at **4b47a19038b798b4a33d9749d25e570443520647**. The game's runtime uses the ABI subset; the vendored PoolManager is deployed only inside local tests. No Uniswap contract is deployed to a live chain by this assignment.
