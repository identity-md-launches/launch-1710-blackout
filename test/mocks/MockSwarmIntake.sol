// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ISwarmIntake} from "../../src/SwarmDesk.sol";
import {OracleAttestation} from "../../src/oracle/OracleAttestation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockSwarmIntake is ISwarmIntake {
    uint256 public price = 0.5 ether;
    uint256 public nonce;
    bytes public lastBody;
    bytes4 public failureSelector;
    mapping(bytes32 => Callback) public callbacks;

    function setPrice(uint256 p) external {
        price = p;
    }

    function priceOf(bytes32, address) external view returns (uint256) {
        return price;
    }

    function requestWithFailure(
        bytes32,
        bytes calldata body,
        Callback calldata cb,
        bytes4 failure,
        address asset,
        uint256 amount
    ) external payable returns (bytes32 id) {
        require(amount == price);
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount));
        id = keccak256(abi.encode(address(this), ++nonce));
        callbacks[id] = cb;
        lastBody = body;
        failureSelector = failure;
    }

    function result(bytes32 id, OracleAttestation.Attestation calldata a, bytes calldata sig) external returns (bool) {
        Callback memory cb = callbacks[id];
        (bool ok,) = cb.target.call{gas: 200_000}(abi.encodeWithSelector(cb.selector, id, a, sig));
        return ok;
    }

    function failure(bytes32 id, uint8 status, bytes32 reason) external returns (bool) {
        (bool ok,) = callbacks[id].target.call{gas: 200_000}(
            abi.encodeWithSelector(failureSelector, id, status, reason, uint16(0), uint16(0), bytes(""))
        );
        return ok;
    }
}

contract MockSwarmDelivery {
    function deliver(address target, bytes32 id, OracleAttestation.Attestation calldata a, bytes calldata sig)
        external
        returns (bool)
    {
        (bool ok,) = target.call{gas: 200_000}(
            abi.encodeWithSignature(
                "onOracleResult(bytes32,(bytes32,uint256,bytes32,uint8,bytes,uint256,uint64,uint64,bytes32,bytes32,uint16,uint16,uint16,uint64,uint64),bytes)",
                id,
                a,
                sig
            )
        );
        return ok;
    }
}
