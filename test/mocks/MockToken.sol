// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    address public callback;
    bytes public callbackData;
    bool public callbackSucceeded;
    bool private inside;
    bool public failTransfers;

    function setCallback(address target, bytes calldata data) external {
        callback = target;
        callbackData = data;
    }

    function setFail(bool value) external {
        failTransfers = value;
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(!failTransfers, "test transfer failure");
        super._update(from, to, amount);
        if (callback != address(0) && !inside) {
            inside = true;
            (callbackSucceeded,) = callback.call(callbackData);
            inside = false;
        }
    }

    constructor() ERC20("TEST ONLY BLACKOUT", "TEST") {
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
