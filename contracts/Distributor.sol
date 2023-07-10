// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';
import './WETH.sol';
import './LETH.sol';

/// @custom:security-contact security@staketogether.app
contract Distributor is AccessControl, Pausable, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_REPORT_MANAGER_ROLE = keccak256('ORACLE_REPORT_MANAGER_ROLE');
  bytes32 public constant ORACLE_REPORT_ROLE = keccak256('ORACLE_REPORT_ROLE');

  StakeTogether public stakeTogether;
  WETH public WETHContract;
  LETH public LETHContract;

  constructor(address _WETH, address _LETH) {
    WETHContract = WETH(payable(_WETH));
    LETHContract = LETH(payable(_LETH));
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(ORACLE_REPORT_MANAGER_ROLE, msg.sender);
  }

  event EtherReceived(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);

  receive() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /*****************
   ** REPORT ORACLES **
   *****************/

  modifier onlyOracle() {
    require(
      activeReportOracles[msg.sender] && reportOraclesBlacklist[msg.sender] < oraclePenalizeLimit,
      'ONLY_ACTIVE_ORACLES'
    );
    _;
  }

  event AddReportOracle(address indexed oracle);
  event RemoveReportOracle(address indexed oracle);
  event PenalizeReportOracle(address indexed oracle, uint256 penalties, bytes32 hash, bool removed);
  event SetReportOracleQuorum(uint256 newQuorum);
  event SetReportOraclePenalizeLimit(uint256 newLimit);
  event SetBunkerMode(bool bunkerMode);

  address[] private reportOracles;
  mapping(address => bool) private activeReportOracles;
  mapping(address => uint256) public reportOraclesBlacklist;
  uint256 public oracleQuorum = 1; // Todo: Mainnet = 3
  uint256 public oraclePenalizeLimit = 3;
  bool public bunkerMode = false;

  function getReportOracles() external view returns (address[] memory) {
    return reportOracles;
  }

  function getActiveReportOracleCount() internal view returns (uint256) {
    uint256 activeCount = 0;
    for (uint256 i = 0; i < reportOracles.length; i++) {
      if (activeReportOracles[reportOracles[i]]) {
        activeCount++;
      }
    }
    return activeCount;
  }

  function isReportOracle(address _oracle) public view returns (bool) {
    return activeReportOracles[_oracle] && reportOraclesBlacklist[_oracle] < oraclePenalizeLimit;
  }

  function addReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportOracles.length < oracleQuorum, 'REPORT_ORACLE_QUORUM_REACHED');
    require(!activeReportOracles[_oracle], 'REPORT_ORACLE_EXISTS');
    reportOracles.push(_oracle);
    activeReportOracles[_oracle] = true;
    emit AddReportOracle(_oracle);
    _updateQuorum();
  }

  function removeReportOracle(address oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(activeReportOracles[oracle], 'ORACLE_NOT_EXISTS');
    activeReportOracles[oracle] = false;
    emit RemoveReportOracle(oracle);
    _updateQuorum();
  }

  function _setReportOracleQuorum(uint256 _oracleQuorum) internal {
    oracleQuorum = _oracleQuorum;
    emit SetReportOracleQuorum(_oracleQuorum);
  }

  function _updateQuorum() internal onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    uint256 totalOracles = getActiveReportOracleCount();
    uint256 newQuorum = (totalOracles * 8) / 10;

    newQuorum = newQuorum < 3 ? 3 : newQuorum;
    newQuorum = newQuorum > totalOracles ? totalOracles : newQuorum;

    oracleQuorum = newQuorum;
    emit SetReportOracleQuorum(newQuorum);
  }

  function _penalizeOracle(address _oracle, bytes32 _reportHash) internal {
    reportOraclesBlacklist[_oracle]++;

    bool remove = reportOraclesBlacklist[_oracle] >= oraclePenalizeLimit;
    if (remove) {
      require(activeReportOracles[_oracle], 'ORACLE_NOT_EXISTS');
      activeReportOracles[_oracle] = false;
      emit RemoveReportOracle(_oracle);
      _updateQuorum();
    }

    emit PenalizeReportOracle(_oracle, reportOraclesBlacklist[_oracle], _reportHash, remove);
  }

  function setReportOraclePenalizeLimit(uint256 _oraclePenalizeLimit) external onlyRole(ADMIN_ROLE) {
    oraclePenalizeLimit = _oraclePenalizeLimit;
    emit SetReportOraclePenalizeLimit(_oraclePenalizeLimit);
  }

  function setBunkerMode(bool _bunkerMode) external onlyRole(ADMIN_ROLE) {
    bunkerMode = _bunkerMode;
    emit SetBunkerMode(_bunkerMode);
  }

  /*****************
   ** REPORT **
   *****************/

  event SubmitReport(
    address indexed oracle,
    uint256 indexed blockNumber,
    uint256 indexed epoch,
    bytes32 hash
  );
  event ConsensusReject(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ConsensusApprove(uint256 indexed blockNumber, uint256 indexed epoch, bytes32 hash);
  event ExecuteReport(
    address indexed oracle,
    uint256 indexed blockNumber,
    uint256 indexed epoch,
    bytes32 hash,
    Report report
  );

  event SetReportBlockFrequency(uint256 frequency);
  event SetReportBlockNumber(uint256 blockNumber);
  event SetReportEpochFrequency(uint256 epoch);
  event SetReportEpochNumber(uint256 epochNumber);
  event SetMaxExitValidators(uint256 maxValidatorsToExit);
  event ValidatorsToExit(uint256 indexed epoch, ValidatorOracle[] validators);

  struct Units {
    uint256 total;
    uint256 pools;
    uint256 operators;
    uint256 stakeTogether;
  }

  struct ValidatorOracle {
    address oracle;
    bytes[] validators;
  }

  struct Report {
    uint256 epoch;
    uint256 lossAmount; // Penalty or Slashing
    uint256 extraAmount; // Extra money on this contract
    Units shares; // Shares to Mint
    Units amounts; // Amount to Send
    ValidatorOracle[] validatorsToExit; // Validators that should exit
    bytes[] exitedValidators; // Validators that already exited
    uint256 restExitAmount; // Rest withdrawal validator amount
    uint256 exitAmount; // Sub withdrawal validator amount
    uint256 WETHAmount; // Amount of ETH to send to WETH contract
    uint256 apr; // Protocol APR for lending calculation
  }

  struct AuditReport {
    address oracle;
    bytes32 reportHash;
  }

  mapping(bytes32 => address[]) public oracleReports;
  mapping(bytes32 => uint256) public oracleReportsVotes;
  mapping(bytes32 => bool) public oracleReportsKey;
  mapping(uint256 => AuditReport[]) public auditReports;
  mapping(uint256 => bytes32) public consensusReport;
  mapping(uint256 => bool) public executedReport;
  uint256 public maxValidatorsToExit = 100;

  uint256 public reportBlockFrequency = 1;
  uint256 public reportBlockNumber = 1;
  uint256 public reportEpochFrequency = 1;
  uint256 public reportEpochNumber = 1;

  function submitReport(
    uint256 _epoch,
    bytes32 _hash,
    Report calldata _report
  ) external onlyOracle whenNotPaused {
    auditReport(_epoch, _report);

    if (block.number >= reportBlockNumber + reportBlockFrequency) {
      reportBlockNumber += reportBlockFrequency;
    }

    oracleReportsVotes[_hash]++;
    oracleReports[_hash].push(msg.sender);
    auditReports[_epoch].push(AuditReport({ oracle: msg.sender, reportHash: _hash }));

    if (oracleReportsVotes[_hash] >= oracleQuorum) {
      consensusReport[_epoch] = _hash;
      emit ConsensusApprove(block.number, _epoch, _hash);
    }
  }

  function executeReport(Report calldata _report) external onlyOracle whenNotPaused nonReentrant {
    bytes32 reportHash = keccak256(abi.encode(_report));
    bytes32 consensusHash = consensusReport[_report.epoch];
    require(reportHash == consensusHash, 'INVALID_REPORT');
    require(!executedReport[_report.epoch], 'REPORT_ALREADY_EXECUTED');

    if (_report.lossAmount > 0) {
      stakeTogether.mintPenalty(_report.epoch, _report.lossAmount);
    }

    if (_report.extraAmount > 0) {
      stakeTogether.refundPool{ value: _report.extraAmount }(_report.epoch);
    }

    if (_report.shares.pools > 0) {
      stakeTogether.mintRewards{ value: _report.amounts.pools }(
        _report.epoch,
        stakeTogether.poolFeeAddress(), // Todo: Check Pools Addresses During Transition
        _report.shares.pools
      );
    }

    if (_report.amounts.operators > 0) {
      stakeTogether.mintRewards{ value: _report.amounts.operators }(
        _report.epoch,
        stakeTogether.operatorFeeAddress(),
        _report.shares.operators
      );
    }

    if (_report.amounts.stakeTogether > 0) {
      stakeTogether.mintRewards{ value: _report.amounts.stakeTogether }(
        _report.epoch,
        stakeTogether.stakeTogetherFeeAddress(),
        _report.shares.stakeTogether
      );
    }

    if (_report.validatorsToExit.length > 0) {
      emit ValidatorsToExit(_report.epoch, _report.validatorsToExit);
    }

    if (_report.exitedValidators.length > 0) {
      for (uint256 i = 0; i < _report.exitedValidators.length; i++) {
        stakeTogether.removeValidator(_report.epoch, _report.exitedValidators[i]);
      }
    }

    if (_report.restExitAmount > 0) {
      stakeTogether.refundPool{ value: _report.restExitAmount }(_report.epoch);
    }

    if (_report.exitAmount > 0) {
      stakeTogether.exitBeaconAmount(_report.epoch, _report.exitAmount);
    }

    if (_report.WETHAmount > 0) {
      payable(address(WETHContract)).transfer(_report.WETHAmount);
    }

    if (_report.apr > 0) {
      LETHContract.setApr(_report.epoch, _report.apr);
    }

    executedReport[_report.epoch] = true;
    reportBlockNumber += reportBlockFrequency;
    reportEpochNumber += reportEpochFrequency;

    for (uint256 i = 0; i < auditReports[_report.epoch].length; i++) {
      if (auditReports[_report.epoch][i].reportHash != consensusHash) {
        _penalizeOracle(auditReports[_report.epoch][i].oracle, auditReports[_report.epoch][i].reportHash);
      }
    }

    delete auditReports[_report.epoch];

    emit ExecuteReport(msg.sender, block.number, _report.epoch, reportHash, _report);
  }

  function auditReport(uint256 _epoch, Report calldata _report) public returns (bool) {
    require(block.number < reportBlockNumber, 'REPORT_BLOCK_NUMBER_NOT_REACHED');

    require(_epoch == reportEpochNumber, 'INVALID_REPORT_EPOCH_NUMBER');

    bytes32 reportKey = keccak256(abi.encodePacked(msg.sender, _epoch));
    require(!oracleReportsKey[reportKey], 'ORACLE_ALREADY_REPORTED');
    oracleReportsKey[reportKey] = true;

    require(address(this).balance >= _report.WETHAmount, 'INSUFFICIENT_ETH_BALANCE');
    require(_report.exitedValidators.length <= maxValidatorsToExit, 'MAX_EXIT_VALIDATORS_REACHED');

    // Todo: Improve Audit Rules

    return true;
  }

  function isReadyForReportSubmission(uint256 _epoch) public view returns (bool) {
    return (_epoch == reportEpochNumber && block.number >= reportBlockNumber);
  }

  function isReadyForReportExecution(uint256 _epoch) public view returns (bool) {
    return (consensusReport[_epoch] != bytes32(0) && !executedReport[_epoch]);
  }

  function _setReportBlockFrequency(uint256 _frequency) internal {
    reportBlockFrequency = _frequency;
    emit SetReportBlockFrequency(_frequency);
  }

  function _setReportEpochFrequency(uint256 _frequency) internal {
    reportEpochFrequency = _frequency;
    emit SetReportEpochFrequency(_frequency);
  }
}
