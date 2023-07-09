// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Distributor is AccessControl, Pausable, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_REPORT_MANAGER_ROLE = keccak256('ORACLE_REPORT_MANAGER_ROLE');
  bytes32 public constant ORACLE_REPORT_ROLE = keccak256('ORACLE_REPORT_ROLE');

  StakeTogether public stakeTogether;
  WETH public WETHContract;

  constructor(address _WETH) {
    WETHContract = WETH(payable(_WETH));
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(ORACLE_REPORT_MANAGER_ROLE, msg.sender);
  }

  event EtherReceived(address indexed sender, uint amount);

  receive() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  event SetStakeTogether(address stakeTogether);

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /*****************
   ** TIME LOCK **
   *****************/

  event ProposeTimeLockAction(
    bytes32 indexed actionKey,
    string action,
    uint256 value,
    address target,
    uint256 executionTime
  );
  event ExecuteTimeLockAction(bytes32 indexed actionKey, string action);

  event SetTimeLockDuration(uint256 newDuration);
  event SetBlockReportGrowthLimit(uint256 newLimit);
  event AddOracle(address oracle);
  event RemoveOracle(address oracle);
  event SetOraclePenalizeLimit(uint256 newLimit);
  event SetOracleQuorum(uint256 newQuorum);
  event SetBunkerMode(bool bunkerMode);

  struct TimeLockedProposal {
    string action;
    uint256 value;
    address target;
    uint256 executionTime;
  }

  uint256 public timeLockDuration = 1 days / 15;
  mapping(bytes32 => TimeLockedProposal) public timeLockedProposals;

  function proposeTimeLockAction(
    string calldata action,
    uint256 value,
    address target
  ) external onlyRole(ADMIN_ROLE) {
    bytes32 actionKey = keccak256(abi.encodePacked(action, target));

    TimeLockedProposal memory proposal = TimeLockedProposal({
      action: action,
      value: value,
      target: target,
      executionTime: block.timestamp + timeLockDuration
    });

    timeLockedProposals[actionKey] = proposal;

    emit ProposeTimeLockAction(actionKey, action, value, target, proposal.executionTime);
  }

  // Todo: Revise Access Control by Each Function
  function executeTimeLockAction(string calldata action, address target) external onlyRole(ADMIN_ROLE) {
    bytes32 actionKey = keccak256(abi.encodePacked(action, target));
    TimeLockedProposal storage proposal = timeLockedProposals[actionKey];
    require(block.timestamp >= proposal.executionTime, 'Time lock not expired yet.');

    if (keccak256(bytes(proposal.action)) == keccak256(bytes('setTimeLockDuration'))) {
      _setTimeLockDuration(proposal.value);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('addOracle'))) {
      _addOracle(proposal.target);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('removeOracle'))) {
      _removeOracle(proposal.target);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setOraclePenalizeLimit'))) {
      _setOraclePenalizeLimit(proposal.value);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setOracleQuorum'))) {
      _setOracleQuorum(proposal.value);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setBunkerMode'))) {
      _setBunkerMode(proposal.value == 1);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setReportBlockFrequency'))) {
      _setReportBlockFrequency(proposal.value);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setReportEpochFrequency'))) {
      _setReportEpochFrequency(proposal.value);
    } else {
      revert('INVALID_ACTION');
    }

    delete timeLockedProposals[actionKey];

    emit ExecuteTimeLockAction(actionKey, proposal.action);
  }

  function isProposalReady(string calldata action, address target) public view returns (bool) {
    bytes32 actionKey = keccak256(abi.encodePacked(action, target));
    TimeLockedProposal storage proposal = timeLockedProposals[actionKey];
    return block.timestamp >= proposal.executionTime;
  }

  function _setTimeLockDuration(uint256 _timeLockDuration) internal {
    timeLockDuration = _timeLockDuration;
    emit SetTimeLockDuration(_timeLockDuration);
  }

  /*****************
   ** REPORT ORACLES **
   *****************/

  modifier onlyOracle() {
    require(
      activeOracles[msg.sender] && oraclesBlacklist[msg.sender] < oraclePenalizeLimit,
      'ONLY_ACTIVE_ORACLES'
    );
    _;
  }

  event PenalizeOracle(address indexed oracle, uint256 penalties, bytes32 hash, bool removed);

  address[] private oracles;
  mapping(address => bool) private activeOracles;
  mapping(address => uint256) public oraclesBlacklist;
  uint256 public oracleQuorum = 1; // Todo: Mainnet = 3
  uint256 public oraclePenalizeLimit = 3;
  bool public bunkerMode = false;

  function getOracles() external view returns (address[] memory) {
    return oracles;
  }

  function getActiveOracleCount() internal view returns (uint256) {
    uint256 activeCount = 0;
    for (uint256 i = 0; i < oracles.length; i++) {
      if (activeOracles[oracles[i]]) {
        activeCount++;
      }
    }
    return activeCount;
  }

  function isOracle(address _oracle) public view returns (bool) {
    return activeOracles[_oracle] && oraclesBlacklist[_oracle] < oraclePenalizeLimit;
  }

  function addOracle(address oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(oracles.length < oracleQuorum, 'QUORUM_REACHED');
    _addOracle(oracle);
  }

  function _setBunkerMode(bool _bunkerMode) internal {
    bunkerMode = _bunkerMode;
    emit SetBunkerMode(_bunkerMode);
  }

  function _addOracle(address oracle) internal {
    require(!activeOracles[oracle], 'ORACLE_EXISTS');
    oracles.push(oracle);
    activeOracles[oracle] = true;
    emit AddOracle(oracle);
    _updateQuorum();
  }

  function _removeOracle(address oracle) internal {
    require(activeOracles[oracle], 'ORACLE_NOT_EXISTS');
    activeOracles[oracle] = false;
    emit RemoveOracle(oracle);
    _updateQuorum();
  }

  function _setOracleQuorum(uint256 _oracleQuorum) internal {
    oracleQuorum = _oracleQuorum;
    emit SetOracleQuorum(_oracleQuorum);
  }

  function _updateQuorum() internal onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    uint256 totalOracles = getActiveOracleCount();
    uint256 newQuorum = (totalOracles * 8) / 10;

    newQuorum = newQuorum < 3 ? 3 : newQuorum;
    newQuorum = newQuorum > totalOracles ? totalOracles : newQuorum;

    oracleQuorum = newQuorum;
    emit SetOracleQuorum(newQuorum);
  }

  function _penalizeOracle(address _oracle, bytes32 _reportHash) internal {
    oraclesBlacklist[_oracle]++;

    bool remove = oraclesBlacklist[_oracle] >= oraclePenalizeLimit;
    if (remove) {
      _removeOracle(_oracle);
    }

    emit PenalizeOracle(_oracle, oraclesBlacklist[_oracle], _reportHash, remove);
  }

  function _setOraclePenalizeLimit(uint256 _oraclePenalizeLimit) internal {
    oraclePenalizeLimit = _oraclePenalizeLimit;
    emit SetOraclePenalizeLimit(_oraclePenalizeLimit);
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
  event SetMaxExitValidators(uint256 maxExitValidators);

  // struct Validator {
  //   bytes publicKey;
  //   uint256 amount;
  // }

  struct Shares {
    uint256 total;
    uint256 stakeTogether;
    uint256 operators;
    uint256 pools;
  }

  struct Amounts {
    uint256 total;
    uint256 pools;
    uint256 operators;
    uint256 stakeTogether;
  }

  struct Report {
    uint256 epoch;
    uint256 lossAmount;
    Shares shares;
    Amounts amounts;
    uint256 WETHAmount; // saque de WETH
    uint256 restExitAmount; // não foi usado no saque (tem que voltar pro pool)
    bytes[] restExitValidators; // validators que sairam
  }

  // Todo: quem deve fazer o saque // Forcar // atualizar
  // Todo: penalizar quem não fez o saque

  enum ReportType {
    SingleHashOutConsensus,
    BatchHashOutConsensus,
    WrongSingleHash,
    WrongBatchHash
  }

  mapping(bytes32 => address[]) public oracleReports;
  mapping(bytes32 => uint256) public oracleReportsVotes;
  mapping(bytes32 => bool) public oracleReportsKey;
  mapping(uint256 => bytes32) public consensusReport;
  mapping(uint256 => bool) public executedReport;
  uint256 public maxExitValidators = 100;

  uint256 public reportBlockFrequency = 1;
  uint256 public reportBlockNumber = 1;
  uint256 public reportEpochFrequency = 1;
  uint256 public reportEpochNumber = 1;

  function submitReport(
    uint256 _epoch,
    bytes32 _hash,
    Report calldata _report
  ) external onlyOracle whenNotPaused {
    // Todo: Valid Report

    auditReport(_epoch, _report);

    if (block.number >= reportBlockNumber + reportBlockFrequency) {
      reportBlockNumber += reportBlockFrequency;
    }

    oracleReportsVotes[_hash]++;
    oracleReports[_hash].push(msg.sender);

    if (oracleReportsVotes[_hash] >= oracleQuorum) {
      consensusReport[_epoch] = _hash;
      emit ConsensusApprove(block.number, _epoch, _hash);
    }

    // Todo: Penalize Oracle
  }

  function executeReport(Report calldata _report) external onlyOracle whenNotPaused nonReentrant {
    bytes32 reportHash = keccak256(abi.encode(_report));
    bytes32 consensusHash = consensusReport[_report.epoch];

    require(consensusHash != bytes32(0), 'REPORT_ALREADY_EXECUTED');
    require(!executedReport[_report.epoch], 'SINGLE_REPORT_ALREADY_EXECUTED');

    if (reportHash != consensusHash) {
      _penalizeOracle(msg.sender, reportHash);
    }

    require(reportHash == consensusHash, 'INVALID_REPORT');

    // TODO: Valid Single Report

    if (_report.lossAmount > 0) {
      stakeTogether.mintPenalty(_report.epoch, _report.lossAmount);
    }

    if (_report.shares.pools > 0) {
      stakeTogether.mintRewards{ value: _report.amounts.pools }(
        _report.epoch,
        stakeTogether.poolFeeAddress(),
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

    if (_report.WETHAmount > 0) {
      payable(address(WETHContract)).transfer(_report.WETHAmount);
    }

    if (_report.restExitAmount > 0) {
      payable(address(stakeTogether)).transfer(_report.restExitAmount);
    }

    if (_report.restExitValidators.length > 0) {
      for (uint256 i = 0; i < _report.restExitValidators.length; i++) {
        stakeTogether.removeValidator(_report.epoch, _report.restExitValidators[i]);
      }
    }

    executedReport[_report.epoch] = true;
    reportBlockNumber += reportBlockFrequency;
    reportEpochNumber += reportEpochFrequency;

    // Transfer funds to pool
    // Transfer funds to withdrawals

    emit ExecuteReport(msg.sender, block.number, _report.epoch, reportHash, _report);

    // Todo: qualquer valor excendente deve ser transferido para o pool (Não como lucro)
  }

  function auditReport(uint256 _epoch, Report calldata _report) public returns (bool) {
    require(block.number < reportBlockNumber, 'REPORT_BLOCK_NUMBER_NOT_REACHED');

    require(_epoch == reportEpochNumber, 'INVALID_REPORT_EPOCH_NUMBER');

    bytes32 reportKey = keccak256(abi.encodePacked(msg.sender, _epoch));
    require(!oracleReportsKey[reportKey], 'ORACLE_ALREADY_REPORTED');
    oracleReportsKey[reportKey] = true;

    require(address(this).balance >= _report.WETHAmount, 'INSUFFICIENT_ETH_BALANCE');
    require(_report.restExitValidators.length <= maxExitValidators, 'MAX_EXIT_VALIDATORS_REACHED');

    return true;
  }

  function _setReportBlockFrequency(uint256 _frequency) internal {
    reportBlockFrequency = _frequency;
    emit SetReportBlockFrequency(_frequency);
  }

  function _setReportEpochFrequency(uint256 _frequency) internal {
    reportEpochFrequency = _frequency;
    emit SetReportEpochFrequency(_frequency);
  }

  // Todo: Create function to check if report is ready to be executed
  // Todo: Move the validation outside of function to be verified externally
}
