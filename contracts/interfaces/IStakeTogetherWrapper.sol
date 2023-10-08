// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.org>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title StakeTogetherWrapper Interface
/// @notice This interface defines the essential structures and functions for the StakeTogetherWrapper.
/// @custom:security-contact security@staketogether.org
interface IStakeTogetherWrapper {
  /// @notice This error is thrown when there is no extra amount of ETH available to transfer.
  error NoExtraAmountAvailable();

  /// @notice This error is thrown when trying to set the stakeTogether address that has already been set.
  error StakeTogetherAlreadySet();

  /// @notice Thrown if the address trying to make a claim is the zero address.
  error ZeroAddress();

  /// @notice Emitted when Ether is received
  /// @param amount The amount of Ether received
  event ReceiveEther(uint256 amount);

  /// @notice Emitted when the StakeTogether address is set
  /// @param stakeTogether The address of the StakeTogether contract
  event SetStakeTogether(address stakeTogether);
}
