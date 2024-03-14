// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAdapter {
  /// @notice Thrown if the caller does not have the appropriate role.
  error NotAuthorized();

  /// @notice Thrown if the caller is not the current oracle.
  error NotCurrentValidatorOracle();

  /// @notice Thrown if there is not enough balance.
  error NotEnoughBalance();

  /// @notice Thrown if the caller is not a validator oracle.
  error OnlyValidatorOracle();

  /// @notice Thrown if the validator already exists.
  error ValidatorExists();

  /// @notice Thrown if the validator oracle already exists.
  error ValidatorOracleExists();

  /// @notice Thrown if the validator oracle is not found.
  error ValidatorOracleNotFound();

  /// @notice Thrown if the withdrawal balance is zero.
  error WithdrawZeroBalance();

  /// @notice Thrown if the withdrawal amount is zero.
  error ZeroAmount();

  /// @notice Thrown if the withdrawal amount is zero.
  error ZeroedGasLimit();

  /// @notice Thrown if the address is the zero address.
  error ZeroAddress();

  /// @notice Configuration for the StakeTogether's Adapter.sol.sol.
  struct Config {
    uint256 validatorSize; /// Size of the validator.
  }

  /// @notice Emitted when a validator is created
  /// @param oracle The address of the oracle
  /// @param amount The amount for the validator
  /// @param publicKey The public key of the validator
  /// @param withdrawalCredentials The withdrawal credentials
  /// @param signature The signature
  /// @param depositDataRoot The deposit data root
  event AddValidator(
    address indexed oracle,
    uint256 amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );

  // @notice Emitted when a validator oracle is added
  /// @param account The address of the account
  event AddValidatorOracle(address indexed account);

  /// @notice Emitted when the next validator oracle is set
  /// @param index The index of the oracle
  /// @param account The address of the account
  event NextValidatorOracle(uint256 index, address indexed account);

  /// @notice Emitted when Ether is received
  /// @param amount The amount of Ether received
  event ReceiveEther(uint256 indexed amount);

  /// @notice Emitted when a validator oracle is removed
  /// @param account The address of the account
  event RemoveValidatorOracle(address indexed account);

  /// @notice Emitted when the configuration is set
  /// @param config The configuration struct
  event SetConfig(Config indexed config);

  /// @notice Emitted when the validator size is set
  /// @param newValidatorSize The new size for the validator
  event SetValidatorSize(uint256 indexed newValidatorSize);

  /// @notice Emitted when the L2 Stake Together contract address is set
  /// @param l2StakeTogether The address of the L2 Stake Together contract
  event SetL2StakeTogether(address indexed l2StakeTogether);

  /// @notice Creates a new validator with the given parameters.
  /// @param _publicKey The public key of the validator.
  /// @param _signature The signature of the validator.
  /// @param _depositDataRoot The deposit data root for the validator.
  /// @dev Only a valid validator oracle can call this function.
  function addValidator(
    bytes calldata _publicKey,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external;

  /// @notice Adds a new validator oracle by its address.
  /// @param _account The address of the validator oracle to add.
  function addValidatorOracle(address _account) external;

  /// @notice Removes a validator oracle by its address.
  /// @param _account The address of the validator oracle to remove.
  function removeValidatorOracle(address _account) external;

  /// @notice Checks if an address is a validator oracle.
  /// @param _account The address to check.
  /// @return True if the address is a validator oracle, false otherwise.
  function isValidatorOracle(address _account) external view returns (bool);

  /// @notice Forces the selection of the next validator oracle.
  function forceNextValidatorOracle() external;

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) external;

  /// @notice Sends the passed value to the L2 StakeTogether contract.
  /// @dev Only callable by the admin role.
  /// @param minGasLimit The minimum gas limit for the transaction.
  /// @param extraData The extra data to be sent.
  function withdrawToL2(uint32 minGasLimit, bytes calldata extraData) external payable;
}
