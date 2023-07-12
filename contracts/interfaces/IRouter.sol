// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

/// @custom:security-contact security@staketogether.app
interface IRouter {
  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  receive() external payable;

  fallback() external payable;

  function setStakeTogether(address _stakeTogether) external;

  function pause() external;

  function unpause() external;

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

  function isReportOracle(address _oracle) external view returns (bool);

  function isReportOracleBlackListed(address _oracle) external view returns (bool);

  function addReportOracle(address _oracle) external;

  function removeReportOracle(address oracle) external;

  function setMinReportOracleQuorum(uint256 _quorum) external;

  function setReportOracleQuorum(uint256 _quorum) external;

  function setReportOraclePenalizeLimit(uint256 _oraclePenalizeLimit) external;

  function blacklistReportOracle(address _oracle) external;

  function unBlacklistReportOracle(address _oracle) external;

  function addSentinel(address _sentinel) external;

  function removeSentinel(address _sentinel) external;

  function setBunkerMode(bool _bunkerMode) external;

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

  function submitReport(uint256 _epoch, bytes32 _hash, Report calldata _report) external;

  function executeReport(bytes32 _hash, Report calldata _report) external;

  function invalidateConsensus(uint256 _epoch, bytes32 _hash) external;

  function setLastConsensusEpoch(uint256 _epoch) external;

  function isReadyToSubmit(uint256 _epoch) external view returns (bool);

  function isReadyToExecute(uint256 _epoch, bytes32 _hash) external view returns (bool);

  function setMinBlockBeforeExecution(uint256 _minBlocksBeforeExecution) external;

  function setMaxValidatorsToExit(uint256 _maxValidatorsToExit) external;

  function setReportBlockFrequency(uint256 _frequency) external;

  function setMaxApr(uint256 _maxApr) external;

  /******************
   ** AUDIT REPORT **
   ******************/

  function auditReport(Report calldata _report, bytes32 _hash) external view returns (bool);
}
