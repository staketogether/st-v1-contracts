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
  bytes32 public constant ADAPTER_ORACLE_ROLE = keccak256('ADAPTER_ORACLE_ROLE'); /// Role for managing adapter oracles.
  bytes32 public constant ADAPTER_ORACLE_MANAGER_ROLE = keccak256('ADAPTER_ORACLE_MANAGER_ROLE'); /// Role for managing adapter oracle managers.
  bytes32 public constant VALIDATOR_ORACLE_SENTINEL_ROLE = keccak256('VALIDATOR_ORACLE_SENTINEL_ROLE'); /// Role for managing validator oracle sentinels.

  IDepositContract public deposit; /// Instance of the deposit contract.
  IBridge public bridge; /// Instance of the bridge contract.
  Config public config; /// Configuration settings.
  address public l2Router; /// Address of the Router on L2.
  uint256 public version; /// Contract version.

  bytes public withdrawalCredentials; /// Credentials for withdrawals.

  address[] private adaptersOracle; /// List of adapter oracles.
  mapping(address => uint256) private adapterOraclesIndices; /// Mapping of adapter oracle indices.
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
  function setL2Router(address _l2) external onlyRole(ADMIN_ROLE) {
    l2Router = _l2;
    emit SetL2Router(_l2);
  }

  /***********************
   ** ADAPTERS ORACLE **
   ***********************/

  /// @notice Adds a new validator oracle by its address.
  /// @param _account The address of the validator oracle to add.
  function addAdapterOracle(address _account) external onlyRole(ADAPTER_ORACLE_MANAGER_ROLE) {
    if (adapterOraclesIndices[_account] != 0) revert AdapterOracleExists();

    adaptersOracle.push(_account);
    adapterOraclesIndices[_account] = adaptersOracle.length;

    _grantRole(ADAPTER_ORACLE_ROLE, _account);
    emit AddAdapterOracle(_account);
  }

  /// @notice Removes a validator oracle by its address.
  /// @param _account The address of the validator oracle to remove.
  function removeAdapterOracle(address _account) external onlyRole(ADAPTER_ORACLE_MANAGER_ROLE) {
    if (adapterOraclesIndices[_account] == 0) revert AdapterOracleNotFound();

    uint256 index = adapterOraclesIndices[_account] - 1;

    if (index < adaptersOracle.length - 1) {
      address lastAddress = adaptersOracle[adaptersOracle.length - 1];
      adaptersOracle[index] = lastAddress;
      adapterOraclesIndices[lastAddress] = index + 1;
    }

    adaptersOracle.pop();
    delete adapterOraclesIndices[_account];

    bool isCurrentOracle = (index == currentOracleIndex);

    if (isCurrentOracle) {
      currentOracleIndex = (currentOracleIndex + 1) % adaptersOracle.length;
    }

    _revokeRole(ADAPTER_ORACLE_ROLE, _account);
    emit RemoveAdapterOracle(_account);
  }

  /// @notice Checks if an address is a validator oracle.
  /// @param _account The address to check.
  /// @return True if the address is a validator oracle, false otherwise.
  function isAdapterOracle(address _account) public view returns (bool) {
    return hasRole(ADAPTER_ORACLE_ROLE, _account) && adapterOraclesIndices[_account] > 0;
  }

  /****************
   ** VALIDATORS **
   ****************/

  /// @notice Creates a new validator with the given parameters.
  /// @param _publicKey The public key of the validator.
  /// @param _signature The signature of the validator.
  /// @param _depositDataRoot The deposit data root for the validator.
  /// @dev Only a valid validator oracle can call this function.
  function addValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external nonReentrant whenNotPaused {
    if (!isAdapterOracle(msg.sender)) revert OnlyAdapterOracle();
    if (msg.sender != adaptersOracle[currentOracleIndex]) revert NotIsCurrentAdapterOracle();
    if (address(this).balance < config.validatorSize) revert NotEnoughBalanceForValidator();
    if (validators[_publicKey]) revert ValidatorExists();

    validators[_publicKey] = true;
    _nextAdapterOracle();
    emit AddValidator(
      msg.sender,
      config.validatorSize,
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
    deposit.deposit{ value: config.validatorSize }(
      _publicKey,
      withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }

  /// @notice Internal function to update the current adapter oracle.
  function _nextAdapterOracle() private {
    currentOracleIndex = (currentOracleIndex + 1) % adaptersOracle.length;
    emit NextAdapterOracle(currentOracleIndex, adaptersOracle[currentOracleIndex]);
  }

  /****************
   ** WITHDRAWS **
   ****************/

  /// @notice Withdraws the amount to the L2 Stake Together contract.
  /// @param _amount The amount to withdraw.
  /// @param _minGasLimit The minimum gas limit for the withdrawal.
  /// @param _extraData Extra data to include in the withdrawal.
  /// @dev Only the admin role can call this function.
  function l2Withdraw(
    uint256 _amount,
    uint32 _minGasLimit,
    bytes calldata _extraData
  ) external nonReentrant whenNotPaused onlyRole(ADAPTER_ORACLE_ROLE) {
    if (_amount == 0) revert ZeroAmount();
    if (_minGasLimit == 0) revert ZeroedGasLimit();
    if (address(this).balance < _amount) revert NotEnoughBalance();
    bridge.bridgeETHTo{ value: _amount }(l2Router, _minGasLimit, _extraData);
    emit L2Withdraw(_amount, _minGasLimit, _extraData);
  }
}
