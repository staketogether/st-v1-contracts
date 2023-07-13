// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IRouter {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  /*******************
   ** REPORT ORACLE **
   *******************/

  event AddReportOracle(address indexed oracle);
  event RemoveReportOracle(address indexed oracle);
  event SetMinReportOracleQuorum(uint256 minQuorum);
  event SetReportOracleQuorum(uint256 quorum);
  event UpdateReportOracleQuorum(uint256 quorum);
  event SetReportOraclePenalizeLimit(uint256 newLimit);
  event PenalizeReportOracle(address indexed oracle, uint256 penalties, bytes32 hash, bool blacklisted);
  event RewardReportOracle(address indexed oracle, uint256 penalties, bytes32 hash);
  event BlacklistReportOracle(address indexed oracle, uint256 penalties);
  event BlacklistReportOracleManually(address indexed oracle, uint256 penalties);
  event UnBlacklistReportOracle(address indexed oracle, uint256 penalties);
  event SetBunkerMode(bool bunkerMode);
  event InvalidateConsensus(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);

  /************
   ** REPORT **
   ************/

  struct Values {
    uint256 total;
    uint256 users;
    uint256 pools;
    uint256 operators;
    uint256 stakeTogether;
  }

  struct ValidatorOracle {
    address oracle;
    bytes[] validators;
  }

  struct Report {
    uint256 blockNumber;
    uint256 epoch;
    uint256 lossAmount; // Penalty or Slashing
    uint256 extraAmount; // Extra money on this contract
    Values shares; // Shares to Mint
    Values amounts; // Amount to Send
    bytes32 poolsMerkleRoot; // Todo: missing merkle das pools
    ValidatorOracle[] validatorsToExit; // Validators that should exit
    bytes[] exitedValidators; // Validators that already exited
    uint256 restExitAmount; // Rest withdrawal validator amount
    uint256 withdrawAmount; // Amount of ETH to send to WETH contract
    uint256 apr; // Protocol APR for lending calculation
  }

  event SubmitReport(
    address indexed oracle,
    uint256 indexed blockNumber,
    uint256 indexed epoch,
    bytes32 hash
  );
  event ConsensusApprove(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ConsensusNotReached(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ExecuteReport(address indexed oracle, bytes32 hash, Report report);
  event SetReportBlockFrequency(uint256 frequency);
  event SetReportBlockNumber(uint256 blockNumber);
  event SetReportEpochFrequency(uint256 epoch);
  event SetReportEpochNumber(uint256 epochNumber);
  event SetMaxValidatorsToExit(uint256 maxValidatorsToExit);
  event SetMinBlockBeforeExecution(uint256 minBlocksBeforeExecution);
  event SetLastConsensusEpoch(uint256 epoch);
  event ValidatorsToExit(uint256 indexed epoch, ValidatorOracle[] validators);
  event SkipNextBlockInterval(uint256 indexed epoch, uint256 indexed blockNumber);
  event SetMaxApr(uint256 maxApr);

  /******************
   ** AUDIT REPORT **
   ******************/
}
