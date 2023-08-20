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
  bytes32 public constant ORACLE_SENTINEL_ROLE = keccak256('ORACLE_SENTINEL_ROLE');
  bytes32 public constant ORACLE_REPORT_ROLE = keccak256('ORACLE_REPORT_ROLE');
  uint256 public version;

  StakeTogether public stakeTogether;
  Withdrawals public withdrawals;
  Airdrop public airdrop;
  Config public config;

  uint256 public totalOracles;
  mapping(address => bool) private oracles;
  mapping(address => bool) public oraclesBlacklist;
  mapping(uint256 => mapping(address => bool)) private oracleVotes;

  mapping(uint256 => mapping(bytes32 => address[])) public reports;
  mapping(uint256 => mapping(bytes32 => uint256)) public reportVotes;
  mapping(uint256 => bytes32) public consensusReport;
  mapping(uint256 => mapping(bytes32 => bool)) public executedReports;
  mapping(uint256 => bool) public revokedReports;

  uint256 public nextReportBlock;
  uint256 public lastConsensusEpoch;
  uint256 public lastExecutedEpoch;

  mapping(bytes32 => uint256) public reportDelayBlocks;

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

    totalOracles = 0;
    nextReportBlock = 1;
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
    emit ReceiveEther(msg.value);
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
    if (config.reportDelayBlocks < 300) {
      config.reportDelayBlocks = 300;
    } else {
      config.reportDelayBlocks = config.reportDelayBlocks;
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
    return oracles[_oracle] && !oraclesBlacklist[_oracle];
  }

  function isReportOracleBlackListed(address _oracle) public view returns (bool) {
    return oraclesBlacklist[_oracle];
  }

  function addReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(!oracles[_oracle], 'REPORT_ORACLE_EXISTS');
    _grantRole(ORACLE_REPORT_ROLE, _oracle);
    oracles[_oracle] = true;
    totalOracles++;
    emit AddReportOracle(_oracle);
    _updateQuorum();
  }

  function removeReportOracle(address oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(oracles[oracle], 'REPORT_ORACLE_NOT_EXISTS');
    _revokeRole(ORACLE_REPORT_ROLE, oracle);
    oracles[oracle] = false;
    totalOracles--;
    emit RemoveReportOracle(oracle);
    _updateQuorum();
  }

  function _updateQuorum() private {
    uint256 newQuorum = MathUpgradeable.mulDiv(totalOracles, 3, 5);
    config.oracleQuorum = newQuorum < config.minOracleQuorum ? config.minOracleQuorum : newQuorum;
    emit UpdateReportOracleQuorum(newQuorum);
  }

  function blacklistReportOracle(address _oracle) external onlyRole(ORACLE_SENTINEL_ROLE) {
    oraclesBlacklist[_oracle] = true;
    if (totalOracles > 0) {
      totalOracles--;
    }
    emit BlacklistReportOracle(_oracle);
  }

  function unBlacklistReportOracle(address _oracle) external onlyRole(ORACLE_SENTINEL_ROLE) {
    require(oracles[_oracle], 'REPORT_ORACLE_NOT_EXISTS');
    require(oraclesBlacklist[_oracle], 'REPORT_ORACLE_NOT_BLACKLISTED');
    oraclesBlacklist[_oracle] = false;
    totalOracles++;
    emit UnBlacklistReportOracle(_oracle);
  }

  function addSentinel(address _account) external onlyRole(ADMIN_ROLE) {
    require(!hasRole(ORACLE_SENTINEL_ROLE, _account), 'SENTINEL_EXISTS');
    grantRole(ORACLE_SENTINEL_ROLE, _account);
  }

  function removeSentinel(address _account) external onlyRole(ADMIN_ROLE) {
    require(hasRole(ORACLE_SENTINEL_ROLE, _account), 'SENTINEL_NOT_EXISTS');
    revokeRole(ORACLE_SENTINEL_ROLE, _account);
  }

  /************
   ** REPORT **
   ************/

  function submitReport(
    uint256 _epoch,
    Report calldata _report
  ) external nonReentrant whenNotPaused activeReportOracle {
    bytes32 hash = isReadyToSubmit(_epoch, _report);

    if (block.number >= nextReportBlock + config.reportFrequency) {
      nextReportBlock += config.reportFrequency;
      emit SkipNextReportFrequency(_epoch, nextReportBlock);
    }

    reports[_epoch][hash].push(msg.sender);
    reportVotes[_epoch][hash]++;
    oracleVotes[_epoch][msg.sender] = true;

    if (consensusReport[_epoch] == bytes32(0)) {
      if (reportVotes[_epoch][hash] >= config.oracleQuorum) {
        consensusReport[_epoch] = hash;
        lastConsensusEpoch = _report.epoch;
        reportDelayBlocks[hash] = block.number;
        emit ConsensusApprove(_report, hash);
      } else {
        emit ConsensusNotReached(_report, hash);
      }
    }

    emit SubmitReport(_report, hash);
  }

  function executeReport(Report calldata _report) external nonReentrant whenNotPaused activeReportOracle {
    bytes32 hash = isReadyToExecute(_report);

    nextReportBlock += config.reportFrequency;
    executedReports[_report.epoch][hash] = true;
    lastExecutedEpoch = _report.epoch;
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

    if (_report.lossAmount > 0 || _report.withdrawRefundAmount > 0) {
      uint256 reduceAmount = _report.lossAmount + _report.withdrawRefundAmount;
      stakeTogether.setBeaconBalance{ value: _report.withdrawRefundAmount }(
        stakeTogether.beaconBalance() - reduceAmount
      );
    }

    if (_report.withdrawAmount > 0) {
      withdrawals.receiveWithdrawEther{ value: _report.withdrawAmount }();
    }

    if (_report.routerExtraAmount > 0) {
      payable(stakeTogether.getFeeAddress(IStakeTogether.FeeRole.StakeTogether)).transfer(
        _report.routerExtraAmount
      );
    }
  }

  function getReportHash(Report calldata _report) external pure returns (bytes32) {
    return keccak256(abi.encode(_report));
  }

  function revokeConsensusReport(uint256 _epoch, bytes32 _hash) external onlyRole(ORACLE_SENTINEL_ROLE) {
    require(consensusReport[_epoch] == _hash, 'EPOCH_NOT_CONSENSUS');
    revokedReports[_epoch] = true;
    emit RevokeConsensusReport(block.number, _epoch, _hash);
  }

  function setLastConsensusEpoch(uint256 _epoch) external onlyRole(ADMIN_ROLE) {
    lastConsensusEpoch = _epoch;
    emit SetLastConsensusEpoch(_epoch);
  }

  function isReadyToSubmit(uint256 _epoch, Report calldata _report) public view returns (bytes32) {
    bytes32 hash = keccak256(abi.encode(_report));
    require(block.number > nextReportBlock, 'BLOCK_NUMBER_NOT_REACHED');
    require(totalOracles >= config.minOracleQuorum, 'MIN_ORACLE_QUORUM_NOT_REACHED');
    require(_report.epoch > lastConsensusEpoch, 'EPOCH_NOT_GREATER_THAN_LAST_CONSENSUS');
    require(!executedReports[_report.epoch][hash], 'REPORT_ALREADY_EXECUTED');
    require(!oracleVotes[_epoch][msg.sender], 'ORACLE_ALREADY_VOTED');
    return hash;
  }

  function isReadyToExecute(Report calldata _report) public view returns (bytes32) {
    bytes32 hash = keccak256(abi.encode(_report));
    require(!revokedReports[_report.epoch], 'REVOKED_REPORT');
    require(!executedReports[_report.epoch][hash], 'REPORT_ALREADY_EXECUTED');
    require(consensusReport[_report.epoch] == hash, 'REPORT_NOT_CONSENSUS');
    require(totalOracles >= config.minOracleQuorum, 'MIN_ORACLE_QUORUM_NOT_REACHED');
    require(block.number >= reportDelayBlocks[hash] + config.reportDelayBlocks, 'TOO_EARLY_TO_EXECUTE');
    require(
      _report.lossAmount + _report.withdrawRefundAmount <= stakeTogether.beaconBalance(),
      'NOT_ENOUGH_BEACON_BALANCE'
    );
    require(
      address(this).balance >=
        (_report.profitAmount +
          _report.withdrawAmount +
          _report.withdrawRefundAmount +
          _report.routerExtraAmount),
      'NOT_ENOUGH_ETH'
    );
    return hash;
  }

  /********************
   ** MOCK FUNCTIONS **
   ********************/

  function initializeV2() external onlyRole(UPGRADER_ROLE) {
    version = 2;
  }

  function setBeaconBalance(uint256 _amount) external payable {
    stakeTogether.setBeaconBalance(_amount);
  }

  function processStakeRewards() external payable {
    stakeTogether.processStakeRewards{ value: msg.value }();
  }

  function addMerkleRoot(uint256 _epoch, bytes32 merkleRoot) external nonReentrant {
    airdrop.addMerkleRoot(_epoch, merkleRoot);
  }
}
