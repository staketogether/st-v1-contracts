// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/// @title Interface for Validators Withdrawals
/// @notice A contract that represent the validator withdrawal functionality
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

  /// @notice Pauses withdrawals.
  /// @dev Only callable by the admin role.
  function pause() external;

  /// @notice Unpauses withdrawals.
  /// @dev Only callable by the admin role.
  function unpause() external;

  /// @notice Receive function to accept incoming ETH transfers.
  receive() external payable;

  /// @notice Transfers any extra amount of ETH in the contract to the StakeTogether fee address.
  /// @dev Only callable by the admin role. Requires that extra amount exists in the contract balance.
  function transferExtraAmount() external;

  /// @notice Sets the StakeTogether contract address.
  /// @param _stakeTogether The address of the new StakeTogether contract.
  /// @dev Only callable by the admin role.
  function setStakeTogether(address _stakeTogether) external;

  /**************
   ** WITHDRAW **
   **************/

  /// @notice Mints tokens to a specific address.
  /// @param _to Address to receive the minted tokens.
  /// @param _amount Amount of tokens to mint.
  /// @dev Only callable by the StakeTogether contract.
  function mint(address _to, uint256 _amount) external;

  /// @notice Withdraws the specified amount of ETH, burning tokens in exchange.
  /// @param _amount Amount of ETH to withdraw.
  /// @dev The caller must have a balance greater or equal to the amount, and the contract must have sufficient ETH balance.
  function withdraw(uint256 _amount) external;

  /// @notice Checks if the contract is ready to withdraw the specified amount.
  /// @param _amount Amount of ETH to check.
  /// @return A boolean indicating if the contract has sufficient balance to withdraw the specified amount.
  function isWithdrawReady(uint256 _amount) external view returns (bool);
}
