// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "./lib/Errors.sol";

/// @notice Numeric governance only: immutable swarm, no owner, upgrade or asset authority.
contract Params {
    enum Key {
        EmissionBps,
        TariffBps,
        PriceStepBps,
        PriceFloor,
        PriceCeiling,
        PriceStart,
        DemandTarget,
        PriceDecayBps,
        RepairBps,
        LobbyKBps,
        LobbyMinWeight,
        FullSetBps,
        ComputePairBps,
        TripleCoreBps,
        AirflowBps,
        ElectricityPairBps,
        OffgridBps,
        RareSetBps,
        EpicSetBps,
        LegendarySetBps,
        MythicSetBps,
        SetCapBps,
        BuyBatch,
        SlippageBps,
        SellHourBps,
        SellDayBps,
        SellDeviationBps,
        Bounty,
        ExpansionPrice,
        MergePrice,
        OverclockPrice,
        PositiveWeight,
        DripPeriod,
        MeasureBounty,
        CreditBounty,
        AuditBounty,
        BuyBounty,
        EntropyBounty,
        SeasonScoreBounty,
        SeasonBounty,
        HeartbeatBps,
        KeeperGasPrice,
        HeartbeatCap,
        AuditHashThreshold,
        RepairHours
    }
    address public immutable swarmWallet;
    mapping(Key => uint256) public get;
    mapping(Key => uint256) public lastChanged;
    event ParamChanged(Key indexed key, uint256 oldValue, uint256 newValue, string letter);

    constructor(address swarm_, uint256 heartbeatBps_, uint256 heartbeatCap_) {
        if (swarm_ == address(0)) revert InvalidAddress();
        if (heartbeatBps_ < 200 || heartbeatBps_ > 5000) revert InvalidValue();
        if (heartbeatCap_ != 1 ether) revert InvalidValue();
        swarmWallet = swarm_;
        uint256[45] memory defaults = [
            uint256(350),
            1500,
            100,
            0.006 ether,
            0.03 ether,
            0.01 ether,
            20,
            200,
            250,
            5000,
            4000,
            1500,
            1000,
            2000,
            500,
            1500,
            2000,
            500,
            1000,
            2000,
            3000,
            10000,
            0.5 ether,
            150,
            500,
            400,
            5000,
            0.001 ether,
            100 ether,
            50 ether,
            100 ether,
            2500,
            42 days,
            0.00006 ether,
            0.00004 ether,
            0.00001 ether,
            0.00015 ether,
            0.00001 ether,
            0.00001 ether,
            0.00004 ether,
            heartbeatBps_,
            50_000_000,
            heartbeatCap_,
            100_000,
            6 ether
        ];
        for (uint256 i; i < defaults.length; ++i) {
            get[Key(i)] = defaults[i];
            lastChanged[Key(i)] = block.timestamp;
        }
    }

    function bounds(Key k) public pure returns (uint256, uint256) {
        if (k == Key.EmissionBps) return (200, 600);
        if (k == Key.TariffBps) return (1000, 3000);
        if (k == Key.PriceStepBps) return (50, 200);
        if (k == Key.PriceFloor) return (0.004 ether, 0.01 ether);
        if (k == Key.PriceCeiling) return (0.02 ether, 0.05 ether);
        if (k == Key.PriceStart) return (0.008 ether, 0.015 ether);
        if (k == Key.DemandTarget) return (10, 40);
        if (k == Key.PriceDecayBps) return (100, 400);
        if (k == Key.RepairBps) return (150, 400);
        if (k == Key.LobbyKBps) return (2500, 10000);
        if (k == Key.LobbyMinWeight) return (4000, 7000);
        if (k == Key.FullSetBps) return (500, 1500);
        if (k == Key.ComputePairBps) return (500, 1000);
        if (k == Key.TripleCoreBps) return (1000, 2000);
        if (k == Key.AirflowBps) return (250, 500);
        if (k == Key.ElectricityPairBps) return (500, 1500);
        if (k == Key.OffgridBps) return (1000, 2000);
        if (k == Key.RareSetBps) return (250, 500);
        if (k == Key.EpicSetBps) return (500, 1000);
        if (k == Key.LegendarySetBps) return (1000, 2000);
        if (k == Key.MythicSetBps) return (1500, 3000);
        if (k == Key.SetCapBps) return (8000, 10000);
        if (k == Key.RepairHours) return (4 ether, 8 ether);
        if (k == Key.BuyBatch) return (0.1 ether, 1 ether);
        if (k == Key.SlippageBps) return (10, 150);
        if (k == Key.SellHourBps) return (200, 600);
        if (k == Key.SellDayBps) return (100, 500);
        if (k == Key.SellDeviationBps) return (2000, 5000);
        if (k == Key.Bounty) return (0.0005 ether, 0.003 ether);
        if (k == Key.ExpansionPrice) return (50 ether, 500 ether);
        if (k == Key.MergePrice) return (25 ether, 250 ether);
        if (k == Key.OverclockPrice) return (50 ether, 500 ether);
        if (k == Key.PositiveWeight) return (2000, 5000);
        if (k == Key.DripPeriod) return (14 days, 56 days);
        if (k == Key.MeasureBounty) return (0.00001 ether, 0.0002 ether);
        if (k == Key.CreditBounty) return (0.000003 ether, 0.00005 ether);
        if (k == Key.AuditBounty) return (0.000001 ether, 0.00003 ether);
        if (k == Key.BuyBounty) return (0.000005 ether, 0.0003 ether);
        if (k == Key.EntropyBounty) return (0.000002 ether, 0.00005 ether);
        if (k == Key.SeasonScoreBounty) return (0.000001 ether, 0.00002 ether);
        if (k == Key.SeasonBounty) return (0.00001 ether, 0.0002 ether);
        if (k == Key.HeartbeatBps) return (200, 5000);
        if (k == Key.HeartbeatCap) return (1 ether, 1 ether);
        if (k == Key.AuditHashThreshold) return (10_000, 10_000_000);
        return (1_000_000, 100_000_000);
    }

    function set(Key k, uint256 next, string calldata letter) external {
        if (msg.sender != swarmWallet) revert Unauthorized();
        (uint256 lo, uint256 hi) = bounds(k);
        uint256 old = get[k];
        uint256 delta = next > old ? next - old : old - next;
        if (
            next < lo || next > hi || delta == 0 || delta > old / 10 || bytes(letter).length == 0
                || bytes(letter).length > 1024
        ) {
            revert InvalidValue();
        }
        if (block.timestamp < lastChanged[k] + 1 days) revert TooEarly();
        get[k] = next;
        lastChanged[k] = block.timestamp;
        emit ParamChanged(k, old, next, letter);
    }
}
