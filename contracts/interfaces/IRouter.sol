// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IRouter {
  struct Config {
    bool bunkerMode;
    uint256 reportFrequency;
    uint256 reportDelay;
    uint256 oracleBlackListLimit;
    uint256 oracleQuorum;
    uint256 minOracleQuorum;
  }

  struct Report {
    uint256 epoch;
    bytes32 merkleRoot;
    uint256 profitAmount;
    uint256 lossAmount;
    uint256 withdrawAmount;
    uint256 withdrawRefundAmount;
    uint256 routerExtraAmount;
    bytes32[] validatorsToRemove;
  }

  event AddReportOracle(address indexed oracle);
  event BlacklistReportOracle(address indexed oracle, uint256 penalties);
  event ConsensusApprove(Report report, bytes32 hash);
  event ConsensusNotReached(Report report, bytes32 hash);
  event ExecuteReport(Report report, bytes32 hash);
  event PenalizeReportOracle(address indexed oracle, uint256 penalties, bytes32 hash, bool blacklisted);
  event ReceiveEther(address indexed sender, uint amount);
  event RemoveReportOracle(address indexed oracle);
  event RevokeConsensus(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event RewardReportOracle(address indexed oracle, uint256 penalties, bytes32 hash);
  event SetConfig(Config config);
  event SetLastConsensusEpoch(uint256 epoch);
  event SetStakeTogether(address stakeTogether);
  event SkipNextReportFrequency(uint256 indexed epoch, uint256 indexed blockNumber);
  event SubmitReport(Report report, bytes32 hash);
  event UnBlacklistReportOracle(address indexed oracle, uint256 penalties);
  event UpdateReportOracleQuorum(uint256 quorum);
  event ValidatorsToRemove(uint256 indexed epoch, bytes32[] validatorsHash);
}
