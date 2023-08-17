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

  function initialize(address _airdrop, address _withdrawals) public initializer {
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

    reportBlockNumber = 1;
    lastConsensusEpoch = 0;
    lastExecutedConsensusEpoch = 0;
  }

  function initializeV2() external onlyRole(UPGRADER_ROLE) {
    version = 2;
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

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

  /************
   ** MOCK FUNCTIONS **
   ************/

  function setBeaconBalance(uint256 _amount) external {
    stakeTogether.setBeaconBalance(_amount);
  }

  function removeValidator(uint256 _epoch, bytes calldata _publicKey) external payable nonReentrant {
    stakeTogether.removeValidator(_epoch, _publicKey);
  }
}
