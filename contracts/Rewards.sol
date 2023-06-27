// SPDX-FileCopyrightText: 2023 Stake Together Labs <info@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';

/// @custom:security-contact security@staketogether.app
contract Rewards is Ownable, Pausable, ReentrancyGuard {
  StakeTogether public stakeTogether;

  event EtherReceived(address indexed sender, uint amount);

  receive() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  fallback() external payable {
    emit EtherReceived(msg.sender, msg.value);
  }

  event SetStakeTogether(address stakeTogether);

  function setStakeTogether(address _stakeTogether) external onlyOwner {
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
  ) external onlyOwner {
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

  function executeTimeLockAction(string calldata action, address target) external onlyOwner {
    bytes32 actionKey = keccak256(abi.encodePacked(action, target));
    TimeLockedProposal storage proposal = timeLockedProposals[actionKey];
    require(block.timestamp >= proposal.executionTime, 'Time lock not expired yet.');

    if (keccak256(bytes(proposal.action)) == keccak256(bytes('setTimeLockDuration'))) {
      _setTimeLockDuration(proposal.value);
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setBlockReportLimit'))) {
      _setReportGrowthLimit(proposal.value);
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
    } else if (keccak256(bytes(proposal.action)) == keccak256(bytes('setReportFrequency'))) {
      _setReportFrequency(proposal.value);
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
   ** ORACLES **
   *****************/

  modifier onlyOracle() {
    require(
      activeOracles[msg.sender] && oraclesBlacklist[msg.sender] < oraclePenalizeLimit,
      'ONLY_ORACLES'
    );
    _;
  }

  event PenalizeOracle(
    address indexed oracle,
    uint256 penalties,
    ReportType reportType,
    bytes32 hash,
    bool removed
  );

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

  function addOracle(address oracle) external onlyOwner {
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

  function _updateQuorum() internal onlyOwner {
    uint256 totalOracles = getActiveOracleCount();
    uint256 newQuorum = (totalOracles * 8) / 10;

    newQuorum = newQuorum < 3 ? 3 : newQuorum;
    newQuorum = newQuorum > totalOracles ? totalOracles : newQuorum;

    oracleQuorum = newQuorum;
    emit SetOracleQuorum(newQuorum);
  }

  function _penalizeOracle(address _oracle, ReportType _reportType, bytes32 _reportHash) internal {
    oraclesBlacklist[_oracle]++;

    bool remove = oraclesBlacklist[_oracle] >= oraclePenalizeLimit;
    if (remove) {
      _removeOracle(_oracle);
    }

    emit PenalizeOracle(_oracle, oraclesBlacklist[_oracle], _reportType, _reportHash, remove);
  }

  function _setOraclePenalizeLimit(uint256 _oraclePenalizeLimit) internal {
    oraclePenalizeLimit = _oraclePenalizeLimit;
    emit SetOraclePenalizeLimit(_oraclePenalizeLimit);
  }

  /*****************
   ** REPORT **
   *****************/

  event SubmitSingleReport(address indexed oracle, uint256 indexed blockNumber, bytes32 reportHash);
  event SingleAndBatchesConsensusApprove(uint256 indexed blockNumber, bytes32 reportHash);
  event SingleConsensusReject(uint256 indexed blockNumber, bytes32 reportHash);

  event SubmitBatchReport(
    address indexed oracle,
    uint256 indexed blockNumber,
    uint256 indexed batchNumber,
    bytes32 batchReportHash
  );

  event SingleConsensusApprove(uint256 indexed blockNumber, bytes32 singleReportHash);

  event BatchConsensusApprove(uint256 indexed blockNumber, bytes32 batchReportHash);
  event BatchConsensusReject(uint256 indexed blockNumber, bytes32 singleReportHash, SingleReport report);

  event ExecuteSingleReport(
    address oracle,
    uint256 indexed blockNumber,
    bytes32 singleReportHash,
    SingleReport report
  );
  event ExecuteBatchReport(
    address oracle,
    uint256 indexed blockNumber,
    uint256 indexed batchNumber,
    bytes32 batchReportHash,
    BatchReport report
  );
  event ReportExecuted(address oracle, uint256 indexed blockNumber);
  event SetReportGrowthLimit(uint256 reportGrowthLimit);
  event SetReportFrequency(uint256 reportFrequency);

  struct Shares {
    uint256 total;
    uint256 stakeTogether;
    uint256 operators;
    uint256 pools;
  }

  struct Amounts {
    uint256 total;
    uint256 stakeTogether;
    uint256 operators;
    uint256 pools;
  }

  struct PoolBatches {
    uint256 total;
    uint256 totalSubmitted;
    uint256 totalSharesSubmitted;
  }

  struct ValidatorBatches {
    uint256 total;
    uint256 totalSubmitted;
  }

  struct Pool {
    address account;
    uint256 amount;
    uint256 sharesAmount;
  }

  struct Validator {
    bytes publicKey;
    uint256 amount;
  }

  struct SingleReport {
    uint256 blockNumber;
    uint256 batchReports;
    uint256 lossAmount;
    Shares shares;
    Amounts amounts;
    PoolBatches poolBatches;
    ValidatorBatches validatorBatches;
  }

  struct BatchReport {
    uint256 blockNumber;
    uint256 batchNumber;
    bytes32 singleReportHash;
    Pool[] pools;
    Validator[] validators;
  }

  enum ReportType {
    SingleHashOutConsensus,
    BatchHashOutConsensus,
    WrongSingleHash,
    WrongBatchHash
  }

  mapping(bytes32 => address[]) public singleReportOracles;
  mapping(bytes32 => uint256) public singleReportsVotes;
  mapping(bytes32 => bool) public singleOracleReport;
  mapping(uint256 => bytes32) public singleReportConsensus;

  mapping(bytes32 => address[]) public batchReportsOracles;
  mapping(bytes32 => uint256) public batchReportsVotes;
  mapping(bytes32 => bool) public batchOracleReport;
  mapping(bytes32 => bytes32) public batchReportConsensus;

  mapping(uint256 => uint256) public totalBatchReportsForBlock;
  mapping(uint256 => uint256) public submittedBatchReportsForBlock;
  mapping(uint256 => uint256) public executedBatchReportsForBlock;

  mapping(uint256 => bool) public executedSingleReports;
  mapping(uint256 => bool) public executedReports;
  mapping(uint256 => bool) public cleanedReports;

  bool public executionPending = false;

  uint256 public reportGrowthLimit = 0.01 ether;
  uint256 public reportFrequency = 1;
  uint256 public reportLastBlock = 0;
  uint256 public reportNextBlock = 1;

  function submitSingleReport(
    uint256 _blockNumber,
    bytes32 _reportHash,
    uint256 _batchesReports
  ) external onlyOracle whenNotPaused {
    require(!executionPending, 'EXECUTION_PENDING');
    require(reportNextBlock + reportFrequency >= block.number, 'REPORT_FREQUENCY_EXCEEDED');
    require(singleReportConsensus[_blockNumber] == bytes32(0), 'NO_SINGLE_CONSENSUS_FOUND');

    if (block.number >= reportNextBlock + reportFrequency) {
      reportNextBlock += reportFrequency;
    }
    require(_blockNumber == reportNextBlock, 'INVALID_REPORT_BLOCK_NUMBER');

    bytes32 singleOracleKey = keccak256(abi.encodePacked(msg.sender, _blockNumber));
    require(!singleOracleReport[singleOracleKey], 'ORACLE_ALREADY_REPORTED');
    singleOracleReport[singleOracleKey] = true;

    // Todo: Valid Single Report

    singleReportsVotes[_reportHash]++;
    totalBatchReportsForBlock[_blockNumber] = _batchesReports;
    singleReportOracles[_reportHash].push(msg.sender);

    if (singleReportsVotes[_reportHash] >= oracleQuorum) {
      singleReportConsensus[_blockNumber] = _reportHash;
      emit SingleConsensusApprove(_blockNumber, _reportHash);
    }

    emit SubmitSingleReport(msg.sender, _blockNumber, _reportHash);
  }

  function submitBatchReports(
    uint256 _blockNumber,
    uint256 _batchNumber,
    bytes32 _singleReportHash,
    bytes32 _batchReportHash
  ) external onlyOracle whenNotPaused {
    require(!executionPending, 'EXECUTION_PENDING');

    if (block.number >= reportNextBlock + reportFrequency) {
      reportNextBlock += reportFrequency;
    }
    require(_singleReportHash != bytes32(0), 'SINGLE_REPORT_HASH_NOT_FOUND');
    require(_blockNumber == reportNextBlock, 'INVALID_REPORT_BLOCK_NUMBER');
    require(singleReportConsensus[_blockNumber] == _singleReportHash, 'SINGLE_CONSENSUS_NOT_APPROVED');

    bytes32 batchReportKey = keccak256(abi.encodePacked(_blockNumber, _batchNumber));
    require(batchReportConsensus[batchReportKey] == bytes32(0), 'BATCH_CONSENSUS_NOT_APPROVED');

    bytes32 batchOracleKey = keccak256(abi.encodePacked(msg.sender, _blockNumber, _batchNumber));
    require(!batchOracleReport[batchOracleKey], 'ORACLE_ALREADY_REPORTED');
    batchOracleReport[batchOracleKey] = true;

    // Todo: Validate Batch Report

    require(_batchNumber == submittedBatchReportsForBlock[_blockNumber], 'INVALID_BATCH_NUMBER');
    require(
      submittedBatchReportsForBlock[_blockNumber] < totalBatchReportsForBlock[_blockNumber],
      'BATCH_REPORTS_EXCEEDED'
    );

    batchReportsVotes[_batchReportHash]++;
    submittedBatchReportsForBlock[_blockNumber]++;
    batchReportsOracles[_batchReportHash].push(msg.sender);

    if (batchReportsVotes[_batchReportHash] >= oracleQuorum) {
      batchReportConsensus[batchReportKey] = _batchReportHash;
      emit BatchConsensusApprove(_blockNumber, _batchReportHash);
    }

    emit SubmitBatchReport(msg.sender, _blockNumber, _batchNumber, _batchReportHash);
  }

  function executeSingleReport(
    SingleReport memory _singleReport
  ) external onlyOracle whenNotPaused nonReentrant {
    bytes32 singleConsensusHash = singleReportConsensus[_singleReport.blockNumber];
    bytes32 singleReportHash = keccak256(abi.encode(_singleReport));

    require(!executionPending, 'EXECUTION_PENDING');
    require(singleConsensusHash != bytes32(0), 'SINGLE_REPORT_HASH_ALREADY_EXECUTED');
    require(!executedSingleReports[_singleReport.blockNumber], 'SINGLE_REPORT_ALREADY_EXECUTED');

    if (singleReportHash != singleConsensusHash) {
      _penalizeOracle(msg.sender, ReportType.WrongSingleHash, singleReportHash);
    }

    require(singleReportHash == singleConsensusHash, 'INVALID_DATA_FOR_SINGLE_REPORT');

    require(
      executedBatchReportsForBlock[_singleReport.blockNumber] ==
        totalBatchReportsForBlock[_singleReport.blockNumber],
      'BATCH_REPORT_SUBMIT_PENDING'
    );

    executedSingleReports[_singleReport.blockNumber] = true;
    executionPending = true;

    // TODO: Valid Single Report

    if (_singleReport.lossAmount > 0) {
      stakeTogether.mintLoss(_singleReport.blockNumber, _singleReport.lossAmount);
    }

    if (_singleReport.amounts.stakeTogether > 0) {
      stakeTogether.mintRewards{ value: _singleReport.amounts.stakeTogether }(
        _singleReport.blockNumber,
        stakeTogether.stakeTogetherFeeAddress(),
        _singleReport.shares.stakeTogether
      );
    }

    if (_singleReport.amounts.operators > 0) {
      stakeTogether.mintRewards{ value: _singleReport.amounts.operators }(
        _singleReport.blockNumber,
        stakeTogether.operatorFeeAddress(),
        _singleReport.shares.operators
      );
    }

    emit ExecuteSingleReport(msg.sender, _singleReport.blockNumber, singleReportHash, _singleReport);

    bytes32 singleOracleKey = keccak256(abi.encodePacked(msg.sender, _singleReport.blockNumber));
    delete singleReportOracles[singleReportHash];
    delete singleReportsVotes[singleReportHash];
    delete singleOracleReport[singleOracleKey];
    delete singleReportConsensus[_singleReport.blockNumber];
  }

  function executeBatchReport(
    BatchReport memory _batchReport
  ) external onlyOracle whenNotPaused nonReentrant {
    bytes32 batchReportHash = keccak256(abi.encode(_batchReport));
    bytes32 batchReportKey = keccak256(
      abi.encodePacked(_batchReport.blockNumber, _batchReport.batchNumber)
    );

    if (batchReportConsensus[batchReportKey] != batchReportHash) {
      _penalizeOracle(msg.sender, ReportType.WrongBatchHash, batchReportHash);
    }

    require(batchReportConsensus[batchReportKey] == batchReportHash, 'BATCH_REPORT_HASH_NOT_VALID');

    bytes32 singleReportHash = singleReportConsensus[_batchReport.blockNumber];
    require(singleReportHash != bytes32(0), 'NO_SINGLE_REPORT_CONSENSUS');
    require(executedSingleReports[_batchReport.blockNumber], 'SINGLE_REPORT_NOT_EXECUTED_YET');
    require(
      _batchReport.batchNumber == executedBatchReportsForBlock[_batchReport.blockNumber],
      'INVALID_BATCH_NUMBER'
    );
    require(
      executedBatchReportsForBlock[_batchReport.blockNumber] <
        totalBatchReportsForBlock[_batchReport.blockNumber],
      'BATCH_REPORTS_EXCEEDED'
    );

    executedBatchReportsForBlock[_batchReport.blockNumber]++;

    // TODO: Valid Batch Report

    for (uint i = 0; i < _batchReport.pools.length; i++) {
      Pool memory pool = _batchReport.pools[i];
      if (pool.amount > 0) {
        stakeTogether.mintRewards{ value: pool.amount }(
          _batchReport.blockNumber,
          pool.account,
          pool.sharesAmount
        );
      }
    }

    for (uint i = 0; i < _batchReport.validators.length; i++) {
      Validator memory validator = _batchReport.validators[i];
      if (validator.amount > 0) {
        stakeTogether.removeValidator{ value: validator.amount }(validator.publicKey);
      }
    }

    emit ExecuteBatchReport(
      msg.sender,
      _batchReport.blockNumber,
      _batchReport.batchNumber,
      batchReportHash,
      _batchReport
    );

    if (
      executedBatchReportsForBlock[_batchReport.blockNumber] ==
      totalBatchReportsForBlock[_batchReport.blockNumber]
    ) {
      executionPending = false;
      reportNextBlock += reportFrequency;
      executedReports[_batchReport.blockNumber] = true;
      emit ReportExecuted(msg.sender, _batchReport.blockNumber);
    }
  }

  function cleanupReport(uint256 _blockNumber) external onlyOracle {
    require(executedReports[_blockNumber], 'REPORT_NOT_EXECUTED');
    require(!cleanedReports[_blockNumber], 'REPORT_ALREADY_CLEANED');

    // Cleanup single report variables
    bytes32 singleReportHash = singleReportConsensus[_blockNumber];
    delete singleReportOracles[singleReportHash];
    delete singleReportsVotes[singleReportHash];
    delete singleReportConsensus[_blockNumber];

    // Cleanup batch report variables
    for (uint256 i = 0; i < totalBatchReportsForBlock[_blockNumber]; i++) {
      bytes32 batchReportKey = keccak256(abi.encodePacked(_blockNumber, i));
      bytes32 batchReportHash = batchReportConsensus[batchReportKey];
      delete batchReportsOracles[batchReportHash];
      delete batchReportsVotes[batchReportHash];
      delete batchReportConsensus[batchReportKey];
    }

    // Cleanup penalized oracles in batch reports
    bytes32 otherHash;
    for (uint256 i = 0; i < oracles.length; i++) {
      otherHash = keccak256(abi.encodePacked(oracles[i], _blockNumber));
      if (otherHash != singleReportHash) {
        _penalizeOracle(oracles[i], ReportType.SingleHashOutConsensus, otherHash);
      }
    }

    // Cleanup penalized oracles in single reports
    for (uint256 i = 0; i < oracles.length; i++) {
      otherHash = keccak256(abi.encodePacked(oracles[i], _blockNumber));
      if (otherHash != singleReportHash) {
        delete singleReportOracles[otherHash];
      }
    }

    // Reset counters
    delete submittedBatchReportsForBlock[_blockNumber];
    delete executedBatchReportsForBlock[_blockNumber];

    cleanedReports[_blockNumber] = true;
  }

  function _setReportGrowthLimit(uint256 _growthLimit) internal {
    reportGrowthLimit = _growthLimit;
    emit SetReportGrowthLimit(_growthLimit);
  }

  function _setReportFrequency(uint256 _frequency) internal {
    reportFrequency = _frequency;
    emit SetReportFrequency(_frequency);
  }

  // Todo: Create function to check if report is ready to be executed
  // Todo: Move the validation outside of function to be verified externally
}
