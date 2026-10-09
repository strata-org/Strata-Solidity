// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// A failure comes with a counterexample, also when z3 would abbreviate
// the model's nested mapping values (deep, with repeated rows) with `let`,
// which Core's model reader cannot parse.
contract CounterexampleModels {
    mapping(uint256 => mapping(uint256 => uint256)) public allow;

    // Refuted, with a counterexample.
    /// @custom:strata requires a != c && a != d && a != e && c != d && c != e && d != e
    /// @custom:strata requires allow[a][1] == 11 && allow[a][2] == 12 && allow[a][3] == 13 && allow[a][4] == 14 && allow[a][5] == 15 && allow[a][6] == 16 && allow[a][7] == 17
    /// @custom:strata requires allow[c][1] == 11 && allow[c][2] == 12 && allow[c][3] == 13 && allow[c][4] == 14 && allow[c][5] == 15 && allow[c][6] == 16 && allow[c][7] == 17
    /// @custom:strata requires allow[d][1] == 51 && allow[d][2] == 52 && allow[d][3] == 53 && allow[d][4] == 54 && allow[d][5] == 55 && allow[d][6] == 56 && allow[d][7] == 57
    /// @custom:strata requires allow[e][1] == 51 && allow[e][2] == 52 && allow[e][3] == 53 && allow[e][4] == 54 && allow[e][5] == 55 && allow[e][6] == 56 && allow[e][7] == 57
    /// @custom:strata ensures allow[b][1] == 0
    function set(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 v) external {
        allow[b][1] = v + 1;
    }
}
