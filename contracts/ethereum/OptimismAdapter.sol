// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IStakeTogether.sol";
import "./interfaces/IBridge.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IExternalNetworkAdapter.sol";

contract OptimismAdapter is IExternalNetworkAdapter {

  IStakeTogether public stakeTogether; /// Instance of the StakeTogether contract.
  IDepositContract public deposit; /// Instance of the deposit contract.
  IBridge public bridge; /// Instance of the bridge contract.
  Config public config; /// Configuration settings for the protocol.
  address private _l2StakeTogether; /// Address of the L2 StakeTogether contract.
  uint256 public version; /// Contract version.

  bytes public withdrawalCredentials; /// Credentials for withdrawals.

  address[] private validatorsOracle; /// List of validator oracles.
  mapping(address => uint256) private validatorsOracleIndices; /// Mapping of validator oracle indices.
  uint256 public currentOracleIndex; /// Current index of the oracle.

  mapping(bytes => bool) public validators; /// Mapping of validators.

  constructor(address stakeTogetherAddress, address depositAddress) {
    stakeTogether = IStakeTogether(stakeTogetherAddress);
    deposit = IDepositContract(depositAddress);
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

  function withdrawToL2(
    uint32 minGasLimit,
    bytes calldata extraData
  ) external payable nonReentrant whenNotPaused onlyAdmin {
    if (msg.value == 0) revert ZeroAmount();
    if (minGasLimit == 0) revert ZeroedGasLimit();
    if (address(this).balance < amount) revert NotEnoughBalance();
    if (amount > address(this).balance) revert WithdrawZeroBalance();
    bridge.bridgeETHTo{value: msg.value}(_l2StakeTogether, minGasLimit, extraData);
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
