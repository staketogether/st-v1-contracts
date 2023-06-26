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

  event ProposeTimeLockAction(string action, uint256 value, address target, uint256 executionTime);
  event ExecuteTimeLockAction(string action);
  event SetTimeLockDuration(uint256 newDuration);
  event SetOraclePenalizeLimit(uint256 newLimit);
  event SetBlockReportGrowthLimit(uint256 newLimit);

  // Todo: add missing events
  // Todo: check if is missing some actions

  struct TimeLockedProposal {
    uint256 value;
    address target;
    uint256 executionTime;
  }

  uint256 public timeLockDuration = 1 days / 15;
  mapping(string => TimeLockedProposal) public timeLockedProposals;

  function proposeTimeLockAction(
    string calldata action,
    uint256 value,
    address target
  ) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals[action];
    require(proposal.executionTime < block.timestamp, 'Previous proposal still pending.');

    proposal.value = value;
    proposal.target = target;
    proposal.executionTime = block.timestamp + timeLockDuration;

    emit ProposeTimeLockAction(action, value, target, proposal.executionTime);
  }

  function executeTimeLockAction(string calldata action) external onlyOwner {
    TimeLockedProposal storage proposal = timeLockedProposals[action];
    require(block.timestamp >= proposal.executionTime, 'Time lock not expired yet.');

    if (keccak256(bytes(action)) == keccak256(bytes('setTimeLockDuration'))) {
      timeLockDuration = proposal.value;
      emit SetTimeLockDuration(proposal.value);
    } else if (keccak256(bytes(action)) == keccak256(bytes('addOracle'))) {
      _addOracle(proposal.target);
    } else if (keccak256(bytes(action)) == keccak256(bytes('removeOracle'))) {
      _removeOracle(proposal.target);
    } else if (keccak256(bytes(action)) == keccak256(bytes('setOraclePenalizeLimit'))) {
      oraclePenalizeLimit = proposal.value;
      emit SetOraclePenalizeLimit(proposal.value);
    } else if (keccak256(bytes(action)) == keccak256(bytes('setBlockReportLimit'))) {
      reportGrowthLimit = proposal.value;
      emit SetBlockReportGrowthLimit(proposal.value);
    }

    // Todo: Add missing operations

    proposal.executionTime = 0;
    emit ExecuteTimeLockAction(action);
  }

  function isProposalReady(string memory proposalName) public view returns (bool) {
    TimeLockedProposal storage proposal = timeLockedProposals[proposalName];
    return block.timestamp >= proposal.executionTime;
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

  event AddOracle(address oracle);
  event RemoveOracle(address oracle);
  event SetBunkerMode(bool bunkerMode);
  event SetOracleQuorum(uint256 newQuorum);

  event OraclePenalized(
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

  function setBunkerMode(bool _bunkerMode) external onlyOwner {
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

    emit OraclePenalized(_oracle, oraclesBlacklist[_oracle], _reportType, _reportHash, remove);
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
    Single,
    Batch
  }

  mapping(bytes32 => uint256) public singleReportsVotes;
  mapping(bytes32 => bool) public singleOracleReport;
  mapping(uint256 => bytes32) public singleReportConsensus;

  mapping(bytes32 => uint256) public batchReportsVotes;
  mapping(bytes32 => bool) public batchOracleReport;
  mapping(bytes32 => bytes32) public batchReportConsensus;

  mapping(uint256 => uint256) public totalBatchReportsForBlock;
  mapping(uint256 => uint256) public submittedBatchReportsForBlock;
  mapping(uint256 => uint256) public executedBatchReportsForBlock;

  mapping(uint256 => bool) public executedSingleReports;
  mapping(uint256 => bool) public executedReports;

  bool public executionPending = false;

  uint256 public reportGrowthLimit = 1;
  uint256 public reportLastBlock = 0;
  uint256 public reportNextBlock = 1;
  uint256 public reportFrequency = 1;

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

    if (singleReportsVotes[_reportHash] >= oracleQuorum) {
      singleReportConsensus[_blockNumber] = _reportHash;
      emit SingleConsensusApprove(_blockNumber, _reportHash);

      // Todo: Penalize oracle if report is invalid
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

    if (batchReportsVotes[_batchReportHash] >= oracleQuorum) {
      batchReportConsensus[batchReportKey] = _batchReportHash;
      emit BatchConsensusApprove(_blockNumber, _batchReportHash);

      // Todo: Penalize oracle if report is invalid
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
    require(singleReportHash == singleConsensusHash, 'INVALID_DATA_FOR_SINGLE_REPORT');
    // Todo: Penalize Oracle if report is invalid

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
  }

  function executeBatchReport(
    BatchReport memory _batchReport
  ) external onlyOracle whenNotPaused nonReentrant {
    bytes32 batchReportHash = keccak256(abi.encode(_batchReport));
    bytes32 batchReportKey = keccak256(
      abi.encodePacked(_batchReport.blockNumber, _batchReport.batchNumber)
    );
    require(batchReportConsensus[batchReportKey] == batchReportHash, 'BATCH_REPORT_HASH_NOT_VALID');
    // Todo Penalize Oracle if report is invalid

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

    if (
      executedBatchReportsForBlock[_batchReport.blockNumber] ==
      totalBatchReportsForBlock[_batchReport.blockNumber]
    ) {
      executionPending = false;
      reportNextBlock += reportFrequency;
      emit ReportExecuted(msg.sender, _batchReport.blockNumber);
    }

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
  }

  // function _penalizeOraclesWithSingleInvalidReports(
  //   uint256 _blockNumber,
  //   bytes32 _consensusReportHash
  // ) internal {
  //   bytes32[] storage oracleReports = singleOracleReportHistory[_blockNumber][msg.sender];
  //   uint256 numReports = oracleReports.length;

  //   for (uint256 i = 0; i < numReports; i++) {
  //     bytes32 reportHash = oracleReports[i];

  //     if (reportHash != _consensusReportHash) {
  //       _penalizeOracle(msg.sender, ReportType.Single, reportHash);
  //     }
  //   }
  // }

  // function _penalizeOraclesWithInvalidBatchReports(
  //   uint256 _blockNumber,
  //   uint256 _batchNumber,
  //   bytes32 _consensusReportHash
  // ) internal {
  //   bytes32[] storage oracleReports = batchOracleReportHistory[_blockNumber][_batchNumber][msg.sender];

  //   for (uint256 i = 0; i < oracleReports.length; i++) {
  //     bytes32 reportHash = oracleReports[i];

  //     // Verificar se o relatório não corresponde ao hash do consenso
  //     if (reportHash != _consensusReportHash) {
  //       _penalizeOracle(msg.sender, ReportType.Batch, reportHash);
  //     }
  //   }

  //   // Adicionar o relatório inválido ao histórico do oráculo
  //   oracleReports.push(_consensusReportHash);
  // }

  // function executeSingleReport(uint256 _blockNumber) external onlyOracle whenNotPaused {
  //   bytes32 consensusReportHash = singleReportConsensus[_blockNumber];
  //   require(consensusReportHash != bytes32(0), 'INVALID_CONSENSUS_HASH');

  //   uint256 votes = singleReportsVotes[consensusReportHash];
  //   SingleReport storage consensusReport = singleReports[consensusReportHash];

  //   blockExecuteReportValidation(consensusReport);

  //   bool isConsensusApprove = consensusReport.shares.pools ==
  //     consensusReport.pools.totalSharesSubmitted &&
  //     consensusReport.pools.total == consensusReport.pools.totalSubmitted;

  //   if (votes >= oracleQuorum && isConsensusApprove) {
  //     consensusReport.meta.consensus = true;
  //     _blockReportActions(consensusReport);
  //     emit SingleConsensusApprove(_blockNumber, consensusReportHash);
  //   } else {
  //     emit SingleConsensusReject(_blockNumber, consensusReportHash);
  //   }

  //   reportLastBlock = reportNextBlock;
  //   reportNextBlock += reportFrequency;
  // }

  // function isBlockReportReady(uint256 blockNumber) public view returns (bool) {
  //   bytes32 reportHash = singleReportConsensus[blockNumber];
  //   return singleReportsVotes[reportHash] >= oracleQuorum;
  // }

  // function submitSingleReportValidation(
  //   bytes32 _reportHash,
  //   SingleReport memory _blockReport
  // ) public view {
  //   // Todo: Check if is missing some validation
  //   require(_blockReport.meta.blockNumber == reportNextBlock, 'BLOCK_REPORT_IS_NOT_NEXT_EXPECTED');
  //   require(_blockReport.meta.consensus == false, 'INVALID_CONSENSUS_EXECUTED');
  //   require(_blockReport.pools.totalSharesSubmitted == 0, 'INVALID_TOTAL_POOLS_SHARES_SUBMITTED');
  //   require(_blockReport.pools.totalSubmitted == 0, 'INVALID_TOTAL_POOLS_SUBMITTED');

  //   uint256 totalPooledEther = stakeTogether.totalPooledEther();
  //   uint256 growthLimit = Math.mulDiv(totalPooledEther, reportGrowthLimit, 100);
  //   require(_blockReport.amounts.total <= growthLimit, 'GROWTH_LIMIT_EXCEEDED');

  //   uint256 stakeTogetherFee = Math.mulDiv(totalPooledEther, stakeTogether.stakeTogetherFee(), 100);
  //   uint256 operatorFee = Math.mulDiv(totalPooledEther, stakeTogether.operatorFee(), 100);
  //   uint256 poolFee = Math.mulDiv(totalPooledEther, stakeTogether.poolFee(), 100);
  //   require(
  //     stakeTogether.pooledEthByShares(_blockReport.shares.stakeTogether) <= stakeTogetherFee,
  //     'STAKE_TOGETHER_FEE_EXCEEDED'
  //   );
  //   require(
  //     stakeTogether.pooledEthByShares(_blockReport.shares.operators) <= operatorFee,
  //     'OPERATOR_FEE_EXCEEDED'
  //   );
  //   require(stakeTogether.pooledEthByShares(_blockReport.shares.pools) <= poolFee, 'POOL_FEE_EXCEEDED');

  //   uint256 totalShares = _blockReport.shares.stakeTogether +
  //     _blockReport.shares.operators +
  //     _blockReport.shares.pools;
  //   require(totalShares == _blockReport.shares.total, 'INVALID_TOTAL_SHARES');

  //   for (uint i = 0; i < _blockReport.meta.exitedValidators.length; i++) {
  //     require(
  //       stakeTogether.isValidator(_blockReport.meta.exitedValidators[i]),
  //       'INVALID_EXITED_VALIDATOR'
  //     );
  //   }

  //   uint256 expectedMaxBeaconBalance = stakeTogether.validatorSize() * stakeTogether.totalValidators();
  //   require(
  //     _blockReport.meta.beaconBalance <= expectedMaxBeaconBalance,
  //     'BEACON_BALANCE_EXCEEDS_EXPECTED_MAX'
  //   );

  //   require(!singleReports[_reportHash].meta.consensus, 'BLOCK_ALREADY_EXECUTED');
  // }

  // function blockExecuteReportValidation(SingleReport memory consensusReport) public pure {
  //   require(!consensusReport.meta.consensus, 'REPORT_ALREADY_EXECUTED');

  //   require(
  //     consensusReport.pools.total == consensusReport.pools.totalSubmitted,
  //     'INVALID_POOLS_SUBMISSION'
  //   );

  //   require(
  //     consensusReport.shares.pools == consensusReport.pools.totalSharesSubmitted,
  //     'INVALID_POOLS_SHARES_SUBMISSION'
  //   );
  // }

  // function _blockReportActions(SingleReport memory _blockReport) private {
  //   stakeTogether.setBeaconBalance(_blockReport.meta.blockNumber, _blockReport.meta.beaconBalance);

  //   stakeTogether.mintRewards{ value: _blockReport.amounts.stakeTogether }(
  //     _blockReport.meta.blockNumber,
  //     stakeTogether.stakeTogetherFeeAddress(),
  //     _blockReport.shares.stakeTogether
  //   );

  //   stakeTogether.mintRewards{ value: _blockReport.amounts.operators }(
  //     _blockReport.meta.blockNumber,
  //     stakeTogether.operatorFeeAddress(),
  //     _blockReport.shares.operators
  //   );

  //   stakeTogether.removeValidators(_blockReport.meta.exitedValidators);

  //   // Todo: Missing

  //   // uint256 poolShares;
  //   // uint256 poolsToSubmit;
  //   // uint256 poolsSubmitted;
  //   // uint256 poolsSharesSubmitted;
  //   // bool consensus;

  //   // Todo: Consensus will be executed just when last pool submits the report
  // }

  // /*****************
  //  ** POOL REPORT **
  //  *****************/

  // function executePoolConsensus(uint256 _blockNumber, address _pool) external onlyOracle whenNotPaused {
  //   poolExecuteReportValidation(_blockNumber, _pool);

  //   bytes32 blockReportHash = singleReportConsensus[_blockNumber];
  //   require(blockReportHash != bytes32(0), 'INVALID_BLOCK_REPORT_HASH');
  //   SingleReport storage blockReport = singleReports[blockReportHash];
  //   require(blockReport.meta.consensus, 'BLOCK_REPORT_NOT_EXECUTED');

  //   bytes32 poolReportHash = keccak256(abi.encode(_pool, blockReportHash));
  //   BatchReport storage poolReport = batchReports[poolReportHash];
  //   require(!poolReport.consensus, 'POOL_REPORT_ALREADY_EXECUTED');

  //   poolReport.consensus = true;

  //   _poolReportActions(poolReport);
  //   emit BatchConsensusApprove(_blockNumber, _pool, poolReportHash);
  // }

  // function isPoolReportReady(uint256 blockNumber, address pool) public view returns (bool) {
  //   bytes32 reportHash = keccak256(abi.encode(pool, singleReportConsensus[blockNumber]));
  //   return batchReports[reportHash].consensus;
  // }

  // function poolSubmitReportValidation(BatchReport memory _poolReport) public view {
  //   // Validate the block report
  //   SingleReport storage blockReport = singleReports[_poolReport.blockReportHash];
  //   require(blockReport.meta.consensus, 'BLOCK_REPORT_NOT_EXECUTED');

  //   // Validate the pool
  //   // Add your validation logic here
  // }

  // function poolExecuteReportValidation(uint256 _blockNumber, address _pool) private view {
  //   bytes32 blockReportHash = singleReportConsensus[_blockNumber];
  //   require(blockReportHash != bytes32(0), 'INVALID_BLOCK_REPORT_HASH');
  //   SingleReport storage blockReport = singleReports[blockReportHash];
  //   require(blockReport.meta.consensus, 'BLOCK_REPORT_NOT_EXECUTED');

  //   bytes32 poolReportHash = keccak256(abi.encode(_pool, blockReportHash));
  //   BatchReport storage poolReport = batchReports[poolReportHash];
  //   require(!poolReport.consensus, 'POOL_REPORT_ALREADY_EXECUTED');
  // }

  // function _poolReportActions(BatchReport memory _poolReport) private {
  //   stakeTogether.mintRewards{ value: _poolReport.amount }(
  //     _poolReport.blockNumber,
  //     _poolReport.pool,
  //     _poolReport.sharesAmount
  //   );
  // }
}
