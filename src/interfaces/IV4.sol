// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ABI subset of Uniswap v4-core at 46c6834698c48bc4a463a86d8420f4eb1d7f3b75.
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

interface IV4PoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData) external returns (int256 delta);
    function take(address currency, address to, uint256 amount) external;
    function sync(address currency) external;
    function settle() external payable returns (uint256);
    function extsload(bytes32 slot) external view returns (bytes32);
}
