// SPDX-FileCopyrightText: 2024 Together Technology LTD <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/// @title Interface for StakeTogether Adapter Contract
/// @notice The Interface for Adapter Contract is responsible to interact with Staking Infrastructure and manage the staking process.
/// It provides functionalities for create validators, withdraw and withdraw rewards.
/// @custom:security-contact security@staketogether.org
interface IAdapter {
  /// @notice Configuration for the StakeTogether's Adapter.sol.sol.
  struct Config {
    uint256 validatorSize; /// Size of the validator.
  }

  /// @notice Emitted when Ether is received
  /// @param amount The amount of Ether received
  event ReceiveEther(uint256 indexed amount);

  /// @notice Emitted when the L2 Stake Together contract address is set
  /// @param l2 The address of the L2 Stake Together contract
  event SetL2(address indexed l2);

  /// @notice Emitted when the configuration is set
  /// @param config The configuration struct
  event SetConfig(Config indexed config);

  /// @notice Sets the configuration for the Stake Together Protocol.
  /// @dev Only callable by the admin role.
  /// @param _config Configuration settings to be applied.
  function setConfig(Config memory _config) external;
}
