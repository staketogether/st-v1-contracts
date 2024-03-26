// SPDX-FileCopyrightText: 2024 Together Technology LTD <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/// @title Interface for StakeTogether Adapter Contract
/// @notice The Interface for Adapter Contract is responsible to interact with Staking Infrastructure and manage the staking process.
/// It provides functionalities for create validators, withdraw and withdraw rewards.
/// @custom:security-contact security@staketogether.org
interface IELAdapter {
  /// @notice Configuration for the StakeTogether's Adapter.sol.sol.
  struct Config {
    uint256 validatorSize; /// Size of the validator.
  }

  /// @notice Thrown if the adapter oracle already exists.
  error AdapterOracleExists();

  /// @notice Thrown if the adapter oracle is not found.
  error AdapterOracleNotFound();

  /// @notice Thrown if the caller is not a adapter oracle.
  error OnlyAdapterOracle();

  /// @notice Thrown if the caller is not the current oracle.
  error NotIsCurrentAdapterOracle();

  /// @notice Thrown if there is not enough balance to create validator.
  error NotEnoughBalanceForValidator();

  /// @notice Thrown if the balance is not enough.
  error NotEnoughBalance();

  /// @notice Thrown if the validator already exists.
  error ValidatorExists();

  /// @notice Thrown if the withdrawal amount is zero.
  error ZeroAmount();

  /// @notice Thrown if the address is the zero address.
  error ZeroAddress();

  /// @notice Thrown if the gas limit is zero.
  error ZeroedGasLimit();

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

  /// @notice Emitted when a validator oracle is added
  /// @param account The address of the account
  event AddAdapterOracle(address indexed account);

  /// @notice Emitted when a adapter oracle is removed
  /// @param account The address of the account
  event RemoveAdapterOracle(address indexed account);

  /// @notice Emitted when Ether is received
  /// @param amount The amount of Ether received
  event ReceiveEther(uint256 indexed amount);

  /// @notice Emitted when the L2 Stake Together contract address is set
  /// @param l2Router The address of the L2 Stake Together contract
  event SetL2Router(address indexed l2Router);

  /// @notice Emitted when the configuration is set
  /// @param config The configuration struct
  event SetConfig(Config indexed config);

  /// @notice Emitted when the next adapter oracle is set
  /// @param index The index of the oracle
  /// @param account The address of the account
  event NextAdapterOracle(uint256 index, address indexed account);

  /// @notice Emitted when the amount is withdrawn to L2
  /// @param amount The amount to be withdrawn
  /// @param minGasLimit The minimum gas limit for the transaction
  /// @param extraData The extra data to be sent
  event L2Withdraw(uint256 amount, uint32 minGasLimit, bytes extraData);

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) external;
}
