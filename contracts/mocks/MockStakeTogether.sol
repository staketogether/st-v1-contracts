// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

import '../Withdrawals.sol';

import '../interfaces/IStakeTogether.sol';
import '../interfaces/IDepositContract.sol';

/// @custom:security-contact security@staketogether.app
contract MockStakeTogether is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  ERC20PermitUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IStakeTogether
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant POOL_MANAGER_ROLE = keccak256('POOL_MANAGER_ROLE');
  bytes32 public constant VALIDATOR_ORACLE_ROLE = keccak256('VALIDATOR_ORACLE_ROLE');
  bytes32 public constant VALIDATOR_ORACLE_MANAGER_ROLE = keccak256('VALIDATOR_ORACLE_MANAGER_ROLE');
  bytes32 public constant VALIDATOR_ORACLE_SENTINEL_ROLE = keccak256('VALIDATOR_ORACLE_SENTINEL_ROLE');

  uint256 public version;

  address public router;
  Withdrawals public withdrawals;
  IDepositContract public deposit;

  bytes public withdrawalCredentials;
  uint256 public beaconBalance;
  Config public config;

  mapping(address => uint256) public shares;
  uint256 public totalShares;
  mapping(address => mapping(address => uint256)) private allowances;

  uint256 public lastResetBlock;
  uint256 public totalDeposited;
  uint256 public totalWithdrawn;

  mapping(address => bool) private pools;

  address[] private validatorsOracle;
  mapping(address => uint256) public validatorsOracleIndices;
  uint256 public currentOracleIndex;

  mapping(bytes => bool) private validators;
  uint256 private totalValidators;

  mapping(FeeRole => address payable) private feesRole;
  mapping(FeeType => Fee) private fees;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
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
}
