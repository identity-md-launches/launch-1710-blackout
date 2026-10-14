// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {GridOperator} from "../GridOperator.sol";

interface IRewards {
    function eventAt(uint256 e) external view returns (GridOperator.Kind, uint16, uint8, bytes32, bool);
    function initialize(address p) external;
    function settle(address p, uint256 limit) external returns (uint256);
    function setWeight(address p, uint256 weight) external;
    function beginMining(address p, uint256 weight) external returns (bool);
    function epoch() external view returns (uint256);
    function live() external view returns (bool);
    function ready() external view returns (bool);
    function epochParam(uint256 e, uint256 key) external view returns (uint256);
    function epochStart() external view returns (uint256);
    function epochEnd() external view returns (uint256);
    function settledEpoch() external view returns (uint256);
    function pending(address p) external view returns (uint256);
    function epochTime(uint256 e) external view returns (uint256);
    function farmWeight(address p, uint256 e) external view returns (uint256);
    function spendTo(address p, uint256 amount, address to) external;
    function spend(address p, uint256 nominal) external returns (uint256);
    function scrap(address p, uint256 hash, uint256 minimum) external returns (uint256);
    function recordSales(uint256 count) external;
    function setReferrer(address p, address ref) external;
    function flagResync(address p) external;
    function seasonReady(uint256 week) external view returns (bool);
    function award(address p, uint256 amount) external;
    function releasePrize(uint256 amount) external;
}

interface ICore {
    function civicPurchase(address p, uint256 cost) external;
    function autoRepair(address p, uint256 e) external;
    function hasFarm(address p) external view returns (bool);
    function count() external view returns (uint256);
    function playerAt(uint256 i) external view returns (address);
    function level(address p) external view returns (uint256);
    function register(address p) external;
    function paidPackBought(address p, uint256 n, uint256 ethValue) external;
    function process(address p, uint256 epoch) external returns (uint256 raw, uint256 productive, uint256 power);
    function committedHash(address p) external view returns (uint256);
    function grantDrop(address p, bytes32 seed) external;
    function activity(address p, uint256 e, uint256 gross, uint256 net) external;
}

interface ISeason {
    function complete(address p, uint256 week) external;
    function recordSpend(address p, uint256 ethValue, bool districtSpend) external;
    function recordRepair(address p, uint256 week, uint256 amount) external;
    function recordActivity(address p, uint256 week, uint256 gross, uint256 committedHash) external;
    function addPrize(uint256 week, uint256 amount) external;
}
