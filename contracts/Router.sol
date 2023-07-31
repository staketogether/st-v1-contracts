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
import './Fees.sol';
import './Liquidity.sol';
import './StakeTogether.sol';
import './Validators.sol';
import './Withdrawals.sol';

import './interfaces/IFees.sol';
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
  Fees public fees;
  Withdrawals public withdrawals;
  Liquidity public liquidity;
  Airdrop public airdrop;
  Validators public validators;
  Config public config;

  uint256 public totalReportOracles;
  mapping(address => bool) private reportOracles;
  mapping(address => uint256) public reportOraclesBlacklist;

  mapping(uint256 => mapping(bytes32 => address[])) public oracleReports;
  mapping(uint256 => mapping(bytes32 => uint256)) public oracleReportsVotes;
  mapping(uint256 => mapping(bytes32 => bool)) public executedReports;
  mapping(uint256 => bytes32[]) public reportHistoric;
  mapping(uint256 => bytes32) public consensusReport;
  mapping(uint256 => bool) public consensusInvalidatedReport;

  uint256 public reportBlockNumber;
  uint256 public lastConsensusEpoch;
  uint256 public lastExecutedConsensusEpoch;

  mapping(bytes32 => uint256) public reportExecutionBlock;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _airdrop,
    address _fees,
    address _liquidity,
    address _validators,
    address _withdrawals
  ) public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);
    _grantRole(ORACLE_REPORT_MANAGER_ROLE, msg.sender);

    version = 1;

    airdrop = Airdrop(payable(_airdrop));
    fees = Fees(payable(_fees));
    liquidity = Liquidity(payable(_liquidity));
    validators = Validators(payable(_validators));
    withdrawals = Withdrawals(payable(_withdrawals));

    reportBlockNumber = 1;
    lastConsensusEpoch = 0;
    lastExecutedConsensusEpoch = 0;
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

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

  function setConfig(Config memory _config) public onlyRole(ADMIN_ROLE) {
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

  modifier onlyReportOracle() {
    require(
      reportOracles[msg.sender] && reportOraclesBlacklist[msg.sender] < config.oracleBlackListLimit,
      'ONLY_REPORT_ORACLE'
    );
    _;
  }

  function isReportOracle(address _oracle) public view returns (bool) {
    return reportOracles[_oracle] && reportOraclesBlacklist[_oracle] < config.oracleBlackListLimit;
  }

  function isReportOracleBlackListed(address _oracle) public view returns (bool) {
    return reportOraclesBlacklist[_oracle] >= config.oracleBlackListLimit;
  }

  function addReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(totalReportOracles < config.reportOracleQuorum, 'REPORT_ORACLE_QUORUM_REACHED');
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

  function blacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    reportOraclesBlacklist[_oracle] = config.oracleBlackListLimit;
    reportOracles[_oracle] = false;
    emit BlacklistReportOracleManually(_oracle, reportOraclesBlacklist[_oracle]);
  }

  function unBlacklistReportOracle(address _oracle) external onlyRole(ORACLE_REPORT_MANAGER_ROLE) {
    require(reportOracles[_oracle], 'REPORT_ORACLE_NOT_EXISTS');
    require(
      reportOraclesBlacklist[_oracle] >= config.oracleBlackListLimit || !reportOracles[_oracle],
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

  function _updateReportOracleQuorum() internal {
    uint256 newQuorum = (totalReportOracles * 8) / 10;
    config.reportOracleQuorum = newQuorum < config.minReportOracleQuorum
      ? config.minReportOracleQuorum
      : newQuorum;
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

      bool blacklist = reportOraclesBlacklist[_oracle] >= config.oracleBlackListLimit;
      if (blacklist) {
        reportOracles[_oracle] = false;
        emit BlacklistReportOracle(_oracle, reportOraclesBlacklist[_oracle]);
        _updateReportOracleQuorum();
      }

      emit PenalizeReportOracle(_oracle, reportOraclesBlacklist[_oracle], _reportHash, blacklist);
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
  ) external onlyReportOracle nonReentrant whenNotPaused {
    require(block.number < reportBlockNumber, 'BLOCK_NUMBER_NOT_REACHED');
    require(_epoch > lastConsensusEpoch, 'EPOCH_LOWER_THAN_LAST_CONSENSUS');

    auditReport(_report, _hash);

    if (block.number >= reportBlockNumber + config.reportBlockFrequency) {
      reportBlockNumber += config.reportBlockFrequency;
      emit SkipNextBlockInterval(_epoch, reportBlockNumber);
    }

    oracleReports[_epoch][_hash].push(msg.sender);
    oracleReportsVotes[_epoch][_hash]++;
    reportHistoric[_epoch].push(_hash);

    if (consensusReport[_epoch] == bytes32(0)) {
      if (oracleReportsVotes[_epoch][_hash] >= config.reportOracleQuorum) {
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

  function executeReport(
    bytes32 _hash,
    Report calldata _report
  ) external nonReentrant whenNotPaused onlyReportOracle {
    require(
      block.number >= reportExecutionBlock[_hash] + config.minBlocksBeforeExecution,
      'MIN_BLOCKS_BEFORE_EXECUTION_NOT_REACHED'
    );
    require(consensusReport[_report.epoch] == _hash, 'REPORT_NOT_CONSENSUS');
    require(!executedReports[_report.epoch][_hash], 'REPORT_ALREADY_EXECUTED');

    auditReport(_report, _hash);

    reportBlockNumber += config.reportBlockFrequency;
    executedReports[_report.epoch][_hash] = true;
    lastExecutedConsensusEpoch = _report.epoch;

    if (_report.lossAmount > 0) {
      uint256 newBeaconBalance = stakeTogether.beaconBalance() - _report.lossAmount;
      stakeTogether.setBeaconBalance(newBeaconBalance);
    }

    (uint256[4] memory _shares, uint256[4] memory _amounts) = fees.estimateFeePercentage(
      IFees.FeeType.StakeRewards,
      _report.profitAmount,
      false
    );

    if (_report.validatorsToExit.length > 0) {
      emit ValidatorsToExit(_report.epoch, _report.validatorsToExit);
    }

    if (_report.exitedValidators.length > 0) {
      for (uint256 i = 0; i < _report.exitedValidators.length; i++) {
        validators.removeValidator(_report.epoch, _report.exitedValidators[i]);
      }
    }

    for (uint256 i = 0; i < reportHistoric[_report.epoch].length; i++) {
      bytes32 reportHash = reportHistoric[_report.epoch][i];
      address[] memory oracles = oracleReports[_report.epoch][reportHash];
      for (uint256 j = 0; j < oracles.length; j++) {
        _rewardOrPenalizeReportOracle(oracles[j], reportHash, reportHash == _hash);
      }
    }

    Fees.FeeRole[4] memory roles = fees.getFeesRoles();
    for (uint i = 0; i < roles.length - 1; i++) {
      if (_shares[i] > 0) {
        stakeTogether.mintRewards{ value: _amounts[i] }(
          fees.getFeeAddress(roles[i]),
          fees.getFeeAddress(IFees.FeeRole.StakeTogether),
          _shares[i],
          IFees.FeeType.StakeRewards,
          roles[i]
        );
      }
    }

    airdrop.addAirdropMerkleRoot(_report.epoch, _report.merkleRoot);

    if (_report.withdrawAmount > 0) {
      payable(address(withdrawals)).transfer(_report.withdrawAmount);
    }

    if (_report.restWithdrawAmount > 0) {
      stakeTogether.refundPool{ value: _report.restWithdrawAmount }();
    }

    if (_report.routerExtraAmount > 0) {
      payable(address(stakeTogether)).transfer(_report.routerExtraAmount);
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

  /******************
   ** AUDIT REPORT **
   ******************/

  function auditReport(Report calldata _report, bytes32 _hash) public view returns (bool) {
    require(keccak256(abi.encode(_report)) == _hash, 'REPORT_HASH_MISMATCH');

    require(block.number < reportBlockNumber, 'BLOCK_NUMBER_NOT_REACHED');
    require(_report.epoch <= lastConsensusEpoch, 'INVALID_EPOCH');
    require(!consensusInvalidatedReport[_report.epoch], 'REPORT_CONSENSUS_INVALIDATED');
    require(!executedReports[_report.epoch][keccak256(abi.encode(_report))], 'REPORT_ALREADY_EXECUTED');
    require(_report.merkleRoot != bytes32(0), 'INVALID_MERKLE_ROOT');
    require(_report.validatorsToExit.length <= config.maxValidatorsToExit, 'TOO_MANY_VALIDATORS_TO_EXIT');

    for (uint256 i = 0; i < _report.validatorsToExit.length; i++) {
      require(_report.validatorsToExit[i].oracle != address(0), 'INVALID_ORACLE_ADDRESS');
    }

    require(_report.withdrawAmount <= withdrawals.totalSupply(), 'INVALID_WITHDRAWALS_AMOUNT');

    require(stakeTogether.beaconBalance() - _report.lossAmount > 0, 'INVALID_BEACON_BALANCE');

    return true;
  }
}
