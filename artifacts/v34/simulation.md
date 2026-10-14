# v3.4 simulation: medians [minimum, maximum], five seeds

35 days; 20% endowment, zero external ETH bootstrap. Unrepaid cohorts remain censored, never counted as repaid.

| Scenario | Drip | Stall day | Drawdown | Gross team ETH | Net team ETH | Pack ETH |
|---|---:|---|---|---|---|---|
| steady | 42 | 35.000 [35.000, 35.000] | 0.099 [0.091, 0.107] | 9.943 [9.915, 9.969] | 9.701 [9.674, 9.727] | 75.131 [74.945, 75.332] |
| steady | 56 | 35.000 [35.000, 35.000] | 0.083 [0.076, 0.088] | 9.933 [9.870, 9.948] | 9.692 [9.629, 9.706] | 75.147 [74.669, 75.268] |
| hype | 42 | 13.750 [13.500, 35.000] | 0.815 [0.811, 0.817] | 11.096 [11.087, 11.165] | 10.855 [10.845, 10.924] | 82.606 [82.464, 83.120] |
| hype | 56 | 35.000 [13.750, 35.000] | 0.805 [0.803, 0.810] | 11.059 [11.037, 11.137] | 10.818 [10.796, 10.896] | 82.373 [82.205, 82.972] |
| weak | 42 | 35.000 [35.000, 35.000] | 0.175 [0.172, 0.188] | 2.259 [2.220, 2.286] | 2.017 [1.979, 2.045] | 16.834 [16.517, 17.012] |
| weak | 56 | 35.000 [35.000, 35.000] | 0.157 [0.148, 0.159] | 2.258 [2.196, 2.262] | 2.017 [1.955, 2.021] | 16.838 [16.376, 16.874] |

Stall >35 is represented as 35 in this table only; raw JSON retains null. Net team deducts the inherited explicit off-chain schedule budget; no heartbeat withdrawal exists.

| Scenario / drip | Join week | Whole-cohort payback days | Fraction repaid | Conditional payback (repaid only) |
|---|---:|---|---|---|
| steady / 42 | 1 | not reached in 5/5 seeds | 0.380 [0.379, 0.403] | 20.500 [20.000, 21.000] |
| steady / 42 | 2 | not reached in 5/5 seeds | 0.117 [0.101, 0.121] | 18.750 [18.000, 19.000] |
| steady / 42 | 3 | not reached in 5/5 seeds | 0.062 [0.046, 0.079] | 15.250 [15.250, 15.500] |
| steady / 56 | 1 | not reached in 5/5 seeds | 0.376 [0.369, 0.387] | 20.250 [20.250, 20.750] |
| steady / 56 | 2 | not reached in 5/5 seeds | 0.114 [0.091, 0.127] | 18.125 [16.500, 19.000] |
| steady / 56 | 3 | not reached in 5/5 seeds | 0.057 [0.038, 0.066] | 15.250 [14.625, 16.875] |
| hype / 42 | 1 | not reached in 5/5 seeds | 0.161 [0.153, 0.170] | 11.250 [11.000, 11.750] |
| hype / 42 | 2 | not reached in 5/5 seeds | 0.040 [0.028, 0.052] | 19.250 [17.750, 19.625] |
| hype / 42 | 3 | not reached in 5/5 seeds | 0.059 [0.037, 0.071] | 16.000 [14.750, 16.500] |
| hype / 56 | 1 | not reached in 5/5 seeds | 0.158 [0.153, 0.161] | 11.250 [10.750, 11.750] |
| hype / 56 | 2 | not reached in 5/5 seeds | 0.031 [0.025, 0.051] | 18.375 [16.500, 20.000] |
| hype / 56 | 3 | not reached in 5/5 seeds | 0.046 [0.045, 0.072] | 16.000 [14.250, 16.250] |
| weak / 42 | 1 | not reached in 5/5 seeds | 0.092 [0.071, 0.108] | 24.375 [23.375, 26.375] |
| weak / 42 | 2 | not reached in 5/5 seeds | 0.026 [0.006, 0.039] | 20.250 [17.000, 21.250] |
| weak / 42 | 3 | not reached in 5/5 seeds | 0.009 [0.009, 0.010] | 16.500 [14.750, 18.750] |
| weak / 56 | 1 | not reached in 5/5 seeds | 0.083 [0.061, 0.102] | 26.000 [22.750, 26.500] |
| weak / 56 | 2 | not reached in 5/5 seeds | 0.025 [0.006, 0.045] | 20.750 [17.250, 23.750] |
| weak / 56 | 3 | not reached in 5/5 seeds | 0.009 [0.000, 0.010] | 15.375 [12.750, 17.250] |

## Steady / 42-day lever comparison

| Current-epoch entry | Inflow regulator | Pack ETH | Repaid week 2 | Repaid week 3 |
|---|---|---|---|---|
| True | True | 75.131 [74.945, 75.332] | 0.117 [0.101, 0.121] | 0.062 [0.046, 0.079] |
| False | True | 76.211 [76.028, 76.362] | 0.126 [0.085, 0.139] | 0.057 [0.049, 0.064] |
| True | False | 78.972 [78.488, 79.357] | 0.082 [0.061, 0.103] | 0.047 [0.035, 0.053] |
