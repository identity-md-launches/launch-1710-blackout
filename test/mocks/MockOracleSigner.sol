// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @dev Test-only ERC1271 shim at the fixed attester address. Verifies signatures, including negative cases.
contract MockOracleSigner {
    address private immutable testSigner;

    constructor(address signer) {
        testSigner = signer;
    }

    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        return err == ECDSA.RecoverError.NoError && recovered == testSigner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}
