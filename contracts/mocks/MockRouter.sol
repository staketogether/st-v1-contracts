// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

import '../Airdrop.sol';
import '../StakeTogether.sol';
import '../Withdrawals.sol';

import '../interfaces/IStakeTogether.sol';
import '../interfaces/IRouter.sol';

/// @custom:security-contact security@staketogether.app
contract MockRouter is
  Initializable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IRouter
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_REPORT_MANAGER_ROLE = keccak256('ORACLE_REPORT_MANAGER_ROLE');
  bytes32 public constant ORACLE_REPORT_SENTINEL_ROLE = keccak256('ORACLE_REPORT_SENTINEL_ROLE');
  bytes32 public constant ORACLE_REPORT_ROLE = keccak256('ORACLE_REPORT_ROLE');
  uint256 public version;

  StakeTogether public stakeTogether;
  Withdrawals public withdrawals;
  Airdrop public airdrop;
  Config public config;

  uint256 public totalReportsOracle;
  mapping(address => bool) private reportsOracles;
  mapping(address => uint256) public reportsOracleBlacklist;

  mapping(uint256 => mapping(bytes32 => address[])) public reports;
  mapping(uint256 => mapping(bytes32 => uint256)) public reportVotes;
  mapping(uint256 => mapping(bytes32 => bool)) public executedReports;
  mapping(uint256 => bytes32[]) public reportHistoric;
  mapping(uint256 => bytes32) public consensusReport;
  mapping(uint256 => bool) public invalidatedReports;

  uint256 public reportBlock;
  uint256 public lastConsensusEpoch;
  uint256 public lastExecutedEpoch;

  mapping(bytes32 => uint256) public reportExecutionBlock;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _airdrop, address _withdrawals) external initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
    _grantRole(ORACLE_REPORT_MANAGER_ROLE, msg.sender);

    version = 1;

    airdrop = Airdrop(payable(_airdrop));
    withdrawals = Withdrawals(payable(_withdrawals));

    reportBlock = 1;
    lastConsensusEpoch = 0;
    lastExecutedEpoch = 0;
  }

  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address _newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable {
    emit ReceiveEther(msg.sender, msg.value);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(address(stakeTogether) == address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) external onlyRole(ADMIN_ROLE) {
    if (config.minBlocksBeforeExecution < 300) {
      config.minBlocksBeforeExecution = 300;
    } else {
      config.minBlocksBeforeExecution = config.minBlocksBeforeExecution;
    }
    config = _config;
    emit SetConfig(_config);
  }

  /*******************
   ** REPORT ORACLE **
   *******************/

  modifier reportOracle() {
    require(
      reportsOracles[msg.sender] && reportsOracleBlacklist[msg.sender] < config.oracleBlackListLimit,
      'ONLY_REPORT_ORACLE'
    );
    _;
  }

  function isReportOracle(address _oracle) external view returns (bool) {
    return reportsOracles[_oracle] && reportsOracleBlacklist[_oracle] < config.oracleBlackListLimit;
  }

  function isReportOracleBlackListed(address _oracle) external view returns (bool) {
    return reportsOracleBlacklist[_oracle] >= config.oracleBlackListLimit;
  }

  function addReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(totalReportsOracle < config.reportOracleQuorum, 'REPORT_ORACLE_QUORUM_REACHED');
    require(!reportsOracles[_oracle], 'REPORT_ORACLE_EXISTS');
    _grantRole(ORACLE_REPORT_ROLE, _oracle);
    reportsOracles[_oracle] = true;
    totalReportsOracle++;
    emit AddReportOracle(_oracle);
    _updateQuorum();
  }

  function removeReportOracle(address oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportsOracles[oracle], 'REPORT_ORACLE_NOT_EXISTS');
    _revokeRole(ORACLE_REPORT_ROLE, oracle);
    reportsOracles[oracle] = false;
    totalReportsOracle--;
    emit RemoveReportOracle(oracle);
    _updateQuorum();
  }

  function _updateQuorum() private {
    uint256 newQuorum = MathUpgradeable.mulDiv(totalReportsOracle, 3, 5);

    config.reportOracleQuorum = newQuorum < config.minReportOracleQuorum
      ? config.minReportOracleQuorum
      : newQuorum;
    emit UpdateReportOracleQuorum(newQuorum);
  }

  function blacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    reportsOracleBlacklist[_oracle] = config.oracleBlackListLimit;
    reportsOracles[_oracle] = false;
    emit BlacklistReportOracleManually(_oracle, reportsOracleBlacklist[_oracle]);
  }

  function unBlacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportsOracles[_oracle], 'REPORT_ORACLE_NOT_EXISTS');
    require(
      reportsOracleBlacklist[_oracle] >= config.oracleBlackListLimit,
      'REPORT_ORACLE_NOT_BLACKLISTED'
    );
    reportsOracleBlacklist[_oracle] = 0;
    reportsOracles[_oracle] = true;
    emit UnBlacklistReportOracle(_oracle, reportsOracleBlacklist[_oracle]);
  }

  function addSentinel(address _account) external onlyRole(ADMIN_ROLE) {
    require(!hasRole(ORACLE_REPORT_SENTINEL_ROLE, _account), 'SENTINEL_EXISTS');
    grantRole(ORACLE_REPORT_SENTINEL_ROLE, _account);
  }

  function removeSentinel(address _account) external onlyRole(ADMIN_ROLE) {
    require(hasRole(ORACLE_REPORT_SENTINEL_ROLE, _account), 'SENTINEL_NOT_EXISTS');
    revokeRole(ORACLE_REPORT_SENTINEL_ROLE, _account);
  }

  function _evaluateOracleConduct(address _oracle, bytes32 _reportHash, bool consensus) private {
    if (consensus) {
      if (reportsOracleBlacklist[_oracle] > 0) {
        reportsOracleBlacklist[_oracle]--;
      }
      emit RewardReportOracle(_oracle, reportsOracleBlacklist[_oracle], _reportHash);
    } else {
      reportsOracleBlacklist[_oracle]++;

      bool blacklist = reportsOracleBlacklist[_oracle] >= config.oracleBlackListLimit;
      if (blacklist) {
        reportsOracles[_oracle] = false;
        emit BlacklistReportOracle(_oracle, reportsOracleBlacklist[_oracle]);
        _updateQuorum();
      }

      emit PenalizeReportOracle(_oracle, reportsOracleBlacklist[_oracle], _reportHash, blacklist);
    }
  }

  function requestValidatorsExit(bytes[] calldata publicKeys) external onlyRole(ADMIN_ROLE) {
    emit RequestValidatorsExit(publicKeys);
  }

  /************
   ** REPORT **
   ************/

  function submitReport(
    uint256 _epoch,
    bytes32 _hash,
    Report calldata _report
  ) external reportOracle nonReentrant whenNotPaused {
    require(block.number < reportBlock, 'BLOCK_NUMBER_NOT_REACHED');
    require(_epoch > lastConsensusEpoch, 'EPOCH_LOWER_THAN_LAST_CONSENSUS');

    validReport(_report, _hash);

    if (block.number >= reportBlock + config.reportBlockFrequency) {
      reportBlock += config.reportBlockFrequency;
      emit SkipNextBlockInterval(_epoch, reportBlock);
    }

    reports[_epoch][_hash].push(msg.sender);
    reportVotes[_epoch][_hash]++;
    reportHistoric[_epoch].push(_hash);

    if (consensusReport[_epoch] == bytes32(0)) {
      if (reportVotes[_epoch][_hash] >= config.reportOracleQuorum) {
        consensusReport[_epoch] = _hash;
        emit ConsensusApprove(block.number, _epoch, _hash);
        reportExecutionBlock[_hash] = block.number;
        lastConsensusEpoch = _report.epoch;
      } else {
        emit ConsensusNotReached(block.number, _epoch, _hash);
      }
    }

    emit SubmitReport(msg.sender, block.number, _epoch, _hash);
  }

  // Todo: simplify this function (too many operations, need economy of gas)
  // Todo: split execute report into multiple operations
  function executeReport(
    bytes32 _hash,
    Report calldata _report
  ) external nonReentrant whenNotPaused reportOracle {
    validReport(_report, _hash);

    for (uint256 i = 0; i < reportHistoric[_report.epoch].length; i++) {
      bytes32 reportHash = reportHistoric[_report.epoch][i];
      address[] memory oracles = reports[_report.epoch][reportHash];
      for (uint256 j = 0; j < oracles.length; j++) {
        _evaluateOracleConduct(oracles[j], reportHash, reportHash == _hash);
      }
    }

    reportBlock += config.reportBlockFrequency;
    executedReports[_report.epoch][_hash] = true;
    lastExecutedEpoch = _report.epoch;
    delete reportHistoric[_report.epoch];
    emit ExecuteReport(msg.sender, _hash, _report);

    // Todo: implement optimized staking rewards

    if (_report.merkleRoot != bytes32(0)) {
      airdrop.addMerkleRoot(_report.epoch, _report.merkleRoot);
    }

    // Todo: implement that
    if (_report.profitAmount > 0) {
      stakeTogether.processStakeRewardsFee{ value: _report.profitAmount }();
    }

    if (_report.lossAmount > 0) {
      uint256 newBeaconBalance = stakeTogether.beaconBalance() - _report.lossAmount;
      stakeTogether.setBeaconBalance(newBeaconBalance);
    }

    if (_report.withdrawAmount > 0) {
      payable(address(withdrawals)).transfer(_report.withdrawAmount);
    }

    if (_report.withdrawRefundAmount > 0) {
      stakeTogether.withdrawRefund{ value: _report.withdrawRefundAmount }();
    }

    if (_report.routerExtraAmount > 0) {
      payable(address(stakeTogether)).transfer(_report.routerExtraAmount);
    }

    if (_report.validatorsToRemove.length > 0) {
      emit ValidatorsToRemove(_report.epoch, _report.validatorsToRemove);
    }

    if (_report.validatorsRemoved.length > 0) {
      emit ValidatorsRemoved(_report.epoch, _report.validatorsRemoved);
    }
  }

  function invalidateConsensus(
    uint256 _epoch,
    bytes32 _hash
  ) external onlyRole(ORACLE_REPORT_SENTINEL_ROLE) {
    require(_epoch == lastConsensusEpoch, 'CAN_ONLY_INVALIDATE_CURRENT_EPOCH');
    require(consensusReport[_epoch] == _hash, 'REPORT_NOT_CONSENSUS_OR_NOT_EXISTS');
    invalidatedReports[_epoch] = true;
    emit InvalidateConsensus(block.number, _epoch, _hash);
  }

  function setLastConsensusEpoch(uint256 _epoch) external onlyRole(ADMIN_ROLE) {
    lastConsensusEpoch = _epoch;
    emit SetLastConsensusEpoch(_epoch);
  }

  function isReadyToSubmit(uint256 _epoch) external view returns (bool) {
    return
      (_epoch > lastConsensusEpoch) && (!invalidatedReports[_epoch]) && (block.number >= reportBlock);
  }

  function isReadyToExecute(uint256 _epoch, bytes32 _hash) external view returns (bool) {
    return
      (_epoch > lastConsensusEpoch) && (!invalidatedReports[_epoch]) && consensusReport[_epoch] == _hash;
  }

  /******************
   ** AUDIT REPORT **
   ******************/

  function validReport(Report calldata _report, bytes32 _hash) public view returns (bool) {
    require(!invalidatedReports[_report.epoch], 'REPORT_CONSENSUS_INVALIDATED');

    require(
      block.number >= reportExecutionBlock[_hash] + config.minBlocksBeforeExecution,
      'MIN_BLOCKS_BEFORE_EXECUTION_NOT_REACHED'
    );
    require(consensusReport[_report.epoch] == _hash, 'REPORT_NOT_CONSENSUS');
    require(!executedReports[_report.epoch][_hash], 'REPORT_ALREADY_EXECUTED');

    require(keccak256(abi.encode(_report)) == _hash, 'REPORT_HASH_MISMATCH');

    require(block.number < reportBlock, 'BLOCK_NUMBER_NOT_REACHED');
    require(_report.epoch <= lastConsensusEpoch, 'INVALID_EPOCH');

    require(!executedReports[_report.epoch][keccak256(abi.encode(_report))], 'REPORT_ALREADY_EXECUTED');
    require(_report.merkleRoot != bytes32(0), 'INVALID_MERKLE_ROOT');

    require(_report.withdrawAmount <= withdrawals.totalSupply(), 'INVALID_WITHDRAWALS_AMOUNT');

    require(stakeTogether.beaconBalance() - _report.lossAmount > 0, 'INVALID_BEACON_BALANCE');

    return true;
  }

  /********************
   ** MOCK FUNCTIONS **
   ********************/

  function setBeaconBalance(uint256 _amount) external {
    stakeTogether.setBeaconBalance(_amount);
  }

  function withdrawRefund() external payable {
    stakeTogether.withdrawRefund{ value: msg.value }();
  }

  function processStakeRewardsFee() external payable {
    stakeTogether.processStakeRewardsFee{ value: msg.value }();
  }

  function addMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external nonReentrant {
    airdrop.addMerkleRoot(_epoch, merkleRoot);
  }
}
