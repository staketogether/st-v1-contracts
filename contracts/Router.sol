// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './StakeTogether.sol';
import './Withdrawals.sol';
import './Loans.sol';
import './Pools.sol';
import './Validators.sol';
import './Fees.sol';

/// @custom:security-contact security@staketogether.app
contract Router is AccessControl, Pausable, ReentrancyGuard {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_REPORT_MANAGER_ROLE = keccak256('ORACLE_REPORT_MANAGER_ROLE');
  bytes32 public constant ORACLE_REPORT_SENTINEL_ROLE = keccak256('ORACLE_REPORT_SENTINEL_ROLE');
  bytes32 public constant ORACLE_REPORT_ROLE = keccak256('ORACLE_REPORT_ROLE');

  StakeTogether public stakeTogether;
  Fees public feesContract;
  Withdrawals public withdrawalsContract;
  Loans public loansContract;
  Pools public poolsContract;
  Validators public validatorsContract;

  struct ValidatorOracle {
    address oracle;
    bytes[] validators;
  }

  struct Report {
    uint256 blockNumber;
    uint256 epoch;
    uint256 profitAmount;
    uint256 lossAmount; // Penalty or Slashing
    uint256 extraAmount; // Extra money on this contract
    bytes32 poolsMerkleRoot; // Todo: missing merkle das pools
    ValidatorOracle[] validatorsToExit; // Validators that should exit
    bytes[] exitedValidators; // Validators that already exited
    uint256 restExitAmount; // Rest withdrawal validator amount
    uint256 withdrawAmount; // Amount of ETH to send to WETH contract
    uint256 apr; // Protocol APR for lending calculation
  }

  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
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

  constructor(
    address _withdrawContract,
    address _loanContract,
    address _poolContract,
    address _validatorsContract,
    address _feesContract
  ) {
    withdrawalsContract = Withdrawals(payable(_withdrawContract));
    loansContract = Loans(payable(_loanContract));
    poolsContract = Pools(payable(_poolContract));
    validatorsContract = Validators(payable(_validatorsContract));
    feesContract = Fees(payable(_feesContract));

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(ORACLE_REPORT_MANAGER_ROLE, msg.sender);
  }

  receive() external payable {
    emit ReceiveEther(msg.sender, msg.value);
  }

  fallback() external payable {
    emit FallbackEther(msg.sender, msg.value);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  /*******************
   ** REPORT ORACLE **
   *******************/

  modifier onlyReportOracle() {
    require(
      reportOracles[msg.sender] && reportOraclesBlacklist[msg.sender] < oracleBlackListLimit,
      'ONLY_REPORT_ORACLE'
    );
    _;
  }

  uint256 public totalReportOracles;
  mapping(address => bool) private reportOracles;
  mapping(address => uint256) public reportOraclesBlacklist;
  uint256 public minReportOracleQuorum = 5;
  uint256 public reportOracleQuorum = minReportOracleQuorum;
  uint256 public oracleBlackListLimit = 3;
  bool public bunkerMode = false;

  function isReportOracle(address _oracle) public view returns (bool) {
    return reportOracles[_oracle] && reportOraclesBlacklist[_oracle] < oracleBlackListLimit;
  }

  function isReportOracleBlackListed(address _oracle) public view returns (bool) {
    return reportOraclesBlacklist[_oracle] >= oracleBlackListLimit;
  }

  function addReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(totalReportOracles < reportOracleQuorum, 'REPORT_ORACLE_QUORUM_REACHED');
    require(!reportOracles[_oracle], 'REPORT_ORACLE_EXISTS');
    _grantRole(ORACLE_REPORT_ROLE, _oracle);
    reportOracles[_oracle] = true;
    totalReportOracles++;
    emit AddReportOracle(_oracle);
    _updateReportOracleQuorum();
  }

  function removeReportOracle(address oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportOracles[oracle], 'REPORT_ORACLE_NOT_EXISTS');
    _revokeRole(ORACLE_REPORT_ROLE, oracle);
    reportOracles[oracle] = false;
    totalReportOracles--;
    emit RemoveReportOracle(oracle);
    _updateReportOracleQuorum();
  }

  function setMinReportOracleQuorum(uint256 _quorum) external onlyRole(ADMIN_ROLE) {
    minReportOracleQuorum = _quorum;
    emit SetMinReportOracleQuorum(_quorum);
  }

  function setReportOracleQuorum(uint256 _quorum) external onlyRole(ADMIN_ROLE) {
    reportOracleQuorum = _quorum;
    emit SetReportOracleQuorum(_quorum);
  }

  function setReportOraclePenalizeLimit(uint256 _oraclePenalizeLimit) external onlyRole(ADMIN_ROLE) {
    oracleBlackListLimit = _oraclePenalizeLimit;
    emit SetReportOraclePenalizeLimit(_oraclePenalizeLimit);
  }

  function blacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    reportOraclesBlacklist[_oracle] = oracleBlackListLimit;
    reportOracles[_oracle] = false;
    emit BlacklistReportOracleManually(_oracle, reportOraclesBlacklist[_oracle]);
  }

  function unBlacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportOracles[_oracle], 'REPORT_ORACLE_NOT_EXISTS');
    require(
      reportOraclesBlacklist[_oracle] >= oracleBlackListLimit || !reportOracles[_oracle],
      'REPORT_ORACLE_NOT_BLACKLISTED'
    );
    reportOraclesBlacklist[_oracle] = 0;
    reportOracles[_oracle] = true;
    emit UnBlacklistReportOracle(_oracle, reportOraclesBlacklist[_oracle]);
  }

  function addSentinel(address _sentinel) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(!hasRole(ORACLE_REPORT_SENTINEL_ROLE, _sentinel), 'SENTINEL_EXISTS');
    grantRole(ORACLE_REPORT_SENTINEL_ROLE, _sentinel);
  }

  function removeSentinel(address _sentinel) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(hasRole(ORACLE_REPORT_SENTINEL_ROLE, _sentinel), 'SENTINEL_NOT_EXISTS');
    revokeRole(ORACLE_REPORT_SENTINEL_ROLE, _sentinel);
  }

  function setBunkerMode(bool _bunkerMode) external onlyRole(ADMIN_ROLE) {
    bunkerMode = _bunkerMode;
    emit SetBunkerMode(_bunkerMode);
  }

  function _updateReportOracleQuorum() internal {
    uint256 newQuorum = (totalReportOracles * 8) / 10;
    reportOracleQuorum = newQuorum < minReportOracleQuorum ? minReportOracleQuorum : newQuorum;
    emit UpdateReportOracleQuorum(newQuorum);
  }

  function _rewardOrPenalizeReportOracle(address _oracle, bytes32 _reportHash, bool consensus) internal {
    if (consensus) {
      if (reportOraclesBlacklist[_oracle] > 0) {
        reportOraclesBlacklist[_oracle]--;
      }
      emit RewardReportOracle(_oracle, reportOraclesBlacklist[_oracle], _reportHash);
    } else {
      reportOraclesBlacklist[_oracle]++;

      bool blacklist = reportOraclesBlacklist[_oracle] >= oracleBlackListLimit;
      if (blacklist) {
        reportOracles[_oracle] = false;
        emit BlacklistReportOracle(_oracle, reportOraclesBlacklist[_oracle]);
        _updateReportOracleQuorum();
      }

      emit PenalizeReportOracle(_oracle, reportOraclesBlacklist[_oracle], _reportHash, blacklist);
    }
  }

  /************
   ** REPORT **
   ************/

  mapping(uint256 => mapping(bytes32 => address[])) public oracleReports;
  mapping(uint256 => mapping(bytes32 => uint256)) public oracleReportsVotes;
  mapping(uint256 => mapping(bytes32 => bool)) public executedReports;
  mapping(uint256 => bytes32[]) public reportHistoric;
  mapping(uint256 => bytes32) public consensusReport;
  mapping(uint256 => bool) public consensusInvalidatedReport;

  uint256 public reportBlockFrequency = 1;
  uint256 public reportBlockNumber = 1;
  uint256 public lastConsensusEpoch = 0;
  uint256 public lastExecutedConsensusEpoch = 0;

  uint256 public maxValidatorsToExit = 100;
  uint256 public minBlocksBeforeExecution = 600;
  mapping(bytes32 => uint256) public reportExecutionBlock;

  uint256 public maxApr = 0.1 ether;

  function submitReport(
    uint256 _epoch,
    bytes32 _hash,
    Report calldata _report
  ) external onlyReportOracle nonReentrant whenNotPaused {
    require(block.number < reportBlockNumber, 'BLOCK_NUMBER_NOT_REACHED');
    require(_epoch > lastConsensusEpoch, 'EPOCH_LOWER_THAN_LAST_CONSENSUS');

    auditReport(_report, _hash);

    if (block.number >= reportBlockNumber + reportBlockFrequency) {
      reportBlockNumber += reportBlockFrequency;
      emit SkipNextBlockInterval(_epoch, reportBlockNumber);
    }

    oracleReports[_epoch][_hash].push(msg.sender);
    oracleReportsVotes[_epoch][_hash]++;
    reportHistoric[_epoch].push(_hash);

    if (consensusReport[_epoch] == bytes32(0)) {
      if (oracleReportsVotes[_epoch][_hash] >= reportOracleQuorum) {
        consensusReport[_epoch] = _hash;
        emit ConsensusApprove(block.number, _epoch, _hash);
        reportExecutionBlock[_hash] = block.number;
        lastConsensusEpoch = _report.epoch;
      } else {
        emit ConsensusNotReached(block.number, _epoch, _hash);
      }
    }
  }

  function executeReport(
    bytes32 _hash,
    Report calldata _report
  ) external nonReentrant whenNotPaused onlyReportOracle {
    require(
      block.number >= reportExecutionBlock[_hash] + minBlocksBeforeExecution,
      'MIN_BLOCKS_BEFORE_EXECUTION_NOT_REACHED'
    );
    require(consensusReport[_report.epoch] == _hash, 'REPORT_NOT_CONSENSUS');
    require(!executedReports[_report.epoch][_hash], 'REPORT_ALREADY_EXECUTED');

    auditReport(_report, _hash);

    reportBlockNumber += reportBlockFrequency;
    executedReports[_report.epoch][_hash] = true;
    lastExecutedConsensusEpoch = _report.epoch;

    (uint256[6] memory shares, uint256[6] memory amounts) = feesContract.estimateFeePercentage(
      Fees.FeeType.Rewards,
      _report.profitAmount
    );

    if (_report.lossAmount > 0) {
      stakeTogether.mintPenalty(_report.lossAmount);
    }

    if (_report.extraAmount > 0) {
      // stakeTogether.refundPool{ value: _report.extraAmount }(_report.epoch);
    }

    if (shares[0] > 0) {
      stakeTogether.mintFeeShares{ value: amounts[0] }(
        feesContract.getFeeAddress(Fees.Roles.Pools),
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        shares[0]
      );

      poolsContract.addRewardsMerkleRoot(_report.epoch, _report.poolsMerkleRoot);
    }

    if (shares[1] > 0) {
      stakeTogether.mintFeeShares{ value: amounts[1] }(
        feesContract.getFeeAddress(Fees.Roles.Operators),
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        shares[1]
      );
    }

    if (shares[2] > 0) {
      stakeTogether.mintFeeShares{ value: amounts[2] }(
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        feesContract.getFeeAddress(Fees.Roles.StakeTogether),
        shares[2]
      );
    }

    if (_report.validatorsToExit.length > 0) {
      emit ValidatorsToExit(_report.epoch, _report.validatorsToExit);
    }

    if (_report.exitedValidators.length > 0) {
      for (uint256 i = 0; i < _report.exitedValidators.length; i++) {
        validatorsContract.removeValidator(_report.epoch, _report.exitedValidators[i]);
      }
    }

    if (_report.restExitAmount > 0) {
      // stakeTogether.refundPool{ value: _report.restExitAmount }(_report.epoch);
    }

    if (_report.withdrawAmount > 0) {
      payable(address(withdrawalsContract)).transfer(_report.withdrawAmount);
    }

    if (_report.apr > 0) {
      // loansContract.setApr(_report.epoch, _report.apr);
    }

    for (uint256 i = 0; i < reportHistoric[_report.epoch].length; i++) {
      bytes32 reportHash = reportHistoric[_report.epoch][i];
      address[] memory oracles = oracleReports[_report.epoch][reportHash];
      for (uint256 j = 0; j < oracles.length; j++) {
        _rewardOrPenalizeReportOracle(oracles[j], reportHash, reportHash == _hash);
      }
    }

    delete reportHistoric[_report.epoch];

    emit ExecuteReport(msg.sender, _hash, _report);
  }

  function invalidateConsensus(
    uint256 _epoch,
    bytes32 _hash
  ) external onlyRole(ORACLE_REPORT_SENTINEL_ROLE) {
    require(_epoch == lastConsensusEpoch, 'CAN_ONLY_INVALIDATE_CURRENT_EPOCH');
    require(consensusReport[_epoch] == _hash, 'REPORT_NOT_CONSENSUS_OR_NOT_EXISTS');
    consensusInvalidatedReport[_epoch] = true;
    emit InvalidateConsensus(block.number, _epoch, _hash);
  }

  function setLastConsensusEpoch(uint256 _epoch) external onlyRole(ADMIN_ROLE) {
    lastConsensusEpoch = _epoch;
    emit SetLastConsensusEpoch(_epoch);
  }

  function isReadyToSubmit(uint256 _epoch) public view returns (bool) {
    return
      (_epoch > lastConsensusEpoch) &&
      (!consensusInvalidatedReport[_epoch]) &&
      (block.number >= reportBlockNumber);
  }

  function isReadyToExecute(uint256 _epoch, bytes32 _hash) public view returns (bool) {
    return
      (_epoch > lastConsensusEpoch) &&
      (!consensusInvalidatedReport[_epoch]) &&
      consensusReport[_epoch] == _hash;
  }

  function setMinBlockBeforeExecution(uint256 _minBlocksBeforeExecution) external onlyRole(ADMIN_ROLE) {
    if (_minBlocksBeforeExecution < 300) {
      _minBlocksBeforeExecution = 300;
    } else {
      minBlocksBeforeExecution = _minBlocksBeforeExecution;
    }
    emit SetMinBlockBeforeExecution(_minBlocksBeforeExecution);
  }

  function setMaxValidatorsToExit(uint256 _maxValidatorsToExit) external onlyRole(ADMIN_ROLE) {
    maxValidatorsToExit = _maxValidatorsToExit;
    emit SetMaxValidatorsToExit(_maxValidatorsToExit);
  }

  function setReportBlockFrequency(uint256 _frequency) external onlyRole(ADMIN_ROLE) {
    reportBlockFrequency = _frequency;
    emit SetReportBlockFrequency(_frequency);
  }

  function setMaxApr(uint256 _maxApr) external onlyRole(ADMIN_ROLE) {
    maxApr = _maxApr;
    emit SetMaxApr(_maxApr);
  }

  /******************
   ** AUDIT REPORT **
   ******************/

  function auditReport(Report calldata _report, bytes32 _hash) public view returns (bool) {
    require(keccak256(abi.encode(_report)) == _hash, 'REPORT_HASH_MISMATCH');

    require(block.number < reportBlockNumber, 'BLOCK_NUMBER_NOT_REACHED');
    require(_report.epoch <= lastConsensusEpoch, 'INVALID_EPOCH');
    require(!consensusInvalidatedReport[_report.epoch], 'REPORT_CONSENSUS_INVALIDATED');
    require(!executedReports[_report.epoch][keccak256(abi.encode(_report))], 'REPORT_ALREADY_EXECUTED');

    require(_report.poolsMerkleRoot != bytes32(0), 'INVALID_POOLS_MERKLE_ROOT');

    require(_report.validatorsToExit.length <= maxValidatorsToExit, 'TOO_MANY_VALIDATORS_TO_EXIT');

    for (uint256 i = 0; i < _report.validatorsToExit.length; i++) {
      require(_report.validatorsToExit[i].oracle != address(0), 'INVALID_ORACLE_ADDRESS');
    }

    require(_report.withdrawAmount <= withdrawalsContract.totalSupply(), 'INVALID_WITHDRAWALS_AMOUNT');

    require(_report.apr <= maxApr, 'INVALID_APR');

    return true;
  }
}
