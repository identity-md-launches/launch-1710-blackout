// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice BLACKOUT v3.14 protocol endpoints, pinned to Robinhood Chain (4663).
/// @dev Never pass these literal addresses as launch constructor words.
library Robinhood {
    address internal constant PROJECT_FACTORY = 0x9C9D2FCB75c2C132C0AC0C42DF3819A42347265e;
    address internal constant PROJECT_REGISTRY = 0xF52bbE066B7Ad2d28C2195D066Ea08DCbcA88406;
    address internal constant INTAKE = 0xa43e6F75ee006411F79Ac1C84120606C2330DE82;
    address internal constant DELIVERY = 0xCE0E6a670AA75E161d02aca3C7F00B94cA428CCb;
    address internal constant ATTESTER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    address internal constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address internal constant LAUNCH_FACTORY = 0xA25B02A1e93903b790E6aaf7dA1b8B8d50294645;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
}
