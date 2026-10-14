// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {SignatureChecker as OZSignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @dev The pinned OZ exposes the memory equivalent; preserve canonical oracle source and semantics.
library SignatureChecker {
    function isValidSignatureNowCalldata(address signer, bytes32 hash, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        return OZSignatureChecker.isValidSignatureNow(signer, hash, signature);
    }
}
