// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IRouter {
  struct Report {
    uint256 blockNumber;
    uint256 epoch;
    uint256 profitAmount;
    uint256 lossAmount; // Penalty or Slashing
    bytes32[7] merkleRoots;
    ValidatorOracle[] validatorsToExit; // Validators that should exit
    bytes[] exitedValidators; // Validators that already exited
    uint256 withdrawAmount; // Amount of ETH to send to WETH contract
    uint256 restWithdrawAmount; // Rest withdrawal validator amount
    uint256 routerExtraAmount; // Extra money on this contract
  }

  struct ValidatorOracle {
    address oracle;
    bytes[] validators;
  }

  event AddReportOracle(address indexed oracle);
  event BlacklistReportOracle(address indexed oracle, uint256 penalties);
  event BlacklistReportOracleManually(address indexed oracle, uint256 penalties);
  event ConsensusApprove(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ConsensusNotReached(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ExecuteReport(address indexed oracle, bytes32 hash, Report report);
  event FallbackEther(address indexed sender, uint amount);
  event InvalidateConsensus(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event PenalizeReportOracle(address indexed oracle, uint256 penalties, bytes32 hash, bool blacklisted);
  event ReceiveEther(address indexed sender, uint amount);
  event RemoveReportOracle(address indexed oracle);
  event RequestValidatorsExit(bytes[] publicKeys);
  event RewardReportOracle(address indexed oracle, uint256 penalties, bytes32 hash);
  event SetBunkerMode(bool bunkerMode);
  event SetLastConsensusEpoch(uint256 epoch);
  event SetMaxApr(uint256 maxApr);
  event SetMaxValidatorsToExit(uint256 maxValidatorsToExit);
  event SetMinBlockBeforeExecution(uint256 minBlocksBeforeExecution);
  event SetMinReportOracleQuorum(uint256 minQuorum);
  event SetReportBlockFrequency(uint256 frequency);
  event SetReportBlockNumber(uint256 blockNumber);
  event SetReportEpochFrequency(uint256 epoch);
  event SetReportEpochNumber(uint256 epochNumber);
  event SetReportOraclePenalizeLimit(uint256 newLimit);
  event SetReportOracleQuorum(uint256 quorum);
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
  event ValidatorsToExit(uint256 indexed epoch, ValidatorOracle[] validators);
}
