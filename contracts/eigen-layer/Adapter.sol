// SPDX-FileCopyrightText: 2024 Together Technology LTD <legal@staketogether.org>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/utils/Address.sol';

import './interfaces/IAdapter.sol';
import './interfaces/IBridge.sol';
import './interfaces/IDepositContract.sol';

/// @title StakeTogether Adapter Contract
/// @notice The Adapter Contract is responsible to interact with Staking Infrastructure and manage the staking process.
/// It provides functionalities for create validators, withdraw and withdraw rewards.
/// @custom:security-contact security@staketogether.org
contract Adapter is
  Initializable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IAdapter
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE'); /// Role for managing upgrades.
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE'); /// Role for administration.
  bytes32 public constant VALIDATOR_ORACLE_ROLE = keccak256('VALIDATOR_ORACLE_ROLE'); /// Role for managing validator oracles.
  bytes32 public constant VALIDATOR_ORACLE_MANAGER_ROLE = keccak256('VALIDATOR_ORACLE_MANAGER_ROLE'); /// Role for managing validator oracle managers.
  bytes32 public constant VALIDATOR_ORACLE_SENTINEL_ROLE = keccak256('VALIDATOR_ORACLE_SENTINEL_ROLE'); /// Role for managing validator oracle sentinels.

  IDepositContract public deposit; /// Instance of the deposit contract.
  IBridge public bridge; /// Instance of the bridge contract.
  Config public config; /// Configuration settings.
  address public l2; /// Address of the StakeTogether on L2.
  uint256 public version; /// Contract version.

  bytes public withdrawalCredentials; /// Credentials for withdrawals.

  address[] private validatorsOracle; /// List of validator oracles.
  mapping(address => uint256) private validatorsOracleIndices; /// Mapping of validator oracle indices.
  uint256 public currentOracleIndex; /// Current index of the oracle.

  mapping(bytes => bool) public validators; /// Mapping of validators.

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Stake Together Pool Initialization
  /// @param _bridge The address of the bridge contract.
  /// @param _deposit The address of the deposit contract.
  /// @param _withdrawalCredentials The bytes for withdrawal credentials.
  function initialize(
    address _bridge,
    address _deposit,
    bytes memory _withdrawalCredentials
  ) public initializer {
    __Pausable_init();
    __ReentrancyGuard_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

    version = 1;

    bridge = IBridge(_bridge);
    deposit = IDepositContract(_deposit);
    withdrawalCredentials = _withdrawalCredentials;
  }

  /// @notice Pauses the contract, preventing certain actions.
  /// @dev Only callable by the admin role.
  function pause() external onlyRole(ADMIN_ROLE) {
    _pause();
  }

  /// @notice Unpauses the contract, allowing actions to resume.
  /// @dev Only callable by the admin role.
  function unpause() external onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  /// @notice Internal function to authorize an upgrade.
  /// @dev Only callable by the upgrader role.
  /// @param _newImplementation Address of the new contract implementation.
  function _authorizeUpgrade(address _newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  /// @notice Receive function to accept incoming ETH transfers.
  /// @dev Non-reentrant to prevent re-entrancy attacks.
  receive() external payable {
    emit ReceiveEther(msg.value);
  }

  /************
   ** CONFIG **
   ************/

  /// @notice Sets the configuration for the Adapter.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) external onlyRole(ADMIN_ROLE) {
    config = _config;
    emit SetConfig(_config);
  }

  /// @notice Sets L2 Stake Together contract address.
  /// @dev Only callable by the admin role.
  /// @param _l2 Address of the L2 Stake Together contract.
  function setL2(address _l2) external onlyRole(ADMIN_ROLE) {
    l2 = _l2;
    emit SetL2(_l2);
  }
}
