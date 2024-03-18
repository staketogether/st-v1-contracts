// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

import "./interfaces/IBridge.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IAdapter.sol";

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
  Config public config; /// Configuration settings for the protocol.
  address public l2StakeTogether; /// Address of the L2 StakeTogether contract.
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

  function initialize(
    address _deposit,
    address _bridge,
    bytes memory _withdrawalCredentials
  ) public initializer {
    __Pausable_init();
    __ReentrancyGuard_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(VALIDATOR_ORACLE_MANAGER_ROLE, msg.sender);

    deposit = IDepositContract(_deposit);
    bridge = IBridge(_bridge);
    withdrawalCredentials = _withdrawalCredentials;
    version = 1;
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

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) external onlyRole(ADMIN_ROLE) {
    config = _config;
    emit SetConfig(_config);
  }

  /// @notice Sets L2 Stake Together contract address.
  /// @dev Only callable by the admin role.
  /// @param _l2StakeTogether Address of the L2 Stake Together contract.
  function setL2StakeTogether(address _l2StakeTogether) external onlyRole(ADMIN_ROLE) {
    l2StakeTogether = _l2StakeTogether;
    emit SetL2StakeTogether(_l2StakeTogether);
  }

  /**********************
   **    VALIDATORS    **
   **********************/

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
    if (!isValidatorOracle(msg.sender)) revert OnlyValidatorOracle();
    if (msg.sender != validatorsOracle[currentOracleIndex]) revert NotCurrentValidatorOracle();
    if (address(this).balance < config.validatorSize) revert NotEnoughBalance();
    if (validators[_publicKey]) revert ValidatorExists();

    validators[_publicKey] = true;
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

  /// @notice Withdraws the amount to the L2 Stake Together contract.
  /// @param _amount The amount to withdraw.
  /// @param _minGasLimit The minimum gas limit for the withdrawal.
  /// @param _extraData Extra data to include in the withdrawal.
  /// @dev Only the admin role can call this function.
  function withdrawToL2(
    uint256 _amount,
    uint32 _minGasLimit,
    bytes calldata _extraData
  ) external nonReentrant whenNotPaused onlyRole(ADMIN_ROLE) {
    if (_amount == 0) revert ZeroAmount();
    if (_minGasLimit == 0) revert ZeroedGasLimit();
    if (address(this).balance < _amount) revert NotEnoughBalance();
    bridge.bridgeETHTo{value: _amount}(l2StakeTogether, _minGasLimit, _extraData);
    emit WithdrawToL2(_amount, _minGasLimit, _extraData);
  }

  /***********************
   ** VALIDATORS ORACLE **
   ***********************/

  /// @notice Adds a new validator oracle by its address.
  /// @param _account The address of the validator oracle to add.
  function addValidatorOracle(address _account) external onlyRole(VALIDATOR_ORACLE_MANAGER_ROLE) {
    if (validatorsOracleIndices[_account] != 0) revert ValidatorOracleExists();

    validatorsOracle.push(_account);
    validatorsOracleIndices[_account] = validatorsOracle.length;

    _grantRole(VALIDATOR_ORACLE_ROLE, _account);
    emit AddValidatorOracle(_account);
  }

  /// @notice Removes a validator oracle by its address.
  /// @param _account The address of the validator oracle to remove.
  function removeValidatorOracle(address _account) external onlyRole(VALIDATOR_ORACLE_MANAGER_ROLE) {
    if (validatorsOracleIndices[_account] == 0) revert ValidatorOracleNotFound();

    uint256 index = validatorsOracleIndices[_account] - 1;

    if (index < validatorsOracle.length - 1) {
      address lastAddress = validatorsOracle[validatorsOracle.length - 1];
      validatorsOracle[index] = lastAddress;
      validatorsOracleIndices[lastAddress] = index + 1;
    }

    validatorsOracle.pop();
    delete validatorsOracleIndices[_account];

    bool isCurrentOracle = (index == currentOracleIndex);

    if (isCurrentOracle) {
      currentOracleIndex = (currentOracleIndex + 1) % validatorsOracle.length;
    }

    _revokeRole(VALIDATOR_ORACLE_ROLE, _account);
    emit RemoveValidatorOracle(_account);
  }

  /// @notice Checks if an address is a validator oracle.
  /// @param _account The address to check.
  /// @return True if the address is a validator oracle, false otherwise.
  function isValidatorOracle(address _account) public view returns (bool) {
    return hasRole(VALIDATOR_ORACLE_ROLE, _account) && validatorsOracleIndices[_account] > 0;
  }

  /// @notice Forces the selection of the next validator oracle.
  function forceNextValidatorOracle() external {
    if (
      !hasRole(VALIDATOR_ORACLE_SENTINEL_ROLE, msg.sender) &&
      !hasRole(VALIDATOR_ORACLE_MANAGER_ROLE, msg.sender)
    ) revert NotAuthorized();
    _nextValidatorOracle();
  }

  /// @notice Internal function to update the current validator oracle.
  function _nextValidatorOracle() private {
    currentOracleIndex = (currentOracleIndex + 1) % validatorsOracle.length;
    emit NextValidatorOracle(currentOracleIndex, validatorsOracle[currentOracleIndex]);
  }
}
