// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

import './Airdrop.sol';
import './StakeTogether.sol';
import './Withdrawals.sol';

import './interfaces/IStakeTogether.sol';
import './interfaces/IRouter.sol';

/// @custom:security-contact security@staketogether.app
contract Router is
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
  mapping(uint256 => bool) public revokedReports;

  uint256 public reportBlock;
  uint256 public lastConsensusEpoch;
  uint256 public lastExecutedEpoch;

  mapping(bytes32 => uint256) public reportDelay;

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
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  /************
   ** CONFIG **
   ************/

  function setConfig(Config memory _config) external onlyRole(ADMIN_ROLE) {
    config = _config;
    if (config.reportDelay < 300) {
      config.reportDelay = 300;
    } else {
      config.reportDelay = config.reportDelay;
    }

    emit SetConfig(_config);
  }

  /*******************
   ** REPORT ORACLE **
   *******************/

  modifier activeReportOracle() {
    require(isReportOracle(msg.sender) && !isReportOracleBlackListed(msg.sender), 'ONLY_ACTIVE_ORACLE');
    _;
  }

  function isReportOracle(address _oracle) public view returns (bool) {
    return reportsOracles[_oracle] && reportsOracleBlacklist[_oracle] < config.oracleBlackListLimit;
  }

  function isReportOracleBlackListed(address _oracle) public view returns (bool) {
    return reportsOracleBlacklist[_oracle] >= config.oracleBlackListLimit;
  }

  function addReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
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

    config.oracleQuorum = newQuorum < config.minOracleQuorum ? config.minOracleQuorum : newQuorum;
    emit UpdateReportOracleQuorum(newQuorum);
  }

  function blacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    reportsOracleBlacklist[_oracle] = config.oracleBlackListLimit;
    if (totalReportsOracle > 0) {
      totalReportsOracle--;
    }
    emit BlacklistReportOracle(_oracle, reportsOracleBlacklist[_oracle]);
  }

  function unBlacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportsOracles[_oracle], 'REPORT_ORACLE_NOT_EXISTS');
    require(
      reportsOracleBlacklist[_oracle] >= config.oracleBlackListLimit,
      'REPORT_ORACLE_NOT_BLACKLISTED'
    );
    reportsOracleBlacklist[_oracle] = 0;
    totalReportsOracle++;
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

  function _evaluateOracles(uint256 _epoch, bytes32 _hash) private {
    for (uint256 i = 0; i < reportHistoric[_epoch].length; i++) {
      bytes32 reportHash = reportHistoric[_epoch][i];
      address[] memory oracles = reports[_epoch][reportHash];
      for (uint256 j = 0; j < oracles.length; j++) {
        _evaluateConduct(oracles[j], reportHash, reportHash == _hash);
      }
    }
  }

  function _evaluateConduct(address _oracle, bytes32 _reportHash, bool consensus) private {
    if (consensus) {
      if (reportsOracleBlacklist[_oracle] > 0) {
        reportsOracleBlacklist[_oracle]--;
      }
      emit RewardReportOracle(_oracle, reportsOracleBlacklist[_oracle], _reportHash);
    } else {
      reportsOracleBlacklist[_oracle]++;
      bool blacklist = reportsOracleBlacklist[_oracle] >= config.oracleBlackListLimit;
      emit PenalizeReportOracle(_oracle, reportsOracleBlacklist[_oracle], _reportHash, blacklist);

      if (blacklist) {
        reportsOracleBlacklist[_oracle] = config.oracleBlackListLimit;
        emit BlacklistReportOracle(_oracle, reportsOracleBlacklist[_oracle]);
        if (totalReportsOracle > 0) {
          totalReportsOracle--;
        }
        _updateQuorum();
      }
    }
  }

  /************
   ** REPORT **
   ************/

  function submitReport(
    uint256 _epoch,
    Report calldata _report
  ) external nonReentrant whenNotPaused activeReportOracle {
    bytes32 hash = keccak256(abi.encode(_report));
    require(block.number < reportBlock, 'BLOCK_NUMBER_NOT_REACHED');
    require(totalReportsOracle >= config.minOracleQuorum, 'MIN_ORACLE_QUORUM_NOT_REACHED');
    require(_report.epoch > lastConsensusEpoch, 'EPOCH_NOT_GREATER_THAN_LAST_CONSENSUS');
    require(!executedReports[_report.epoch][hash], 'REPORT_ALREADY_EXECUTED');
    require(keccak256(abi.encode(_report)) == hash, 'REPORT_HASH_MISMATCH');
    require(stakeTogether.beaconBalance() - _report.lossAmount > 0, 'INVALID_BEACON_BALANCE');

    if (block.number >= reportBlock + config.reportFrequency) {
      reportBlock += config.reportFrequency;
      emit SkipNextReportFrequency(_epoch, reportBlock);
    }

    reports[_epoch][hash].push(msg.sender);
    reportVotes[_epoch][hash]++;
    reportHistoric[_epoch].push(hash);

    if (consensusReport[_epoch] == bytes32(0)) {
      if (reportVotes[_epoch][hash] >= config.oracleQuorum) {
        consensusReport[_epoch] = hash;
        lastConsensusEpoch = _report.epoch;
        reportDelay[hash] = block.number;
        emit ConsensusApprove(_report, hash);
        _evaluateOracles(_epoch, hash);
      } else {
        emit ConsensusNotReached(_report, hash);
      }
    }

    emit SubmitReport(_report, hash);
  }

  function executeReport(Report calldata _report) external nonReentrant whenNotPaused activeReportOracle {
    bytes32 hash = keccak256(abi.encode(_report));
    require(!revokedReports[_report.epoch], 'REVOKED_REPORT');
    require(!executedReports[_report.epoch][hash], 'REPORT_ALREADY_EXECUTED');
    require(consensusReport[_report.epoch] == hash, 'REPORT_NOT_CONSENSUS');
    require(totalReportsOracle >= config.minOracleQuorum, 'MIN_ORACLE_QUORUM_NOT_REACHED');
    require(block.number >= reportDelay[hash] + config.reportDelay, 'TOO_EARLY_TO_EXECUTE_REPORT');

    reportBlock += config.reportFrequency;
    executedReports[_report.epoch][hash] = true;
    lastExecutedEpoch = _report.epoch;
    delete reportHistoric[_report.epoch];
    emit ExecuteReport(_report, hash);

    if (_report.validatorsToRemove.length > 0) {
      emit ValidatorsToRemove(_report.epoch, _report.validatorsToRemove);
    }

    if (_report.merkleRoot != bytes32(0)) {
      airdrop.addMerkleRoot(_report.epoch, _report.merkleRoot);
    }

    if (_report.profitAmount > 0) {
      stakeTogether.processStakeRewards{ value: _report.profitAmount }();
    }

    if (_report.lossAmount > 0) {
      stakeTogether.setBeaconBalance(stakeTogether.beaconBalance() - _report.lossAmount);
    }

    if (_report.withdrawAmount > 0) {
      payable(address(withdrawals)).transfer(_report.withdrawAmount);
    }

    if (_report.withdrawRefundAmount > 0) {
      stakeTogether.withdrawRefund{ value: _report.withdrawRefundAmount }();
    }

    if (_report.routerExtraAmount > 0) {
      payable(stakeTogether.getFeeAddress(IStakeTogether.FeeRole.StakeTogether)).transfer(
        _report.routerExtraAmount
      );
    }
  }

  function revokeConsensus(uint256 _epoch, bytes32 _hash) external onlyRole(ORACLE_REPORT_SENTINEL_ROLE) {
    require(consensusReport[_epoch] == _hash, 'EPOCH_NOT_CONSENSUS');
    revokedReports[_epoch] = true;
    emit RevokeConsensus(block.number, _epoch, _hash);
  }

  function setLastConsensusEpoch(uint256 _epoch) external onlyRole(ADMIN_ROLE) {
    lastConsensusEpoch = _epoch;
    emit SetLastConsensusEpoch(_epoch);
  }

  function isReadyToSubmit(uint256 _epoch) external view returns (bool) {
    return (_epoch > lastConsensusEpoch) && (!revokedReports[_epoch]) && (block.number >= reportBlock);
  }

  function isReadyToExecute(uint256 _epoch, bytes32 _hash) external view returns (bool) {
    return (_epoch > lastConsensusEpoch) && (!revokedReports[_epoch]) && consensusReport[_epoch] == _hash;
  }
}
