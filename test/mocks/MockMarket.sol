// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMarket} from "../../src/interfaces/Interfaces.sol";

contract MockMarket is IMarket {
    IERC20 public token;
    address public desk;
    bytes32 public gameConfigHash;

    function configureBinding(address d, bytes32 h) external {
        desk = d;
        gameConfigHash = h;
    }
    uint256 public initializedAt;
    address public fees;

    function configureLaunch(uint256 t, address f) external {
        initializedAt = t;
        fees = f;
    }
    uint256 public rate = 1_000_000 ether;
    bool public fail;
    uint256 public fillBps = 10000;

    constructor(address token_) {
        token = IERC20(token_);
    }

    function setFailure(bool value) external {
        fail = value;
    }

    function setFill(uint256 value) external {
        fillBps = value;
    }

    function setRate(uint256 value) external {
        rate = value;
    }

    function quote(uint256 ethAmount) external view returns (uint256) {
        return ethAmount * rate / 1 ether;
    }

    uint256 public depth = 1_000_000 ether;

    function setDepth(uint256 value) external {
        depth = value;
    }

    function maxSellBatch() external view returns (uint256) {
        return depth / 1000;
    }

    function quoteSell(uint256 amount) public view returns (uint256) {
        return amount * 1 ether / rate;
    }

    function sell(uint256 amount, uint256 minimum, address recipient) external returns (uint256 received) {
        require(!fail, "market failure");
        token.transferFrom(msg.sender, address(this), amount);
        received = quoteSell(amount) * fillBps / 10000;
        require(received >= minimum, "minimum");
        (bool ok,) = recipient.call{value: received}("");
        require(ok);
    }

    function buy(uint256, address recipient) external payable returns (uint256 amount) {
        require(!fail, "market failure");
        amount = msg.value * rate / 1 ether * fillBps / 10000;
        token.transfer(recipient, amount);
    }
}
