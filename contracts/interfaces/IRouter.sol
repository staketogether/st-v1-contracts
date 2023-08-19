// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IRouter {
  struct Config {
    bool bunkerMode;
    uint256 minBlocksBeforeExecution;
    uint256 minReportOracleQuorum;
    uint256 oracleBlackListLimit;
    uint256 reportBlockFrequency;
    uint256 reportOracleQuorum;
  }

  struct Report {
    uint256 blockNumber;
    uint256 epoch;
    bytes32 merkleRoot;
    uint256 profitAmount;
    uint256 lossAmount; // Penalty or Slashing
    uint256 withdrawAmount; // Amount of ETH to send to WETH contract
    uint256 withdrawRefundAmount; // Rest withdrawal validator amount
    uint256 routerExtraAmount; // Extra money on this contract
    ValidatorOracle[] validatorsToRemove; // Validators that should be removed
    ValidatorOracle[] validatorsRemoved; // Validators that was removed
  }

  struct ValidatorOracle {
    address oracle;
    bytes[] validators;
  }

  event AddReportOracle(address indexed oracle);
  event BlacklistReportOracle(address indexed oracle, uint256 penalties);
  event ConsensusApprove(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ConsensusNotReached(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ExecuteReport(address indexed oracle, bytes32 hash, Report report);
  event InvalidateConsensus(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event PenalizeReportOracle(address indexed oracle, uint256 penalties, bytes32 hash, bool blacklisted);
  event ReceiveEther(address indexed sender, uint amount);
  event RemoveReportOracle(address indexed oracle);
  event RewardReportOracle(address indexed oracle, uint256 penalties, bytes32 hash);
  event SetConfig(Config config);
  event SetLastConsensusEpoch(uint256 epoch);
  event SetStakeTogether(address stakeTogether);
  event SkipNextBlockInterval(uint256 indexed epoch, uint256 indexed blockNumber);
  event SubmitReport(
    address indexed oracle,
    uint256 indexed blockNumber,
    uint256 indexed epoch,
    bytes32 hash
  );
  event UnBlacklistReportOracle(address indexed oracle, uint256 penalties);
  event UpdateReportOracleQuorum(uint256 quorum);
  event ValidatorsToRemove(uint256 indexed epoch, ValidatorOracle[] validators);
  event ValidatorsRemoved(uint256 indexed epoch, ValidatorOracle[] validators);
}
