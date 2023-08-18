// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title Interface for Validators Withdrawals
/// @notice A contract that represent the validator withdrawal functionality
/// @dev Use this interface to interact with the withdrawal contract
/// @custom:security-contact security@staketogether.app
interface IWithdrawals {
  /// @notice Emitted when Ether is received
  /// @param sender The address of the sender
  /// @param amount The amount of Ether received
  event ReceiveEther(address indexed sender, uint amount);

  /// @notice Emitted when the StakeTogether address is set
  /// @param stakeTogether The address of the StakeTogether contract
  event SetStakeTogether(address stakeTogether);

  /// @notice Emitted when a user withdraws funds
  /// @param user The address of the user who is withdrawing
  /// @param amount The amount being withdrawn
  event Withdraw(address indexed user, uint256 amount);
}
